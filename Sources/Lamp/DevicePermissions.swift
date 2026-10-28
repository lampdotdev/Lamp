import Foundation

/// What the person said on Lamp's device card (`device_permission`): whether the agent may change one of their devices
/// (a key press, opening an app, volume, power) while it works on a wish that controls them. Reading a device needs no
/// card. Kept in Lamp's own folder, by the wish's instance, never in the app's folder, which the agent can write.
/// "Allow once" lasts until the person next writes to the chat; "Always" lasts as long as the wish.
enum DevicePermissions {
    struct Kept: Codable, Equatable {
        var always: [String] = []
        var once: String?
        /// Where the device allowed once was, for as long as that lasts.
        var onceAddress: String?
        /// Each always-allowed device's address (or `.local` name), from the card that asked about it: what a command may
        /// reach.
        var addresses: [String: String] = [:]
        /// The address a card that's up was asked for, kept apart until the person allows it.
        var asked: [String: String] = [:]
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

    /// The addresses of the devices the agent may change now.
    static func allowedAddresses(_ wish: LampProject) -> Set<String> {
        let kept = kept(wish)
        return Set(kept.always.compactMap { kept.addresses[$0]?.lowercased() } + (kept.onceAddress.map { [$0.lowercased()] } ?? []))
    }

    /// The card is up: the device's address is noted, to be allowed with it.
    static func asking(about device: String, at address: String, for wish: LampProject) {
        var kept = kept(wish)
        kept.asked[device] = address
        save(kept, for: wish)
    }

    /// The person's answer to the card, as the option they chose.
    static func answer(_ choice: String, about device: String, for wish: LampProject) {
        var kept = kept(wish)
        let address = kept.asked.removeValue(forKey: device)
        if choice == allowOnce { (kept.once, kept.onceAddress) = (device, address) }
        if choice == allowAlways(device) {
            // The address the card was for, now allowed for good: an earlier one for the same name is no longer.
            kept.addresses[device] = address
            if !kept.always.contains(device) { kept.always.append(device) }
        }
        save(kept, for: wish)
    }

    /// The person wrote to the chat again: what they allowed once is spent.
    static func endOnce(for wish: LampProject) {
        var kept = kept(wish)
        guard kept.once != nil else { return }
        (kept.once, kept.onceAddress) = (nil, nil)
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
    /// `setUp` is Lamp's own word on the device at that address: one it only found isn't called the person's, since it
    /// may be a neighbor's. Allowing it here lets the agent use it, and nothing more: it's no more set up for it.
    static func card(device: String, doing: String, setUp: Bool = true) -> Talk.Ask {
        Talk.Ask(layout: .steps, questions: [
            Talk.Question(question: setUp ? "Try it on your \(device)?" : "Try it on \(device)?",
                          options: [Talk.Option(title: allowOnce, detail: doing, symbol: "hand.tap"),
                                    Talk.Option(title: allowAlways(device), symbol: "checkmark.seal"),
                                    Talk.Option(title: notNow, symbol: "xmark")],
                          personOnly: true),
        ], device: device)
    }

    /// What the engines' command checks are told (`CommandRisk`, `CodexReview`, Claude Code's auto mode): changing a
    /// device on the network needs the person's yes on the card; reading one doesn't.
    static let commandRule = "Sending a command that changes a device on the user's home network (a TV, speaker, light or console: a key press, opening an app, a volume, input, power or setting change), unless the user allowed that device on Lamp's device card in this conversation: their answer to \"Try it on your <device>?\" or \"Try it on <device>?\" is \"\(allowOnce)\" or \"Always for <device>\". Asking a device what it is or what it's playing changes nothing and is fine."

    /// Whether a shell command reaches a device on the home network (a private address or a `.local` name) in a way
    /// that could change it: every part of it that names one must be a plain `curl` read. Codex's own check, where
    /// Codex runs ordinary commands in its sandbox with the network open and no reviewer sees them.
    static func mayChangeADevice(_ command: String) -> Bool { !devicesChanged(by: command).isEmpty }

    /// The home network's addresses and `.local` names a command reaches other than by a plain `curl` read, lowercased.
    static func devicesChanged(by command: String) -> Set<String> {
        let home = #"\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b|\b[A-Za-z0-9][A-Za-z0-9-]*\.local\b"#
        let writes = #"(^|\s)(-X|--request)\s*(?!GET\b)\S|(^|\s)(-d|--data[a-z-]*|--json|-F|--form|-T|--upload-file)(\s|=|$)"#
        var reached: Set<String> = []
        for part in command.components(separatedBy: CharacterSet(charactersIn: ";|&\n")) {
            let part = part.trimmingCharacters(in: .whitespaces)
            guard let regex = try? NSRegularExpression(pattern: home) else { continue }
            let hosts = regex.matches(in: part, range: NSRange(part.startIndex..., in: part))
                .compactMap { Range($0.range, in: part).map { part[$0].lowercased() } }
            guard !hosts.isEmpty, !part.hasPrefix("curl ") || part.range(of: writes, options: .regularExpression) != nil else { continue }
            reached.formUnion(hosts)
        }
        return reached
    }

    static let commandRefusal = "This reaches a device on the person's network in a way that could change it. Ask with `device_permission` first; to read a device, use a plain `curl` GET."

    /// What `use_app` says on an app that reaches devices before the person has allowed one.
    static let useRefusal = "This app controls the person's devices: use it only on a device they've allowed, named in `device` as on Lamp's card. Ask with `device_permission` first for a device they haven't allowed, naming it and what you'd press."
}
