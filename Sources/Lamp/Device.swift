import Foundation
import AppKit

/// One device the person owns, as Lamp read it from the device itself: never a kind guessed by a model, but
/// the exact model, its software and what sets it apart, so a wish is built for the device it lands on. The
/// Mac is read from its own hardware and displays; iPhones, iPads and Apple Watches from Xcode's device list.
/// Every kind of device Lamp comes to support fills the same record, and the lists (Try On, Settings →
/// Building) and the agent's note read nothing but it.
struct Device: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case mac, iphone, ipad, watch
        var name: String {
            switch self {
            case .mac: return "Mac"
            case .iphone: return "iPhone"
            case .ipad: return "iPad"
            case .watch: return "Apple Watch"
            }
        }
        var symbol: String {
            switch self {
            case .mac: return "laptopcomputer"
            case .iphone: return "iphone"
            case .ipad: return "ipad"
            case .watch: return "applewatch"
            }
        }
        /// An iPhone or iPad: where Play can put an app directly.
        var isPhone: Bool { self == .iphone || self == .ipad }
    }

    /// A screen, in pixels and in the points an app lays out in.
    struct Screen: Hashable {
        let name: String
        let width: Int     // pixels
        let height: Int
        let scale: Int     // pixels per point
        var words: String { "\(width / scale)×\(height / scale) points at \(scale)x" }
    }

    /// How Lamp reaches the device to put software on it.
    enum Reach: Hashable {
        case thisMac
        case cable
        case network
        /// A watch goes with its iPhone's app; Lamp never reaches it on its own.
        case throughPhone
        var words: String {
            switch self {
            case .thisMac: return "this Mac"
            case .cable: return "plugged in"
            case .network: return "on the network"
            case .throughPhone: return "through its iPhone"
            }
        }
    }

    /// Where the device's setup stands. Nothing is set up in advance: the next step is what the list shows
    /// beside a device, and what a wish for it does first.
    enum Setup: Hashable {
        case ready
        /// The next step, in a short line for the list.
        case needs(String)
        /// Nothing runs on it; it can only be talked to. No Apple device is one, but the shape is shared.
        case talkOnly
        var words: String {
            switch self {
            case .ready: return "Ready"
            case .needs(let step): return step
            case .talkOnly: return "Can only be talked to"
            }
        }
    }

    /// The udid for a device of Xcode's; this Mac is `Device.macID`.
    let id: String
    let kind: Kind
    let maker: String
    /// "iPhone 16 Pro Max", "MacBook Pro".
    let model: String
    /// "iPhone17,2", "Mac16,5".
    let modelID: String
    /// The person's own name for it ("Celsius", "Matt's Mac").
    let name: String
    /// "iOS", "watchOS", "macOS", and its version ("27.0").
    let os: String
    let osVersion: String
    var screens: [Screen] = []
    /// How it's used: "touch", "keyboard", "pointer", "Digital Crown".
    var input: [String] = []
    /// What changes what's built: "Dynamic Island", "HealthKit", "NFC", a chip.
    var features: [String] = []
    var reach: Reach
    /// Xcode's device list says these of a phone or watch: trusted this Mac for development, Developer Mode on,
    /// a tunnel open now (opened on demand, so false says little).
    var paired = true
    var developerMode = true
    var connected = true
    /// A watch's: whether an iPhone it can go with is set up, read off the list it came in.
    var companionReady = false

    static let macID = "this-mac"

    var udid: String { id }
    var family: DeviceFamily? { kind == .ipad ? .ipad : kind == .iphone ? .iphone : nil }
    var osMajor: String { String(osVersion.split(separator: ".").first ?? Substring(osVersion)) }

    /// Where its setup stands, given the team apps are signed for (Settings → Building): a phone needs
    /// pairing, Developer Mode and a team before Play can put an app on it; a watch goes with its iPhone.
    func setup(team: String = Devices.team) -> Setup {
        switch kind {
        case .mac: return .ready
        case .iphone, .ipad:
            if !paired { return .needs("Pair it with this Mac") }
            if !developerMode { return .needs("Turn on Developer Mode on it") }
            if team.count != 10 { return .needs("Choose your Apple team") }
            return .ready
        case .watch:
            return companionReady ? .ready : .needs("Set up the iPhone it's paired with")
        }
    }

    /// The model and software, in one line for a list: "iPhone 16 Pro Max · iOS 27".
    var line: String { "\(model) · \(os) \(osMajor)" }

    /// The device as the agent is told it: "iPhone 16 Pro Max, iOS 27, Dynamic Island".
    var forAgent: String {
        var parts = ["\(model), \(os) \(osMajor)"]
        parts += features
        for screen in screens { parts.append("screen \(screen.words)") }
        return parts.joined(separator: ", ")
    }

    /// `thisMac` with its hardware read off the main thread: the system's profile takes a moment the first time.
    @MainActor static func readThisMac() async -> Device {
        _ = await Task.detached { macHardware }.value
        return thisMac()
    }

    /// This Mac, from its own hardware (its model and chip, read once) and the displays on it now.
    @MainActor static func thisMac() -> Device {
        let hardware = macHardware
        let screens = NSScreen.screens.map { screen in
            let scale = Int(screen.backingScaleFactor.rounded())
            return Screen(name: screen.localizedName, width: Int(screen.frame.width * screen.backingScaleFactor),
                          height: Int(screen.frame.height * screen.backingScaleFactor), scale: max(scale, 1))
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return Device(id: macID, kind: .mac, maker: "Apple", model: hardware.model, modelID: hardware.modelID,
                      name: Host.current().localizedName ?? "This Mac", os: "macOS",
                      osVersion: "\(version.majorVersion).\(version.minorVersion)", screens: screens,
                      input: ["keyboard", "pointer"], features: hardware.chip.map { [$0] } ?? [], reach: .thisMac)
    }

    /// The Mac's model id (`hw.model`) and, from the system's own profile, its marketing name and chip. The
    /// profile takes a moment and the hardware doesn't change, so it's read once.
    private static let macHardware: (model: String, modelID: String, chip: String?) = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: size + 1)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        let modelID = String(cString: bytes).nilIfEmpty ?? "Mac"
        let profile = Subprocess.runBlocking("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json"], mergeErrors: false, timeout: 20).output
        let hardware = (profile.data(using: .utf8)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["SPHardwareDataType"] as? [[String: Any]])?.first ?? [:]
        return (hardware["machine_name"] as? String ?? "Mac", modelID, hardware["chip_type"] as? String)
    }()

    /// A device from one entry of Xcode's device list (`devicectl list devices`): an iPhone, iPad or Apple Watch
    /// the person owns. Nil for a simulator or a kind Lamp doesn't make apps for.
    static func from(devicectl entry: [String: Any]) -> Device? {
        let hardware = entry["hardwareProperties"] as? [String: Any] ?? [:]
        let properties = entry["deviceProperties"] as? [String: Any] ?? [:]
        let connection = entry["connectionProperties"] as? [String: Any] ?? [:]
        guard hardware["reality"] as? String == "physical", let udid = hardware["udid"] as? String else { return nil }
        let kind: Kind
        switch hardware["deviceType"] as? String {
        case "iPhone": kind = .iphone
        case "iPad": kind = .ipad
        case "appleWatch": kind = .watch
        default: return nil
        }
        let productType = hardware["productType"] as? String ?? ""
        let model = hardware["marketingName"] as? String ?? kind.name
        let os = hardware["platform"] as? String ?? (kind == .watch ? "watchOS" : "iOS")
        var device = Device(id: udid, kind: kind, maker: "Apple", model: model, modelID: productType,
                            name: properties["name"] as? String ?? model, os: os,
                            osVersion: properties["osVersionNumber"] as? String ?? "",
                            input: kind == .watch ? ["touch", "Digital Crown"] : ["touch"],
                            features: features(kind: kind, productType: productType),
                            reach: kind == .watch ? .throughPhone : connection["transportType"] as? String == "wired" ? .cable : .network)
        device.connected = connection["tunnelState"] as? String == "connected" || properties["ddiServicesAvailable"] as? Bool == true
        device.paired = connection["pairingState"] as? String == "paired"
        device.developerMode = properties["developerModeStatus"] as? String == "enabled"
        return device
    }

    /// What a device has that changes what's built for it, read off its product type. The Dynamic Island is
    /// on every iPhone from the 14 Pro (iPhone15,2) on, but the 16e (iPhone17,5).
    static func features(kind: Kind, productType: String) -> [String] {
        switch kind {
        case .iphone:
            var features: [String] = []
            if let generation = Int(productType.dropFirst("iPhone".count).split(separator: ",").first ?? ""),
               generation >= 15, productType != "iPhone17,5" {
                features.append("Dynamic Island")
            }
            return features + ["NFC", "HealthKit"]
        case .watch: return ["HealthKit"]
        case .ipad, .mac: return []
        }
    }
}

