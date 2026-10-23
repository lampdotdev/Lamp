import CryptoKit
import Foundation
import Network

/// Phones as controllers for a TV app, through Lamp itself: the phone's page comes from Lamp's gateway on the local
/// network (`Store.phonePage`), and so does its socket (`/phone/<app>/socket`), so nothing leaves the home and nothing
/// is hosted anywhere. Each running TV app is one session: its host is the TV preview, joined in this process through
/// its bridge (`TVPreview`), or the app on a TV, which joins over the Wi‑Fi with a credential it asks Lamp for
/// (`/app/controller`). Phones send buttons, sticks and tilt to the host and get small messages back; Lamp passes them
/// on and keeps nothing.
///
/// The page is plain http on the local network, so a phone's browser keeps its motion sensors from it: buttons and
/// sticks work as they are, and tilt only where the person has put https in front of the page themselves.
@MainActor
final class PhoneControllers {
    static let shared = PhoneControllers()

    enum Limits {
        static let players = 8
        static let message = 1024          // bytes, any message on a socket
        static let perSecond = 120.0       // messages a phone may send each second, a little over a screen's rate
        static let backlog = 32            // messages waiting to go to a TV past which movement is dropped
        static let silence: TimeInterval = 15
        static let beat: TimeInterval = 5
    }

    /// Where a session's host is: the preview in this process, or the app on a TV over its socket.
    enum Host {
        case preview((String) -> Void)
        case socket(WebSocketPeer)
    }

    final class Player {
        var peer: WebSocketPeer?
        /// While a phone that dropped off may still come back with its credential, its number stays its own.
        var heldUntil = Date.distantPast
        var tokens = Limits.perSecond
        var refilled = Date()
        var over: Date?
        init(peer: WebSocketPeer) { self.peer = peer }
    }

    final class Session {
        var host: Host?
        var players: [Int: Player] = [:]
        var renewed = Date()
    }

    private var sessions: [String: Session] = [:]
    private var ticker: Timer?
    /// Sockets not yet past their hello: held here, since nothing else holds them until they're a player or a host.
    private var greeting: [ObjectIdentifier: WebSocketPeer] = [:]

    // MARK: The host

    /// The TV preview joins as its app's host; what comes for it goes to `deliver`, as JSON text.
    func attachPreview(_ project: LampProject, deliver: @escaping (String) -> Void) {
        let session = session(for: project.id)
        if case .socket(let peer) = session.host { peer.close(code: 4000) }
        session.host = .preview(deliver)
        welcomeHost(session, app: project.id)
    }

    /// The preview has gone: phones hear the app isn't there, and with no TV to wait for, they're let go.
    func detachPreview(_ project: LampProject) {
        guard let session = sessions[project.id], case .preview = session.host else { return }
        hostLeft(session, app: project.id)
        if project.device == nil { end(project.id) }
    }

    /// What the preview's page sends: a fresh link for phones, a message to them, or its beat.
    func fromPreview(_ project: LampProject, _ message: [String: Any]) {
        guard let session = sessions[project.id], case .preview = session.host else { return }
        fromHost(session, app: project.id, message: message)
    }

    /// A TV app on a TV opening a game for phones: a credential for its own socket, never Lamp's token for its AI.
    func hostCredential(for project: LampProject) -> String {
        _ = session(for: project.id)
        return ControllerCredential.issue(kind: .host, app: project.id)
    }

    // MARK: Sockets

    /// A socket from a phone, or from a TV app, at `/phone/<app>/socket`. `pageOrigins` are what a phone's page here
    /// is served as (the request's own Host, by http or https), the only pages let in as players.
    func accept(_ peer: WebSocketPeer, app: String, pageOrigins: [String], origin: String?) {
        var greeted = false
        let id = ObjectIdentifier(peer)
        greeting[id] = peer
        peer.onClose = { [weak self] in self?.greeting[id] = nil }
        peer.onMessage = { [weak self, weak peer] text in
            guard let self, let peer, !greeted else { return }
            greeted = true
            self.greeting[id] = nil
            guard let hello = Self.parse(text), hello["t"] as? String == "hello",
                  let claim = ControllerCredential.check(hello["credential"] as? String, kinds: [.host, .join, .controller], app: app),
                  let project = Store.shared.projects.first(where: { $0.id == app }), Store.servesPhonePage(project) || claim.kind == .host
            else { return peer.close(code: 4003) }
            if claim.kind == .host { return self.joinAsHost(peer, app: app) }
            guard let origin, pageOrigins.contains(origin) else { return peer.close(code: 4003) }
            self.joinAsPlayer(peer, app: app, resuming: claim.kind == .controller ? claim.player : nil)
        }
        peer.start()
        startTicking()
        Task { @MainActor [weak self, weak peer] in
            try? await Task.sleep(for: .seconds(5))
            if !greeted { peer?.close(code: 4001); self?.greeting[id] = nil }
        }
    }

