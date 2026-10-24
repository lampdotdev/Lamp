import CryptoKit
import Foundation
import LampRelayKit
import Network

/// Phones as controllers for a TV app. Lamp introduces the two sides and stays out of what they say to each other, so
/// a game's buttons and files never wait for Lamp, nor Lamp for them:
///
/// - A wish's iPhone app listens on the phone itself (`LampController` in LampSupport) and tells Lamp where
///   (`register`); Lamp gives it a key of its own for that listener. When the TV app's page asks Lamp who its players
///   are (`/app/controller`), Lamp gives it that address with a ticket signed with the listener's key, and the page opens
///   its socket straight to the phone.
/// - A phone's page in a browser can't listen, so it joins through the relay (`ControllerRelay`, a process of Lamp's
///   own), and so does the TV page, a wish's Mac app, and an iPhone app that can't listen. Lamp starts the relay, opens
///   and ends each app's session there and signs who may join it; the relay passes their messages on.
///
/// Either way Lamp hands out only short-lived credentials (`ControllerCredential`, `ticket`), and keeps no message.
/// The page is plain http on the local network, so a phone's browser keeps its motion sensors from it: buttons and
/// sticks work as they are, and tilt only where the person has put https in front of the page themselves.
@MainActor
final class PhoneControllers {
    static let shared = PhoneControllers()

    /// A wish's iPhone app listening for its TV app: where it is, and the key its tickets are signed with, for as long
    /// as it keeps saying it's there.
    struct Listener {
        let wish: String
        let device: String
        var address: String
        var port: UInt16
        let key: SymmetricKey
        var renewed: Date
    }

    /// A listener that hasn't said it's there for this long is forgotten (the app renews every 20 seconds).
    static let listenerLife: TimeInterval = 60
    /// A ticket only has to last until the TV page has opened its socket with it.
    static let ticketLife: TimeInterval = 120

    private var listeners: [String: Listener] = [:]

    // MARK: The TV app's page

    /// A credential for the TV app's page as its game's host at the relay, never the app's token for its AI. The
    /// preview's says so, so that a TV running the same app meanwhile waits for the preview to close.
    func hostCredential(for project: LampProject, preview: Bool) -> String {
        ControllerCredential.issue(kind: .host, app: project.id, preview: preview)
    }

    /// The wish's iPhone apps listening now, each as the page reaches it, with a ticket for it. A phone in the simulator
    /// listens on this Mac: the preview reaches it at the loopback address it registered from, and a TV on the network
    /// at this Mac's address on that network.
    func directLinks(for wish: String, preview: Bool, from asker: String?) -> [[String: Any]] {
        let now = Date()
        listeners = listeners.filter { now.timeIntervalSince($0.value.renewed) < Self.listenerLife }
        return listeners.filter { $0.value.wish == wish }.sorted { $0.key < $1.key }.compactMap { id, listener in
            var address = listener.address
            // A link-local address names its interface, which no page can say in an address: such a phone isn't offered.
            if address.contains("%") { return nil }
            if Self.isLoopback(address), let asker, !Self.isLoopback(asker) {
                guard let mine = IntegrationRunner.macAddress(near: asker) else { return nil }
                address = mine
            }
            let host = address.contains(":") ? "[\(address)]" : address
            return ["kind": "direct", "socket": "ws://\(host):\(listener.port)/", "device": listener.device,
                    "credential": Self.ticket(listener: id, key: listener.key, preview: preview)]
        }
    }

    /// What the page shows the phone it opens a socket to: signed with the listener's own key, for that listener, so it
    /// opens no other phone's game and is no use for long.
    static func ticket(listener: String, key: SymmetricKey, preview: Bool, now: Date = Date()) -> String {
        ControllerToken.issue(kind: .host, app: listener, generation: 0, preview: preview, lifetime: ticketLife, now: now, key: key)
    }

    // MARK: A wish's iPhone app

