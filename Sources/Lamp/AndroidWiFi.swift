import Combine
import AppKit
import SwiftUI

/// Connecting an Android device over Wi‑Fi: the only way to reach most TVs (a Google TV, an Android TV, a Fire TV),
/// which have no cable to plug into a Mac, and handy for a phone. adb does it: a device with Wireless debugging pairs
/// with a code it shows (`adb pair`), and adb then connects to it by itself, as it does each time it sees the device
/// again; a Fire TV connects on port 5555 once its ADB debugging is on, and asks on its screen whether to allow this
/// Mac. Once connected, adb lists it like a device on a cable (`Adb.devices`), a TV under a record of Lamp's
/// (`AndroidTVs`), and Try On offers it.
///
/// The window goes by what each device shows now, not by a fixed order of steps: one this Mac is already allowed on
/// is ready, one offering to pair needs only its code (sent once the six digits are in), a Fire TV's old port is
/// connected to, and one that shows nothing yet gets the steps on its remote. A TV found on the network that has no
/// debugging on yet (`AndroidTVs.found`) is listed with those steps.
@MainActor
final class AndroidWiFi: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = AndroidWiFi()

    /// A device on the network that's offering to pair or to connect, as adb's own search finds it, or a TV the look
    /// on the network found with nothing of adb's on yet. Each way in is its own port: pairing, Wireless debugging's
    /// connection, and the old adb port.
    struct Found: Identifiable, Equatable {
        var id: String { host }
        let host: String
        var name: String?
        var pairPort: Int?
        var connectPort: Int?
        var legacyPort: Int?
    }

    enum State: Equatable { case idle, working(String), done(String), failed(String) }

    @Published private(set) var found: [Found] = []
    @Published private(set) var selected: String?
    @Published var code = ""
    /// Typed by hand when adb's search can't see the device (another subnet, or the network blocks it): where its
    /// pairing screen says to pair, and where its Wireless debugging screen says to connect.
    @Published var pairingAddress = "" { didSet { if pairingAddress != oldValue { moveOn() } } }
    @Published var connectionAddress = "" { didSet { if connectionAddress != oldValue { moveOn() } } }
    @Published var typing = false { didSet { if typing != oldValue { moveOn() } } }
    @Published private(set) var state: State = .idle

    private var window: NSWindow?
    private var resizing: AnyCancellable?
    private var looking: Task<Void, Never>?
    /// Which device and which attempt the window is on now: an answer for one the person has moved on from, or for a
    /// window closed meanwhile, changes nothing.
    private var generation = UUID()
    /// The code and the pairing endpoint last sent, so a code is sent once, and only again once it's changed.
    private var sent: (code: String, endpoint: String)?
    /// A pairing or a connection is in flight, whichever device it was for: adb is asked one thing at a time.
    private var busy = false

    func show(host: String? = nil) {
        if window == nil {
            let (window, resizing) = FittedWindow.make(AndroidWiFiView(model: self), following: objectWillChange)
            self.resizing = resizing
            window.delegate = self
            window.title = "Connect Over Wi‑Fi"
            window.center()
            self.window = window
        }
        if let host { select(host) }
        AndroidTVs.settingUp = true
        // The look on the network names TVs with no debugging on yet; it's made once the person asks for this.
        if Store.shared.hosts.isEmpty { Store.shared.refreshDevices(everything: true) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // What a TV offers changes as the person turns things on and opens and closes its pairing screen.
        looking?.cancel()
        looking = Task { [weak self] in
            while !Task.isCancelled {
                let services = await Adb.networkServices()
                guard let self else { return }
                let named = AndroidTVs.found(in: Store.shared.hosts)
                self.found = AndroidWiFi.combine(services, named)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        AndroidTVs.settingUp = false
        looking?.cancel()
        looking = nil
        window = nil
        generation = UUID()
        selected = nil
        state = .idle
        code = ""
        sent = nil
    }

    func select(_ host: String) {
        guard selected != host else { return }
        selected = host
        moveOn()
        code = ""
        state = .idle
    }

    /// What the person typed or chose changed: an attempt still running is for something else now, and its answer
    /// changes nothing. It goes on to its end, and nothing new starts until it has (`busy`).
    private func moveOn() {
        generation = UUID()
        sent = nil
    }

    /// adb's search and the TVs the network look named, one entry per address.
    static func combine(_ services: [Found], _ named: [Found]) -> [Found] {
        var all = services
        for tv in named {
            if let index = all.firstIndex(where: { $0.host == tv.host }) { all[index].name = all[index].name ?? tv.name } else { all.append(tv) }
        }
        return all.sorted { $0.host < $1.host }
    }

    // MARK: Where a device stands

    enum Standing: Equatable {
        /// This Mac is allowed on it: it's in adb's listing, reading what it is.
        case ready(String)
        /// Its pairing screen is open.
        case pairing
        /// Wireless debugging is on, but this Mac isn't paired with it (or no longer is).
        case notPaired
        /// It offers adb's old port only: a Fire TV.
        case legacy
        /// It shows nothing of adb's yet.
        case nothing
    }

    func standing(of device: Found, among devices: [Device]) -> Standing {
        if let ready = devices.first(where: { $0.kind == .android && $0.address == device.host && $0.adbState == "device" }) { return .ready(ready.name) }
        if device.pairPort != nil { return .pairing }
        if device.connectPort != nil { return .notPaired }
        if device.legacyPort != nil { return .legacy }
        return .nothing
    }

    var current: Found? { selected.flatMap { host in found.first { $0.host == host } } }

    // MARK: Pairing

    /// The code as it's typed: digits only, six at most; once there are six, sent to the endpoint the TV offers, or the
    /// one typed by hand, if this code hasn't been sent there already.
    func codeChanged() {
        let digits = String(code.filter(\.isNumber).prefix(6))
        if digits != code { code = digits; return }
        guard digits.count == 6, !busy, let (host, port) = pairingEndpoint() else { return }
        let endpoint = "\(host):\(port)"
        if let sent, sent.code == digits, sent.endpoint == endpoint { return }
        sent = (digits, endpoint)
        pair(host: host, port: port, code: digits)
    }

    private func pairingEndpoint() -> (String, Int)? {
        if typing { return Self.endpoint(pairingAddress) }
        guard let current, let port = current.pairPort else { return nil }
        return (current.host, port)
    }

    /// "192.168.1.20:37123", on this Mac's network.
    static func endpoint(_ text: String) -> (String, Int)? {
        let parts = text.trimmed.split(separator: ":").map(String.init)
        guard parts.count == 2, let port = Int(parts[1]), (1...65535).contains(port), DeviceAddress.isPrivate(parts[0]) else { return nil }
        return (parts[0], port)
    }

    private func pair(host: String, port: Int, code: String) {
        let mine = generation
        busy = true
        state = .working("Pairing…")
        Task {
            defer { done(mine) }
            // Checked again once the address is free: a request that waited for it may be for a window since closed.
            let result = await AndroidTVs.exclusively("\(host):\(port)") { [self] () async -> Adb.Pairing? in
                guard mine == generation else { return nil }
                return await Adb.pair(host: host, port: port, code: code)
            }
            // A pairing that worked holds whatever the window does next: the TV is reached over Wireless debugging.
            if result == .paired { AndroidTVs.paired(at: host) }
            guard let result, mine == generation else { return }
            switch result {
            case .paired:
                self.code = ""
                await connectAfterPairing(host: host, generation: mine)
            case .wrongCode:
                // adb says the same when the code is wrong and when the screen closed meanwhile.
                self.code = ""
                sent = nil
                state = .failed("That code didn't work, or the pairing screen closed. Type the code the TV shows now.")
            case .unanswered:
                // The same code can go again once the screen is open again.
                sent = nil
                state = .failed("The TV's pairing screen didn't answer. Open Pair device with pairing code again, and keep it open.")
            }
        }
    }

    /// The end of a pairing or a connection. One the person moved on from leaves a code they typed meanwhile, for
    /// another device, to be sent now.
    private func done(_ mine: UUID) {
        busy = false
        if mine != generation { codeChanged() }
    }

    /// adb connects a device it has just paired with once its search sees the device's connection, so Lamp waits for
    /// that first; then it connects to the port the search shows, or the one typed from the TV's Wireless debugging
    /// screen. Never the old 5555 port: a device paired this way is reached the way it was paired.
    private func connectAfterPairing(host: String, generation mine: UUID) async {
        state = .working("Connecting…")
        for _ in 0..<8 {
            if await finishIfReady(host: host, generation: mine) { return }
            try? await Task.sleep(for: .seconds(1))
            guard mine == generation else { return }
        }
        let port = (await Adb.networkServices()).first { $0.host == host }?.connectPort
        guard mine == generation else { return }
        let typed = Self.endpoint(connectionAddress).flatMap { $0.0 == host && $0.1 != 5555 ? $0.1 : nil }
        guard let target = port ?? typed else {
            typing = true
            state = .failed("Paired. Now type the address and port the TV's Wireless debugging screen shows, under IP address & port.")
            return
        }
        _ = await AndroidTVs.exclusively("\(host):\(target)") { [self] () async -> Bool? in
            guard mine == generation else { return nil }
            return await Adb.connect(target: "\(host):\(target)")
        }
        guard mine == generation else { return }
        await waitUntilReady(host: host, generation: mine, seconds: 6)
    }

    /// Connects to the address and port typed from the TV's Wireless debugging screen, or a Fire TV's 5555.
    func connect() {
        guard !busy else { return }
        let target: (String, Int)?
        if typing {
            target = Self.endpoint(connectionAddress)
        } else if let current, let port = current.connectPort ?? current.legacyPort {
            target = (current.host, port)
        } else {
            target = nil
        }
        guard let (host, port) = target else {
            state = .failed("Type the address and port the TV shows, like 192.168.1.20:5555.")
            return
        }
        if AndroidTVs.requiresTLS(host), port == 5555 || current?.legacyPort == port {
            state = .failed("It's paired over Wireless debugging: type the port its Wireless debugging screen shows, not 5555.")
            return
        }
        let mine = generation
        busy = true
        state = .working("Connecting…")
        Task {
            defer { done(mine) }
            let connected = await AndroidTVs.exclusively("\(host):\(port)") { [self] () async -> Bool? in
                guard mine == generation else { return nil }
                return await Adb.connect(target: "\(host):\(port)")
            }
            guard let connected, mine == generation else { return }
            guard connected else {
                state = .failed(port == 5555 ? "The TV didn't answer. Check ADB debugging is on and it's on this Wi‑Fi."
                                             : "The TV didn't answer. Check Wireless debugging is on and it's on this Wi‑Fi.")
                return
            }
            // A Fire TV asks on its screen now; Lamp waits for the person's answer.
            await waitUntilReady(host: host, generation: mine, seconds: 60)
        }
    }

    private func waitUntilReady(host: String, generation mine: UUID, seconds: Int) async {
        for _ in 0..<seconds {
            if await finishIfReady(host: host, generation: mine) { return }
            guard mine == generation else { return }
            if (await Adb.devices()).contains(where: { $0.address == host && $0.adbState == "unauthorized" }) {
                guard mine == generation else { return }
                state = .working("On the TV, choose Allow, and tick Always allow.")
            }
            try? await Task.sleep(for: .seconds(1))
        }
        guard mine == generation else { return }
        state = .failed("Lamp connected, but the TV didn't let this Mac in. Try again, or pair it with a code.")
    }

    /// The device at an address that's ready: listed allowed and reading what it is.
    static func ready(at host: String, among devices: [Device], services: [AndroidTVs.Service], tls: Bool) -> Device? {
        devices.first { $0.kind == .android && $0.address == host && $0.adbState == "device" && (!tls || AndroidTVs.isTLS($0.adb, services: services)) }
    }


    /// Ready once adb lists the device at that address allowed and reading what it is.
    private func finishIfReady(host: String, generation mine: UUID) async -> Bool {
        let services = AndroidTVs.services((await Adb.run(["mdns", "services"], timeout: 10)).output)
        guard let device = Self.ready(at: host, among: await Adb.devices(), services: services, tls: AndroidTVs.requiresTLS(host)) else { return false }
        guard mine == generation else { return true }
        Store.shared.refreshDevices()
        state = .done("\(device.name) is connected. Choose it under Try On.")
        return true
    }
}

struct AndroidWiFiView: View {
    @ObservedObject var model: AndroidWiFi
    @ObservedObject private var store = Store.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.found.isEmpty, !model.typing {
                Text("Lamp doesn't see a TV with debugging on yet.").foregroundStyle(.secondary)
                steps
            } else if !model.typing {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.found) { device in
                        Button { model.select(device.host) } label: {
                            HStack {
                                Image(systemName: model.selected == device.host ? "largecircle.fill.circle" : "circle")
                                Label(device.name ?? device.host, systemImage: "tv")
                                Spacer()
                                Text(words(model.standing(of: device, among: store.devices))).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if model.typing {
                Form {
                    TextField("Pairing address", text: $model.pairingAddress, prompt: Text("192.168.1.20:37123"))
                    SecureField("Pairing code", text: $model.code, prompt: Text("Shown on the TV"))
                    TextField("Connection address", text: $model.connectionAddress, prompt: Text("192.168.1.20:41045"))
                }
            } else if let device = model.current {
                selected(device)
            }
            HStack {
                switch model.state {
                case .idle: EmptyView()
                case .working(let words): ProgressView().controlSize(.small); Text(words).foregroundStyle(.secondary)
                case .done(let words): Label(words, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed(let words): Label(words, systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                }
                Spacer()
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(model.typing ? "Choose from the List" : "Type an Address…") { model.typing.toggle() }
                    .buttonStyle(.link)
                Spacer()
                if model.typing {
                    Button("Connect") { model.connect() }.disabled(model.connectionAddress.trimmed.isEmpty)
                }
            }
        }
        .font(.callout)
        .onChange(of: model.code) { model.codeChanged() }
        .padding(20)
        .frame(width: 460)
    }

    @ViewBuilder
    private func selected(_ device: AndroidWiFi.Found) -> some View {
        switch model.standing(of: device, among: store.devices) {
        case .ready:
            EmptyView()
        case .pairing:
            Form { SecureField("Pairing code", text: $model.code, prompt: Text("Shown on the TV")) }
        case .notPaired:
            Text("On the TV, in Wireless debugging, choose Pair device with pairing code.").fixedSize(horizontal: false, vertical: true)
        case .legacy:
            HStack {
                Text("A Fire TV: Lamp connects, then the TV asks to allow this Mac.").fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Connect") { model.connect() }.keyboardShortcut(.defaultAction)
            }
        case .nothing:
            steps
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Google TV or Android TV: Settings, System, About, then select Android TV OS build seven times. Back in System, Developer options, turn on Wireless debugging and choose Pair device with pairing code.")
            Text("Fire TV: Settings, My Fire TV, Developer options, then turn on ADB debugging.")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func words(_ standing: AndroidWiFi.Standing) -> String {
        switch standing {
        case .ready: return "Connected"
        case .pairing: return "Ready to pair"
        case .notPaired: return "Not paired"
        case .legacy: return "Fire TV"
        case .nothing: return "Debugging off"
        }
    }
}

extension Adb {
    /// The devices on the network offering to pair or to connect, from adb's own search, one per address.
    static func networkServices() async -> [AndroidWiFi.Found] {
        guard FileManager.default.isExecutableFile(atPath: AndroidTools.adb) else { return [] }
        return services(from: (await run(["mdns", "services"], timeout: 10)).output)
    }

    /// `adb mdns services` read into one entry per address, each way in on a port of its own.
    static func services(from output: String) -> [AndroidWiFi.Found] {
        var byHost: [String: AndroidWiFi.Found] = [:]
        for service in AndroidTVs.services(output) {
            // An emulator, Lamp's own included, announces itself at the address it has inside the emulator (10.0.2.15),
            // which nothing on the network can reach.
            guard DeviceAddress.isPrivate(service.host), !service.name.uppercased().hasPrefix("ADB-EMULATOR") else { continue }
            var entry = byHost[service.host] ?? AndroidWiFi.Found(host: service.host)
            if service.isPairing { entry.pairPort = service.port } else if service.transport == .tls { entry.connectPort = service.port } else if service.transport == .legacy { entry.legacyPort = service.port }
            byHost[service.host] = entry
        }
        return byHost.values.sorted { $0.host < $1.host }
    }

    enum Pairing { case paired, wrongCode, unanswered }

    /// Pairs this Mac's adb with a device by the code it shows, given on adb's input rather than in its arguments.
    static func pair(host: String, port: Int, code: String) async -> Pairing {
        let result = await Subprocess.run(AndroidTools.adb, ["pair", "\(host):\(port)"], env: AndroidTools.environment, timeout: 30, input: Data((code + "\n").utf8))
        let said = (result.output + result.errors).lowercased()
        if said.contains("successfully paired") { return .paired }
        if said.contains("wrong password") { return .wrongCode }
        return .unanswered
    }
}
