import CryptoKit
import Foundation
import SystemConfiguration

/// What the controllers' service does (`ControllerService`), apart from how it's reached: the games Lamp has given it
/// (each installation's page versions, its key's verifier and the code signature its game must have), and each game's
/// session while it's played: its page served on a port of its own (`PhonePageServer`) and its place at the relay
/// (`Relay`), in this process, with a key that lives only in its memory. A session lasts while its game keeps asking
/// for it (`ControllerService.lease`) and ends when the game's connection does; with none left nothing listens for phones.
///
/// Everything happens on `queue`. A restart of the service is a new epoch: the key is new, every credential handed out
/// before is worthless, and games ask again for a fresh session, as they do when Lamp's relay starts again.
public final class ControllerHost: @unchecked Sendable {
    public struct Version: Codable, Equatable, Sendable {
        public var version: String
        public var keyVerifier: String
        /// The game's designated requirement, which its connection is held to once it says which game it is.
        public var requirement: String
        public var provisioned: Date
    }

    public struct Installation: Codable, Equatable, Sendable {
        /// Oldest first; the last is the newest build's.
        public var versions: [Version]
    }

    /// One game's session while it's played.
    final class Live: @unchecked Sendable {
        let version: String
        var generation: Int
        var site: PhonePageServer?
        var lease: Date
        /// The connections that asked for it: when the last goes (the game quit), it ends.
        var owners: Set<Int> = []
        init(version: String, generation: Int, lease: Date) {
            self.version = version
            self.generation = generation
            self.lease = lease
        }
    }

    public let queue = DispatchQueue(label: "dev.lamp.controllers")
    public let names: ControllerService.Names
    public let folder: URL
    public let epoch = UUID().uuidString
    private let key = SymmetricKey(size: .bits256)
    private var installations: [String: Installation] = [:]
    private var live: [String: Live] = [:]
    private var generations: [String: Int] = [:]
    private var relay: Relay?
    private var relayPort: UInt16?
    private var ticker: DispatchSourceTimer?
    /// This Mac's names and addresses, and the address a phone's link carries. Changed by tests.
    public var hosts: () -> Set<String> = ControllerHost.macNames
    public var linkHost: () -> String = { PhonePageServer.localAddresses().first ?? ControllerHost.localHostName() ?? "127.0.0.1" }
    /// Told when a session opens or ends, for the log and the tests.
    public var onChange: (_ app: String, _ open: Bool) -> Void = { _, _ in }

    public init(names: ControllerService.Names, folder: URL) {
        self.names = names
        self.folder = folder
        load()
    }

    private var registryURL: URL { folder.appendingPathComponent("registry.json") }
    private func pages(_ app: String) -> URL { folder.appendingPathComponent("pages").appendingPathComponent(app) }

    private func load() {
        guard let data = try? Data(contentsOf: registryURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        installations = (try? decoder.decode([String: Installation].self, from: data)) ?? [:]
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(installations) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: registryURL, options: .atomic)
        chmod(registryURL.path, 0o600)
    }

    // MARK: From Lamp

    /// Lamp's calls (`provision`, `revoke`, `query`), from Lamp itself only: the service lets no one else in where they arrive.
    public func manage(_ request: [String: Any]) -> [String: Any] {
        queue.sync {
            switch request["op"] as? String {
            case "hello": return hello
            case "provision": return provision(request)
            case "revoke":
                guard let app = request["installation"] as? String, ControllerService.isName(app) else { return ["error": "No such game."] }
                revoke(app)
                return ["ok": true]
            case "query": return query
            default: return ["error": "This service doesn't know that call."]
            }
        }
    }

    private var hello: [String: Any] { ["protocol": ControllerService.protocolVersion, "epoch": epoch] }

    private var query: [String: Any] {
        var listed: [[String: Any]] = []
        for (app, installation) in installations.sorted(by: { $0.key < $1.key }) {
            var entry: [String: Any] = ["installation": app, "versions": installation.versions.map(\.version)]
            if let game = live[app] { entry["live"] = ["version": game.version, "generation": game.generation, "port": game.site.map { Int($0.port) } ?? 0] }
            listed.append(entry)
        }
        var answer = hello
        answer["installations"] = listed
        if let relayPort { answer["relay"] = Int(relayPort) }
        return answer
    }