// MARK: - What the agent is told

/// The line on the device a request is for, at the end of the request, in the shape `Device.forAgent` gives:
/// the exact device, never a kind. Like `AIStatus` it rides with the request rather than the system prompt,
/// which Claude Code and Codex keep from a conversation's start, and is sent once per conversation and again
/// only when it changes (Try On moved, a phone's software updated), so most requests carry nothing.
enum DeviceNote {
    @MainActor static func line(for project: LampProject, store: Store) -> String {
        let phones = store.devices.filter { $0.kind.isPhone }
        if project.onIOS {
            if let udid = project.device, let phone = phones.first(where: { $0.udid == udid }) {
                return "Try On points at the person's \(phone.name): \(phone.forAgent)."
            }
            let simulator = project.simulator.flatMap { udid in store.simulators.first { $0.udid == udid } }
            var line = simulator.map { "Try On points at the \($0.name) simulator, iOS \($0.runtime.map(String.init).joined(separator: "."))." }
                ?? "Try On points at the \(project.family.name) simulator."
            // The phones the person has, exactly, with what each still needs: the app is for one of them in the
            // end, and what it has (a Dynamic Island, say) matters before it ever goes there.
            for phone in phones {
                let state = phone.setup() == .ready ? "set up for the app to go on it" : "not set up yet (next: \(phone.setup().words.lowercased()))"
                line += " The person's \(phone.name) (\(phone.forAgent)) is \(state)."
            }
            return line
        }
        let mac = store.thisMac ?? Device.thisMac()
        return "It opens on this Mac: \(mac.forAgent)."
    }

    @MainActor static func brief(for project: LampProject, engine: Engine, session: String?) -> String {
        let now = line(for: project, store: .shared)
        switch note.telling(now, for: project, engine: engine, session: session) {
        case .fresh: return "\n\n---\nThe device this app is for (from Lamp, not part of the request above): \(now)"
        case .changed: return "\n\n---\nThe device this app is for has changed (from Lamp, not part of the request above): \(now)"
        case .nothing: return ""
        }
    }

    /// The agent answered, so the request and the line in it arrived.
    @MainActor static func delivered(to project: LampProject, session: String? = nil) { note.delivered(to: project, session: session) }

    /// The engine summed up its conversation: the line may be gone from it, so the next request says it again.
    @MainActor static func compacted(_ project: LampProject) { note.compacted(project) }

    @MainActor private static let note = RequestNote(file: ".lamp/device-shown.json")
}