    /// The iPhone app's listener, at `port` on the address its request came from: the key its tickets are signed with,
    /// the same for as long as that listener lasts.
    func register(listener id: String, wish: String, device: String, address: String, port: UInt16) -> SymmetricKey? {
        let now = Date()
        // A listener's id is its own, and a ticket names it: one another wish's app has is never taken over.
        if let known = listeners[id], known.wish != wish, now.timeIntervalSince(known.renewed) < Self.listenerLife { return nil }
        if var known = listeners[id], known.wish == wish, now.timeIntervalSince(known.renewed) < Self.listenerLife {
            known.address = address
            known.port = port
            known.renewed = now
            listeners[id] = known
            return known.key
        }
        let key = SymmetricKey(size: .bits256)
        // A phone that starts listening again (the app reopened) is the same phone: its old listener is gone.
        listeners = listeners.filter { !($0.value.wish == wish && $0.value.device == device) }
        listeners[id] = Listener(wish: wish, device: device, address: address, port: port, key: key, renewed: now)
        return key
    }

    /// The app's game is over (its page isn't served anywhere): what Lamp handed out for it is no use any more.
    func forgetListeners(of wish: String) {
        listeners = listeners.filter { $0.value.wish != wish }
    }

    // MARK: Sessions

    /// Ends the game of every app whose phone page isn't served any more.
    func endAll(except serving: Set<String>) {
        for app in ControllerCredential.apps where !serving.contains(app) { end(app) }
    }

    /// The app has stopped: its phones are let go, and their links and credentials are no use any more.
    func end(_ app: String) {
        ControllerCredential.forget(app)
        forgetListeners(of: app)
        ControllerRelay.end(app)
    }

    static func isLoopback(_ address: String) -> Bool {
        address == "::1" || address.hasPrefix("127.") || address == "localhost"
    }
}

/// The controllers' credentials for the relay (`ControllerToken`), signed with a key kept only in this Lamp's memory,
/// which Lamp gives the relay as it starts it, so none outlives Lamp, and none is the app's token for its AI. Each app's
/// session has a generation: ending it makes every credential it handed out worthless.
enum ControllerCredential {
    typealias Kind = ControllerToken.Kind
    typealias Claim = ControllerToken.Claim

    nonisolated(unsafe) private static var key = SymmetricKey(size: .bits256)
    nonisolated(unsafe) private static var generations: [String: Int] = [:]
    nonisolated(unsafe) private static var known: Set<String> = []
    private static let lock = NSLock()

    /// The key, as the relay is given it.
    static var keyData: Data { lock.withLock { key.withUnsafeBytes { Data($0) } } }

    static func generation(_ app: String) -> Int { lock.withLock { generations[app] ?? 0 } }

    /// The apps credentials have been handed out for since their sessions last ended.
    static var apps: Set<String> { lock.withLock { known } }

    static func issue(kind: Kind, app: String, player: Int? = nil, preview: Bool = false, peer: String? = nil, now: Date = Date()) -> String {
        lock.withLock {
            known.insert(app)
            return ControllerToken.issue(kind: kind, app: app, generation: generations[app] ?? 0, player: player, preview: preview, peer: peer, now: now, key: key)
        }
    }

    /// What a credential says when this Lamp made it, for this app in its current session, of one of these kinds, and it
    /// hasn't run out; nil otherwise, whatever is wrong with it.
    static func check(_ token: String?, kinds: Set<Kind>, app: String, now: Date = Date()) -> Claim? {
        lock.withLock { ControllerToken.check(token, kinds: kinds, app: app, generation: generations[app] ?? 0, now: now, key: key) }
    }

    static func forget(_ app: String) {
        lock.withLock {
            generations[app, default: 0] += 1
            known.remove(app)
        }
    }
}

/// The relay between TV apps and their phones, and between the apps of one wish (`Relay`), run as a process of its own
/// from Lamp's Helpers while any TV app takes players or any wish's room is open (`WishRooms`), so a game's messages and
/// files, and what a wish's apps say to each other, never pass through Lamp. Lamp tells it on its input which apps'
/// sessions and which wishes' rooms are open, with the key their credentials are signed with; it says on its output where
/// it listens and who is in each room, and it ends when Lamp does (its input closes). It keeps the port it had for as long as Lamp runs, so a phone's page that
/// lost its socket finds it again where it was.
@MainActor
enum ControllerRelay {
    private static var process: Process?
    private static var input: FileHandle?
    private static var port: UInt16?
    private static var lastPort: UInt16 = 0
    private static var waiting: [UUID: CheckedContinuation<UInt16?, Never>] = [:]
    /// What each open session is, as the relay is told it; told again to a relay started afresh.
    private static var sessions: [String: [String: Any]] = [:]
    private static var restarts: [Date] = []
    private static var hostsRead: (names: [String], at: Date)?