    /// A build of a game: its page's files, its key's verifier and its signature, kept as a version of its own beside
    /// the ones before, so a game still open with an earlier build keeps its page. A few versions are kept, never one
    /// being played.
    private func provision(_ request: [String: Any]) -> [String: Any] {
        guard let app = request["installation"] as? String, ControllerService.isName(app),
              let version = request["version"] as? String, ControllerService.isName(version),
              let verifier = request["keyVerifier"] as? String, Data(base64Encoded: verifier)?.count == 32,
              let requirement = request["requirement"] as? String, Self.isRequirement(requirement),
              let encoded = request["files"] as? [[String: Any]] else {
            return ["error": "Lamp's request to take the game's phone page was incomplete."]
        }
        let snapshot: ControllerSnapshot
        do {
            snapshot = try ControllerSnapshot(encoded: encoded)
            try snapshot.check()
        } catch {
            return ["error": "\(error)"]
        }
        guard snapshot.version == version else { return ["error": "The phone page didn't arrive as Lamp sent it."] }
        let target = pages(app).appendingPathComponent(version)
        let fm = FileManager.default
        if !fm.fileExists(atPath: target.path) {
            do {
                try fm.createDirectory(at: pages(app), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try snapshot.write(to: target)
            } catch {
                return ["error": "The service couldn't keep the game's phone page: \(error.localizedDescription)"]
            }
        }
        var installation = installations[app] ?? Installation(versions: [])
        installation.versions.removeAll { $0.version == version }
        installation.versions.append(Version(version: version, keyVerifier: verifier, requirement: requirement, provisioned: Date()))
        let playing = live[app]?.version
        while installation.versions.count > 3, let oldest = installation.versions.first(where: { $0.version != playing && $0.version != version }) {
            installation.versions.removeAll { $0.version == oldest.version }
            try? fm.removeItem(at: pages(app).appendingPathComponent(oldest.version))
        }
        installations[app] = installation
        save()
        return ["ok": true, "version": version]
    }

    /// The game is gone: its session ends and nothing of it is kept.
    private func revoke(_ app: String) {
        end(app)
        installations[app] = nil
        save()
        try? FileManager.default.removeItem(at: pages(app))
    }

    // MARK: From a game

    /// The signature a game's connection must have from now on, for the build it says it is; nil for a game or build
    /// this service wasn't given.
    public func requirement(installation app: String, version: String) -> String? {
        queue.sync { installations[app]?.versions.first { $0.version == version }?.requirement }
    }

    /// A game asking for its session, on a connection already held to its signature (`requirement`): opened, or the one
    /// it has renewed. Asking again is how a game keeps it; asking with another build's version starts a new one.
    public func open(installation app: String, version: String, key given: String, connection: Int, now: Date = Date()) -> [String: Any] {
        queue.sync {
            guard let build = installations[app]?.versions.first(where: { $0.version == version }),
                  ControllerService.matches(given, verifier: build.keyVerifier) else {
                return ["status": 403, "error": "Lamp didn't set up phone controllers for this copy of the game. Open the game from Lamp to update it."]
            }
            if let game = live[app], game.version != version { end(app) }
            let game: Live
            if let known = live[app] {
                game = known
            } else {
                game = Live(version: version, generation: generations[app, default: 0], lease: now)
                live[app] = game
                onChange(app, true)
            }
            game.lease = now.addingTimeInterval(ControllerService.lease)
            game.owners.insert(connection)
            startTicking()
            guard let relayPort = startRelay() else { return ["status": 503, "error": "The link for controllers couldn't open."] }
            if game.site == nil { openSite(app, game) }
            configure(app, game)
            let credential = ControllerToken.issue(kind: .host, app: app, generation: game.generation, key: key)
            return ["status": 200, "links": [["kind": "relay", "socket": "ws://127.0.0.1:\(relayPort)/", "app": app, "credential": credential]],
                    "renew": ControllerService.renew, "epoch": epoch]
        }
    }

    /// A game's connection has gone: the sessions only it kept end.
    public func closed(connection: Int) {
        queue.async {
            for (app, game) in self.live where game.owners.remove(connection) != nil && game.owners.isEmpty { self.end(app) }
        }
    }

    /// For tests: lets time pass, ending the sessions whose game stopped asking.
    public func expire(now: Date = Date()) {
        queue.sync { expireLeases(now) }
    }

    /// For tests and the log: the port a game's page is served at now, nil while it has no session.
    public func pagePort(_ app: String) -> UInt16? { queue.sync { live[app]?.site?.port } }
    public var openSessions: [String] { queue.sync { Array(live.keys).sorted() } }
    public var relayListening: Bool { queue.sync { relay != nil } }

    // MARK: Sessions

    private func end(_ app: String) {
        guard let game = live.removeValue(forKey: app) else { return }
        game.site?.stop()
        relay?.end(app: app)
        // Every credential of this session is worthless from now on.
        generations[app] = game.generation + 1
        onChange(app, false)
        if live.isEmpty { stopRelay() }
    }

    private func expireLeases(_ now: Date) {
        for (app, game) in live where game.lease < now { end(app) }
    }

    /// The relay, started when a game first needs it at the port it had before (the first of the service's, while it's
    /// free), so a phone whose socket dropped finds it where it was.
    private func startRelay() -> UInt16? {
        if let relayPort, relay != nil { return relayPort }
        let started = Relay(key: key)
        let ready = DispatchSemaphore(value: 0)
        let port = Said<UInt16>()
        started.onStopped = { [weak self, weak started] in
            guard let self else { return }
            self.queue.async {
                guard self.relay === started else { return }
                // The network went away under it: the next ask starts it again, and the games' phones join afresh.
                self.relay = nil
                self.relayPort = nil
            }
        }
        started.start(port: relayPort ?? names.relayPort) { given in
            port.value = given
            ready.signal()
        }
        guard ready.wait(timeout: .now() + 5) == .success, let port = port.value else { started.stop(); return nil }
        relay = started
        relayPort = port
        for (app, game) in live { configure(app, game) }
        return port
    }

    private func stopRelay() {
        relay?.stop()
        relay = nil
        ticker?.cancel()
        ticker = nil
    }

    /// The game's session at the relay as it is now: its generation, and where its page is at this Mac's address on the
    /// network, which moves when the network changes; told again each time the game asks, so a phone's link follows.
    private func configure(_ app: String, _ game: Live) {
        guard let relay else { return }
        let names = Array(hosts()).sorted()
        let page = game.site.map { "http://\(linkHost()):\($0.port)/" }
        relay.configure(app: app, Relay.Session(generation: game.generation, pagePort: game.site?.port, page: page, hosts: names))
    }

    /// Opens the game's page on a free port of the service's, from one worked out from its id, so a game tends to keep
    /// the same address from run to run.
    private func openSite(_ app: String, _ game: Live) {
        let root = pages(app).appendingPathComponent(game.version)
        let range = names.pagePorts
        let count = Int(range.count)
        let start = Int(app.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 } % UInt32(count))
        let taken = Set(live.values.compactMap { $0.site?.port })
        let hosts = self.hosts
        for step in 0..<count {
            let port = range.lowerBound + UInt16((start + step) % count)
            guard !taken.contains(port) else { continue }
            let site = PhonePageServer(port: port, root: root, app: app, hosts: { hosts() }, relayPort: { [weak self] in
                self?.queue.sync { self?.relayPort }
            })
            let ready = DispatchSemaphore(value: 0)
            let listening = Said<Bool>()
            site.start(ready: { ok in listening.value = ok; ready.signal() }, onFailure: { [weak self, weak game, weak site] in
                self?.queue.async {
                    guard let game, game.site === site else { return }
                    game.site = nil
                }
            })
            guard ready.wait(timeout: .now() + 5) == .success, listening.value == true else { site.stop(); continue }
            game.site = site
            return
        }
    }

