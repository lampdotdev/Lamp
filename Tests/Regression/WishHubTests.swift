import LampRelayKit
import XCTest
@testable import Lamp

/// Lamp introducing the apps of a wish to each other (`WishRooms`): an app that shows its own token is told its wish's
/// room, which peer it is and a credential that opens only that; an app alone is told so; and an app that can't hold a
/// socket is joined to the room by Lamp and fed by long-poll (`WishProxies`), talking with one that holds its own.
@MainActor
final class WishHubTests: XCTestCase {
    private let wish = LampProject(id: "scoreboard", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard"), platform: .tv)
    private var phone: LampProject {
        LampProject(id: "scoreboard.iphone", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard/iPhone"), platform: .iphone, partOf: "scoreboard")
    }
    private var android: LampProject {
        LampProject(id: "scoreboard.android", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard/Android"), platform: .android, partOf: "scoreboard")
    }

    override func setUp() {
        // The relay built beside the tests, since the test runner isn't Lamp's bundle.
        ControllerRelay.executable = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("LampRelay")
    }

    override func tearDown() async throws {
        WishRooms.forgetAll()
    }

    func testAnAppOfAWishIsToldItsRoomAndAnAppAloneIsToldSo() async throws {
        let (status, answer) = await WishRooms.answer(for: phone, wish: wish, parts: [phone, android], host: "192.168.1.20")
        XCTAssertEqual(status, 200, "\(answer)")
        XCTAssertEqual(answer["room"] as? String, "wish:scoreboard")
        XCTAssertEqual(answer["peer"] as? String, "iphone")
        XCTAssertTrue((answer["socket"] as? String ?? "").hasPrefix("ws://192.168.1.20:"), "by the name the app reached Lamp at: \(answer)")
        XCTAssertEqual((answer["apps"] as? [[String: Any]])?.compactMap { $0["peer"] as? String }, ["tv", "iphone", "android"])
        let credential = answer["credential"] as? String
        XCTAssertEqual(ControllerCredential.check(credential, kinds: [.peer], app: "wish:scoreboard")?.peer, "iphone")
        XCTAssertNil(ControllerCredential.check(credential, kinds: [.host, .join, .controller], app: "wish:scoreboard"), "a peer's is nothing else")
        XCTAssertNil(ControllerCredential.check(credential, kinds: [.peer], app: "scoreboard"), "and opens no TV app's game")

        let (aloneStatus, alone) = await WishRooms.answer(for: wish, wish: wish, parts: [], host: "127.0.0.1")
        XCTAssertEqual(aloneStatus, 200)
        XCTAssertEqual(alone["alone"] as? Bool, true)
        XCTAssertNil(alone["credential"])
    }

    func testAnAppThatCantHoldASocketIsJoinedByLampAndTalksWithOneThatCan() async throws {
        let parts = [phone, android]
        // The Android app polls: Lamp joins it to the room, and the first thing it hears is its welcome.
        var (status, polled) = await WishProxies.poll(android, wish: wish, parts: parts, device: "Android emulator")
        XCTAssertEqual(status, 200, "\(polled)")
        var events = polled["events"] as? [[String: Any]] ?? []
        XCTAssertEqual(events.first?["t"] as? String, "welcome", "\(polled)")
        XCTAssertEqual(events.first?["peer"] as? String, "android")

        // The iPhone app holds its own socket.
        let (phoneStatus, told) = await WishRooms.answer(for: phone, wish: wish, parts: parts, host: "127.0.0.1")
        XCTAssertEqual(phoneStatus, 200)
        let socket = URLSession.shared.webSocketTask(with: try XCTUnwrap(URL(string: try XCTUnwrap(told["socket"] as? String))))
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }
        try await socket.send(.string(Self.json(["t": "hello", "app": "wish:scoreboard", "credential": told["credential"] ?? "", "device": "iPhone simulator"])))
        let welcome = try await Self.text(socket)
        XCTAssertEqual((welcome["peers"] as? [[String: Any]])?.first?["peer"] as? String, "android", "the Android app is already there: \(welcome)")

        (status, polled) = await WishProxies.poll(android, wish: wish, parts: parts, device: "")
        events = polled["events"] as? [[String: Any]] ?? []
        XCTAssertEqual(events.first?["t"] as? String, "joined")
        XCTAssertEqual((events.first?["peer"] as? [String: Any])?["device"] as? String, "iPhone simulator")

        // Both ways.
        let (sentStatus, sent) = await WishProxies.send(android, body: ["to": "iphone", "data": ["score": 7]])
        XCTAssertEqual(sentStatus, 200, "\(sent)")
        let heard = try await Self.text(socket)
        XCTAssertEqual(heard["from"] as? String, "android")
        XCTAssertEqual((heard["data"] as? [String: Any])?["score"] as? Int, 7)
        try await socket.send(.string(Self.json(["t": "send", "to": "android", "data": "your turn"])))
        (status, polled) = await WishProxies.poll(android, wish: wish, parts: parts, device: "")
        events = polled["events"] as? [[String: Any]] ?? []
        XCTAssertEqual(events.first?["t"] as? String, "message")
        XCTAssertEqual(events.first?["from"] as? String, "iphone")
        XCTAssertEqual(events.first?["data"] as? String, "your turn")

        // Lamp hears who is in the room, for the line the builder is told.
        for _ in 0..<50 where WishRooms.presence(of: wish).count < 2 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(WishRooms.presence(of: wish).compactMap { $0["peer"] as? String }.sorted(), ["android", "iphone"])

        // Too big for one message, said so and not sent.
        let (bigStatus, _) = await WishProxies.send(android, body: ["data": String(repeating: "A", count: ControllerWire.message)])
        XCTAssertEqual(bigStatus, 413)

        // An app that lost touch with Lamp for a while asks to join afresh, and gets the whole state again in a new welcome.
        (status, polled) = await WishProxies.poll(android, wish: wish, parts: parts, device: "", rejoin: true)
        events = polled["events"] as? [[String: Any]] ?? []
        XCTAssertEqual(events.first?["t"] as? String, "welcome", "\(polled)")
        XCTAssertEqual((events.first?["peers"] as? [[String: Any]])?.first?["peer"] as? String, "iphone")
    }

    /// A room's credentials are no TV app's session: the sync that ends the games whose phone pages aren't served
    /// (`PhoneControllers.endAll`) leaves them as they are, so a network sync never throws a wish's apps out of their room.
    func testARoomsCredentialsOutliveTheTVGamesCleanup() async throws {
        let (status, answer) = await WishRooms.answer(for: phone, wish: wish, parts: [phone, android], host: "127.0.0.1")
        XCTAssertEqual(status, 200, "\(answer)")
        XCTAssertFalse(ControllerCredential.apps.contains("wish:scoreboard"), "a room isn't among the games")
        let generation = ControllerCredential.generation("wish:scoreboard")
        PhoneControllers.shared.endAll(except: [])
        XCTAssertEqual(ControllerCredential.check(answer["credential"] as? String, kinds: [.peer], app: "wish:scoreboard")?.peer, "iphone")
        XCTAssertEqual(ControllerCredential.generation("wish:scoreboard"), generation, "the room's generation is its own")
    }

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
