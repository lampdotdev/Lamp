import Foundation

/// Suggests the next change a user might ask for, shown as ghost text in the composer once the agent
/// finishes a turn. Tab accepts it, Escape dismisses it. Fails soft: any error means no suggestion.
@MainActor
enum NextStep {
    private static let prompt = """
    You suggest the next message a user might send to Lamp, an AI that builds and changes an app for \
    them while they describe what they want in plain words.

    Propose ONE short follow-up message the user is most likely to want to send next.

    Rules:
    - Always suggest something. If the next step is uncertain, pick the most plausible concrete one rather \
    than generic filler like "\(examples[0])" or "\(examples[1])".
    - Keep it to 5-10 words, on a single line, with no surrounding quotes, markdown, or emoji.
    - Write it as an instruction or question addressed to Lamp, mimicking the voice and tone of the user's \
    previous messages: match their casing, punctuation, formality, and phrasing habits so it reads like \
    something they would actually type.
    - Make it specific to this conversation (reference the actual app and work).
    - Prefer a concrete next step: taking up a suggestion Lamp just made, fixing something it mentioned, \
    extending the change, or polishing how the app looks and feels.
    - Where the conversation says the user took a request back, they decided against it: never suggest that \
    request again, or anything that amounts to it.

    Respond with JSON: {"suggestion": "..."}
    """

    private static let historyLimit = 20
    private static let maxConversationChars = 60_000
    private static let maxWords = 12
    private static let maxChars = 100
    /// The filler the prompt rules out, in its own words: a suggestion that is one of them is no suggestion.
    static let examples = ["keep going", "looks good"]

    /// One generation per finished agent turn, keyed by that turn's last agent message.
    private static var cache: [UUID: String] = [:]

    /// The agent message a suggestion would follow up on: the latest chat message, when it's the agent's.
    static func turn(in lines: [LogLine]) -> UUID? {
        guard let last = lines.last(where: { $0.kind == .user || $0.kind == .agent }), last.kind == .agent,
              lines.contains(where: { $0.kind == .user }) else { return nil }
        return last.id
    }

    static func suggest(for project: LampProject, lines: [LogLine]) async -> String? {
        guard let turn = turn(in: lines) else { return nil }
        if let cached = cache[turn] { return cached }

        let conversation = conversationText(lines.filter { $0.kind == .user || $0.kind == .agent }.suffix(historyLimit))
        let request = "\(prompt)\nThe app is \(AppKind(project).phrase) called \(project.name).\n\nHere is the conversation:\n\(conversation)"
        guard let (text, _) = try? await AppAI.complete(prompt: request, images: [], system: "", json: true,
                                                         model: await AppAI.helperModel()),
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["suggestion"] as? String,
              let suggestion = normalize(raw) else { return nil }
        cache[turn] = suggestion
        return suggestion
    }

    /// Newest-last, trimmed from the oldest end so the latest turns always fit.
    private static func conversationText(_ lines: ArraySlice<LogLine>) -> String {
        var parts: [String] = []
        var total = 0
        for line in lines.reversed() {
            let text = line.text.trimmed
            guard !text.isEmpty else { continue }
            let tookBack = (line.tookBack?.suffix(6)).map { requests in
                " (the user sent this in place of earlier requests, which they took back: "
                    + requests.map { "“\($0.prefix(200))”" }.joined(separator: ", ") + ")"
            } ?? ""
            let part = "\(line.kind == .user ? "User" : "Lamp")\(tookBack): \(text)\n\n"
            if total + part.count > maxConversationChars { break }
            parts.insert(part, at: 0)
            total += part.count
        }
        return parts.joined()
    }

    /// Collapses to one line, strips wrapping quotes, and drops overlong answers instead of cutting them mid-thought.
    static func normalize(_ raw: String) -> String? {
        var text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if text.count > 1, let first = text.first, first == text.last, first == "\"" || first == "'" {
            text = String(text.dropFirst().dropLast()).trimmed
        }
        guard !text.isEmpty, text.split(separator: " ").count <= maxWords, text.count <= maxChars,
              !AppAI.parrots(text, examples: examples) else { return nil }
        return text
    }
}

