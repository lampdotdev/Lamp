import CryptoKit
import LampRelayKit
import XCTest

/// A wish's apps in their room at the relay: each gets in by proving it holds the wish's key, hears who else is there,
/// and sends JSON to one of them or to all, sealed; someone without the key gets in nowhere, and nothing seen on the
/// network lets them in or reads what the apps say.
final class WishRoomTests: XCTestCase {
    private let key = WishChannel.random(32)
    private let room = "wish:scoreboard"
    private let apps: [String: (kind: String, name: String)] = ["tv": ("tv", "the TV app"), "iphone": ("iphone", "the iPhone app"),
                                                               "android": ("android", "the Android app")]

    private func start() async throws -> (Relay, URL) {
        let relay = Relay(key: SymmetricKey(size: .bits256))
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        relay.configureRoom(room, key: key, apps: apps)
        return (relay, try XCTUnwrap(URL(string: "ws://127.0.0.1:\(port)/")))
    }

    private func join(_ address: URL, as peer: String, device: String, key: Data? = nil, wire: Int? = nil) async throws -> WishPeer {
        try await WishPeer.join(address, as: peer, device: device, key: key ?? self.key, wire: wire)
    }

    func testTheAppsOfAWishSeeEachOtherAndExchangeMessages() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }

        let tv = try await join(address, as: "tv", device: "TV preview")
        let welcomeTV = try await tv.next()
        XCTAssertEqual(welcomeTV["t"] as? String, "welcome")
        XCTAssertEqual(welcomeTV["peer"] as? String, "tv")
        XCTAssertEqual((welcomeTV["peers"] as? [[String: Any]])?.count, 0, "nobody else yet")
        XCTAssertNil(welcomeTV["credential"], "nothing to come back with: the key is what lets an app in")

        let phone = try await join(address, as: "iphone", device: "iPhone simulator")
        let welcomePhone = try await phone.next()
        let seen = try XCTUnwrap((welcomePhone["peers"] as? [[String: Any]])?.first)
        XCTAssertEqual(seen["peer"] as? String, "tv")
        XCTAssertEqual(seen["kind"] as? String, "tv")
        XCTAssertEqual(seen["name"] as? String, "the TV app")
        XCTAssertEqual(seen["device"] as? String, "TV preview")
        let joined = try await tv.next()
        XCTAssertEqual(joined["t"] as? String, "joined")
        XCTAssertEqual((joined["peer"] as? [String: Any])?["peer"] as? String, "iphone")

        // To one peer, and to everyone else.
        try await phone.send(["t": "send", "to": "tv", "data": ["score": 3]])
        let heard = try await tv.next()
        XCTAssertEqual(heard["t"] as? String, "message")
        XCTAssertEqual(heard["from"] as? String, "iphone")
        XCTAssertEqual((heard["data"] as? [String: Any])?["score"] as? Int, 3)

        let android = try await join(address, as: "android", device: "Android emulator")
        _ = try await android.next()
        _ = try await tv.next()      // joined
        _ = try await phone.next()   // joined
        try await tv.send(["t": "send", "data": "round 2"])
        let onPhone = try await phone.next(), onAndroid = try await android.next()
        XCTAssertEqual(onPhone["data"] as? String, "round 2")
        XCTAssertEqual(onAndroid["data"] as? String, "round 2")

        // A message to an app that isn't there comes back as undelivered, and nothing crashes.
        android.socket.cancel(with: .goingAway, reason: nil)
        let left = try await tv.next()
        XCTAssertEqual(left["t"] as? String, "left")
        XCTAssertEqual(left["peer"] as? String, "android")
        _ = try await phone.next()
        try await tv.send(["t": "send", "to": "android", "data": 1])
        let undelivered = try await tv.next()
        XCTAssertEqual(undelivered["t"] as? String, "undelivered")
        XCTAssertEqual(undelivered["to"] as? String, "android")
        XCTAssertEqual(relay.members(of: room), ["iphone", "tv"])
        tv.socket.cancel(with: .goingAway, reason: nil)
        phone.socket.cancel(with: .goingAway, reason: nil)
    }

    func testOnlyAnAppHoldingTheWishsKeyGetsIn() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        // Another wish's key: its tag names no room here.
        try await Self.refused(try await join(address, as: "tv", device: "x", key: WishChannel.random(32)).socket)
        // A peer id the wish has no app for.
        try await Self.refused(try await join(address, as: "roku", device: "x").socket)
        // Someone who saw this wish's tag on the network but hasn't its key: the relay answers, and their proof fails.
        let socket = URLSession.shared.webSocketTask(with: address)
        socket.resume()
        try await socket.send(.string(Self.json(["t": "hello", "tag": WishChannel.tag(for: SymmetricKey(data: key)).base64EncodedString(),
                                                 "peer": "tv", "nonce": WishChannel.random(16).base64EncodedString()])))
        guard case .string(let text) = try await socket.receive() else { return XCTFail("no challenge") }
        XCTAssertEqual(Self.parse(text)?["t"] as? String, "challenge")
        try await socket.send(.string(Self.json(["t": "proof", "proof": WishChannel.random(32).base64EncodedString()])))
        try await Self.refused(socket)
        // A TV app's game credential isn't for a room.
        relay.configure(app: "scoreboard", Relay.Session(generation: 0, pagePort: nil, page: nil, hosts: []))
        let host = URLSession.shared.webSocketTask(with: address)
        host.resume()
        try await host.send(.string(Self.json(["t": "hello", "app": room, "credential": ControllerToken.issue(kind: .host, app: room, generation: 0, key: SymmetricKey(size: .bits256))])))
        try await Self.refused(host)
        XCTAssertEqual(relay.members(of: room), [])
    }

    /// Someone on the Wi‑Fi who recorded an app joining and talking: nothing they saw is a credential, nothing they saw
    /// reads as what the apps said, and the hello and proof sent again from somewhere else get nowhere, while the app
    /// they named stays in the room.
    func testWhatAnEavesdropperSawNeitherReadsNorGetsThemIn() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        let tv = try await join(address, as: "tv", device: "TV")
        _ = try await tv.next()
        let phone = try await join(address, as: "iphone", device: "iPhone")
        _ = try await phone.next()
        _ = try await tv.next()   // joined
        try await phone.send(["t": "send", "to": "tv", "data": "the secret score is 41"])
        let heard = try await tv.next()
        XCTAssertEqual(heard["data"] as? String, "the secret score is 41")

        let seen = phone.wire + tv.wire
        for message in seen {
            switch message {
            case .string(let text):
                XCTAssertTrue(["hello", "challenge", "proof", "beat"].contains(Self.parse(text)?["t"] as? String ?? ""), "only the handshake and beats in clear: \(text)")
                XCTAssertFalse(text.contains("credential"))
            case .data(let data):
                XCTAssertNil(data.range(of: Data("secret score".utf8)), "a message crosses sealed")
                XCTAssertNil(data.range(of: Data("welcome".utf8)))
            @unknown default:
                break
            }
        }
        // The phone's own hello and proof, sent again on a socket of their own.
        let texts = phone.wire.compactMap { message -> String? in if case .string(let text) = message, Self.parse(text)?["t"] as? String != "beat" { return text }; return nil }
        let hello = try XCTUnwrap(texts.first { Self.parse($0)?["t"] as? String == "hello" })
        let proof = try XCTUnwrap(texts.first { Self.parse($0)?["t"] as? String == "proof" })
        let replay = URLSession.shared.webSocketTask(with: address)
        replay.resume()
        try await replay.send(.string(hello))
        _ = try await replay.receive()   // a fresh challenge, which the old proof doesn't answer
        try await replay.send(.string(proof))
        try await Self.refused(replay)
        XCTAssertEqual(relay.members(of: room), ["iphone", "tv"], "the app it named is still in the room")
        try await phone.send(["t": "send", "to": "tv", "data": "still you?"])
        let still = try await tv.next()
        XCTAssertEqual(still["data"] as? String, "still you?")
    }

    /// A sealed message sent again, one changed on the way, or anything in clear but a beat, after the handshake: the
    /// relay lets that link go rather than pass it on.
    func testAMessageReplayedChangedOrInClearLetsTheLinkGo() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        for attack in ["replayed", "changed", "clear"] {
            let tv = try await join(address, as: "tv", device: "TV")
            _ = try await tv.next()
            let phone = try await join(address, as: "iphone", device: "iPhone")
            _ = try await phone.next()
            _ = try await tv.next()   // joined
            let sealed = phone.sealer!.seal(try JSONSerialization.data(withJSONObject: ["t": "send", "to": "tv", "data": 1]))
            try await phone.socket.send(.data(sealed))
            let first = try await tv.next()
            XCTAssertEqual(first["data"] as? Int, 1)
            switch attack {
            case "replayed": try await phone.socket.send(.data(sealed))
            case "changed":
                var changed = phone.sealer!.seal(try JSONSerialization.data(withJSONObject: ["t": "send", "to": "tv", "data": 2]))
                changed[changed.startIndex + 3] ^= 0x40
                try await phone.socket.send(.data(changed))
            default: try await phone.socket.send(.string(Self.json(["t": "send", "to": "tv", "data": 3])))
            }
            try await Self.closed(phone.socket, code: 4003)
            let left = try await tv.next()
            XCTAssertEqual(left["t"] as? String, "left", attack)
            tv.socket.cancel(with: .goingAway, reason: nil)
            for _ in 0..<50 where !relay.members(of: room).isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        }
    }

    /// Someone who saw a wish's tag on the network can start handshakes they can't finish: from one address, no more
    /// than eight sockets wait unproven at once, through the hello and the proof alike.
    func testOneAddressHoldsNoMoreThanEightUnprovenSockets() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        let tag = WishChannel.tag(for: SymmetricKey(data: key)).base64EncodedString()
        var waiting: [URLSessionWebSocketTask] = []
        for _ in 0..<8 {
            let socket = URLSession.shared.webSocketTask(with: address)
            socket.resume()
            try await socket.send(.string(Self.json(["t": "hello", "tag": tag, "peer": "tv", "nonce": WishChannel.random(16).base64EncodedString()])))
            guard case .string(let text) = try await socket.receive() else { return XCTFail("no challenge") }
            XCTAssertEqual(Self.parse(text)?["t"] as? String, "challenge")
            waiting.append(socket)
        }
        defer { for socket in waiting { socket.cancel(with: .goingAway, reason: nil) } }
        // The ninth from the same address isn't taken at all: no challenge comes.
        let ninth = URLSession.shared.webSocketTask(with: address)
        ninth.resume()
        try? await ninth.send(.string(Self.json(["t": "hello", "tag": tag, "peer": "tv", "nonce": WishChannel.random(16).base64EncodedString()])))
        let answered = try? await ninth.receive()
        if case .string(let text)? = answered { XCTFail("a ninth unproven socket was answered: \(text)") }
    }

    func testANewKeyOrTheRoomsEndLetsItsMembersGo() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        let tv = try await join(address, as: "tv", device: "TV")
        _ = try await tv.next()
        let fresh = WishChannel.random(32)
        relay.configureRoom(room, key: fresh, apps: apps)
        try await Self.closed(tv.socket, code: 4005)
        // The old key is no use for the room now.
        try await Self.refused(try await join(address, as: "tv", device: "TV").socket)
        let again = try await join(address, as: "tv", device: "TV", key: fresh)
        let welcomed = try await again.next()
        XCTAssertEqual(welcomed["t"] as? String, "welcome")
        relay.endRoom(room)
        try await Self.closed(again.socket, code: 4005)
    }

    func testTheSameAppBackOnANewSocketTakesItsPlace() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        let tv = try await join(address, as: "tv", device: "TV")
        _ = try await tv.next()
        let first = try await join(address, as: "iphone", device: "iPhone")
        _ = try await first.next()
        let arrived = try await tv.next()
        XCTAssertEqual(arrived["t"] as? String, "joined")
        let second = try await join(address, as: "iphone", device: "iPhone")
        let welcomed = try await second.next()
        XCTAssertEqual(welcomed["t"] as? String, "welcome")
        try await Self.closed(first.socket, code: 4000)
        XCTAssertEqual(relay.members(of: room), ["iphone", "tv"])
        // The others see it leave and arrive again, so they can catch it up on what it missed while it was away.
        let left = try await tv.next(), joined = try await tv.next()
        XCTAssertEqual("\(left["t"] ?? "") \(left["peer"] ?? "")", "left iphone")
        XCTAssertEqual(joined["t"] as? String, "joined")
    }

    /// An app added to the wish, or taken from it, while others are in the room: they're told the list again, so the new
    /// one is known before it opens and the one gone is forgotten.
    func testMembersHearTheWishsAppsWhenTheyChange() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        let tv = try await join(address, as: "tv", device: "TV")
        let welcome = try await tv.next()
        XCTAssertEqual((welcome["apps"] as? [[String: Any]])?.compactMap { $0["peer"] as? String }, ["android", "iphone", "tv"])

        relay.configureRoom(room, key: key, apps: ["tv": ("tv", "the TV app"), "iphone": ("iphone", "the iPhone app"),
                                                   "android": ("android", "the Android app"), "mac": ("mac", "the Mac app")])
        let added = try await tv.next()
        XCTAssertEqual(added["t"] as? String, "apps")
        XCTAssertEqual((added["apps"] as? [[String: Any]])?.compactMap { $0["peer"] as? String }, ["android", "iphone", "mac", "tv"])

        relay.configureRoom(room, key: key, apps: ["tv": ("tv", "the TV app"), "mac": ("mac", "the Mac app")])
        let taken = try await tv.next()
        XCTAssertEqual((taken["apps"] as? [[String: Any]])?.compactMap { $0["peer"] as? String }, ["mac", "tv"])
    }

    /// An app the wish asks for and Lamp hasn't made is marked so in the list the others hear, so they say it isn't ready
    /// rather than ask the person to open it; once it's made, they hear the list again without the mark.
    func testAnAppNotMadeYetIsMarkedInTheList() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        relay.configureRoom(room, key: key, apps: apps, waiting: ["android"])
        let tv = try await join(address, as: "tv", device: "TV")
        let welcome = try await tv.next()
        let listed = (welcome["apps"] as? [[String: Any]] ?? []).map { "\($0["peer"] as? String ?? ""):\($0["waiting"] as? Bool ?? false)" }
        XCTAssertEqual(listed, ["android:true", "iphone:false", "tv:false"])
        relay.configureRoom(room, key: key, apps: apps)
        let made = try await tv.next()
        XCTAssertEqual(made["t"] as? String, "apps")
        XCTAssertEqual((made["apps"] as? [[String: Any]])?.compactMap { $0["waiting"] }.count, 0)
    }

    /// What an app says of its own link (its state, and the apps it reaches straight) is kept for Lamp, which tells the
    /// builder, and isn't passed to the others.
    func testWhatAnAppSaysOfItsLinkReachesLampAlone() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        let said = Said()
        relay.onRoomChanged = { _, members in said.add(members) }
        let tv = try await join(address, as: "tv", device: "TV")
        _ = try await tv.next()
        let phone = try await join(address, as: "iphone", device: "iPhone")
        _ = try await phone.next()
        _ = try await tv.next()   // joined
        try await phone.send(["t": "status", "state": "localNetworkDenied", "direct": ["tv", "roku"]])
        try await phone.send(["t": "send", "to": "tv", "data": 1])
        let next = try await tv.next()
        XCTAssertEqual(next["t"] as? String, "message", "the others hear nothing of it: \(next)")
        let phoneSaid = try XCTUnwrap(said.last?.first { $0["peer"] as? String == "iphone" })
        let link = try XCTUnwrap(phoneSaid["link"] as? [String: Any])
        XCTAssertEqual(link["state"] as? String, "localNetworkDenied")
        XCTAssertEqual(link["direct"] as? [String], ["tv"], "only apps the wish has")
        tv.socket.cancel(with: .goingAway, reason: nil)
        phone.socket.cancel(with: .goingAway, reason: nil)
    }

    /// Values go to the one app they're for, with who sent them, and the relay keeps none of them; each member says what
    /// it speaks in its join, which the others hear with it (1 for an app from before that says nothing).
    func testValuesGoToTheAppTheyreForAndEachSaysWhatItSpeaks() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        let tv = try await join(address, as: "tv", device: "TV", wire: 2)
        _ = try await tv.next()
        let phone = try await join(address, as: "iphone", device: "iPhone")
        let welcome = try await phone.next()
        XCTAssertEqual((welcome["peers"] as? [[String: Any]])?.first?["wire"] as? Int, 2)
        let joined = try await tv.next()
        XCTAssertEqual((joined["peer"] as? [String: Any])?["wire"] as? Int, 1, "an app from before says nothing of it")
        let android = try await join(address, as: "android", device: "Android", wire: 2)
        _ = try await android.next()
        _ = try await tv.next()
        _ = try await phone.next()

        let values: [String: Any] = ["list": ["v": ["milk"], "c": [5, 0, "tv"]]]
        try await tv.send(["t": "values", "to": "android", "values": values])
        try await tv.send(["t": "values", "to": "mac", "values": values])   // no such member: nothing comes back
        try await tv.send(["t": "send", "data": "after"])
        let got = try await android.next()
        XCTAssertEqual(got["t"] as? String, "values")
        XCTAssertEqual(got["from"] as? String, "tv")
        XCTAssertEqual(((got["values"] as? [String: Any])?["list"] as? [String: Any])?["v"] as? [String], ["milk"])
        let onPhone = try await phone.next()
        XCTAssertEqual(onPhone["data"] as? String, "after", "the other app heard none of it: \(onPhone)")
        _ = try await android.next()
        tv.socket.cancel(with: .goingAway, reason: nil)
        phone.socket.cancel(with: .goingAway, reason: nil)
        android.socket.cancel(with: .goingAway, reason: nil)
    }

    private final class Said: @unchecked Sendable {
        private let lock = NSLock()
        private var lists: [[[String: Any]]] = []
        func add(_ members: [[String: Any]]) { lock.lock(); lists.append(members); lock.unlock() }
        var last: [[String: Any]]? { lock.lock(); defer { lock.unlock() }; return lists.last }
    }

    /// A file goes to the one app it's for: its start and its pieces with the sender's name where the receiver's was, its
    /// acknowledgements back; a piece past the size the file said ends it for both. A file for an app from before files is
    /// turned down, and nothing of it reaches that app.
    func testAFilesPiecesGoToTheAppTheyreForAndKeepToWhatItSaid() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        let tv = try await join(address, as: "tv", device: "TV", wire: 3)
        _ = try await tv.next()
        let phone = try await join(address, as: "iphone", device: "iPhone", wire: 3)
        _ = try await phone.next()
        _ = try await tv.next()
        let android = try await join(address, as: "android", device: "Android", wire: 2)
        _ = try await android.next()
        _ = try await tv.next()
        _ = try await phone.next()

        try await tv.send(["t": "file", "to": "android", "id": 1, "name": "old.bin", "type": "", "size": 10])
        let turnedDown = try await tv.next()
        XCTAssertEqual(turnedDown["t"] as? String, "file-refuse")
        XCTAssertEqual(turnedDown["from"] as? String, "android")
        XCTAssertEqual(turnedDown["reason"] as? String, "That app is out of date.")

        try await tv.send(["t": "file", "to": "iphone", "id": 7, "name": "picture.png", "type": "image/png", "size": 6])
        let started = try await phone.next()
        XCTAssertEqual(started["t"] as? String, "file")
        XCTAssertEqual(started["from"] as? String, "tv")
        XCTAssertEqual(started["size"] as? Int, 6)
        XCTAssertEqual(started["name"] as? String, "picture.png")
        try await tv.sendSealed(WishChannel.piece(peer: "iphone", id: 7, bytes: Data([1, 2, 3, 4])))
        let piece = try await phone.nextPlain()
        let header = try XCTUnwrap(WishChannel.pieceHeader(piece))
        XCTAssertEqual(header.peer, "tv", "the receiver hears who it's from")
        XCTAssertEqual(header.id, 7)
        XCTAssertEqual([UInt8](piece.dropFirst(header.offset)), [1, 2, 3, 4])
        try await phone.send(["t": "file-ack", "to": "tv", "id": 7, "got": 4])
        let acknowledged = try await tv.next()
        XCTAssertEqual(acknowledged["t"] as? String, "file-ack")
        XCTAssertEqual(acknowledged["from"] as? String, "iphone")
        XCTAssertEqual(acknowledged["got"] as? Int, 4)

        try await tv.sendSealed(WishChannel.piece(peer: "iphone", id: 7, bytes: Data([5, 6, 7])))
        let cancelled = try await phone.next()
        XCTAssertEqual(cancelled["t"] as? String, "file-cancel", "a piece past its size ends it: \(cancelled)")
        let refused = try await tv.next()
        XCTAssertEqual(refused["t"] as? String, "file-refuse")
        XCTAssertEqual(refused["reason"] as? String, "The file didn't keep to its size.")

        try await tv.send(["t": "send", "data": "after"])
        let onAndroid = try await android.next()
        XCTAssertEqual(onAndroid["data"] as? String, "after", "the app from before files heard none of it: \(onAndroid)")
        for each in [tv, phone, android] { each.socket.cancel(with: .goingAway, reason: nil) }
    }

    // MARK: Helpers

    private static func refused(_ socket: URLSessionWebSocketTask) async throws { try await closed(socket, code: 4003) }

    private static func closed(_ socket: URLSessionWebSocketTask, code: Int) async throws {
        do {
            while true {
                switch try await socket.receive() {
                case .data: XCTFail("let in: a sealed message came")
                case .string(let text):
                    if let message = parse(text), message["t"] as? String != "beat", message["t"] as? String != "challenge" { XCTFail("let in: \(message)") }
                @unknown default: break
                }
            }
        } catch {
            XCTAssertEqual(socket.closeCode.rawValue, code)
        }
    }

    static func parse(_ text: String) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] }

    static func json(_ value: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: value)) ?? Data(), as: UTF8.self)
    }
}

