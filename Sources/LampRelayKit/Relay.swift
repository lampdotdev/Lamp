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
///
/// Beside the games, a **room** for each wish of more than one app (`configureRoom`, with the wish's key): the wish's
/// apps join it as peers by proving they hold the key, over a handshake that sends nothing anyone could use again
/// (`WishChannel`), and everything after it is sealed, so what they say crosses the network unreadable. A peer names
/// which app it is in its hello, hears who else is in the room (`welcome`, `joined`, `left`) and sends JSON messages to
/// one peer or to all (`send` → `message`) and the values they share to one peer (`values`), under the same size and
/// rate limits as a phone's; it keeps no values itself. What the copies share in collections (`LampStore.shared`) Lamp
/// keeps, as a member under the relay's own name (`WishKeeper`), when Lamp gives the room a folder for it. Files go to one peer in pieces (`WishChannel.piece`) under the
/// controllers' flow (`ControllerWire`: a window ahead of what's acknowledged, two at once each way between two apps),
/// and a game's controls from a wish's app to its TV app's `Lamp.controllers` as `pad` messages; both only to an app
/// that speaks 3 or more, since an earlier one would take a piece for a message gone wrong. The relay tells whoever
/// runs it who is in each room (`onRoomChanged`), so Lamp can say so to the builder.
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

    /// How often one socket may send: about as often as a screen draws. Past that its messages are dropped, and one
    /// that goes on past it for ten seconds is let go.
    final class Rate {
        var tokens = ControllerWire.perSecond
        var refilled = Date()
        /// Since when it has gone on past its rate, with no more than a moment's pause, and when it last did.
        var over: Date?
        var lastDropped = Date.distantPast

        func allowed(_ peer: RelayPeer?) -> Bool {
            let now = Date()
            tokens = min(ControllerWire.perSecond, tokens + now.timeIntervalSince(refilled) * ControllerWire.perSecond)
            refilled = now
            // A pause of a couple of seconds ends the stretch: a flood that lets one message through now and then still counts.
            if now.timeIntervalSince(lastDropped) > 2 { over = nil }
            if tokens >= 1 { tokens -= 1; return true }
            lastDropped = now
            if over == nil { over = now }
            if let over, now.timeIntervalSince(over) > 10 { peer?.close(code: 4008) }
            return false
        }
    }

    final class Player {
        var peer: RelayPeer?
        /// While a phone that dropped off may still come back with its credential, its place stays its own.
        var heldUntil = Date.distantPast
        let rate = Rate()
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

    /// One of a wish's apps in its room, by the peer id it proved itself as, with its link's seals each way.
    final class Member {
        let peer: RelayPeer
        let kind: String
        let name: String
        let device: String
        /// What it speaks, as it said in its join: 1 for an app from before values, which said nothing of it.
        let wire: Int
        let since = Date()
        let rate = Rate()
        var sealer: WishChannel.Sealer
        var opener: WishChannel.Sealer
        /// Where the app listens for the wish's other apps, as it said: what they keep for when Lamp is closed.
        var at: [String] = []
        /// How its link stands, as it last said: its state, and the apps it reaches straight. For Lamp, not the others.
        var link: [String: Any] = [:]
        /// Files on their way from it, by the peer each is for and its id (`sendingKey`).
        var sending: [String: Transfer] = [:]
        /// How often it may send a game's controls to each player, apart (an app, and which of its controllers): a TV app
        /// speaks to each of its players every frame. A few dozen at most are kept, so made-up ids hold nothing for long.
        var padRates: [String: Rate] = [:]
        init(peer: RelayPeer, kind: String, name: String, device: String, wire: Int, sealer: WishChannel.Sealer, opener: WishChannel.Sealer) {
            self.peer = peer
            self.kind = kind
            self.name = name
            self.device = device
            self.wire = wire
            self.sealer = sealer
            self.opener = opener
        }
        var described: [String: Any] { ["kind": kind, "name": name, "device": device, "wire": wire, "since": Int(since.timeIntervalSince1970 * 1000), "at": at] }
        /// What a message `to` reaches: the copy it names, or every copy of the app it names.
        func isFor(_ to: String, id: String) -> Bool { id == to || (!to.contains(".") && WishChannel.app(of: id) == to) }
        /// Everything to a member goes sealed, in the order it's said, on the relay's queue.
        func send(_ text: String) { peer.send(sealed: sealer.seal(Data(text.utf8))) }
    }

    /// A wish's room: its key, which apps it may have (from Lamp, by peer id: what each is called), and which are in it now.
    final class Room {
        let key: SymmetricKey
        let keyData: Data
        let tag: Data
        var apps: [String: (kind: String, name: String)]
        var waiting: Set<String> = []
        var members: [String: Member] = [:]
        /// Lamp keeping the wish's shared collections (`WishKeeper`), when Lamp gave the room a folder for them.
        var keeper: WishKeeper?
        init(key: Data, apps: [String: (kind: String, name: String)]) {
            self.keyData = key
            self.key = SymmetricKey(data: key)
            self.tag = WishChannel.tag(for: self.key)
            self.apps = apps
        }
    }

    public let queue = DispatchQueue(label: "dev.lamp.relay")
    private let key: SymmetricKey
    private var listener: NWListener?
    /// The listener stopped after it was ready (the network went away under it): whoever runs the relay starts it again.
    public var onStopped: @Sendable () -> Void = {}
    private var games: [String: Game] = [:]
    private var rooms: [String: Room] = [:]
    /// Each room by its tag, which is all a hello says of which wish it's for.
    private var tags: [Data: String] = [:]
    /// Sockets past their hello and not yet in a room: proving they hold the wish's key.
    private var proving: [ObjectIdentifier: (peer: RelayPeer, from: String)] = [:]
    /// Who is in a room, each time that changes: the room's key and its members (`peer`, `kind`, `name`, `device`, `since`).
    public var onRoomChanged: @Sendable (_ room: String, _ members: [[String: Any]]) -> Void = { _, _ in }
    /// What a copy said to Lamp itself (`send` to the relay's name): what it has of a page's change. For Lamp alone.
    public var onHeard: @Sendable (_ room: String, _ copy: String, _ data: Any) -> Void = { _, _, _ in }
    /// Sockets not yet past their hello: held here, since nothing else holds them until they're a player or a host.
    private var greeting: [ObjectIdentifier: (peer: RelayPeer, from: String)] = [:]
    /// How many sockets may wait to say hello at once, in all and from one address (an IPv6 one by its network, since a
    /// device can take many there): a phone or a TV opens one at a time.
    static let greetingLimit = (all: 64, each: 8)
    /// Text waiting to go to the host past which phones' messages to it are dropped, well before the host is let go
    /// for falling behind (`RelayPeer.textLimit`). Changed only by tests, which make a host count as behind.
    nonisolated(unsafe) static var hostBehind = 128
    private var ticker: DispatchSourceTimer?

    /// The largest message a socket takes: a file's piece, a game's or a wish's sealed one with its header and seal. A
    /// browser and an Android app send each as one frame, never split, so the whole piece must fit in one.
    public static let messageLimit = ControllerWire.chunk + 1024

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
        socket.maximumMessageSize = Self.messageLimit
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
    /// preview's own address, on a TV a file of its package ("file://", or "null"), a game's on the Mac at the address
    /// Lamp's app around it serves it at, and a wish's own app sends no origin at all. Each of those, like any client that isn't a browser, could say whatever origin it liked, so the
    /// credential in its hello is what lets it in, as it is for everyone. Which app's page asked isn't known here (the
    /// Network framework doesn't say which socket a handshake is for); a page of one app can't hold another's
    /// credentials, which are what decide the app.
    private func admits(origin: String?) -> Bool {
        guard let origin else { return true }
        if ["null", "file://", "lamp-tv://app", "lamp-game://app"].contains(origin.lowercased()) { return true }
        guard let url = URL(string: origin), url.scheme == "http", let host = url.host?.lowercased(), let port = url.port else { return false }
        return games.values.contains { $0.session.pagePort.map(Int.init) == port && $0.session.hosts.contains(host) }
    }

    /// The process is ending: what each room's keeper hasn't written yet is written now, before this returns, so a
    /// change a copy made in the last moment before Lamp quit isn't lost. Never on the relay's own queue.
    public func finish() {
        queue.sync { for room in rooms.values { room.keeper?.close() } }
    }

    public func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            for app in Array(self.games.keys) { self.endGame(app) }
            for room in Array(self.rooms.keys) { self.endRoom(room) }
            for waiting in self.greeting.values { waiting.peer.close(code: 1001) }
            self.greeting = [:]
            for waiting in self.proving.values { waiting.peer.close(code: 1001) }
            self.proving = [:]
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

    /// Opens a wish's room, or brings it up to date (an app added or taken away). `key`: the wish's key, which every app
    /// of the wish holds and proves it does to get in; `apps`: each app the wish may have, by its peer id, with its kind
    /// and name; a peer whose id isn't among them is turned away. `waiting`: those of them Lamp hasn't made yet, so the
    /// others can say so. `keep`: the folder Lamp keeps the wish's shared collections in (`WishKeeper`), none for a
    /// room that keeps nothing. A new key ends the old room first, letting its members go.
    public func configureRoom(_ room: String, key: Data, apps: [String: (kind: String, name: String)], waiting: Set<String> = [], keep: URL? = nil) {
        queue.async {
            if let known = self.rooms[room], known.keyData != key { self.closeRoom(room) }
            if let known = self.rooms[room] {
                known.keeper?.appCount = apps.count
                let changed = Set(known.apps.map { "\($0.key)\t\($0.value.kind)\t\($0.value.name)" })
                    != Set(apps.map { "\($0.key)\t\($0.value.kind)\t\($0.value.name)" }) || known.waiting != waiting
                known.apps = apps
                known.waiting = waiting
                for (id, member) in known.members where apps[WishChannel.app(of: id)] == nil { member.peer.close(code: 4005); known.members[id] = nil }
                // An app added to the wish or taken from it, while the others are in the room: they hear the list again,
                // so the one not open yet is known to them, and the one gone isn't.
                if changed {
                    let list = Self.json(["t": "apps", "apps": Self.roster(known)])
                    for member in known.members.values { member.send(list) }
                }
            } else {
                let made = Room(key: key, apps: apps)
                made.waiting = waiting
                if let keep { made.keeper = self.keeper(for: made, in: keep) }
                self.rooms[room] = made
                self.tags[made.tag] = room
                self.startTicking()
            }
        }
    }

    /// Lamp's own word to some copies of a wish's apps (a page's change put into each open copy, `Store.pageToCopies`):
    /// passed as a message from the relay's own name, which no app of a wish has (`prove`), so a page can tell it's
    /// Lamp's. `done` is told the copies it went to.
    public func say(in room: String, to copies: [String], data: Any, done: @escaping ([String]) -> Void) {
        queue.async {
            guard let known = self.rooms[room] else { return done([]) }
            let out = Self.json(["t": "message", "from": WishChannel.relayName, "data": data, "at": Self.now])
            var reached: [String] = []
            for id in copies.sorted() {
                guard let member = known.members[id] else { continue }
                member.send(out)
                reached.append(id)
            }
            done(reached)
        }
    }

    /// The wish is gone, or its room isn't wanted any more: its members are let go. `forget`: the wish is gone, and what
    /// Lamp kept of its shared collections goes with it.
    public func endRoom(_ room: String, forget: Bool = false) {
        queue.async {
            if forget { self.rooms[room]?.keeper?.forget() }
            self.closeRoom(room)
        }
    }

    /// Lamp as a keeper of the room's shared collections, speaking to its members as the relay's own name.
    private func keeper(for room: Room, in folder: URL) -> WishKeeper {
        let keeper = WishKeeper(folder: folder, key: room.key, queue: queue)
        keeper.appCount = room.apps.count
        keeper.send = { [weak room] copy, message in
            // A copy that has stopped reading misses what's said meanwhile, as from another copy: the next sums make it up.
            guard let member = room?.members[copy], member.wire >= WishKeeper.wire, member.peer.pendingText <= Self.hostBehind else { return }
            var out = message
            out["from"] = WishChannel.relayName
            member.send(Self.json(out))
        }
        keeper.sendPiece = { [weak room] copy, piece in
            guard let member = room?.members[copy], member.wire >= WishKeeper.wire else { return false }
            return member.peer.send(piece: piece, seal: { [weak member] plain in member?.sealer.seal(plain) ?? Data() })
        }
        keeper.present = { [weak room] in room?.members.mapValues(\.wire) ?? [:] }
        return keeper
    }

    private func closeRoom(_ room: String) {
        guard let known = rooms.removeValue(forKey: room) else { return }
        known.keeper?.close()
        if tags[known.tag] == room { tags[known.tag] = nil }
        for member in known.members.values { member.peer.close(code: 4005) }
        if !known.members.isEmpty { onRoomChanged(room, []) }
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
        // Unproven sockets are held to these from their hello through a wish's handshake, which a tag seen on the
        // network is enough to start.
        guard greeting.count + proving.count < Self.greetingLimit.all,
              greeting.values.filter({ $0.from == from }).count + proving.values.filter({ $0.from == from }).count < Self.greetingLimit.each else {
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
            self.hello(peer, text: text, from: from)
        }
        peer.start(on: queue)
        startTicking()
        queue.asyncAfter(deadline: .now() + 5) { [weak self, weak peer] in
            guard !greeted else { return }
            peer?.close(code: 4001)
            self?.greeting[id] = nil
        }
    }

    private func hello(_ peer: RelayPeer, text: String, from: String) {
        guard let hello = Self.parse(text), hello["t"] as? String == "hello" else { return peer.close(code: 4003) }
        // A wish's app names its wish by its tag alone; a TV app's game is named by its app, with a credential for it.
        if hello["tag"] != nil { return prove(peer, hello: hello, from: from) }
        guard let app = hello["app"] as? String, let game = games[app],
              let claim = ControllerToken.check(hello["credential"] as? String, kinds: [.host, .join, .controller], app: app,
                                                generation: game.session.generation, key: key)
        else { return peer.close(code: 4003) }
        if claim.kind == .host { return joinAsHost(peer, game: game, app: app, preview: claim.preview) }
        joinAsPlayer(peer, game: game, app: app, resuming: claim.kind == .controller ? claim.player : nil)
    }

    // MARK: A wish's room

    /// A wish's app proving it holds the wish's key (`WishChannel`): its hello names the wish by tag and itself by peer
    /// id, with a nonce; the relay answers with its own nonce and its proof, and lets it into the room once its proof
    /// checks and its first sealed message says what device it is. Anything else, or nothing for a few seconds, and the
    /// socket goes, with one code for all of it so nobody learns which part was wrong.
    private func prove(_ peer: RelayPeer, hello: [String: Any], from: String) {
        guard let tag = (hello["tag"] as? String).flatMap({ Data(base64Encoded: $0) }), tag.count == WishChannel.tagSize,
              let roomKey = tags[tag], let room = rooms[roomKey],
              let id = hello["peer"] as? String, WishChannel.isName(id), room.apps[WishChannel.app(of: id)] != nil,
              // The relay's own name is Lamp's (`say`): no app takes it.
              WishChannel.app(of: id) != WishChannel.relayName,
              let clientNonce = (hello["nonce"] as? String).flatMap({ Data(base64Encoded: $0) }), clientNonce.count == WishChannel.nonceSize
        else { return peer.close(code: 4003) }
        let serverNonce = WishChannel.random(WishChannel.nonceSize)
        let transcript = WishChannel.transcript(tag: tag, client: id, server: WishChannel.relayName, clientNonce: clientNonce, serverNonce: serverNonce)
        let handle = ObjectIdentifier(peer)
        proving[handle] = (peer, from)
        peer.onClose = { [weak self] in self?.proving[handle] = nil }
        peer.send(Self.json(["t": "challenge", "peer": WishChannel.relayName, "nonce": serverNonce.base64EncodedString(),
                             "proof": WishChannel.serverProof(key: room.key, transcript: transcript).base64EncodedString()]))
        var proven = false
        peer.onText = { [weak self, weak peer, weak room] text in
            guard let self, let peer, let room else { return }
            guard !proven, let said = Self.parse(text), said["t"] as? String == "proof",
                  let proof = (said["proof"] as? String).flatMap({ Data(base64Encoded: $0) }),
                  WishChannel.same(proof, WishChannel.clientProof(key: room.key, transcript: transcript)) else { return peer.close(code: 4003) }
            proven = true
            let keys = WishChannel.keys(key: room.key, transcript: transcript)
            var opener = WishChannel.Sealer(key: keys.client)
            // From here on nothing goes in clear: a text message is someone else's, and lets the link go.
            peer.onText = { [weak peer] _ in peer?.close(code: 4003) }
            peer.onBinary = { [weak self, weak peer, weak room] sealed in
                guard let self, let peer, let room else { return }
                guard let plain = opener.open(sealed), let join = Self.parse(String(decoding: plain, as: UTF8.self)), join["t"] as? String == "join",
                      self.rooms[roomKey] === room, let named = room.apps[WishChannel.app(of: id)] else { return peer.close(code: 4003) }
                self.proving[handle] = nil
                self.joinRoom(peer, room: room, key: roomKey, id: id, kind: named.kind, name: named.name, device: Self.short(join["device"], 40),
                              wire: (join["wire"] as? Int).map { min(max($0, 1), 999) } ?? 1, sealer: WishChannel.Sealer(key: keys.server), opener: opener)
            }
        }
        peer.onBinary = { [weak peer] _ in peer?.close(code: 4003) }
        queue.asyncAfter(deadline: .now() + 5) { [weak self, weak peer] in
            guard let self, let peer, self.proving[handle]?.peer === peer else { return }
            self.proving[handle] = nil
            peer.close(code: 4001)
        }
    }

    private func joinRoom(_ peer: RelayPeer, room: Room, key: String, id: String, kind: String, name: String, device: String, wire: Int,
                          sealer: WishChannel.Sealer, opener: WishChannel.Sealer) {
        // The same copy of the app back on a new socket (reopened, or its old link not yet noticed gone): the new one is it.
        // A copy is an app on one device ("screen.k3j9x0ab"), so the same app open on another device is a member of its own.
        // The others hear that it left before they hear it join, so they see it arrive again and can catch it up on what
        // it missed.
        if let old = room.members[id] {
            old.peer.onClose = {}
            old.peer.close(code: 4000)
            room.members[id] = nil
            Self.dropFiles(to: id, in: room)
            room.keeper?.left(id)
            let left = Self.json(["t": "left", "peer": id])
            for (_, each) in room.members { each.send(left) }
        }
        let member = Member(peer: peer, kind: kind, name: name, device: device, wire: wire, sealer: sealer, opener: opener)
        let others = room.members.sorted { $0.key < $1.key }.map { Self.described($0.key, $0.value) }
        room.members[id] = member
        var welcome: [String: Any] = ["t": "welcome", "role": "peer", "peer": id, "peers": others, "apps": Self.roster(room), "now": Self.now]
        // Lamp keeps the wish's shared collections: a copy that knows it shares them with Lamp too.
        if room.keeper != nil { welcome["keeps"] = true }
        member.send(Self.json(welcome))
        let joined = Self.json(["t": "joined", "peer": Self.described(id, member)])
        for (other, each) in room.members where other != id { each.send(joined) }
        // Beats are the one thing said in clear, both ways: they carry nothing, and an app that can't hold a socket has Lamp
        // beat for it (`WishProxies`). Any other text is someone else's, and lets the link go.
        peer.onText = { [weak peer] text in if Self.parse(text)?["t"] as? String != "beat" { peer?.close(code: 4003) } }
        peer.onBinary = { [weak self, weak room, weak member] sealed in
            guard let self, let room, let member else { return }
            // A message that doesn't open as the next one from this app was changed, replayed or made up on the way.
            guard let plain = member.opener.open(sealed) else { return member.peer.close(code: 4003) }
            if plain.first == 1 { return self.pieceFromMember(room, id: id, member: member, data: plain) }
            guard plain.count <= WishChannel.sealedLimit else { return member.peer.close(code: 1009) }
            self.fromMember(room, key: key, id: id, member: member, text: String(decoding: plain, as: UTF8.self))
        }
        peer.onClose = { [weak self, weak room, weak member] in
            guard let self, let room, let member, room.members[id] === member else { return }
            room.members[id] = nil
            Self.dropFiles(to: id, in: room)
            room.keeper?.left(id)
            let left = Self.json(["t": "left", "peer": id])
            for each in room.members.values { each.send(left) }
            self.onRoomChanged(key, self.membersDescribed(room))
        }
        onRoomChanged(key, membersDescribed(room))
        room.keeper?.joined(id, wire: wire)
    }

    private func fromMember(_ room: Room, key: String, id: String, member: Member, text: String) {
        guard let message = Self.parse(text) else { return }
        let kind = message["t"] as? String ?? ""
        // How the app's link stands, for whoever builds the wish to see; said only when it changes.
        if kind == "status", member.rate.allowed(member.peer) {
            let direct = (message["direct"] as? [String] ?? []).filter { WishChannel.isName($0) && room.apps[WishChannel.app(of: $0)] != nil }.prefix(8)
            member.link = ["state": Self.short(message["state"], 32), "direct": Array(direct)]
            return onRoomChanged(key, membersDescribed(room))
        }
        // Where the app listens: a few addresses, each host:port, passed to the others to keep.
        if kind == "at", member.rate.allowed(member.peer), let given = message["addresses"] as? [String] {
            member.at = Array(given.filter { $0.utf8.count <= 64 && !$0.contains(where: { $0.isWhitespace }) }.prefix(8))
            let said = Self.json(["t": "at", "peer": id, "addresses": member.at])
            for (other, each) in room.members where other != id { each.send(said) }
            return
        }
        // The values the wish's apps share, for one copy (or each copy of one app): passed on as they are, since each copy
        // keeps and merges its own.
        if kind == "values", member.rate.allowed(member.peer), let values = message["values"] as? [String: Any],
           let to = message["to"] as? String {
            // With what the sender's values add up to, or its request for all of the other's, so a setting lost on the
            // way is made up.
            var out: [String: Any] = ["t": "values", "from": id, "values": values]
            if let sum = message["sum"] as? String, sum.utf8.count <= 64 { out["sum"] = sum }
            if message["ask"] as? Bool == true { out["ask"] = true }
            let said = Self.json(out)
            for (other, each) in room.members where other != id && each.isFor(to, id: other) && each.peer.pendingText <= Self.hostBehind { each.send(said) }
            return
        }
        // The app's shared collections (`LampStore.shared`), for one copy (or each copy of one app) that speaks 5: passed on
        // as they are, since each copy keeps and merges its own.
        if kind == "store", member.rate.allowed(member.peer), let to = message["to"] as? String {
            // For Lamp, which keeps the wish's collections; and what copies say to each other is kept as well.
            if to == WishChannel.relayName { return room.keeper?.heard(message, from: id) ?? () }
            room.keeper?.overheard(message, from: id)
            var out = message
            out["to"] = nil
            out["from"] = id
            let said = Self.json(out)
            for (other, each) in room.members where other != id && each.wire >= 5 && each.isFor(to, id: other) && each.peer.pendingText <= Self.hostBehind { each.send(said) }
            return
        }
        if kind == "pad" || kind.hasPrefix("file") { return fileOrPad(room, id: id, member: member, kind: kind, message: message) }
        guard kind == "send", member.rate.allowed(member.peer), let data = message["data"] else { return }
        let to = message["to"] as? String
        if to == WishChannel.relayName { return onHeard(key, id, data) }
        let out = Self.json(["t": "message", "from": id, "data": data, "at": Self.now])
        if let to {
            // To one copy, or to every copy of one app. Told when none is there, or the one it's for has stopped reading,
            // so the sender's library can say so.
            let targets = room.members.filter { $0.key != id && $0.value.isFor(to, id: $0.key) }
            let reading = targets.values.filter { $0.peer.pendingText <= Self.hostBehind }
            guard !reading.isEmpty else {
                return member.send(Self.json(["t": "undelivered", "to": to, "reason": targets.isEmpty ? "not in the room" : "busy"]))
            }
            for target in reading { target.send(out) }
        } else {
            for (other, each) in room.members where other != id && each.peer.pendingText <= Self.hostBehind { each.send(out) }
        }
    }

    /// A file's messages and a game's controls, each for one app (`to`) and passed on as from the sender (`from`), only to an
    /// app that speaks 3 or more. A file is held to the size it was announced at and to a window ahead of what its receiver
    /// has acknowledged, as a phone's is; its acknowledgements aren't counted against the rate, since they're what keeps it
    /// moving.
    private func fileOrPad(_ room: Room, id: String, member: Member, kind: String, message: [String: Any]) {
        guard let to = message["to"] as? String, to != id else { return }
        // A shared file's bytes to or from Lamp, which keeps them (`WishKeeper`).
        if to == WishChannel.relayName {
            guard let keeper = room.keeper, kind != "pad" else { return }
            if kind == "file" {
                guard member.rate.allowed(member.peer) else { return }
                keeper.fileStarts(message, from: id)
            } else {
                keeper.fileEnded(message, from: id)
            }
            return
        }
        let target = room.members[to].flatMap { $0.wire >= 3 ? $0 : nil }
        switch kind {
        case "pad":
            // A button let go is never dropped for a TV that's behind: one it thinks is still held stays held.
            // By the player it's for or from: an app, and which of its controllers (`pad`), since each is a player of its own.
            let player = to + "\t" + Self.short((message["m"] as? [String: Any])?["pad"], 16)
            if member.padRates[player] == nil, member.padRates.count >= 64 { member.padRates = [:] }
            let rate = member.padRates[player] ?? Rate()
            member.padRates[player] = rate
            guard room.apps[WishChannel.app(of: to)] != nil, rate.allowed(member.peer), let m = message["m"] as? [String: Any], let target,
                  target.peer.pendingText <= Self.hostBehind || (m["t"] as? String == "button" && m["down"] as? Bool != true) else { return }
            target.send(Self.json(["t": "pad", "from": id, "m": m]))
        case "file":
            guard member.rate.allowed(member.peer), let fileID = ControllerWire.isID(message["id"]) else { return }
            let refuse = { (reason: String) in member.send(Self.json(["t": "file-refuse", "from": to, "id": fileID, "reason": reason])) }
            guard let size = message["size"] as? Int, size >= 0, size <= ControllerWire.file else { return refuse("The file is too big to send.") }
            guard let target else { return refuse(room.members[to] == nil ? "That app isn't open." : "That app is out of date.") }
            guard target.peer.pendingText <= Self.hostBehind else { return refuse("That app is busy; try again.") }
            let key = Self.sendingKey(to, fileID)
            guard member.sending[key] == nil, member.sending.keys.filter({ $0.hasPrefix(to + "\t") }).count < ControllerWire.transfers else {
                return refuse("Another file is still on its way.")
            }
            member.sending[key] = Transfer(size: size)
            target.send(Self.json(["t": "file", "from": id, "id": fileID, "name": Self.short(message["name"], 200),
                                   "type": Self.short(message["type"], 100), "size": size, "ch": Self.short(message["ch"], 16)]))
        case "file-cancel":
            guard let fileID = ControllerWire.isID(message["id"]), member.sending.removeValue(forKey: Self.sendingKey(to, fileID)) != nil else { return }
            target?.send(Self.json(["t": "file-cancel", "from": id, "id": fileID]))
        case "file-ack":
            // From the file's receiver, for its sender's transfer.
            guard let fileID = ControllerWire.isID(message["id"]), let sender = room.members[to], let got = message["got"] as? Int,
                  let transfer = sender.sending[Self.sendingKey(id, fileID)], transfer.acknowledge(got) else { return }
            if got == transfer.size { sender.sending[Self.sendingKey(id, fileID)] = nil }
            sender.send(Self.json(["t": "file-ack", "from": id, "id": fileID, "got": got]))
        case "file-refuse":
            guard let fileID = ControllerWire.isID(message["id"]), let sender = room.members[to],
                  sender.sending.removeValue(forKey: Self.sendingKey(id, fileID)) != nil else { return }
            sender.send(Self.json(["t": "file-refuse", "from": id, "id": fileID, "reason": Self.short(message["reason"], 200)]))
        default:
            break
        }
    }

    /// A piece of a file from a member, for the peer its header names: passed on sealed for that peer, with the sender's
    /// name in its place. A piece past the file's size, or past the window the receiver has acknowledged, is a sender
    /// that doesn't keep to what it said: the file goes no further, and both hear so.
    private func pieceFromMember(_ room: Room, id: String, member: Member, data: Data) {
        guard let (to, fileID, offset) = WishChannel.pieceHeader(data) else { return }
        if to == WishChannel.relayName {
            let bytes = data.dropFirst(offset)
            guard !bytes.isEmpty, bytes.count <= ControllerWire.chunk else { return }
            return room.keeper?.piece(Data(bytes), id: fileID, from: id) ?? ()
        }
        guard let transfer = member.sending[Self.sendingKey(to, fileID)] else { return }
        let bytes = data.count - offset
        let kept = room.members[to] != nil && bytes > 0 && bytes <= ControllerWire.chunk && transfer.passed + bytes <= transfer.size
            && transfer.passed + bytes - transfer.acknowledged <= ControllerWire.window + ControllerWire.chunk
        guard kept, let target = room.members[to],
              target.peer.send(piece: WishChannel.piece(peer: id, id: fileID, bytes: data.dropFirst(offset)),
                               seal: { [weak target] plain in target?.sealer.seal(plain) ?? Data() }) else {
            member.sending[Self.sendingKey(to, fileID)] = nil
            room.members[to]?.send(Self.json(["t": "file-cancel", "from": id, "id": fileID]))
            member.send(Self.json(["t": "file-refuse", "from": to, "id": fileID,
                                   "reason": kept ? "That app is busy; try again." : "The file didn't keep to its size."]))
            return
        }
        transfer.passed += bytes
        transfer.unacknowledged += 1
    }

    private static func sendingKey(_ to: String, _ id: UInt32) -> String { "\(to)\t\(id)" }

    /// A member gone: the files on their way to it go with it (its own went with it), and their senders hear it left.
    private static func dropFiles(to id: String, in room: Room) {
        for member in room.members.values { member.sending = member.sending.filter { !$0.key.hasPrefix(id + "\t") } }
    }

    /// Every app the room's wish has, as a member is told it: in its welcome, and again when the list changes.
    private static func roster(_ room: Room) -> [[String: Any]] {
        room.apps.sorted { $0.key < $1.key }.map { id, app in
            var described: [String: Any] = ["peer": id, "kind": app.kind, "name": app.name]
            if room.waiting.contains(id) { described["waiting"] = true }
            return described
        }
    }

    /// A member as the others are told of it: its peer name (which copy it is), and the app it's a copy of.
    private static func described(_ id: String, _ member: Member) -> [String: Any] {
        var described = member.described
        described["peer"] = id
        described["app"] = WishChannel.app(of: id)
        return described
    }

    private func membersDescribed(_ room: Room) -> [[String: Any]] {
        room.members.sorted { $0.key < $1.key }.map { id, member in
            var described = Self.described(id, member)
            if !member.link.isEmpty { described["link"] = member.link }
            return described
        }
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

    private func allowed(_ player: Player) -> Bool { player.rate.allowed(player.peer) }

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
        for room in rooms.values {
            room.keeper?.tick()
            for member in room.members.values {
                if now.timeIntervalSince(member.peer.heard) > ControllerWire.silence { member.peer.close(code: 4002); continue }
                member.peer.send(#"{"t":"beat"}"#)
            }
        }
    }

    // MARK: For tests

    /// The app's session as the relay has it, read on its queue.
    public func hasSession(_ app: String) -> Bool { queue.sync { games[app] != nil } }
    /// Who is in a room now, read on its queue.
    public func members(of room: String) -> [String] { queue.sync { rooms[room]?.members.keys.sorted() ?? [] } }

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
        // Slashes as they came: escaped, a message heavy with them could grow past what the apps take.
        String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: .withoutEscapingSlashes)) ?? Data("{}".utf8), as: UTF8.self)
    }
}
