import CryptoKit
import LampRelayKit
import XCTest
@testable import Lamp

/// Lamp introducing the apps of a wish to each other (`WishRooms`): an app that shows its own token is told where its
/// wish's room is and which peer it is, and nothing that lets it in, which is the wish's key it was given at install (the
/// TV preview, asking through its bridge, is given the key); an app alone is told so; and an app that can't hold a socket
/// has Lamp hold one for it, which carries its handshake and sealed messages unread (`WishProxies`).
@MainActor
final class WishHubTests: XCTestCase {
    private let wish = LampProject(id: "scoreboard", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard"), platform: .tv)
    private var phone: LampProject {
        LampProject(id: "scoreboard.iphone", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard/iPhone"), platform: .iphone, partOf: "scoreboard")
    }
    private var android: LampProject {
        LampProject(id: "scoreboard.android", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard/Android"), platform: .android, partOf: "scoreboard")
    }
    private let keys = FileManager.default.temporaryDirectory.appendingPathComponent("wish-keys-\(UUID().uuidString)")
    private var keptKeys = WishKeys.folder

    override func setUp() {
        // The relay built beside the tests, since the test runner isn't Lamp's bundle.
        ControllerRelay.executable = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("LampRelay")
        keptKeys = WishKeys.folder
        WishKeys.folder = keys
    }

    override func tearDown() async throws {
        WishRooms.forgetAll()
        WishKeys.folder = keptKeys
        try? FileManager.default.removeItem(at: keys)
    }

    func testAnAppOfAWishIsToldWhereItsRoomIsAndNothingThatLetsItIn() async throws {
        let (status, answer) = await WishRooms.answer(for: phone, wish: wish, apps: [wish, phone, android], host: "192.168.1.20")
        XCTAssertEqual(status, 200, "\(answer)")
        XCTAssertEqual(answer["peer"] as? String, "iphone")
        XCTAssertTrue((answer["socket"] as? String ?? "").hasPrefix("ws://192.168.1.20:"), "by the name the app reached Lamp at: \(answer)")
        XCTAssertEqual((answer["apps"] as? [[String: Any]])?.compactMap { $0["peer"] as? String }, ["tv", "iphone", "android"])
        XCTAssertNil(answer["credential"])
        XCTAssertNil(answer["key"], "the key is the app's from its install, never in an answer that may cross the network")

        // The TV preview's page asks through its bridge on this Mac and was put on no device: it's given the key.
        let (_, preview) = await WishRooms.answer(for: wish, wish: wish, apps: [wish, phone, android], host: "127.0.0.1", preview: true)
        XCTAssertEqual(preview["key"] as? String, WishKeys.key(for: wish).base64EncodedString())

        let (aloneStatus, alone) = await WishRooms.answer(for: wish, wish: wish, apps: [wish], host: "127.0.0.1")
        XCTAssertEqual(aloneStatus, 200)
        XCTAssertEqual(alone["alone"] as? Bool, true)
        XCTAssertNil(alone["socket"])

        // Peers are named by their folder in the wish: an app for iPhone and Mac made in Apple/ is "apple", and one made
        // for the Mac too in place keeps its iPhone/ folder and its name, while its kind stays the device word the tools
        // use; an app at the wish's root is named by the folder its kind would have.
        let both = LampProject(id: "scoreboard.apple", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard/Apple"), platform: .universal, partOf: "scoreboard")
        XCTAssertEqual(WishRooms.describe(both, in: wish)["peer"] as? String, "apple")
        XCTAssertEqual(WishRooms.describe(both, in: wish)["kind"] as? String, "iphone")
        let grown = LampProject(id: "scoreboard.iphone", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard/iPhone"), platform: .universal, partOf: "scoreboard")
        XCTAssertEqual(WishRooms.describe(grown, in: wish)["peer"] as? String, "iphone", "a part changed in place keeps its folder and its name")
        XCTAssertEqual(WishRooms.describe(wish, in: wish)["peer"] as? String, "tv")
        let mac = LampProject(id: "tally", name: "Tally", exe: "Tally", dir: URL(fileURLWithPath: "/tmp/tally"), platform: .mac)
        XCTAssertEqual(WishRooms.describe(mac, in: mac)["peer"] as? String, "mac")
    }

    /// The Android app's side, as LampSupport.kt does it, through Lamp's proxy; and the iPhone app on its own socket.
    func testAnAppThatCantHoldASocketTalksThroughLampWhichCarriesItSealed() async throws {
        let parts = [wish, phone, android]
        let key = SymmetricKey(data: WishKeys.key(for: wish))
        var (status, opened) = await WishProxies.open(android, wish: wish, apps: parts)
        XCTAssertEqual(status, 200, "\(opened)")
        XCTAssertEqual(opened["peer"] as? String, "android")
        let link = try XCTUnwrap(opened["link"] as? Int)
        XCTAssertNil(opened["socket"], "the app talks to Lamp, not the relay")

        // Its hello, and the relay's challenge, as text.
        let tag = WishChannel.tag(for: key), nonce = WishChannel.random(16)
        let hello = Self.json(["t": "hello", "tag": tag.base64EncodedString(), "peer": "android", "nonce": nonce.base64EncodedString()])
        var (sentStatus, sent) = await WishProxies.send(android, body: ["link": link, "frames": [["text": hello]]])
        XCTAssertEqual(sentStatus, 200, "\(sent)")
        var events = try await poll(link)
        let challenge = try XCTUnwrap((events.first?["text"] as? String).flatMap(Self.parse), "\(events)")
        XCTAssertEqual(challenge["t"] as? String, "challenge")
        let transcript = WishChannel.transcript(tag: tag, client: "android", server: challenge["peer"] as? String ?? "", clientNonce: nonce,
                                                serverNonce: Data(base64Encoded: challenge["nonce"] as? String ?? "")!)
        let channel = WishChannel.keys(key: key, transcript: transcript)
        var sealer = WishChannel.Sealer(key: channel.client), opener = WishChannel.Sealer(key: channel.server)
        func sealed(_ value: [String: Any]) throws -> [String: Any] { ["data": sealer.seal(try JSONSerialization.data(withJSONObject: value)).base64EncodedString()] }
        func open(_ event: [String: Any]) throws -> [String: Any] {
            let data = try XCTUnwrap((event["data"] as? String).flatMap { Data(base64Encoded: $0) }, "a sealed message: \(event)")
            return try XCTUnwrap((try JSONSerialization.jsonObject(with: try XCTUnwrap(opener.open(data)))) as? [String: Any])
        }
        (sentStatus, sent) = await WishProxies.send(android, body: ["link": link, "frames": [
            ["text": Self.json(["t": "proof", "proof": WishChannel.clientProof(key: key, transcript: transcript).base64EncodedString()])],
            try sealed(["t": "join", "device": "Android emulator"])]])
        XCTAssertEqual(sentStatus, 200, "\(sent)")
        events = try await poll(link)
        XCTAssertEqual(try open(events[0])["t"] as? String, "welcome", "the first thing it hears, sealed: \(events)")

        // The iPhone app holds its own socket.
        let (phoneStatus, told) = await WishRooms.answer(for: phone, wish: wish, apps: parts, host: "127.0.0.1")
        XCTAssertEqual(phoneStatus, 200)
        let iphone = try await WishPeer.join(try XCTUnwrap(URL(string: try XCTUnwrap(told["socket"] as? String))), as: "iphone", device: "iPhone simulator",
                                             key: WishKeys.key(for: wish))
        defer { iphone.socket.cancel(with: .goingAway, reason: nil) }
        let welcome = try await iphone.next()
        XCTAssertEqual((welcome["peers"] as? [[String: Any]])?.first?["peer"] as? String, "android", "the Android app is already there: \(welcome)")
        events = try await poll(link)
        XCTAssertEqual(try open(events[0])["t"] as? String, "joined")

        // Both ways.
        (sentStatus, sent) = await WishProxies.send(android, body: ["link": link, "frames": [try sealed(["t": "send", "to": "iphone", "data": ["score": 7]])]])
        XCTAssertEqual(sentStatus, 200, "\(sent)")
        let heard = try await iphone.next()
        XCTAssertEqual(heard["from"] as? String, "android")
        XCTAssertEqual((heard["data"] as? [String: Any])?["score"] as? Int, 7)
        try await iphone.send(["t": "send", "to": "android", "data": "your turn"])
        events = try await poll(link)
        let message = try open(events[0])
        XCTAssertEqual(message["from"] as? String, "iphone")
        XCTAssertEqual(message["data"] as? String, "your turn")

        // Lamp hears who is in the room, for the line the builder is told.
        for _ in 0..<50 where WishRooms.presence(of: wish).count < 2 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(WishRooms.presence(of: wish).compactMap { $0["peer"] as? String }.sorted(), ["android", "iphone"])

        // Too big for one message or a file's piece, said so and not sent.
        let (bigStatus, _) = await WishProxies.send(android, body: ["link": link, "frames": [["data": Data(count: WishChannel.pieceLimit + 2048).base64EncodedString()]]])
        XCTAssertEqual(bigStatus, 413)

        // A new link ends the old one: nothing of it reaches the new handshake.
        (status, opened) = await WishProxies.open(android, wish: wish, apps: parts)
        let next = try XCTUnwrap(opened["link"] as? Int)
        XCTAssertNotEqual(next, link)
        let stalePoll = await WishProxies.poll(android, link: link).0
        let staleSend = await WishProxies.send(android, body: ["link": link, "frames": []]).0
        XCTAssertEqual(stalePoll, 409)
        XCTAssertEqual(staleSend, 409)
    }

    /// An Android app that stops polling (force-stopped, closed) is let go of within seconds, so the wish's other apps see
    /// it leave while it's gone, and arrive again when it's back, rather than taking it as open the whole time.
    func testAnAppThatStopsPollingIsSeenToLeave() async throws {
        let parts = [wish, phone, android]
        let key = SymmetricKey(data: WishKeys.key(for: wish))
        let (wait, grace) = (WishProxies.wait, WishProxies.grace)
        WishProxies.wait = 1
        WishProxies.grace = 1
        defer { WishProxies.wait = wait; WishProxies.grace = grace }
        let (_, opened) = await WishProxies.open(android, wish: wish, apps: parts)
        let link = try XCTUnwrap(opened["link"] as? Int)
        let tag = WishChannel.tag(for: key), nonce = WishChannel.random(16)
        _ = await WishProxies.send(android, body: ["link": link, "frames": [["text": Self.json(["t": "hello", "tag": tag.base64EncodedString(), "peer": "android", "nonce": nonce.base64EncodedString()])]]])
        let first = try await poll(link)
        let challenge = try XCTUnwrap((first.first?["text"] as? String).flatMap(Self.parse))
        let transcript = WishChannel.transcript(tag: tag, client: "android", server: challenge["peer"] as? String ?? "", clientNonce: nonce,
                                                serverNonce: Data(base64Encoded: challenge["nonce"] as? String ?? "")!)
        var sealer = WishChannel.Sealer(key: WishChannel.keys(key: key, transcript: transcript).client)
        _ = await WishProxies.send(android, body: ["link": link, "frames": [
            ["text": Self.json(["t": "proof", "proof": WishChannel.clientProof(key: key, transcript: transcript).base64EncodedString()])],
            ["data": sealer.seal(try JSONSerialization.data(withJSONObject: ["t": "join", "device": "Android emulator"])).base64EncodedString()]]])
        _ = try await poll(link)

        let (_, told) = await WishRooms.answer(for: phone, wish: wish, apps: parts, host: "127.0.0.1")
        let socket = try XCTUnwrap(URL(string: try XCTUnwrap(told["socket"] as? String)))
        let iphone = try await WishPeer.join(socket, as: "iphone", device: "iPhone simulator", key: WishKeys.key(for: wish))
        defer { iphone.socket.cancel(with: .goingAway, reason: nil) }
        let welcome = try await iphone.next()
        let present = (welcome["peers"] as? [[String: Any]])?.first?["peer"] as? String
        XCTAssertEqual(present, "android", "\(welcome)")

        // The Android app stops: no more polls. Within a few seconds the iPhone app hears it left.
        let started = Date()
        var heard: [String: Any] = [:]
        while heard["t"] as? String != "left", Date().timeIntervalSince(started) < 8 { heard = try await iphone.next() }
        XCTAssertEqual("\(heard["t"] ?? "") \(heard["peer"] ?? "")", "left android")
        XCTAssertLessThan(Date().timeIntervalSince(started), 6, "within seconds of its last poll")
    }

    private func poll(_ link: Int) async throws -> [[String: Any]] {
        for _ in 0..<5 {
            let (status, polled) = await WishProxies.poll(android, link: link)
            XCTAssertEqual(status, 200, "\(polled)")
            let events = polled["events"] as? [[String: Any]] ?? []
            if !events.isEmpty { return events }
        }
        XCTFail("nothing came")
        return []
    }

    private static func parse(_ text: String) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] }

    private static func json(_ value: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: value)) ?? Data(), as: UTF8.self)
    }
}