/// Names an app from the first thing its user asked for, says in a sentence what it is, and sketches its main parts for the build card
/// while the agent is still thinking. Fails soft: without a name the app stays untitled.
@MainActor
enum AppName {
    /// The names and parts the prompt shows as examples. One of them back as the answer, for a request that
    /// never mentioned it, is the model repeating the prompt: the app stays untitled, the part is left out.
    static let exampleNames = ["Lucide Picker", "Build Tally", "Brew Log", "Notes", "Stopwatch", "Calendar", "Photo Booth", "Night Shift"]
    static let exampleParts = ["Your habits, ticked off daily", "A reminder in the evening"]
    static let exampleDescription = "A place to keep the family's recipes."

    private static let prompt = """
    Name a small app from what its user asked for.

    First, check whether the user already named it. A name is usually a capitalized phrase used as a title, \
    often at the very start ("\(exampleNames[0]), an app that…", "\(exampleNames[1]): a counter…", "make me an app called \
    \(exampleNames[2])"). If they named it, use their name exactly as they wrote it, even if it includes a brand or \
    product name. Their choice beats every rule below.

    Only if they didn't name it, pick a name in the spirit of Apple's own apps: one or two plain, friendly \
    words that say what it is or evoke it (\(exampleNames[3...].joined(separator: ", "))). No "App", \
    "Pro" or "AI" suffix, no made-up portmanteaus, no emoji, and not the name of an existing product or brand.

    Then sketch what it will do: 3 or 4 short phrases, two to six words each, naming its main parts the way \
    its user would ("\(exampleParts[0])", "\(exampleParts[1])"). No file, type or framework \
    names.

    Last, describe it: one short, plain sentence saying what the app is, like the line under an app's name \
    in a store ("\(exampleDescription)"). Not a list of features and not how it works: what it is, in \
    everyday words.

    Respond with JSON: {"named_by_user": true or false, "name": "...", "parts": ["...", "..."], "description": "..."}
    """

    struct Suggestion {
        var name: String?
        /// A guess at the app's main parts, shown until the agent gives its own plan.
        var sketch: [String]
        /// What the app is, for someone it's shared with (`LampProject.description`).
        var description: String?
    }

    static func suggest(for brief: String) async -> Suggestion? {
        let request = "\(prompt)\n\nThe user asked for:\n\(brief.prefix(4000))"
        guard let (text, _) = try? await AppAI.complete(prompt: request, images: [], system: "", json: true,
                                                         model: await AppAI.helperModel()),
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return nil }
        let sketch = (object["parts"] as? [Any] ?? []).compactMap { ($0 as? String)?.trimmed }
            .filter { !$0.isEmpty && $0.count <= 60 && !AppAI.parrots($0, examples: exampleParts, asked: brief) }.prefix(5)
        return Suggestion(name: name(object, asked: brief), sketch: sketch.count >= 2 ? Array(sketch) : [],
                          description: description(object, asked: brief))
    }

    /// The sentence as the model gave it, on one line. None, or the prompt's own example back, is no description.
    static func description(_ object: [String: Any], asked brief: String) -> String? {
        guard let raw = object["description"] as? String else { return nil }
        let words = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !words.isEmpty, !AppAI.parrots(words, examples: [exampleDescription], asked: brief) else { return nil }
        return words
    }

    static func name(_ object: [String: Any], asked brief: String) -> String? {
        guard let raw = object["name"] as? String else { return nil }
        let name = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’."))
        // The user's own name gets more room than one Lamp makes up.
        let named = object["named_by_user"] as? Bool ?? false
        guard !name.isEmpty, name.split(separator: " ").count <= (named ? 5 : 3), name.count <= (named ? 40 : 24),
              !AppAI.parrots(name, examples: exampleNames, asked: brief) else { return nil }
        return name
    }
}
