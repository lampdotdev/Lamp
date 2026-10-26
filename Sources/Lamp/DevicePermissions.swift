import Foundation

/// What the person said on Lamp's device card (`device_permission`): whether the agent may change one of their devices
/// (a key press, opening an app, volume, power) while it works on a wish that controls them. Reading a device needs no
/// card. Kept in Lamp's own folder, by the wish's instance, never in the app's folder, which the agent can write.
/// "Allow once" lasts until the person next writes to the chat; "Always" lasts as long as the wish.
enum DevicePermissions {
    struct Kept: Codable, Equatable {
        var always: [String] = []
        var once: String?
    }

    static let allowOnce = "Allow once"
    static func allowAlways(_ device: String) -> String { "Always for \(device)" }
    static let notNow = "Not now"

    private static var folder: URL { Edition.supportFolder.appendingPathComponent("DevicePermissions") }

    private static func file(_ wish: LampProject) -> URL {
        folder.appendingPathComponent((wish.instance.isEmpty ? wish.id : wish.instance) + ".json")
    }

    static func kept(_ wish: LampProject) -> Kept {
        (try? Data(contentsOf: file(wish))).flatMap { try? JSONDecoder().decode(Kept.self, from: $0) } ?? Kept()
    }

    private static func save(_ kept: Kept, for wish: LampProject) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if kept == Kept() { try? FileManager.default.removeItem(at: file(wish)); return }
        try? JSONEncoder().encode(kept).write(to: file(wish), options: .atomic)
    }

    /// The devices the agent may change now.
    static func allowed(_ wish: LampProject) -> [String] {
        let kept = kept(wish)
        return kept.always + (kept.once.map { [$0] } ?? [])
    }

    /// The person's answer to the card, as the option they chose.
    static func answer(_ choice: String, about device: String, for wish: LampProject) {
        var kept = kept(wish)
        if choice == allowOnce { kept.once = device }
        if choice == allowAlways(device), !kept.always.contains(device) { kept.always.append(device) }
        save(kept, for: wish)
    }

    /// The person wrote to the chat again: what they allowed once is spent.
    static func endOnce(for wish: LampProject) {
        var kept = kept(wish)
        guard kept.once != nil else { return }
        kept.once = nil
        save(kept, for: wish)
    }

    /// Forgotten with the wish.
    static func forget(_ wish: LampProject) { try? FileManager.default.removeItem(at: file(wish)) }

    /// Whether an app reaches the person's devices: its code uses Lamp's blocks for them, or it declares the local
    /// network for them in capabilities.json.
    static func reachesDevices(_ app: LampProject) -> Bool {
        let capabilities = Template.Capabilities.load(app).checked
        return capabilities.localNetwork != nil || !(capabilities.bonjourServices ?? []).isEmpty
            || Skills.appSwift(of: app, matches: #"\b(LampRoku|LampNetwork)\b"#)
    }

    /// The card: one question, three answers, only the person's to give.
    static func card(device: String, doing: String) -> Talk.Ask {
        Talk.Ask(layout: .steps, questions: [
            Talk.Question(question: "Try it on your \(device)?",
                          options: [Talk.Option(title: allowOnce, detail: doing, symbol: "hand.tap"),
                                    Talk.Option(title: allowAlways(device), symbol: "checkmark.seal"),
                                    Talk.Option(title: notNow, symbol: "xmark")],
                          personOnly: true),
        ], device: device)
    }

    /// What the engines' command checks are told (`CommandRisk`, `CodexReview`, Claude Code's auto mode): changing a
    /// device on the network needs the person's yes on the card; reading one doesn't.
    static let commandRule = "Sending a command that changes a device on the user's home network (a TV, speaker, light or console: a key press, opening an app, a volume, input, power or setting change), unless the user allowed that device on Lamp's device card in this conversation: their answer to \"Try it on your <device>?\" is \"\(allowOnce)\" or \"Always for <device>\". Asking a device what it is or what it's playing changes nothing and is fine."

    /// Whether a shell command reaches a device on the home network (a private address or a `.local` name) in a way
    /// that could change it: every part of it that names one must be a plain `curl` read. Codex's own check, where
    /// Codex runs ordinary commands in its sandbox with the network open and no reviewer sees them.
    static func mayChangeADevice(_ command: String) -> Bool {
        let home = #"\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b|[A-Za-z0-9-]\.local\b"#
        let writes = #"(^|\s)(-X|--request)\s*(?!GET\b)\S|(^|\s)(-d|--data[a-z-]*|--json|-F|--form|-T|--upload-file)(\s|=|$)"#
        let parts = command.components(separatedBy: CharacterSet(charactersIn: ";|&\n"))
        return parts.contains { part in
            let part = part.trimmingCharacters(in: .whitespaces)
            guard part.range(of: home, options: .regularExpression) != nil else { return false }
            return !part.hasPrefix("curl ") || part.range(of: writes, options: .regularExpression) != nil
        }
    }

    static let commandRefusal = "This reaches a device on the person's network in a way that could change it. Ask with `device_permission` first; to read a device, use a plain `curl` GET."

    /// What `use_app` says on an app that reaches devices before the person has allowed one.
    static let useRefusal = "This app controls the person's devices: use it only on a device they've allowed, named in `device` as on Lamp's card. Ask with `device_permission` first for a device they haven't allowed, naming it and what you'd press."
}
