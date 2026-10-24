import CryptoKit
import LampRelayKit
import XCTest

/// A wish's apps in their room at the relay: each joins with a credential naming which app it is, hears who else is
/// there, and sends JSON to one of them or to all; a credential of another kind, or for another room, gets in nowhere.
final class WishRoomTests: XCTestCase {
    private let key = SymmetricKey(size: .bits256)
    private let room = "wish:scoreboard"
    private let apps: [String: (kind: String, name: String)] = ["tv": ("tv", "the TV app"), "iphone": ("iphone", "the iPhone app"),
                                                               "android": ("android", "the Android app")]

    private func start() async throws -> (Relay, URL) {
        let relay = Relay(key: key)
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        relay.configureRoom(room, generation: 0, apps: apps)
        return (relay, try XCTUnwrap(URL(string: "ws://127.0.0.1:\(port)/")))
    }

    private func join(_ address: URL, as peer: String, device: String, credential: String? = nil, room: String? = nil) async throws -> URLSessionWebSocketTask {
        let socket = URLSession.shared.webSocketTask(with: address)
        socket.maximumMessageSize = 1 << 20
        socket.resume()
        let token = credential ?? ControllerToken.issue(kind: .peer, app: self.room, generation: 0, peer: peer, key: key)
        try await socket.send(.string(Self.json(["t": "hello", "app": room ?? self.room, "credential": token, "device": device])))
        return socket
    }

