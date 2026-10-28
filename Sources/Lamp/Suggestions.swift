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
        // Not over the agent's questions: the card has the likely answers, and a guess at one in the message
        // box would sit beside them as another.
        guard Talk.open(in: lines) == nil,
              let last = lines.last(where: { $0.kind == .user || $0.kind == .agent }), last.kind == .agent,
              lines.contains(where: { $0.kind == .user }) else { return nil }
        return last.id
    }

    static func suggest(for project: LampProject, lines: [LogLine]) async -> String? {
        guard let turn = turn(in: lines) else { return nil }
        if let cached = cache[turn] { return cached }

        let conversation = conversationText(lines.filter { $0.kind == .user || $0.kind == .agent }.suffix(historyLimit))
        // A game is always offered more fun (`GameFun`), unless the person just asked for it.
        let fun = GameFun.offered(for: project) && !GameFun.asked(lines.last { $0.kind == .user }?.text ?? "")
        let request = "\(prompt)\nThe app is \(project.platform.target.identity.phrase) called \(project.name)."
            + (fun ? " It's a game: unless a more specific next step is plain (a fix or an idea Lamp just mentioned), suggest exactly \"\(GameFun.title)\"." : "")
            + "\n\nHere is the conversation:\n\(conversation)"
        guard let (text, _) = try? await AppAI.complete(prompt: request, images: [], system: "", json: true,
                                                         model: await AppAI.helperModel()),
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["suggestion"] as? String,
              let suggestion = normalize(raw) else { return fun ? GameFun.title : nil }
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

/// Names an app from the first thing its user asked for, and sketches its main parts for the chat's chapters
/// while the agent is still thinking. Fails soft: without a name the app stays untitled.
@MainActor
enum AppName {
    /// The names and parts the prompt shows as examples. One of them back as the answer, for a request that
    /// never mentioned it, is the model repeating the prompt: the app stays untitled, the part is left out.
    static let exampleNames = ["Lucide Picker", "Build Tally", "Brew Log", "Notes", "Stopwatch", "Calendar", "Photo Booth", "Night Shift"]
    static let exampleParts = ["Your habits, ticked off daily", "A reminder in the evening"]

    /// Made when asked: the devices it lists are the table's (`Places`), so a new row is named with no edit here.
    private static var prompt: String { """
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

    Last, list the devices the request names or plainly means, in these words: \(namingDevices) "My phone" is \
    ["iphone"] unless they say it's an Android; [] when it names none. Never choose how it's made or add a device it \
    doesn't mention: the builder decides the rest. A request for something to run on a device of theirs Lamp can't \
    put apps on yet is ["other"].

    And the color of its icon's background, one of: \(Icons.backgrounds.map(\.name).joined(separator: ", ")). Pick \
    what suits its mood, like Apple's own icons: mostly one vivid color, sometimes white or graphite.

    Respond with JSON: {"named_by_user": true or false, "name": "...", "parts": ["...", "..."], \
    "devices": ["..."], "color": "..."}
    """ }

    /// The table's words for each device (`Places`), as the naming call answers with them.
    private static var namingDevices: String {
        Places.all.map { place in place.words.map { "\"\($0)\"" }.joined(separator: " or ") + " for " + place.name }.joined(separator: ", ") + "."
    }

    struct Suggestion {
        var name: String?
        /// A guess at the app's main parts, shown until the agent gives its own plan.
        var sketch: [String]
        /// The devices the request names, in the table's words (`Places`): what the agent is told it named. What the
        /// wish's apps are and where they run is the agent's to decide (`Agent.undecidedPrompt`).
        var devices: [String] = []
        /// For one of the person's devices Lamp can't make apps for yet (`seen`): nothing is made until the agent has
        /// set the device up and given the wish its kind.
        var forOtherDevice = false
        /// The icon's background (`Icons.backgrounds`), chosen here so the blueprint shows it from the start and the
        /// icon keeps it.
        var color: String?

        private var rows: [Place] { devices.compactMap { Places.named($0) } }

        /// The wish names a phone or tablet, Apple's or Android's: what makes Lamp look for the person's phones.
        var forPhone: Bool { rows.contains { $0.destination == .ios || $0.destination.isAndroid } }

        /// The wish names a TV or another device Lamp reaches over the network (one Lamp can't make apps for yet too):
        /// what makes Lamp look on the network for it.
        var forDevice: Bool { forOtherDevice || rows.contains { $0.destination == .tv || $0.destination == .androidTV || $0.destination == .device } }
    }

    static func suggest(for brief: String, devices: [Device] = []) async -> Suggestion? {
        let request = "\(prompt)\(seen(devices))\n\nThe user asked for:\n\(brief.prefix(4000))"
        guard let (text, _) = try? await AppAI.complete(prompt: request, images: [], system: "", json: true,
                                                         model: await AppAI.helperModel()),
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return nil }
        let sketch = (object["parts"] as? [Any] ?? []).compactMap { ($0 as? String)?.trimmed }
            .filter { !$0.isEmpty && $0.count <= 60 && !AppAI.parrots($0, examples: exampleParts, asked: brief) }.prefix(5)
        var named: [String] = []
        for word in (object["devices"] as? [String] ?? []).map({ $0.trimmed.lowercased() }) {
            guard let id = word == "other" ? "other" : Places.named(word)?.id, !named.contains(id) else { continue }
            named.append(id)
        }
        return Suggestion(name: name(object, asked: brief), sketch: sketch.count >= 2 ? Array(sketch) : [],
                          devices: named.filter { $0 != "other" }, forOtherDevice: named == ["other"],
                          color: (object["color"] as? String).flatMap { name in Icons.backgrounds.first { $0.name == name.trimmed.lowercased() }?.name })
    }

    /// The person's devices Lamp found just now, each with what to answer for a wish that's for it, so "my TV" or
    /// "my Roku" is read as the device they have: a Roku isn't a Samsung or LG TV. A wish to run something on one Lamp
    /// can't put apps on yet is "other", which leaves the wish a draft for the agent to set the device up
    /// (`device_integration`) and make the app for it once it can, rather than starting it as something else; a wish
    /// to control any device (a remote for the speakers, buttons that open the Roku's apps) is an app on this Mac or
    /// a phone like any other.
    ///
    /// Only devices set up with Lamp are the person's: one only found on the network may be a neighbor's, so it's listed
    /// apart and answered only when the request names it, never for "my TV" alone.
    static func seen(_ devices: [Device]) -> String {
        func listed(_ devices: [Device]) -> [String] {
            devices.compactMap { device -> String? in
                guard let answer = answer(for: device) else { return nil }
                let what = [device.maker, device.model].filter { !$0.isEmpty }.joined(separator: " ")
                let name = device.name.isEmpty || device.name == device.model ? what : "\(device.name) (\(what))"
                return "- \(name.replacingOccurrences(of: "\n", with: " ").prefix(80)): [\"\(answer)\"]"
            }
        }
        let mine = listed(devices.filter(\.isSetUp)), possible = listed(devices.filter { !$0.isSetUp })
        guard !mine.isEmpty || !possible.isEmpty else { return "" }
        var text = mine.isEmpty ? "" : "\n\nThe person's devices, set up with Lamp, with what to answer when the request is for one of them (by its name, "
            + "its maker, its model or what it is: \"my TV\" is the TV here).\n" + mine.prefix(20).joined(separator: "\n")
        if !possible.isEmpty {
            text += "\n\nAlso found on the network just now but not set up with Lamp, so they may not be the person's, with what to answer "
                + "only when the request names one of them by its name, maker or model (\"my TV\" alone isn't one of these).\n"
                + possible.prefix(20).joined(separator: "\n")
        }
        return text + "\n\nThese answers come before the rules above. "
            + "Answer a device only when what's asked for runs on that device itself (a game or a channel on it); an app that "
            + "plays to it, controls it or reads it doesn't run on it, and is answered by the rules above. [\"other\"] is a device "
            + "Lamp can't put apps on yet: answer it alone, with \"devices_by_user\" true."
    }

    /// What the naming call answers for a wish that's for this device, or nil to leave it off the list: this Mac and
    /// Apple's phones, iPads and watches, which the rules already name ("my phone"), since listing them drew wishes
    /// that named no device to the iPhone; and the emulator, which is Lamp's own.
    static func answer(for device: Device) -> String? {
        switch device.kind {
        case .mac, .androidEmulator, .iphone, .ipad, .watch: return nil
        case .android: return device.features.contains("tv") ? "android-tv" : "android"
        case .samsungTV, .lgTV: return "tv"
        case .other:
            guard let id = device.integration, DeviceApps.makesApps(id) else { return "other" }
            return id
        }
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