    private func startTicking() {
        guard ticker == nil else { return }
        let ticker = DispatchSource.makeTimerSource(queue: queue)
        ticker.schedule(deadline: .now() + 5, repeating: 5)
        ticker.setEventHandler { [weak self] in
            guard let self else { return }
            self.expireLeases(Date())
            // A page that stopped listening (the network went away under it) opens again where it can.
            for (app, game) in self.live where game.site == nil {
                self.openSite(app, game)
                self.configure(app, game)
            }
        }
        ticker.resume()
        self.ticker = ticker
    }

    // MARK: This Mac

    /// Whether a requirement is one the system can read: one it can't would make XPC throw.
    public static func isRequirement(_ text: String) -> Bool {
        var requirement: SecRequirement?
        return !text.isEmpty && text.utf8.count <= 4096 && SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess
    }

    /// This Mac's Bonjour name, as phones may reach it ("name.local").
    public static func localHostName() -> String? {
        guard let name = SCDynamicStoreCopyLocalHostName(nil) as String?, !name.isEmpty else { return nil }
        return name + ".local"
    }

    /// The names and addresses a page is served as: this Mac's on its networks, and the loopback ones.
    public static func macNames() -> Set<String> {
        var names: Set<String> = ["127.0.0.1", "localhost", "::1"]
        if let name = localHostName() { names.insert(name.lowercased()) }
        for address in PhonePageServer.localAddresses() { names.insert(address.lowercased()) }
        return names
    }
}

/// What a callback on another queue says, read after a semaphore says it has.
private final class Said<Value>: @unchecked Sendable {
    var value: Value?
}