/// One app of the wish on its own socket, joined the way LampSupport joins: hello, the relay's challenge checked,
/// its proof, then everything sealed. `wire` is every message that crossed the socket either way, as it went.
final class WishPeer {
    let socket: URLSessionWebSocketTask
    var sealer: WishChannel.Sealer?
    var opener: WishChannel.Sealer?
    var wire: [URLSessionWebSocketTask.Message] = []
    init(_ socket: URLSessionWebSocketTask) { self.socket = socket }

    func say(_ message: URLSessionWebSocketTask.Message) async throws { wire.append(message); try await socket.send(message) }
    func hear() async throws -> URLSessionWebSocketTask.Message { let m = try await socket.receive(); wire.append(m); return m }

    func send(_ value: [String: Any]) async throws {
        try await say(.data(sealer!.seal(try JSONSerialization.data(withJSONObject: value))))
    }

    func sendSealed(_ plain: Data) async throws { try await say(.data(sealer!.seal(plain))) }

    /// What the next sealed message holds, as it is, past beats.
    func nextPlain() async throws -> Data {
        while true {
            switch try await hear() {
            case .data(let sealed): return try XCTUnwrap(opener!.open(sealed), "a sealed message that opens")
            case .string(let text): XCTAssertEqual(WishRoomTests.parse(text)?["t"] as? String, "beat", "only beats are in clear: \(text)")
            @unknown default: continue
            }
        }
    }