    private func joinAsHost(_ peer: WebSocketPeer, app: String) {
        let session = session(for: app)
        switch session.host {
        case .socket(let old): old.close(code: 4000)
        case .preview: return peer.close(code: 4009)   // the preview is this app's host on this Mac
        case nil: break
        }
        session.host = .socket(peer)
        peer.onMessage = { [weak self] text in
            guard let self, let message = Self.parse(text) else { return }
            self.fromHost(session, app: app, message: message)
        }
        peer.onClose = { [weak self, weak peer] in
            guard let self, case .socket(let current) = session.host, current === peer else { return }
            self.hostLeft(session, app: app)
        }
        welcomeHost(session, app: app)
    }

    private func joinAsPlayer(_ peer: WebSocketPeer, app: String, resuming: Int?) {
        let session = session(for: app)
        let now = Date()
        var number = resuming
        if let resuming, let old = session.players[resuming]?.peer {
            old.close(code: 4000)   // the same phone, back on a new connection
        }
        if number == nil {
            number = (1...Limits.players).first { n in
                guard let player = session.players[n] else { return true }
                return player.peer == nil && player.heldUntil < now
            }
        }
        guard let number else {
            peer.send(#"{"t":"full"}"#)
            return peer.close(code: 4004)
        }
        let player = Player(peer: peer)
        session.players[number] = player
        peer.send(Self.json(["t": "welcome", "role": "controller", "player": number, "host": session.host != nil,
                             "credential": ControllerCredential.issue(kind: .controller, app: app, player: number)]))
        toHost(session, ["t": "joined", "player": number])
        peer.onMessage = { [weak self] text in self?.fromPlayer(session, number: number, player: player, text: text) }
        peer.onClose = { [weak self, weak peer] in
            guard let self, session.players[number] === player, player.peer === peer else { return }
            player.peer = nil
            player.heldUntil = Date().addingTimeInterval(ControllerCredential.Kind.controller.lifetime)
            self.toHost(session, ["t": "left", "player": number])
        }
    }

    private func fromPlayer(_ session: Session, number: Int, player: Player, text: String) {
        guard allowed(player), let message = Self.parse(text), session.host != nil else { return }
        let at = Int(Date().timeIntervalSince1970 * 1000)
        let seq = message["seq"] as? Int ?? 0
        let name = (message["name"] as? String).flatMap { $0.range(of: "^[A-Za-z0-9_-]{1,32}$", options: .regularExpression) != nil ? $0 : nil }
        switch message["t"] as? String {
        case "button":
            guard let name else { return }
            toHost(session, ["t": "button", "player": number, "name": name, "down": message["down"] as? Bool == true, "seq": seq, "at": at])
        case "axis":
            guard let name else { return }
            // Movement is only worth its latest value: when the TV is behind, it's dropped rather than queued.
            if case .socket(let peer) = session.host, peer.pending > Limits.backlog { return }
            toHost(session, ["t": "axis", "player": number, "name": name, "x": Self.clamp(message["x"]), "y": Self.clamp(message["y"]), "seq": seq, "at": at])
        case "message":
            guard let data = message["data"] else { return }
            toHost(session, ["t": "message", "player": number, "data": data, "at": at])
        default:
            break
        }
    }

    private func fromHost(_ session: Session, app: String, message: [String: Any]) {
        switch message["t"] as? String {
        case "link":
            sendLink(session, app: app)
        case "send":
            guard let data = message["data"] else { return }
            let to = (message["player"] as? Int).flatMap { $0 == 0 ? nil : $0 }
            let text = Self.json(["t": "message", "data": data])
            for (number, player) in session.players where to == nil || to == number { player.peer?.send(text) }
        default:
            break
        }
    }

    /// A link for phones, once the app's site is listening and by the port it holds.
    private func sendLink(_ session: Session, app: String) {
        Task { @MainActor in
            guard let port = await PhoneSites.ready(app), sessions[app] === session else { return }
            let join = ControllerCredential.issue(kind: .join, app: app)
            toHost(session, ["t": "link", "url": TVs.phonePage(port: port) + "#" + join])
        }
    }

    /// The app's site has opened, perhaps at another port than before: its host is given a link to where it is.
    func siteOpened(_ app: String) {
        guard let session = sessions[app], session.host != nil else { return }
        sendLink(session, app: app)
    }

    // A phone may send about as often as its screen draws; past that its messages are dropped, and a phone that goes
    // on past it for ten seconds is let go.
    private func allowed(_ player: Player) -> Bool {
        let now = Date()
        player.tokens = min(Limits.perSecond, player.tokens + now.timeIntervalSince(player.refilled) * Limits.perSecond)
        player.refilled = now
        if player.tokens >= 1 { player.tokens -= 1; player.over = nil; return true }
        if player.over == nil { player.over = now }
        if let over = player.over, now.timeIntervalSince(over) > 10 { player.peer?.close(code: 4008) }
        return false
    }

    // MARK: Sessions

    private func session(for app: String) -> Session {
        if let session = sessions[app] { return session }
        let session = Session()
        sessions[app] = session
        startTicking()
        return session
    }

    private func welcomeHost(_ session: Session, app: String) {
        let players = session.players.filter { $0.value.peer != nil }.keys.sorted()
        toHost(session, ["t": "welcome", "role": "host", "players": players, "now": Self.now])
        for player in session.players.values { player.peer?.send(#"{"t":"state","host":true}"#) }
    }

    private func hostLeft(_ session: Session, app: String) {
        session.host = nil
        for player in session.players.values { player.peer?.send(#"{"t":"state","host":false}"#) }
    }

    /// Ends the game of every app whose phone page isn't served any more.
    func endAll(except serving: Set<String>) {
        for app in sessions.keys where !serving.contains(app) { end(app) }
    }

    /// The app has stopped: its phones are let go, and their links and credentials are no use any more.
    func end(_ app: String) {
        guard let session = sessions.removeValue(forKey: app) else { return }
        for player in session.players.values { player.peer?.close(code: 4005) }
        switch session.host {
        case .socket(let peer): peer.close(code: 4005)
        case .preview(let deliver): deliver(#"{"t":"closed"}"#)
        case nil: break
        }
        ControllerCredential.forget(app)
    }

    private func toHost(_ session: Session, _ message: [String: Any]) {
        let text = Self.json(message)
        switch session.host {
        case .preview(let deliver): deliver(text)
        case .socket(let peer): peer.send(text)
        case nil: break
        }
    }

    // Every few seconds: a beat on every socket (with Lamp's time, which the host uses to tell how old movement is),
    // fresh credentials for the phones each minute, and sockets that have gone quiet let go.
    private func startTicking() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: Limits.beat, repeats: true) { _ in
            MainActor.assumeIsolated { PhoneControllers.shared.tick() }
        }
    }

    private func tick() {
        let now = Date()
        let beat = Self.json(["t": "beat", "now": Self.now])
        for (app, session) in sessions {
            let renew = now.timeIntervalSince(session.renewed) >= 60
            if renew { session.renewed = now }
            for (number, player) in session.players {
                guard let peer = player.peer else {
                    if player.heldUntil < now { session.players[number] = nil }
                    continue
                }
                if now.timeIntervalSince(peer.heard) > Limits.silence { peer.close(code: 4002); continue }
                peer.send(beat)
                if renew {
                    peer.send(Self.json(["t": "credential", "credential": ControllerCredential.issue(kind: .controller, app: app, player: number)]))
                }
            }
            switch session.host {
            case .socket(let peer):
                if now.timeIntervalSince(peer.heard) > Limits.silence { peer.close(code: 4002) } else { peer.send(beat) }
            case .preview(let deliver):
                deliver(beat)
            case nil:
                break
            }
        }
    }

    private static var now: Int { Int(Date().timeIntervalSince1970 * 1000) }
    private static func clamp(_ value: Any?) -> Double {
        guard let n = (value as? NSNumber)?.doubleValue, n.isFinite else { return 0 }
        return max(-1, min(1, n))
    }
    static func parse(_ text: String) -> [String: Any]? {
        guard text.utf8.count <= Limits.message else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }
    static func json(_ value: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8), as: UTF8.self)
    }
}

/// The controllers' credentials: short signed tokens, each for one kind of holder in one app's session, signed with a key
/// that lives only in this Lamp's memory, so none outlives Lamp, and none is the app's token for its AI.
///
///   host        the app on a TV, for its socket, for as long as a session may last.
///   join        what a phone's link carries, after the #, which a browser never sends: for fifteen minutes.
///   controller  given to a phone once it has joined: its player, for two minutes, renewed while it stays, so a phone
///               that drops off comes back as the same player.
enum ControllerCredential {
    enum Kind: String, CaseIterable {
        case host, join, controller
        var lifetime: TimeInterval {
            switch self {
            case .host: 12 * 3600
            case .join: 15 * 60
            case .controller: 2 * 60
            }
        }
    }

    struct Claim: Equatable {
        let kind: Kind
        let app: String
        let player: Int?
    }

    nonisolated(unsafe) private static var key = SymmetricKey(size: .bits256)
    /// Each app's generation: ending its session makes every credential it handed out worthless.
    nonisolated(unsafe) private static var generations: [String: Int] = [:]
    private static let lock = NSLock()

    static func issue(kind: Kind, app: String, player: Int? = nil, now: Date = Date()) -> String {
        lock.lock(); defer { lock.unlock() }
        var payload: [String: Any] = ["k": kind.rawValue, "a": app, "g": generations[app] ?? 0,
                                      "e": Int(now.addingTimeInterval(kind.lifetime).timeIntervalSince1970),
                                      "n": Data((0..<9).map { _ in UInt8.random(in: 0...255) }).urlSafeBase64]
        if let player { payload["p"] = player }
        let body = ((try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()).urlSafeBase64
        return body + "." + Data(HMAC<SHA256>.authenticationCode(for: Data(body.utf8), using: key)).urlSafeBase64
    }

    /// What a credential says when this Lamp made it, for this app in its current session, of one of these kinds, and it
    /// hasn't run out; nil otherwise, whatever is wrong with it.
    static func check(_ token: String?, kinds: Set<Kind>, app: String, now: Date = Date()) -> Claim? {
        guard let token, token.utf8.count <= 1024 else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let signature = Data(urlSafeBase64: String(parts[1])) else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: Data(parts[0].utf8), using: key),
              let body = Data(urlSafeBase64: String(parts[0])),
              let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let kind = (payload["k"] as? String).flatMap(Kind.init(rawValue:)), kinds.contains(kind),
              payload["a"] as? String == app, payload["g"] as? Int == (generations[app] ?? 0),
              let expires = payload["e"] as? Int, Double(expires) > now.timeIntervalSince1970 else { return nil }
        return Claim(kind: kind, app: app, player: payload["p"] as? Int)
    }

    static func forget(_ app: String) {
        lock.lock(); defer { lock.unlock() }
        generations[app, default: 0] += 1
    }
}

extension Data {
    var urlSafeBase64: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    init?(urlSafeBase64 text: String) {
        guard text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        var plain = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        plain += String(repeating: "=", count: (4 - plain.count % 4) % 4)
        self.init(base64Encoded: plain)
    }
}

/// The server side of a WebSocket on a connection the gateway has taken (RFC 6455): text messages, pings and closes,
/// each message capped, small enough to read whole.
@MainActor
final class WebSocketPeer {
    private let connection: NWConnection
    private let key: String
    private var buffer = Data()
    private var parts = Data()
    private(set) var open = true
    /// Sent messages not yet handed to the network: how far behind the other end is.
    private(set) var pending = 0
    private(set) var heard = Date()
    var onMessage: (String) -> Void = { _ in }
    var onClose: () -> Void = {}

    init(connection: NWConnection, key: String, leftover: Data) {
        self.connection = connection
        self.key = key
        self.buffer = leftover
    }

    func start() {
        let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
        connection.send(content: Data("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n".utf8),
                        completion: .contentProcessed { _ in })
        process()
        receive()
    }

    func send(_ text: String) {
        guard open else { return }
        pending += 1
        connection.send(content: Self.frame(0x1, Data(text.utf8)), completion: .contentProcessed { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.pending -= 1 } }
        })
    }

