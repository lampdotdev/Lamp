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
    /// network or Bonjour types in capabilities.json. A game's phones aren't devices it controls, and need no declaration:
    /// the relay they join is Lamp's own, in the game (`GamePhones`), which gives the reason the system shows itself. So
    /// what a game declares is taken as being for devices, unless it's known to be only for its phones
    /// (`declaresNetworkOnlyForPhones`).
    static func reachesDevices(_ app: LampProject) -> Bool {
        let capabilities = Template.Capabilities.load(app).checked
        let declared = capabilities.localNetwork != nil || !(capabilities.bonjourServices ?? []).isEmpty
        return (declared && !declaresNetworkOnlyForPhones(app)) || Skills.appSwift(of: app, matches: #"\b(LampRoku|LampNetwork)\b"#)
    }

    /// Whether a game's local network declaration is known to be for its phones and nothing else: its reason is the very
    /// sentence Lamp gives a game's phones (`GamePhones.iosNetworkReason`, with the game's name), it has a phone page, and
    /// nothing else of a device controller (Bonjour types to look for, Lamp's own wish service aside; Lamp's blocks for
    /// devices in Swift of its own). A reason in the game's own words, whatever it says, can't be told apart from one for
    /// devices, so it counts as reaching them. The declaration itself stays as the game wrote it.
    static func declaresNetworkOnlyForPhones(_ app: LampProject) -> Bool {
        guard hostsPhonesAndDeclaresNetwork(app), let reason = Template.Capabilities.load(app).checked.localNetwork else { return false }
        let lamps = GamePhones.iosNetworkReason.replacingOccurrences(of: "{{NAME}}", with: app.name)
        return plain(reason) == plain(lamps)
    }

    /// A web game with a phone page that declares the local network, and nothing else a device controller has.
    private static func hostsPhonesAndDeclaresNetwork(_ app: LampProject) -> Bool {
        guard GameKit.isGame(app), GameKit.engine(app) == .web, !GameKit.ownsLoop(app) else { return false }
        let capabilities = Template.Capabilities.load(app).checked
        return capabilities.localNetwork != nil && (capabilities.bonjourServices ?? []).allSatisfy({ $0 == Template.wishServiceType })
            && FileManager.default.fileExists(atPath: app.dir.appendingPathComponent(TVTemplate.phoneFolder).appendingPathComponent("index.html").path)
            && !Skills.appSwift(of: app, matches: #"\b(LampRoku|LampNetwork)\b"#)
    }

    /// A sentence as it's compared: case, spacing, the kind of hyphen and a closing period aside.
    private static func plain(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "\u{2011}", with: "-")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    /// Said after a refusal, for a game whose declaration may be only for its phones from an older Lamp (it has a phone
    /// page, and its own page code names no address on the home network nor a `.local` name): why it's asked about all
    /// the same. Only ever an explanation: what the page's code names decides nothing.
    static func whyAsked(_ app: LampProject) -> String {
        guard hostsPhonesAndDeclaresNetwork(app), !declaresNetworkOnlyForPhones(app), !pageNamesHomeNetwork(app) else { return "" }
        return " Its capabilities.json declares the local network, which may be only for its phones (a game made by an older Lamp; "
            + "its page names no device's address), but Lamp can't tell that apart from controlling a device, so it asks all the same."
    }

    /// Whether the game's own page code (Web/ and src/, Lamp's files and libraries aside) names an address on the home
    /// network or a `.local` name.
    private static func pageNamesHomeNetwork(_ app: LampProject) -> Bool {
        let home = #"\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b|\b[A-Za-z0-9][A-Za-z0-9-]*\.local\b"#
        let lamps: Set<String> = ["three", "rapier", "phaser"]
        for folder in [GameKit.webFolder, "src"] {
            guard let walk = FileManager.default.enumerator(at: app.dir.appendingPathComponent(folder), includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walk {
                if url.hasDirectoryPath, lamps.contains(url.lastPathComponent) { walk.skipDescendants(); continue }
                guard ["js", "mjs", "ts", "html", "json"].contains(url.pathExtension.lowercased()), !url.lastPathComponent.hasPrefix("lamp"),
                      let text = AppFile.text(url, in: app) else { continue }
                if text.range(of: home, options: .regularExpression) != nil { return true }
            }
        }
        return false
    }

    /// Whether a `use_app` call on the app has to name a device the person allowed: whenever it reaches devices. A game
    /// is used in the window the person plays it in, on the real network, as every app is.
    static func useNeedsDevice(_ app: LampProject) -> Bool {
        reachesDevices(app)
    }

    /// Whether a look that opens a game or starts it again has to name a device the person allowed: a game that reaches
    /// devices runs that code as it starts, with no one pressing anything.
    static func openNeedsDevice(_ app: LampProject) -> Bool {
        GameKit.isGame(app) && reachesDevices(app)
    }

    /// The card: one question, three answers, only the person's to give.
    /// Whether what answers at an address now is set up with Lamp: a set-up device that's away keeps its last address,
    /// which another device may have taken, so it doesn't count.
    static func setUp(at address: String, among devices: [Device]) -> Bool {
        let here = devices.filter { $0.address?.lowercased() == address.lowercased() && !$0.isAway }
        return !here.isEmpty && here.allSatisfy(\.isSetUp)
    }

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
    static let openRefusal = "This game controls the person's devices, and opening it or starting it again runs that code: do it only with a device they've allowed, named in `device` as on Lamp's card. Ask with `device_permission` first for a device they haven't allowed, naming it and that the game opens. A look at the game while it's open needs none."

    /// Why a change waits for Reload in a game that reaches devices with none allowed (`Store.mayRunChange`).
    static let heldForDevices = "the game controls the person's devices, and its new code runs only with a device they've allowed"

    /// What the agent hears of such a change.
    static let heldRefusal = "it controls the person's devices, and its new code runs only with a device they've allowed on Lamp's card, so it waits for the person's Reload, which puts it in: don't say it's in. Once they've allowed a device (ask with `device_permission`, naming it and that the game's changes go in) and that Reload is done, your changes go in as you save them."

    static let useRefusal = "This app controls the person's devices: use it only on a device they've allowed, named in `device` as on Lamp's card. Ask with `device_permission` first for a device they haven't allowed, naming it and what you'd press."
}