    func testTheAppsOfAWishSeeEachOtherAndExchangeMessages() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }

        let tv = try await join(address, as: "tv", device: "TV preview")
        let welcomeTV = try await Self.text(tv)
        XCTAssertEqual(welcomeTV["role"] as? String, "peer")
        XCTAssertEqual(welcomeTV["peer"] as? String, "tv")
        XCTAssertEqual((welcomeTV["peers"] as? [[String: Any]])?.count, 0, "nobody else yet")

        let phone = try await join(address, as: "iphone", device: "iPhone simulator")
        let welcomePhone = try await Self.text(phone)
        let seen = try XCTUnwrap((welcomePhone["peers"] as? [[String: Any]])?.first)
        XCTAssertEqual(seen["peer"] as? String, "tv")
        XCTAssertEqual(seen["kind"] as? String, "tv")
        XCTAssertEqual(seen["name"] as? String, "the TV app")
        XCTAssertEqual(seen["device"] as? String, "TV preview")
        let joined = try await Self.text(tv)
        XCTAssertEqual(joined["t"] as? String, "joined")
        XCTAssertEqual((joined["peer"] as? [String: Any])?["peer"] as? String, "iphone")

        // To one peer, and to everyone else.
        try await phone.send(.string(Self.json(["t": "send", "to": "tv", "data": ["score": 3]])))
        let heard = try await Self.text(tv)
        XCTAssertEqual(heard["t"] as? String, "message")
        XCTAssertEqual(heard["from"] as? String, "iphone")
        XCTAssertEqual((heard["data"] as? [String: Any])?["score"] as? Int, 3)

        let android = try await join(address, as: "android", device: "Android emulator")
        _ = try await Self.text(android)
        _ = try await Self.text(tv)      // joined
        _ = try await Self.text(phone)   // joined
        try await tv.send(.string(Self.json(["t": "send", "data": "round 2"])))
        let onPhone = try await Self.text(phone), onAndroid = try await Self.text(android)
        XCTAssertEqual(onPhone["data"] as? String, "round 2")
        XCTAssertEqual(onAndroid["data"] as? String, "round 2")

        // A message to an app that isn't there comes back as undelivered, and nothing crashes.
        android.cancel(with: .goingAway, reason: nil)
        let left = try await Self.text(tv)
        XCTAssertEqual(left["t"] as? String, "left")
        XCTAssertEqual(left["peer"] as? String, "android")
        _ = try await Self.text(phone)
        try await tv.send(.string(Self.json(["t": "send", "to": "android", "data": 1])))
        let undelivered = try await Self.text(tv)
        XCTAssertEqual(undelivered["t"] as? String, "undelivered")
        XCTAssertEqual(undelivered["to"] as? String, "android")
        XCTAssertEqual(relay.members(of: room), ["iphone", "tv"])
        tv.cancel(with: .goingAway, reason: nil)
        phone.cancel(with: .goingAway, reason: nil)
    }

    func testOnlyAPeerCredentialForThisRoomNamingOneOfItsAppsGetsIn() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        relay.configure(app: "scoreboard", Relay.Session(generation: 0, pagePort: nil, page: nil, hosts: []))

        // A TV page's host credential is for its game, not the room; a peer's isn't for the game.
        let host = ControllerToken.issue(kind: .host, app: room, generation: 0, key: key)
        try await Self.refused(try await join(address, as: "tv", device: "x", credential: host))
        let peerForGame = ControllerToken.issue(kind: .peer, app: "scoreboard", generation: 0, peer: "tv", key: key)
        try await Self.refused(try await join(address, as: "tv", device: "x", credential: peerForGame, room: "scoreboard"))
        // A peer id the wish has no app for.
        let stranger = ControllerToken.issue(kind: .peer, app: room, generation: 0, peer: "roku", key: key)
        try await Self.refused(try await join(address, as: "roku", device: "x", credential: stranger))
        // Another key, or a run-out credential.
        let forged = ControllerToken.issue(kind: .peer, app: room, generation: 0, peer: "tv", key: SymmetricKey(size: .bits256))
        try await Self.refused(try await join(address, as: "tv", device: "x", credential: forged))
        let old = ControllerToken.issue(kind: .peer, app: room, generation: 0, peer: "tv", now: Date().addingTimeInterval(-2 * 3600), key: key)
        try await Self.refused(try await join(address, as: "tv", device: "x", credential: old))
        XCTAssertEqual(relay.members(of: room), [])
    }

    func testEndingOrRemakingARoomLetsItsMembersGo() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        let tv = try await join(address, as: "tv", device: "TV")
        _ = try await Self.text(tv)
        relay.configureRoom(room, generation: 1, apps: apps)
        try await Self.closed(tv, code: 4005)
        // The old generation's credential is no use for the new room.
        try await Self.refused(try await join(address, as: "tv", device: "TV"))
        let fresh = try await join(address, as: "tv", device: "TV", credential: ControllerToken.issue(kind: .peer, app: room, generation: 1, peer: "tv", key: key))
        let welcomed = try await Self.text(fresh)
        XCTAssertEqual(welcomed["t"] as? String, "welcome")
        relay.endRoom(room)
        try await Self.closed(fresh, code: 4005)
    }

    func testTheSameAppBackOnANewSocketTakesItsPlace() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        let first = try await join(address, as: "iphone", device: "iPhone")
        _ = try await Self.text(first)
        let second = try await join(address, as: "iphone", device: "iPhone")
        let welcomed = try await Self.text(second)
        XCTAssertEqual(welcomed["t"] as? String, "welcome")
        try await Self.closed(first, code: 4000)
        XCTAssertEqual(relay.members(of: room), ["iphone"])
    }

    /// Someone on the Wi‑Fi who saw an app's hello has its credential. Sent again, it gets in nowhere: it was good once,
    /// and the app it named stays in the room.
    func testACapturedHelloCredentialNeitherGetsInNorThrowsTheAppOut() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        let credential = ControllerToken.issue(kind: .peer, app: room, generation: 0, peer: "tv", key: key)
        let tv = try await join(address, as: "tv", device: "TV", credential: credential)
        let welcome = try await Self.text(tv)
        XCTAssertEqual(welcome["t"] as? String, "welcome")
        let phone = try await join(address, as: "iphone", device: "iPhone")
        _ = try await Self.text(phone)
        _ = try await Self.text(tv)   // joined

        // The same credential, sent again from somewhere else.
        try await Self.refused(try await join(address, as: "tv", device: "TV", credential: credential))
        XCTAssertEqual(relay.members(of: room), ["iphone", "tv"], "the app it named is still in the room")
        try await phone.send(.string(Self.json(["t": "send", "to": "tv", "data": "still you?"])))
        let heard = try await Self.text(tv)
        XCTAssertEqual(heard["data"] as? String, "still you?")
    }

    /// A credential is good for minutes, not an hour: one made a few minutes ago gets in nowhere.
    func testAPeersCredentialRunsOutInMinutes() async throws {
        XCTAssertLessThanOrEqual(ControllerToken.Kind.peer.lifetime, 5 * 60)
        let (relay, address) = try await start()
        defer { relay.stop() }
        let old = ControllerToken.issue(kind: .peer, app: room, generation: 0, peer: "tv", now: Date().addingTimeInterval(-6 * 60), key: key)
        try await Self.refused(try await join(address, as: "tv", device: "TV", credential: old))
    }

    /// The relay hands a joined app a fresh credential over its socket, at once and again while it stays, and that is
    /// what lets it back in after its link drops; each is good once.
    func testTheRelayRenewsAPeersCredentialOverItsSocket() async throws {
        let renewal = Relay.peerRenewal
        Relay.peerRenewal = 0
        defer { Relay.peerRenewal = renewal }
        let (relay, address) = try await start()
        defer { relay.stop() }
        let tv = try await join(address, as: "tv", device: "TV")
        let welcome = try await Self.text(tv)
        let given = try XCTUnwrap(welcome["credential"] as? String, "the welcome carries a fresh credential")
        var renewed: String?
        for _ in 0..<5 where renewed == nil {
            let next = try await Self.text(tv)
            if next["t"] as? String == "credential" { renewed = next["credential"] as? String }
        }
        let fresh = try XCTUnwrap(renewed, "a renewal came over the socket")
        XCTAssertNotEqual(fresh, given)
        tv.cancel(with: .goingAway, reason: nil)
        for _ in 0..<50 where relay.members(of: room).contains("tv") { try await Task.sleep(for: .milliseconds(50)) }

        let back = try await join(address, as: "tv", device: "TV", credential: fresh)
        let rejoined = try await Self.text(back)
        XCTAssertEqual(rejoined["t"] as? String, "welcome", "the renewed credential lets the app back in")
        back.cancel(with: .goingAway, reason: nil)
        for _ in 0..<50 where relay.members(of: room).contains("tv") { try await Task.sleep(for: .milliseconds(50)) }
        try await Self.refused(try await join(address, as: "tv", device: "TV", credential: fresh))
    }

    /// An app added to the wish, or taken from it, while others are in the room: they're told the list again, so the new
    /// one is known before it opens and the one gone is forgotten.
    func testMembersHearTheWishsAppsWhenTheyChange() async throws {
        let (relay, address) = try await start()
        defer { relay.stop() }
        let tv = try await join(address, as: "tv", device: "TV")
        let welcome = try await Self.text(tv)
        XCTAssertEqual((welcome["apps"] as? [[String: Any]])?.compactMap { $0["peer"] as? String }, ["android", "iphone", "tv"])

        relay.configureRoom(room, generation: 0, apps: ["tv": ("tv", "the TV app"), "iphone": ("iphone", "the iPhone app"),
                                                        "android": ("android", "the Android app"), "mac": ("mac", "the Mac app")])
        let added = try await Self.text(tv)
        XCTAssertEqual(added["t"] as? String, "apps")
        XCTAssertEqual((added["apps"] as? [[String: Any]])?.compactMap { $0["peer"] as? String }, ["android", "iphone", "mac", "tv"])

        relay.configureRoom(room, generation: 0, apps: ["tv": ("tv", "the TV app"), "mac": ("mac", "the Mac app")])
        let taken = try await Self.text(tv)
        XCTAssertEqual((taken["apps"] as? [[String: Any]])?.compactMap { $0["peer"] as? String }, ["mac", "tv"])
    }

    // MARK: Helpers

    private static func refused(_ socket: URLSessionWebSocketTask) async throws { try await closed(socket, code: 4003) }

    private static func closed(_ socket: URLSessionWebSocketTask, code: Int) async throws {
        do {
            while true {
                if case .string(let text) = try await socket.receive(),
                   let message = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any], message["t"] as? String != "beat" {
                    XCTFail("let in: \(message)")
                    return
                }
            }
        } catch {
            XCTAssertEqual(socket.closeCode.rawValue, code)
        }
    }

    /// The next text message on a socket, past beats.
    private static func text(_ socket: URLSessionWebSocketTask) async throws -> [String: Any] {
        while true {
            if case .string(let text) = try await socket.receive(),
               let message = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any], message["t"] as? String != "beat" {
                return message
            }
        }
    }

    private static func json(_ value: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: value)) ?? Data(), as: UTF8.self)
    }
}
