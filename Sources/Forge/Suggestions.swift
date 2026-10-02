import Foundation

/// Suggests the next change a user might ask for, shown as ghost text in the composer once the agent
/// finishes a turn. Tab accepts it, Escape dismisses it. Fails soft: any error means no suggestion.
@MainActor
enum NextStep {
    private static let prompt = """
    You suggest the next message a user might send to Forge, an AI that builds and changes a Mac app for \
    them while they describe what they want in plain words.

    Propose ONE short follow-up message the user is most likely to want to send next.

    Rules:
    - Always suggest something. If the next step is uncertain, pick the most plausible concrete one rather \
    than generic filler like "keep going" or "looks good".
    - Keep it to 5-10 words, on a single line, with no surrounding quotes, markdown, or emoji.
    - Write it as an instruction or question addressed to Forge, mimicking the voice and tone of the user's \
    previous messages: match their casing, punctuation, formality, and phrasing habits so it reads like \
    something they would actually type.
    - Make it specific to this conversation (reference the actual app and work).
    - Prefer a concrete next step: taking up a suggestion Forge just made, fixing something it mentioned, \
    extending the change, or polishing how the app looks and feels.

    Respond with JSON: {"suggestion": "..."}
    """

    private static let historyLimit = 20
    private static let maxConversationChars = 60_000
    private static let maxWords = 12
    private static let maxChars = 100

    /// One generation per finished agent turn, keyed by that turn's last agent message.
    private static var cache: [UUID: String] = [:]

    /// The agent message a suggestion would follow up on: the latest chat message, when it's the agent's.
    static func turn(in lines: [LogLine]) -> UUID? {
        guard let last = lines.last(where: { $0.kind == .user || $0.kind == .agent }), last.kind == .agent,
              lines.contains(where: { $0.kind == .user }) else { return nil }
        return last.id
    }

    static func suggest(for project: ForgeProject, lines: [LogLine]) async -> String? {
        guard let turn = turn(in: lines) else { return nil }
        if let cached = cache[turn] { return cached }

        let conversation = conversationText(lines.filter { $0.kind == .user || $0.kind == .agent }.suffix(historyLimit))
        let request = "\(prompt)\nThe app is called \(project.name).\n\nHere is the conversation:\n\(conversation)"
        guard let (text, _) = try? await AppAI.complete(prompt: request, images: [], system: "", json: true,
                                                         model: AppAI.models[0].openRouter),
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
            let part = "\(line.kind == .user ? "User" : "Forge"): \(text)\n\n"
            if total + part.count > maxConversationChars { break }
            parts.insert(part, at: 0)
            total += part.count
        }
        return parts.joined()
    }

    /// Collapses to one line, strips wrapping quotes, and drops overlong answers instead of cutting them mid-thought.
    private static func normalize(_ raw: String) -> String? {
        var text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if text.count > 1, let first = text.first, first == text.last, first == "\"" || first == "'" {
            text = String(text.dropFirst().dropLast()).trimmed
        }
        guard !text.isEmpty, text.split(separator: " ").count <= maxWords, text.count <= maxChars else { return nil }
        return text
    }
}
