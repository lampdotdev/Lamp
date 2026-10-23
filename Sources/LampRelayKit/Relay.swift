import CryptoKit
import Foundation
import Network

/// Phones and a TV app's page talking to each other, in a process of Lamp's own (`LampRelay`, which Lamp starts while a
/// TV app takes players), never in Lamp's: a phone's page, a wish's Mac app, and the TV app's page (in the preview or on
/// the TV) each open a WebSocket here, and the relay passes what they say on, on a queue of its own. Lamp only opens and
/// ends each app's session (`configure`, `end`) and hands out the credentials that let each one in, signed with the key
/// it gave the relay; the relay makes the ones a session goes on to need (a link's, a phone's renewal) with the same key.
///
/// Each running TV app is one session: one host (its page) and up to eight phones, each at a place (1…8) the TV page
/// numbers as it likes (`player` messages). Phones send buttons, sticks and messages to the host, and files both ways,
/// in pieces with their own flow control (`ControllerWire`). The relay keeps nothing once it's passed on, holds every
/// file to the size it was announced at and to a window ahead of what's been acknowledged, and lets go of anything
/// that doesn't keep to that.
public final class Relay: @unchecked Sendable {
    public struct Session: Equatable, Sendable {
        /// Lamp's generation of the app's session: credentials of an earlier one get nowhere.
        public var generation: Int
        /// The port the app's phone page is served at, and the address phones open (`link`), when it has one.
        public var pagePort: UInt16?
        public var page: String?
        /// The names and addresses the page is served as (this Mac's), lowercased: the only pages let in.
        public var hosts: [String]
        public init(generation: Int, pagePort: UInt16?, page: String?, hosts: [String]) {
            self.generation = generation
            self.pagePort = pagePort
            self.page = page
            self.hosts = hosts
        }
    }

    final class Transfer {
        let size: Int
        var passed = 0
        var acknowledged = 0
        /// Pieces passed that haven't been acknowledged yet: an acknowledgement goes on only for one, so a receiver
        /// can't flood the sender with them.
        var unacknowledged = 0
        init(size: Int) { self.size = size }

        /// Whether an acknowledgement is one to pass on: it's for more than the last, no more than has been passed, and
        /// for a piece not yet acknowledged (or the end of an empty file). False for anything else, which is dropped.
        func acknowledge(_ got: Int) -> Bool {
            if size == 0, got == 0, acknowledged == 0, unacknowledged == 0 { unacknowledged = -1; return true }
            guard got > acknowledged, got <= passed, unacknowledged > 0 else { return false }
            acknowledged = got
            unacknowledged -= 1
            return true
        }
    }

    final class Player {
        var peer: RelayPeer?
        /// While a phone that dropped off may still come back with its credential, its place stays its own.
        var heldUntil = Date.distantPast
        var tokens = ControllerWire.perSecond
        var refilled = Date()
        /// Since when it has gone on past its rate, with no more than a moment's pause, and when it last did.
        var over: Date?
        var lastDropped = Date.distantPast
        /// Files on their way from the phone to the host, and from the host to the phone, by the sender's id.
        var toHost: [UInt32: Transfer] = [:]
        var toPhone: [UInt32: Transfer] = [:]
        init(peer: RelayPeer) { self.peer = peer }
    }

    final class Game {
        var session: Session
        var host: RelayPeer?
        var hostIsPreview = false
        var players: [Int: Player] = [:]
        var renewed = Date()
        init(session: Session) { self.session = session }
    }

    public let queue = DispatchQueue(label: "dev.lamp.relay")
    private let key: SymmetricKey
    private var listener: NWListener?
    /// The listener stopped after it was ready (the network went away under it): whoever runs the relay starts it again.
    public var onStopped: @Sendable () -> Void = {}
    private var games: [String: Game] = [:]
    /// Sockets not yet past their hello: held here, since nothing else holds them until they're a player or a host.
    private var greeting: [ObjectIdentifier: (peer: RelayPeer, from: String)] = [:]
    /// How many sockets may wait to say hello at once, in all and from one address (an IPv6 one by its network, since a
    /// device can take many there): a phone or a TV opens one at a time.
    static let greetingLimit = (all: 64, each: 8)
    /// Text waiting to go to the host past which phones' messages to it are dropped, well before the host is let go
    /// for falling behind (`RelayPeer.textLimit`). Changed only by tests, which make a host count as behind.
    nonisolated(unsafe) static var hostBehind = 128
    private var ticker: DispatchSourceTimer?

