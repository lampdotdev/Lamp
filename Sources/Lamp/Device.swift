import Foundation
import AppKit

/// One device the person owns, as Lamp read it from the device itself: never a kind guessed by a model, but
/// the exact model, its software and what sets it apart, so a wish is built for the device it lands on. The
/// Mac is read from its own hardware and displays; iPhones, iPads and Apple Watches from Xcode's device list.
/// Every kind of device Lamp comes to support fills the same record, and the lists (Try On, Settings →
/// Building) and the agent's note read nothing but it.
struct Device: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case mac, iphone, ipad, watch, android, androidEmulator, samsungTV, lgTV
        /// A device found by an integration (`Integration`), or one on the network nothing Lamp has knows yet.
        case other
        var name: String {
            switch self {
            case .mac: return "Mac"
            case .iphone: return "iPhone"
            case .ipad: return "iPad"
            case .watch: return "Apple Watch"
            case .android: return "Android device"
            case .androidEmulator: return "Android emulator"
            case .samsungTV: return "Samsung TV"
            case .lgTV: return "LG TV"
            case .other: return "Device"
            }
        }
        var symbol: String {
            switch self {
            case .mac: return "laptopcomputer"
            case .iphone: return "iphone"
            case .ipad: return "ipad"
            case .watch: return "applewatch"
            case .android, .androidEmulator: return "smartphone"
            case .samsungTV, .lgTV: return "tv"
            case .other: return "dot.radiowaves.left.and.right"
            }
        }
        /// An iPhone or iPad: where Play can put an app directly.
        var isPhone: Bool { self == .iphone || self == .ipad }
        /// An Android phone or tablet of the person's, or the emulator on this Mac.
        var isAndroid: Bool { self == .android || self == .androidEmulator }
        /// A TV a web app goes on (`TVs`).
        var isTV: Bool { self == .samsungTV || self == .lgTV }
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
    /// A watch's: whether the list it came in holds an iPhone its app can go with, paired with this Mac with
    /// Developer Mode on. The team is judged when the watch's setup is asked, as a phone's is, so a team chosen
    /// after the list was read counts at once.
    var hasCompanionIPhone = false
    /// An Android device's state as adb lists it: "device" (usable), "unauthorized" (debugging not yet allowed to
    /// this Mac), "offline".
    var adbState = "device"
    /// An Android device's pixels per inch, for turning its pictures' pixels into points.
    var density: Int?
    /// A TV's address on the network, and a Samsung TV's device id, which its certificate names.
    var address: String?
    var duid: String?
    /// The integration that found it; nil for a device on the network Lamp doesn't know yet.
    var integration: String?
    /// For a device Lamp doesn't know: what it said when it was found, for whoever writes its integration.
    var discovery: String?

    static let macID = "this-mac"

    var udid: String { id }
    /// A TV or other device Lamp reaches over the network that didn't answer the last look: off, or on another network
    /// (a home elsewhere). Its setup is kept as it was, but nothing can be put on it, or set up, until it's found
    /// again. Not a phone: Xcode opens a phone's connection only when it's needed, so its `connected` says little.
    var isAway: Bool { (kind.isTV || kind == .other) && reach == .network && !connected }
    /// Where it stands for a list: "Not on this network" while it's away, else its setup's words.
    var status: String { isAway ? "Not on this network" : setup().words }
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
            if !hasCompanionIPhone { return .needs("Set up the iPhone it's paired with") }
            if team.count != 10 { return .needs("Choose your Apple team") }
            return .ready
        case .androidEmulator:
            return adbState == "device" ? .ready : .needs("Start it again")
        case .android:
            switch adbState {
            case "device": return .ready
            case "unauthorized": return .needs("Allow USB debugging on it")
            case "offline": return .needs("Reconnect it")
            default: return .needs("Turn on USB debugging on it")
            }
        case .samsungTV:
            // `paired` is kept (a setup step worked); `developerMode`, pointed at this Mac.
            if !developerMode { return .needs("Turn on developer mode on it") }
            if !paired || duid == nil { return .needs("Connect to it") }
            if !TizenSigning.hasCertificates(for: duid ?? "") { return .needs("Sign in to Samsung") }
            return .ready
        case .lgTV:
            return developerMode ? .ready : .needs("Turn on Developer Mode on it")
        case .other:
            guard integration != nil else { return .needs("Lamp could learn to work with this") }
            return Integrations.next(for: self).map { .needs($0.title) } ?? .ready
        }
    }

    /// The address in the id of a device found on the network that Lamp doesn't know yet ("found:<address>", with
    /// "#<hardware address>" after it when the look knew that), and the hardware address.
    static func foundAddress(_ id: String) -> String? {
        guard id.hasPrefix("found:") else { return nil }
        return String(id.dropFirst("found:".count)).components(separatedBy: "#").first
    }

    static func foundHardware(_ id: String) -> String? {
        guard id.hasPrefix("found:"), let mark = id.firstIndex(of: "#") else { return nil }
        return String(id[id.index(after: mark)...])
    }

    /// What it is rather than what it's called, for one found on the network that Lamp doesn't know yet: the name a
    /// device gives itself there is often a person's, and this one is written into its setup conversation's folder.
    var plainName: String {
        guard id.hasPrefix("found:") else { return name }
        if maker.isEmpty || model.localizedCaseInsensitiveContains(maker) { return model.nilIfEmpty ?? "Device" }
        return model.isEmpty || model == maker ? maker : "\(maker) \(model)"
    }

    /// The model and software, in one line for a list: "iPhone 16 Pro Max · iOS 27".
    var line: String {
        if kind == .other { return [model, [os, osVersion].filter { !$0.isEmpty }.joined(separator: " ")].filter { !$0.isEmpty }.joined(separator: " · ") }
        return "\(model) · \(os) \(kind.isTV ? osVersion : osMajor)"
    }

    /// The device as the agent is told it: "iPhone 16 Pro Max, iOS 27, Dynamic Island".
    var forAgent: String {
        // A TV's software version is told whole (Tizen 6.5): its apps differ by the point release. An LG TV's is read
        // only once Lamp can reach it, so until then it's said to be unknown rather than left out.
        let version = kind.isTV ? (osVersion.isEmpty ? "version unknown" : osVersion) : osMajor
        var parts = ["\(kind.isTV ? maker + " " + model : model), \(os) \(version)"]
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

    /// An Android device from adb's listing and its own properties (`Adb.getprop`): the emulator Lamp made, or the
    /// person's phone or tablet, plugged in (a plain serial) or on the network (an address and port).
    static func from(adb serial: String, state: String, properties: [String: String]) -> Device {
        let emulator = serial.hasPrefix("emulator-") || properties["ro.kernel.qemu"] == "1" || properties["ro.boot.qemu"] == "1"
        let maker = properties["ro.product.manufacturer"].flatMap { $0.isEmpty ? nil : $0 } ?? (emulator ? "Google" : "Android")
        let model = properties["ro.product.model"].flatMap { $0.isEmpty ? nil : $0 }
        // A TV (Google TV, Android TV, Fire TV, Lamp's TV emulator) has the leanback feature.
        let tv = properties["leanback"] == "true"
        let name = emulator ? (tv ? AndroidTools.tvAVDName : AndroidTools.avdName) : (model.map { "\(maker) \($0)" } ?? (tv ? "Android TV" : "Android device"))
        var device = Device(id: serial, kind: emulator ? .androidEmulator : .android, maker: maker,
                            model: emulator ? "Android emulator" : (model ?? "Android device"),
                            modelID: properties["ro.product.device"] ?? "", name: name, os: "Android",
                            osVersion: properties["ro.build.version.release"] ?? "",
                            input: [tv ? "remote" : "touch"], features: tv ? ["tv"] : [], reach: emulator ? .thisMac : serial.contains(":") ? .network : .cable)
        device.adbState = state
        device.density = properties["density"].flatMap { Int($0) }
        if let size = properties["size"], let density = device.density {
            let parts = size.split(separator: "x").compactMap { Int($0) }
            if parts.count == 2 { device.screens = [Screen(name: "screen", width: parts[0], height: parts[1], scale: max(1, Int((Double(density) / 160).rounded())))] }
        }
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
        case .ipad, .mac, .android, .androidEmulator, .samsungTV, .lgTV, .other: return []
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
        let here = place(for: project, store: store)
        // A game says every place it's played and what the slowest allows, then where Try On points.
        return GameKit.isGame(project) ? Agent.Rules.gamePlaces(project) + " " + here
            : ScreenKit.isScreen(project) ? Agent.Rules.screenPlaces(project) + " " + here : here
    }

    @MainActor private static func place(for project: LampProject, store: Store) -> String {
        let phones = store.devices.filter { $0.kind.isPhone }
        if project.onDevice {
            let name = DeviceApps.integration(for: project)?.name ?? "device"
            let mine = store.devices.filter { $0.integration != nil && $0.integration == project.deviceIntegration }
            guard !mine.isEmpty else { return "No \(name) of the person's has been found on the network yet; the app goes on one once it's found and set up." }
            return mine.map { device in
                let state = device.setup() == .ready ? "set up for apps" : "not set up yet (next: \(device.setup().words.lowercased()))"
                let chosen = device.id == project.device || (project.device == nil && mine.count == 1)
                let place = device.isAway ? " Lamp doesn't find it on the network now, so nothing can be put on it until it's back." : ""
                return "\(chosen ? "The app goes on" : "Also known:") the person's \(device.name) (\(device.forAgent)), \(state).\(place)"
            }.joined(separator: " ")
        }
        if project.onTV {
            let onTV = Runtime.onTV(project)
            return tv(previewOpen: TVPreview.isOpen(project), chosen: project.device, tvs: store.devices.filter { $0.kind.isTV },
                      onTV: onTV, current: onTV.isEmpty ? "" : Runtime.fingerprint(project))
        }
        if project.onAndroid {
            let androids = store.devices.filter { $0.kind == .android }
            var line: String
            if let serial = project.device {
                line = androids.first(where: { $0.udid == serial }).map { "Try On points at the person's \($0.name): \($0.forAgent)." }
                    ?? (store.androidListed ? "Try On points at one of the person's Android devices, which Lamp's device list didn't return; it's put there once it's connected."
                        : "Try On points at one of the person's Android devices, which Lamp hasn't looked for yet; Play puts it there once it's connected.")
            } else {
                line = "Try On points at the Android emulator on this Mac (\(AndroidTools.avdName), Android \(AndroidTools.platformLevel == 36 ? "16" : "\(AndroidTools.platformLevel)"), a Pixel-sized phone): that is where the app opens and what the person sees."
            }
            for device in androids where device.udid != project.device {
                let state = device.setup() == .ready ? "set up for the app to go on it" : "not set up yet (next: \(device.setup().words.lowercased()))"
                line += " The person's \(device.name) (\(device.forAgent)) is \(state)."
            }
            // Only once adb has been asked: before, Lamp doesn't know whether one is connected.
            if androids.isEmpty, store.androidListed {
                line += " No Android phone or tablet of the person's is connected to this Mac, so call it the emulator, never their phone; they can plug one in and choose it under Try On."
            }
            return line
        }
        // What a free team can't sign, said for any app with an iPhone half wherever Try On points (an app for both on this
        // Mac is signed for the team too), since it changes what to declare.
        let freeTeam = project.hasIOS && PhoneTools.xcodeFreeTeams().contains(Devices.team) ? " " + TeamLimits.agentLine : ""
        if project.onIOS {
            if let udid = project.device {
                // Chosen, but not in the list (away, or the lookup failed): still where Play puts the app.
                guard let phone = phones.first(where: { $0.udid == udid }) else {
                    return "Try On points at one of the person's phones, which Lamp's device list didn't return; Play still puts the app there once it's connected." + freeTeam
                }
                return "Try On points at the person's \(phone.name): \(phone.forAgent)." + freeTeam
            }
            let simulator = project.simulator.flatMap { udid in store.simulators.first { $0.udid == udid } }
            var line = simulator.map { "Try On points at the \($0.name) simulator, \($0.family.os) \($0.runtime.map(String.init).joined(separator: "."))." }
                ?? "Try On points at the \(project.family.name) simulator."
            if project.family.isOtherOS { line += " " + Agent.Rules.otherOS(project.family) }
            // The phones the person has, exactly, with what each still needs: the app is for one of them in the
            // end, and what it has (a Dynamic Island, say) matters before it ever goes there.
            for phone in phones {
                let state = phone.setup() == .ready ? "set up for the app to go on it" : "not set up yet (next: \(phone.setup().words.lowercased()))"
                line += " The person's \(phone.name) (\(phone.forAgent)) is \(state)."
            }
            return line + freeTeam
        }
        let mac = store.thisMac ?? Device.thisMac()
        return (GameKit.isGame(project) ? "It opens in its window on this Mac: \(mac.forAgent)." : "It opens on this Mac: \(mac.forAgent).") + freeTeam
    }

    /// Where a TV app is, from what Lamp has seen: the preview, which the agent's tools reach, and each of the person's
    /// TVs, which they don't. A TV found on the network is only that: Lamp hasn't asked it what it's running, so that
    /// stays unknown, and the agent is left to find out what else it can learn of it rather than being told it can't.
    static func tv(previewOpen: Bool, chosen: String?, tvs: [Device], onTV: [String: Runtime.OnTV], current: String) -> String {
        var line = "The TV preview, a window on this Mac with a remote's keys, is \(previewOpen ? "open" : "closed") now; "
            + "look_at_app and use_app reach only the preview."
        if chosen == nil { line += " Try On points at the preview, so Play opens the app there." }
        if let chosen, !tvs.contains(where: { $0.udid == chosen }) {
            line += " Try On points at one of the person's TVs, which Lamp doesn't find on the network now."
        }
        for tv in tvs.sorted(by: { ($0.udid == chosen ? 0 : 1, $0.name) < ($1.udid == chosen ? 0 : 1, $1.name) }) {
            var facts = [tv.forAgent]
            if tv.screens.isEmpty { facts.append("screen size unknown") }
            line += " The person's \(tv.name) (\(facts.joined(separator: ", ")))"
            line += tv.udid == chosen ? " is chosen under Try On, so Play puts the app on it." : " isn't chosen under Try On."
            line += tv.connected ? " Lamp finds it on the network now." : " Lamp doesn't find it on the network now."
            if tv.setup() != .ready { line += " It isn't set up for apps yet (next: \(tv.setup().words.lowercased()))." }
            if let put = onTV[tv.udid] {
                line += " Lamp last put this app on it and opened it at \(put.at.formatted(date: .abbreviated, time: .shortened)), "
                    + (put.fingerprint == current ? "with the code as it is now." : "and the code has changed since.")
            } else {
                line += " Lamp has no record of putting this app on it."
            }
        }
        if tvs.isEmpty, chosen == nil { line += " No TV of the person's has been found on the network." }
        if chosen != nil || !tvs.isEmpty {
            line += " Whether the app is running on a TV now, and how it looks or runs there, Lamp doesn't know. "
                + "You might be able to get a screenshot or other state from the TV another way: take a look if it matters."
        }
        return line
    }

    @MainActor static func brief(for project: LampProject, engine: Engine, session: String?) -> String {
        // A wish whose apps are all in folders of their own is on no device itself: where each opens is the wish's note.
        // A game or a screen in a folder of its own still has its places and budget said here, as one in the wish's own
        // folder has: they change with its places and with Try On, which no note of the wish's says.
        let own = project.holdsApp ? [line(for: project, store: .shared)] : []
        let placed = project.isPart ? [] : Store.shared.parts(of: project).filter(\.platform.addsPlaces).map { part in
            "\(Parts.name(of: part).prefix(1).uppercased() + Parts.name(of: part).dropFirst()) in \(part.dir.lastPathComponent)/: "
                + line(for: part, store: .shared)
        }
        // And every device of the person's Lamp knows, with what each can run, so an app is made for the ones they have:
        // said for a wish whose apps are all in folders of their own too.
        let known = Places.known(Store.shared.devices)
        guard !own.isEmpty || !placed.isEmpty || !known.isEmpty else { return "" }
        let now = (own + placed + (known.isEmpty ? [] : [known])).joined(separator: "\n")
        let what = own.isEmpty && placed.isEmpty ? "The person's devices" : placed.isEmpty ? "The device this app is for"
            : own.isEmpty ? "Where the wish's game or screen is" : "The devices this wish's apps are for"
        switch note.telling(now, for: project, engine: engine, session: session) {
        case .fresh: return "\n\n---\n\(what) (from Lamp, not part of the request above): \(now)"
        case .changed: return "\n\n---\n\(what), changed (from Lamp, not part of the request above): \(now)"
        case .nothing: return ""
        }
    }

    /// The agent answered, so the request and the line in it arrived.
    @MainActor static func delivered(to project: LampProject, session: String? = nil) { note.delivered(to: project, session: session) }

    /// The engine summed up its conversation: the line may be gone from it, so the next request says it again.
    @MainActor static func compacted(_ project: LampProject) { note.compacted(project) }

    @MainActor private static let note = RequestNote(file: ".lamp/device-shown.json")
}