    func close(code: UInt16 = 1000) {
        guard open else { return }
        let payload = Data([UInt8(code >> 8), UInt8(code & 0xff)])
        connection.send(content: Self.frame(0x8, payload), completion: .contentProcessed { [connection] _ in connection.cancel() })
        closed()
    }

    private func closed() {
        guard open else { return }
        open = false
        onClose()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.open else { return }
                    if let data { self.buffer.append(data) }
                    self.process()
                    if done || error != nil { self.connection.cancel(); self.closed() } else if self.open { self.receive() }
                }
            }
        }
    }

    private func process() {
        while open {
            guard let frame = Self.parse(buffer) else { return }
            guard frame.length > 0 else { return close(code: 1009) }   // too big, or not masked as a client's must be
            buffer.removeFirst(frame.length)
            heard = Date()
            switch frame.opcode {
            case 0x8: return close()
            case 0x9: connection.send(content: Self.frame(0xA, frame.payload), completion: .contentProcessed { _ in })
            case 0xA: break
            case 0x0, 0x1:
                parts.append(frame.payload)
                guard parts.count <= PhoneControllers.Limits.message else { return close(code: 1009) }
                if frame.fin {
                    let text = String(decoding: parts, as: UTF8.self)
                    parts = Data()
                    onMessage(text)
                }
            default:
                return close(code: 1003)   // binary isn't spoken here
            }
        }
    }

    private static func frame(_ opcode: UInt8, _ payload: Data) -> Data {
        var head = Data([0x80 | opcode])
        if payload.count < 126 { head.append(UInt8(payload.count)) }
        else if payload.count < 65536 { head.append(contentsOf: [126, UInt8(payload.count >> 8), UInt8(payload.count & 0xff)]) }
        else { head.append(127); head.append(contentsOf: (0..<8).reversed().map { UInt8((UInt64(payload.count) >> ($0 * 8)) & 0xff) }) }
        return head + payload
    }

    /// One frame off the front: nil while it hasn't all come, length 0 when it's too big or unmasked.
    private static func parse(_ data: Data) -> (fin: Bool, opcode: UInt8, payload: Data, length: Int)? {
        let bytes = [UInt8](data.prefix(14))
        guard bytes.count >= 2 else { return nil }
        let fin = bytes[0] & 0x80 != 0, opcode = bytes[0] & 0x0f
        guard bytes[1] & 0x80 != 0 else { return (fin, opcode, Data(), 0) }
        var length = Int(bytes[1] & 0x7f), offset = 2
        if length == 126 {
            guard bytes.count >= 4 else { return nil }
            length = Int(bytes[2]) << 8 | Int(bytes[3]); offset = 4
        } else if length == 127 {
            return (fin, opcode, Data(), 0)
        }
        guard length <= PhoneControllers.Limits.message else { return (fin, opcode, Data(), 0) }
        guard data.count >= offset + 4 + length else { return nil }
        let start = data.startIndex
        let mask = [UInt8](data[(start + offset)..<(start + offset + 4)])
        var payload = [UInt8](data[(start + offset + 4)..<(start + offset + 4 + length)])
        for i in payload.indices { payload[i] ^= mask[i & 3] }
        return (fin, opcode, Data(payload), offset + 4 + length)
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
        // Stopping the listener leaves the sockets it took open, so the game ends too: its phones and host are let go
        // and its credentials are worthless, whether the app was deleted or is no longer set to open anywhere.
        PhoneControllers.shared.endAll(except: serving)
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
                PhoneControllers.shared.siteOpened(app)
                TVPreview.phonePageMoved(app, to: TVs.phonePage(port: port))
            }
        }
        var avoided: Set<UInt16> = []
        for _ in 0..<4 {
            guard let port = port(for: app, avoiding: avoided) else { return false }
            let site = Gateway(site: port, pages: { request in
                await Store.shared.phonePage(request.within(app))
            }, sockets: { request, connection, leftover in
                Task { @MainActor in Store.shared.phoneSocket(request.within(app), connection: connection, leftover: leftover) }
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