    /// The names and addresses a phone's page can be served as: this Mac's, as the gateway checks a page's Host. Read
    /// again every half minute at most, since the name comes from a command.
    private static var hosts: [String] {
        if let hostsRead, hostsRead.at.timeIntervalSinceNow > -30 { return hostsRead.names }
        let names = Array(Set([Devices.macHost.lowercased()] + Devices.localAddresses + ["127.0.0.1", "localhost", "::1"])).sorted()
        hostsRead = (names, Date())
        return names
    }
    /// For tests: the relay to run, when it isn't in this bundle's Helpers.
    static var executable: URL?

    private static var program: URL? {
        if let executable { return executable }
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/LampRelay")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        // A build that isn't a bundle (swift run): the relay is built beside Lamp.
        let beside = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("LampRelay")
        return beside.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
    }

    /// Where the relay listens, once it does, starting it when it isn't running. Nil when it can't start, when no TV app
    /// takes players, or when it hasn't said within a few seconds.
    static func ready() async -> UInt16? {
        if let port { return port }
        guard !sessions.isEmpty || !rooms.isEmpty else { return nil }
        let id = UUID()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            waiting.removeValue(forKey: id)?.resume(returning: nil)
        }
        return await withCheckedContinuation { waiting[id] = $0; if process == nil { launch() } }
    }

    /// Opens or brings up to date the sessions of the apps that take players now, and ends the rest; with none left the
    /// relay is let go, so nothing listens for phones while no TV app wants them.
    static func sync(_ serving: [LampProject]) {
        let wanted = Dictionary(serving.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for app in sessions.keys where wanted[app] == nil { end(app) }
        for project in wanted.values { open(project.id) }
        if sessions.isEmpty, rooms.isEmpty { quit() }
    }

    /// The wishes' rooms (`WishRooms`), each as the relay is told it: told again to a relay started afresh.
    private static var rooms: [String: [String: Any]] = [:]
    /// Who is in each room now, as the relay last said: the room's key, then its members (`peer`, `kind`, `name`,
    /// `device`, `since`).
    private(set) static var presence: [String: [[String: Any]]] = [:]
    static var roomKeys: [String] { Array(rooms.keys) }

    /// Opens a wish's room, or tells the relay its apps again when they changed.
    static func openRoom(_ key: String, generation: Int, apps: [[String: Any]]) {
        let line: [String: Any] = ["op": "room", "app": key, "generation": generation, "apps": apps]
        guard rooms[key].map({ NSDictionary(dictionary: $0) != NSDictionary(dictionary: line) }) ?? true else { return }
        rooms[key] = line
        if process == nil { launch() } else { send(line) }
    }

    static func endRoom(_ key: String) {
        presence[key] = nil
        guard rooms.removeValue(forKey: key) != nil else { return }
        send(["op": "end-room", "app": key])
        if sessions.isEmpty, rooms.isEmpty { quit() }
    }

    /// The app's session as it is now: its generation and the address its phone page is at. Sent again when the page moves.
    static func open(_ app: String) {
        var line: [String: Any] = ["op": "session", "app": app, "generation": ControllerCredential.generation(app), "hosts": hosts]
        if PhoneSites.isOpen(app), let pagePort = PhoneSites.port(for: app) {
            line["pagePort"] = Int(pagePort)
            line["page"] = TVs.phonePage(port: pagePort)
        }
        guard sessions[app].map({ NSDictionary(dictionary: $0) != NSDictionary(dictionary: line) }) ?? true else { return }
        sessions[app] = line
        if process == nil { launch() } else { send(line) }
    }

    /// The app's page has moved: an open session is told where it is now. One that isn't open (its page stopped being
    /// served while its site opened) stays closed.
    static func refresh(_ app: String) {
        guard sessions[app] != nil else { return }
        open(app)
    }

    static func end(_ app: String) {
        guard sessions.removeValue(forKey: app) != nil else { return }
        send(["op": "end", "app": app])
        if sessions.isEmpty, rooms.isEmpty { quit() }
    }

    private static func launch() {
        guard process == nil else { return }
        guard let program else {
            NSLog("Lamp's controller relay isn't in this build.")
            return finish(nil)
        }
        let process = Process()
        process.executableURL = program
        let input = Pipe(), output = Pipe()
        // A relay that has quit makes a write fail; without this it would end Lamp with SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { gone in Task { @MainActor in ended(gone) } }
        var pending = Data()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            pending.append(data)
            while let end = pending.firstIndex(of: 0x0A) {
                let line = pending[..<end]
                pending.removeSubrange(...end)
                guard let said = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { continue }
                switch said["op"] as? String {
                case "ready":
                    let port = (said["port"] as? Int).flatMap { UInt16(exactly: $0) }
                    Task { @MainActor in if Self.process === process { finish(port) } }
                case "room":
                    guard let room = said["app"] as? String else { continue }
                    let members = said["peers"] as? [[String: Any]] ?? []
                    Task { @MainActor in if Self.process === process, rooms[room] != nil { presence[room] = members } }
                default:
                    continue
                }
            }
        }
        do {
            try process.run()
        } catch {
            NSLog("Lamp's controller relay didn't start: \(error.localizedDescription)")
            return finish(nil)
        }
        self.process = process
        self.input = input.fileHandleForWriting
        send(["op": "start", "key": ControllerCredential.keyData.base64EncodedString(), "port": Int(lastPort)])
        for line in sessions.values { send(line) }
        for line in rooms.values { send(line) }
    }

    private static func finish(_ port: UInt16?) {
        self.port = port
        if let port { lastPort = port }
        for waiter in waiting.values { waiter.resume(returning: port) }
        waiting = [:]
    }

    private static func send(_ line: [String: Any]) {
        guard let input, var data = try? JSONSerialization.data(withJSONObject: line) else { return }
        data.append(0x0A)
        try? input.write(contentsOf: data)
    }

    /// The relay ended. Wanted still, it's started again, though not more than a few times a minute.
    private static func ended(_ gone: Process) {
        guard process === gone else { return }
        process = nil
        input = nil
        port = nil
        presence = [:]
        finish(nil)
        guard !sessions.isEmpty || !rooms.isEmpty else { return }
        restarts = restarts.filter { $0.timeIntervalSinceNow > -60 } + [Date()]
        guard restarts.count <= 3 else { return NSLog("Lamp's controller relay keeps ending; it's left off until a TV app opens again.") }
        launch()
    }

    private static func quit() {
        guard let process else { return }
        self.process = nil
        presence = [:]
        try? input?.close()
        input = nil
        finish(nil)
        process.terminate()
    }
}