    public init(key: SymmetricKey) {
        self.key = key
    }

    // MARK: Listening

    /// Starts listening on every address, at `port` when it's free (the one it had before, so phones' pages find it
    /// where they last did), else wherever the system gives. `ready` hears the port once, nil when it couldn't.
    public func start(port: UInt16 = 0, ready: @escaping @Sendable (UInt16?) -> Void) {
        queue.async { self.listen(port, ready: ready) }
    }

    private func listen(_ port: UInt16, ready: @escaping @Sendable (UInt16?) -> Void) {
        let socket = NWProtocolWebSocket.Options()
        socket.autoReplyPing = true
        socket.maximumMessageSize = ControllerWire.chunk + ControllerWire.header
        socket.setClientRequestHandler(queue) { [weak self] _, headers in
            let admitted = self?.admits(origin: headers.first { $0.name.lowercased() == "origin" }?.value) ?? false
            return NWProtocolWebSocket.Response(status: admitted ? .accept : .reject, subprotocol: nil)
        }
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(socket, at: 0)
        guard let listener = try? NWListener(using: parameters, on: port == 0 ? .any : (NWEndpoint.Port(rawValue: port) ?? .any)) else {
            return port == 0 ? ready(nil) : listen(0, ready: ready)
        }
        var told = false
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard !told else { return }
                told = true
                ready(listener?.port?.rawValue)
            case .failed:
                listener?.cancel()
                if self.listener === listener { self.listener = nil }
                guard !told else { return self.onStopped() }
                told = true
                // The port it had before is someone else's now: anywhere will do.
                if port != 0 { self.listen(0, ready: ready) } else { ready(nil) }
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    /// A browser always says which page opened a socket: of web pages, only an app's own phone page, at the port it's
    /// served at by one of this Mac's names, is let in. A TV app's page isn't a web page: in the preview it's at the
    /// preview's own address, on a TV a file of its package ("file://", or "null"), and a wish's own app sends no origin
    /// at all. Each of those, like any client that isn't a browser, could say whatever origin it liked, so the
    /// credential in its hello is what lets it in, as it is for everyone. Which app's page asked isn't known here (the
    /// Network framework doesn't say which socket a handshake is for); a page of one app can't hold another's
    /// credentials, which are what decide the app.
    private func admits(origin: String?) -> Bool {
        guard let origin else { return true }
        if ["null", "file://", "lamp-tv://app"].contains(origin.lowercased()) { return true }
        guard let url = URL(string: origin), url.scheme == "http", let host = url.host?.lowercased(), let port = url.port else { return false }
        return games.values.contains { $0.session.pagePort.map(Int.init) == port && $0.session.hosts.contains(host) }
    }

    public func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            for app in Array(self.games.keys) { self.endGame(app) }
            for waiting in self.greeting.values { waiting.peer.close(code: 1001) }
            self.greeting = [:]
            self.ticker?.cancel()
            self.ticker = nil
        }
    }

    // MARK: Sessions, from Lamp

    /// Opens an app's session, or brings it up to date (its page moved). A new generation ends the old game first.
    public func configure(app: String, _ session: Session) {
        queue.async {
            if let game = self.games[app], game.session.generation != session.generation { self.endGame(app) }
            if let game = self.games[app] {
                let moved = game.session.page != session.page
                game.session = session
                if moved, game.host != nil { self.sendLink(game, app: app) }
            } else {
                self.games[app] = Game(session: session)
                self.startTicking()
            }
        }
    }

    /// The app's session is over: its phones and host are let go.
    public func end(app: String) {
        queue.async { self.endGame(app) }
    }

    private func endGame(_ app: String) {
        guard let game = games.removeValue(forKey: app) else { return }
        for player in game.players.values { player.peer?.close(code: 4005) }
        game.host?.close(code: 4005)
    }

    // MARK: Sockets

    private func accept(_ connection: NWConnection) {
        var from = "?"
        if case .hostPort(let host, _) = connection.endpoint {
            switch host {
            case .ipv6(let address) where address.asIPv4 == nil: from = address.rawValue.prefix(8).map { String(format: "%02x", $0) }.joined()
            default: from = "\(host)"
            }
        }
        guard greeting.count < Self.greetingLimit.all, greeting.values.filter({ $0.from == from }).count < Self.greetingLimit.each else {
            return connection.cancel()
        }
        let peer = RelayPeer(connection: connection)
        let id = ObjectIdentifier(peer)
        var greeted = false
        greeting[id] = (peer, from)
        peer.onClose = { [weak self] in self?.greeting[id] = nil }
        peer.onBinary = { [weak peer] _ in peer?.close(code: 4003) }
        peer.onText = { [weak self, weak peer] text in
            guard let self, let peer, !greeted else { return }
            greeted = true
            self.greeting[id] = nil
            self.hello(peer, text: text)
        }
        peer.start(on: queue)
        startTicking()
        queue.asyncAfter(deadline: .now() + 5) { [weak self, weak peer] in
            guard !greeted else { return }
            peer?.close(code: 4001)
            self?.greeting[id] = nil
        }
    }

    private func hello(_ peer: RelayPeer, text: String) {
        guard let hello = Self.parse(text), hello["t"] as? String == "hello", let app = hello["app"] as? String,
              let game = games[app],
              let claim = ControllerToken.check(hello["credential"] as? String, kinds: [.host, .join, .controller], app: app,
                                                generation: game.session.generation, key: key)
        else { return peer.close(code: 4003) }
        if claim.kind == .host { return joinAsHost(peer, game: game, app: app, preview: claim.preview) }
        joinAsPlayer(peer, game: game, app: app, resuming: claim.kind == .controller ? claim.player : nil)
    }

    private func joinAsHost(_ peer: RelayPeer, game: Game, app: String, preview: Bool) {
        if let old = game.host {
            // The preview is the app's host on this Mac: a TV running the same app meanwhile waits for it to close.
            if game.hostIsPreview && !preview { return peer.close(code: 4009) }
            old.onClose = {}
            old.close(code: 4000)
            dropTransfers(game)
            // The files on their way to or from the old host end with it, and each phone hears so, as when a host just
            // leaves, before it hears the new one is there.
            for player in game.players.values { player.peer?.send(#"{"t":"state","host":false}"#) }
        }
        game.host = peer
        game.hostIsPreview = preview
        peer.onText = { [weak self, weak game] text in
            guard let self, let game, let message = Self.parse(text) else { return }
            self.fromHost(game, app: app, message: message)
        }
        peer.onBinary = { [weak self, weak game] data in
            guard let self, let game else { return }
            self.pieceFromHost(game, data: data)
        }
        peer.onClose = { [weak self, weak game, weak peer] in
            guard let self, let game, game.host === peer else { return }
            game.host = nil
            game.hostIsPreview = false
            self.dropTransfers(game)
            for player in game.players.values { player.peer?.send(#"{"t":"state","host":false}"#) }
        }
        let players = game.players.filter { $0.value.peer != nil }.keys.sorted()
        peer.send(Self.json(["t": "welcome", "role": "host", "players": players, "now": Self.now]))
        for player in game.players.values { player.peer?.send(#"{"t":"state","host":true}"#) }
    }

    private func joinAsPlayer(_ peer: RelayPeer, game: Game, app: String, resuming: Int?) {
        let now = Date()
        var number = resuming
        if let resuming, let old = game.players[resuming]?.peer {
            old.onClose = {}
            old.close(code: 4000)   // the same phone, back on a new connection
            if let host = game.host { host.send(Self.json(["t": "left", "player": resuming])) }
        }
        if number == nil {
            number = (1...ControllerWire.players).first { n in
                guard let player = game.players[n] else { return true }
                return player.peer == nil && player.heldUntil < now
            }
        }
        guard let number else {
            peer.send(#"{"t":"full"}"#)
            return peer.close(code: 4004)
        }
        let player = Player(peer: peer)
        game.players[number] = player
        peer.send(Self.json(["t": "welcome", "role": "controller", "place": number, "host": game.host != nil,
                             "credential": ControllerToken.issue(kind: .controller, app: app, generation: game.session.generation,
                                                                 player: number, key: key)]))
        game.host?.send(Self.json(["t": "joined", "player": number]))
        peer.onText = { [weak self, weak game, weak player] text in
            guard let self, let game, let player else { return }
            self.fromPlayer(game, number: number, player: player, text: text)
        }
        peer.onBinary = { [weak self, weak game, weak player] data in
            guard let self, let game, let player else { return }
            self.pieceFromPlayer(game, number: number, player: player, data: data)
        }
        peer.onClose = { [weak game, weak player, weak peer] in
            guard let game, let player, game.players[number] === player, player.peer === peer else { return }
            player.peer = nil
            player.heldUntil = Date().addingTimeInterval(ControllerToken.Kind.controller.lifetime)
            player.toHost = [:]
            player.toPhone = [:]
            game.host?.send(Self.json(["t": "left", "player": number]))
        }
    }

    // MARK: From a phone

    private func fromPlayer(_ game: Game, number: Int, player: Player, text: String) {
        guard let message = Self.parse(text) else { return }
        let kind = message["t"] as? String ?? ""
        // A file's acknowledgements come as fast as its pieces, and are what keeps it moving: they aren't counted.
        guard ["file-ack", "file-cancel", "file-refuse"].contains(kind) || allowed(player) else { return }
        guard let host = game.host else {
            if kind == "file", let id = ControllerWire.isID(message["id"]) {
                player.peer?.send(Self.json(["t": "file-refuse", "id": id, "reason": "The TV app isn't there."]))
            }
            return
        }
        // A TV that's behind isn't let go for what phones send it: what they send meanwhile is dropped instead, all but
        // what keeps a file moving, and buttons, whose letting go the TV must never miss (a button it thinks is still
        // held stays held). They're small, and the rate a phone may send at bounds them.
        if host.pendingText > Self.hostBehind, !["file-ack", "file-cancel", "file-refuse", "button"].contains(kind) {
            if kind == "file", let id = ControllerWire.isID(message["id"]) { refuse(player, id: id, "The TV app is busy; try again.") }
            return
        }
        let at = Self.now
        let seq = message["seq"] as? Int ?? 0
        let name = (message["name"] as? String).flatMap { $0.range(of: "^[A-Za-z0-9_-]{1,32}$", options: .regularExpression) != nil ? $0 : nil }
        switch kind {
        case "button":
            guard let name else { return }
            host.send(Self.json(["t": "button", "player": number, "name": name, "down": message["down"] as? Bool == true, "seq": seq, "at": at]))
        case "axis":
            guard let name else { return }
            // Movement is only worth its latest value: when the TV is behind, it's dropped rather than queued.
            if host.pendingText > ControllerWire.backlog { return }
            host.send(Self.json(["t": "axis", "player": number, "name": name, "x": Self.clamp(message["x"]), "y": Self.clamp(message["y"]), "seq": seq, "at": at]))
        case "message":
            guard let data = message["data"] else { return }
            host.send(Self.json(["t": "message", "player": number, "data": data, "at": at]))
        case "too-big":
            // A message the phone's own library refused as over the limit: said in the TV app's log, where the builder
            // looks, since the phone's console is out of sight.
            guard let bytes = message["bytes"] as? Int else { return }
            host.send(Self.json(["t": "too-big", "player": number, "bytes": bytes]))
        case "file":
            guard let id = ControllerWire.isID(message["id"]) else { return }
            guard let size = message["size"] as? Int, size >= 0, size <= ControllerWire.file else {
                return refuse(player, id: id, "The file is too big to send.")
            }
            guard player.toHost[id] == nil, player.toHost.count < ControllerWire.transfers else {
                return refuse(player, id: id, "Another file is still on its way.")
            }
            player.toHost[id] = Transfer(size: size)
            host.send(Self.json(["t": "file", "player": number, "id": id, "name": Self.short(message["name"], 200),
                                 "type": Self.short(message["type"], 100), "size": size, "at": at]))
        case "file-cancel":
            guard let id = ControllerWire.isID(message["id"]), player.toHost.removeValue(forKey: id) != nil else { return }
            host.send(Self.json(["t": "file-cancel", "player": number, "id": id]))
        case "file-ack":
            guard let id = ControllerWire.isID(message["id"]), let transfer = player.toPhone[id], let got = message["got"] as? Int,
                  transfer.acknowledge(got) else { return }
            if got == transfer.size { player.toPhone[id] = nil }
            host.send(Self.json(["t": "file-ack", "player": number, "id": id, "got": got]))
        case "file-refuse":
            guard let id = ControllerWire.isID(message["id"]), player.toPhone.removeValue(forKey: id) != nil else { return }
            host.send(Self.json(["t": "file-refuse", "player": number, "id": id, "reason": Self.short(message["reason"], 200)]))
        default:
            break
        }
    }

    private func pieceFromPlayer(_ game: Game, number: Int, player: Player, data: Data) {
        guard let (_, id) = ControllerWire.chunkHeader(data), let transfer = player.toHost[id] else { return }
        let bytes = data.count - ControllerWire.header
        // A piece past the file's size, or past the window the host has acknowledged, is a sender that doesn't keep to
        // what it said: the file goes no further.
        guard let host = game.host, bytes > 0, transfer.passed + bytes <= transfer.size,
              transfer.passed + bytes - transfer.acknowledged <= ControllerWire.window + ControllerWire.chunk,
              host.send(piece: ControllerWire.readdressed(data, to: UInt8(number))) else {
            player.toHost[id] = nil
            game.host?.send(Self.json(["t": "file-cancel", "player": number, "id": id]))
            return refuse(player, id: id, "The file didn't keep to its size.")
        }
        transfer.passed += bytes
        transfer.unacknowledged += 1
    }

    // MARK: From the host

    private func fromHost(_ game: Game, app: String, message: [String: Any]) {
        let number = message["player"] as? Int ?? 0
        let player = game.players[number]
        switch message["t"] as? String {
        case "link":
            sendLink(game, app: app)
        case "send":
            guard let data = message["data"] else { return }
            let text = Self.json(["t": "message", "data": data])
            for (place, each) in game.players where number == 0 || number == place { each.peer?.send(text) }
        case "player":
            // The number the TV page knows this phone by, which the phone shows.
            guard let player, let shown = message["number"] as? Int, shown > 0, shown < 1000 else { return }
            player.peer?.send(Self.json(["t": "player", "number": shown]))
        case "file":
            guard let id = ControllerWire.isID(message["id"]) else { return }
            guard let player, let peer = player.peer, let size = message["size"] as? Int, size >= 0, size <= ControllerWire.file,
                  player.toPhone[id] == nil, player.toPhone.count < ControllerWire.transfers else {
                game.host?.send(Self.json(["t": "file-refuse", "player": number, "id": id, "reason": "The phone can't take it now."]))
                return
            }
            player.toPhone[id] = Transfer(size: size)
            peer.send(Self.json(["t": "file", "id": id, "name": Self.short(message["name"], 200), "type": Self.short(message["type"], 100), "size": size]))
        case "file-cancel":
            guard let id = ControllerWire.isID(message["id"]), let player, player.toPhone.removeValue(forKey: id) != nil else { return }
            player.peer?.send(Self.json(["t": "file-cancel", "id": id]))
        case "file-ack":
            guard let id = ControllerWire.isID(message["id"]), let player, let transfer = player.toHost[id], let got = message["got"] as? Int,
                  transfer.acknowledge(got) else { return }
            if got == transfer.size { player.toHost[id] = nil }
            player.peer?.send(Self.json(["t": "file-ack", "id": id, "got": got]))
        case "file-refuse":
            guard let id = ControllerWire.isID(message["id"]), let player, player.toHost.removeValue(forKey: id) != nil else { return }
            player.peer?.send(Self.json(["t": "file-refuse", "id": id, "reason": Self.short(message["reason"], 200)]))
        default:
            break
        }
    }

    private func pieceFromHost(_ game: Game, data: Data) {
        guard let (place, id) = ControllerWire.chunkHeader(data), let player = game.players[Int(place)], let transfer = player.toPhone[id] else { return }
        let bytes = data.count - ControllerWire.header
        guard let peer = player.peer, bytes > 0, transfer.passed + bytes <= transfer.size,
              transfer.passed + bytes - transfer.acknowledged <= ControllerWire.window + ControllerWire.chunk,
              peer.send(piece: ControllerWire.readdressed(data, to: 0)) else {
            return cancelToPhone(game, number: Int(place), player: player, id: id)
        }
        transfer.passed += bytes
        transfer.unacknowledged += 1
    }

    private func cancelToPhone(_ game: Game, number: Int, player: Player, id: UInt32) {
        player.toPhone[id] = nil
        player.peer?.send(Self.json(["t": "file-cancel", "id": id]))
        game.host?.send(Self.json(["t": "file-refuse", "player": number, "id": id, "reason": "The file didn't keep to its size."]))
    }

    private func refuse(_ player: Player, id: UInt32, _ reason: String) {
        player.peer?.send(Self.json(["t": "file-refuse", "id": id, "reason": reason]))
    }

    /// A host that leaves takes every file on its way with it; each phone hears its host has gone, which ends its own.
    private func dropTransfers(_ game: Game) {
        for player in game.players.values {
            player.toHost = [:]
            player.toPhone = [:]
        }
    }

    /// A link for phones: the page's address with a fresh join credential after the #.
    private func sendLink(_ game: Game, app: String) {
        guard let page = game.session.page, let host = game.host else { return }
        let join = ControllerToken.issue(kind: .join, app: app, generation: game.session.generation, key: key)
        host.send(Self.json(["t": "link", "url": page + "#" + join]))
    }

    // A phone may send about as often as its screen draws; past that its messages are dropped, and a phone that goes
    // on past it for ten seconds is let go.
    private func allowed(_ player: Player) -> Bool {
        let now = Date()
        player.tokens = min(ControllerWire.perSecond, player.tokens + now.timeIntervalSince(player.refilled) * ControllerWire.perSecond)
        player.refilled = now
        // A pause of a couple of seconds ends the stretch: a flood that lets one message through now and then still counts.
        if now.timeIntervalSince(player.lastDropped) > 2 { player.over = nil }
        if player.tokens >= 1 { player.tokens -= 1; return true }
        player.lastDropped = now
        if player.over == nil { player.over = now }
        if let over = player.over, now.timeIntervalSince(over) > 10 { player.peer?.close(code: 4008) }
        return false
    }

    // MARK: Beats

    // Every few seconds: a beat on every socket (with the relay's time, which the host uses to tell how old movement
    // is), fresh credentials for the phones each minute, and sockets that have gone quiet let go.
    private func startTicking() {
        guard ticker == nil else { return }
        let ticker = DispatchSource.makeTimerSource(queue: queue)
        ticker.schedule(deadline: .now() + ControllerWire.beat, repeating: ControllerWire.beat)
        ticker.setEventHandler { [weak self] in self?.tick() }
        ticker.resume()
        self.ticker = ticker
    }

    private func tick() {
        let now = Date()
        let beat = Self.json(["t": "beat", "now": Self.now])
        for (app, game) in games {
            let renew = now.timeIntervalSince(game.renewed) >= 60
            if renew { game.renewed = now }
            for (number, player) in game.players {
                guard let peer = player.peer else {
                    if player.heldUntil < now { game.players[number] = nil }
                    continue
                }
                if now.timeIntervalSince(peer.heard) > ControllerWire.silence { peer.close(code: 4002); continue }
                peer.send(beat)
                if renew {
                    peer.send(Self.json(["t": "credential", "credential": ControllerToken.issue(kind: .controller, app: app, generation: game.session.generation,
                                                                                               player: number, key: key)]))
                }
            }
            if let host = game.host {
                if now.timeIntervalSince(host.heard) > ControllerWire.silence { host.close(code: 4002) } else { host.send(beat) }
            }
        }
    }

    // MARK: For tests

    /// The app's session as the relay has it, read on its queue.
    public func hasSession(_ app: String) -> Bool { queue.sync { games[app] != nil } }

    private static var now: Int { Int(Date().timeIntervalSince1970 * 1000) }
    private static func clamp(_ value: Any?) -> Double {
        guard let n = (value as? NSNumber)?.doubleValue, n.isFinite else { return 0 }
        return max(-1, min(1, n))
    }
    private static func short(_ value: Any?, _ limit: Int) -> String { String(((value as? String) ?? "").prefix(limit)) }
    static func parse(_ text: String) -> [String: Any]? {
        guard text.utf8.count <= ControllerWire.message else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }
    static func json(_ value: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8), as: UTF8.self)
    }
}