    /// The next sealed message, past beats.
    func next() async throws -> [String: Any] {
        while true {
            switch try await hear() {
            case .data(let sealed):
                let plain = try XCTUnwrap(opener!.open(sealed), "a sealed message that opens")
                return try XCTUnwrap((try JSONSerialization.jsonObject(with: plain)) as? [String: Any])
            case .string(let text):
                XCTAssertEqual(WishRoomTests.parse(text)?["t"] as? String, "beat", "only beats are in clear: \(text)")
            @unknown default:
                continue
            }
        }
    }

    static func join(_ address: URL, as peer: String, device: String, key: Data, wire: Int? = nil) async throws -> WishPeer {
        let joined = WishPeer(URLSession.shared.webSocketTask(with: address))
        joined.socket.maximumMessageSize = 1 << 20
        joined.socket.resume()
        let key = SymmetricKey(data: key)
        let tag = WishChannel.tag(for: key), nonce = WishChannel.random(16)
        try await joined.say(.string(WishRoomTests.json(["t": "hello", "tag": tag.base64EncodedString(), "peer": peer, "nonce": nonce.base64EncodedString()])))
        // Turned away at its hello, the socket is closed before any challenge: what it was closed with is the caller's to see.
        guard let first = try? await joined.hear(), case .string(let text) = first, let challenge = WishRoomTests.parse(text), challenge["t"] as? String == "challenge",
              let theirs = (challenge["nonce"] as? String).flatMap({ Data(base64Encoded: $0) }),
              let proof = (challenge["proof"] as? String).flatMap({ Data(base64Encoded: $0) }) else { return joined }
        let transcript = WishChannel.transcript(tag: tag, client: peer, server: challenge["peer"] as? String ?? "", clientNonce: nonce, serverNonce: theirs)
        XCTAssertEqual(proof, WishChannel.serverProof(key: key, transcript: transcript), "the relay proves it holds the wish's key")
        try await joined.say(.string(WishRoomTests.json(["t": "proof", "proof": WishChannel.clientProof(key: key, transcript: transcript).base64EncodedString()])))
        let keys = WishChannel.keys(key: key, transcript: transcript)
        joined.sealer = WishChannel.Sealer(key: keys.client)
        joined.opener = WishChannel.Sealer(key: keys.server)
        try await joined.send(wire.map { ["t": "join", "device": device, "wire": $0] } ?? ["t": "join", "device": device])
        return joined
    }
}