/// Each TV app's phone page on a port of its own (`Edition.phonePagePorts`), so each app's page is an origin of its own
/// in the phone's browser: what one app's page keeps (a player's credential) is out of reach of another app's page in
/// the same tab, which a path of one shared address couldn't give. A site is open only while the app's page is served
/// (`Store.servesPhonePage`); its port is kept for the app while Lamp runs, so the address an app was given stays its.
@MainActor
enum PhoneSites {
    private static var ports: [String: UInt16] = [:]
    private static var sites: [String: Gateway] = [:]
    private static var opening: Set<String> = []
    private static var waiting: [String: [CheckedContinuation<UInt16?, Never>]] = [:]

    /// The app's port: the one it has, while it's still free or its site holds it, else the first free one in Lamp's
    /// range, starting from a place worked out from its id so an app tends to keep the same one from run to run. A port
    /// is kept for an app whose page isn't served only while no other app needs it: the range is a pool, never a limit
    /// on how many apps have had a page.
    static func port(for app: String, avoiding avoided: Set<UInt16> = []) -> UInt16? {
        if let port = ports[app], !avoided.contains(port), sites[app] != nil || opening.contains(app) || isFree(port) { return port }
        ports[app] = nil
        let range = Edition.phonePagePorts
        let count = Int(range.count)
        let start = Int(app.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 } % UInt32(count))
        let candidates = (0..<count).map { range.lowerBound + UInt16((start + $0) % count) }.filter { !avoided.contains($0) }
        let inUse = Set(ports.filter { sites[$0.key] != nil || opening.contains($0.key) }.values)
        let kept = Set(ports.values)
        // First a port no other app keeps; then one kept by an app whose page isn't served now, which gives it up.
        for port in candidates where !kept.contains(port) && isFree(port) {
            ports[app] = port
            return port
        }
        for port in candidates where !inUse.contains(port) && isFree(port) {
            for (other, held) in ports where held == port { ports[other] = nil }
            ports[app] = port
            return port
        }
        return nil
    }

    /// Whether the app's site is open and listening.
    static func isOpen(_ app: String) -> Bool { sites[app] != nil }

    /// The port the app's site listens on, once it does: a page's address is only ever given for a port its site holds,
    /// never one it was given and may yet lose. Nil when its page isn't served.
    static func ready(_ app: String, wanted: @escaping @MainActor () -> Bool = { false }) async -> UInt16? {
        if sites[app] != nil { return ports[app] }
        if opening.contains(app) { return await withCheckedContinuation { waiting[app, default: []].append($0) } }
        let isWanted: @MainActor () -> Bool = { wanted() || served(app) }
        guard isWanted() else { return nil }
        return await open(app, wanted: isWanted) ? ports[app] : nil
    }

    private static func served(_ app: String) -> Bool {
        Store.shared.projects.first { $0.id == app }.map(Store.servesPhonePage) ?? false
    }

    /// Opens the sites of the apps whose phone pages are served and closes the rest; apps that are gone give their
    /// ports back.
    static func sync(_ projects: [LampProject]) {
        let serving = Set(projects.filter(Store.servesPhonePage).map(\.id))
        let known = Set(projects.map(\.id))
        for (app, site) in sites where !serving.contains(app) {
            site.stop()
            sites[app] = nil
        }
        // The game ends too: its phones and host are let go and its credentials are worthless, whether the app was
        // deleted or is no longer set to open anywhere.
        PhoneControllers.shared.endAll(except: serving)
        ControllerRelay.sync(projects.filter(Store.servesPhonePage))
        for app in ports.keys where !known.contains(app) { ports[app] = nil }
        for app in serving where sites[app] == nil && !opening.contains(app) {
            Task { @MainActor in _ = await open(app, wanted: { served(app) }) }
        }
    }

    /// Opens the app's site and counts it open only once it's listening. A port that turns out to be taken (by another
    /// program since it was chosen) is left for the next free one; a site that stops listening later is let go, and
    /// the next sync opens it again.
    @discardableResult
    static func open(_ app: String, wanted: @escaping @MainActor () -> Bool) async -> Bool {
        guard sites[app] == nil, !opening.contains(app) else { return sites[app] != nil }
        opening.insert(app)
        defer {
            opening.remove(app)
            let port = sites[app] != nil ? ports[app] : nil
            for waiter in waiting.removeValue(forKey: app) ?? [] { waiter.resume(returning: port) }
            // A host that asked for a link while the site was opening, or before it moved, gets one for where it is.
            if let port {
                ControllerRelay.refresh(app)
                TVPreview.phonePageMoved(app, to: TVs.phonePage(port: port))
            }
        }
        var avoided: Set<UInt16> = []
        for _ in 0..<4 {
            guard let port = port(for: app, avoiding: avoided) else { return false }
            let site = Gateway(site: port, pages: { request in
                await Store.shared.phonePage(request.within(app))
            })
            // Weakly: the listener keeps this callback, and the site keeps the listener.
            let started = await site.startSite(onFailure: { [weak site] in
                Task { @MainActor in
                    guard let site, sites[app] === site else { return }
                    sites[app] = nil
                    ports[app] = nil
                    if served(app) { _ = await open(app, wanted: { served(app) }) }
                }
            })
            guard started else {
                site.stop()
                ports[app] = nil
                avoided.insert(port)
                continue
            }
            // Closed while it opened: nothing is to be served there.
            guard wanted() else { site.stop(); return false }
            sites[app] = site
            return true
        }
        return false
    }

    /// For tests: the app keeps this port, as if it had been given it earlier.
    static func keep(_ port: UInt16, for app: String) { ports[app] = port }

    /// For tests: every site closed and every port given back.
    static func forgetAll() {
        for site in sites.values { site.stop() }
        sites = [:]
        ports = [:]
    }

    static func isFree(_ port: UInt16) -> Bool {
        let fd = socket(AF_INET6, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var no: Int32 = 0
        setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &no, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = port.bigEndian
        address.sin6_addr = in6addr_any
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0 }
        }
    }
}

extension Gateway.Request {
    /// A request to an app's own site, as the path under `/phone/<app>` the page's code has always read it at.
    func within(_ app: String) -> Gateway.Request {
        var request = Gateway.Request(method: method, path: "/phone/\(app)" + path, headers: headers, body: body)
        request.fromNetwork = fromNetwork
        request.peerPort = peerPort
        request.peerAddress = peerAddress
        return request
    }
}
