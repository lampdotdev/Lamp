import CryptoKit
import JavaScriptCore
import LampRelayKit
import XCTest
@testable import Lamp

/// A wish's own apps playing its TV app's game on the wish's link: a controller made again in the same moment still
/// gets in, and a TV app speaking to several players through Lamp's room is neither held back nor let go.
@MainActor
final class WishControllerTests: XCTestCase {
    /// A controller replaced by a new one in the same turn (a SwiftUI view's @StateObject made again): the old one's
    /// `leave` goes after the new one's `join`, so the TV page ignores the join (the app is still a player) and then
    /// lets the player go. The new controller should still end up connected.
    static let replacedPadHarness = """
        @main struct Harness {
            @MainActor static func main() {
                setvbuf(stdout, nil, _IONBF, 0)
                func spin(_ seconds: Double, until done: () -> Bool = { false }) {
                    let end = Date().addingTimeInterval(seconds)
                    while Date() < end, !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
                }
                var pad: LampController? = LampController.connect()
                spin(40) { pad!.state == .connected && pad!.player != nil }
                print("first \\(pad!.state.rawValue)")
                pad = nil
                let again = LampController.connect()
                spin(15) { again.state == .connected }
                print("second \\(again.state.rawValue)")
                spin(1)
            }
        }
        """

    private func built(_ key: Data, main: String) throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-wish-controller-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try WishNativeTests.program(main: main).write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>dev.lamp.test.controller</string>"
            + Template.wishKeyPlistLines(key) + "</dict></plist>"
        try plist.write(to: work.appendingPathComponent("wish.plist"), atomically: true, encoding: .utf8)
        let made = TestShell.run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o app main.swift -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker wish.plist 2>&1", in: work)
        XCTAssertEqual(made.status, 0, made.output)
        return work
    }

    func testAControllerMadeAgainInTheSameTurnStillConnects() async throws {
        let relay = Relay(key: SymmetricKey(size: .bits256))
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        let key = WishChannel.random(32)
        relay.configureRoom("wish:controller", key: key, apps: ["mac": ("mac", "the Mac app"), "tv": ("tv", "the TV app")])
        let work = try built(key, main: Self.replacedPadHarness)
        defer { try? FileManager.default.removeItem(at: work) }
        let suite = "lamp-wish-controller-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: "\(suite)-mac") }
        let mac = Task.detached { TestShell.run("LAMP_SOCKET='ws://127.0.0.1:\(port)/' LAMP_APPS=mac,tv LAMP_DEFAULTS=\(suite)-mac LAMP_PEER=mac ./app 2>&1", in: work).output }
        try await Task.sleep(for: .seconds(3))
        relay.stop()

        let page = PageWithSockets()
        defer { page.end() }
        let tag = WishChannel.tag(for: SymmetricKey(data: key)).map { String(format: "%02x", $0) }.joined()
        let apps = #"[{ peer: 'mac', kind: 'mac', name: 'the Mac app' }, { peer: 'tv', kind: 'tv', name: 'the TV app' }]"#
        page.context.evaluateScript("""
            store['lamp:install.wish'] = JSON.stringify({ app: 'wishapp', key: '\(key.base64EncodedString())' });
            store['lamp:wish.\(tag)'] = JSON.stringify({ me: 'tv', apps: \(apps), at: {} });
            window.tizen = { systeminfo: { getPropertyValue: function (kind, ok) { if (kind === 'WIFI_NETWORK') ok({ ipAddress: '127.0.0.1' }); } } };
            LampAI._post = function (path) {
              if (path === '/app/wish') return Promise.reject(new Error("Couldn't reach Lamp."));
              return Promise.resolve({ links: [], renew: 60 });
            };
            """)
        page.context.evaluateScript(TVTemplate.controllersJS)
        page.context.evaluateScript(TVTemplate.wishJS.replacingOccurrences(of: DeviceSupport.webMarker, with: #"/*LAMP_INSTALL*/{"app":"wishapp","routes":[]}"#))
        page.context.evaluateScript("""
            var events = [];
            Lamp.controllers.onJoin(function (n) { events.push('join ' + n); });
            Lamp.controllers.onLeave(function (n) { events.push('leave ' + n); });
            Lamp.wish.start();
            Lamp.controllers.start();
            """)
        let said = await mac.value
        let events = page.context.evaluateScript("events.join(',')")?.toString() ?? ""
        XCTAssertTrue(said.contains("first connected"), said)
        XCTAssertTrue(said.contains("second connected"), "the new controller never got in: \(said) / page: \(events)")
    }

    /// A TV app in the room speaking to three of the wish's apps playing its game at 60 frames a second each (what
    /// `Lamp.controllers.send(0, …)` does: one `pad` message per player) is held to one phone's rate for all of them,
    /// and let go after ten seconds; a game host on the phones' relay has no such limit.
    func testATVSpeakingToThreePlayersThroughTheRoomIsNotDroppedNorLetGo() async throws {
        let relay = Relay(key: SymmetricKey(size: .bits256))
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        defer { relay.stop() }
        let address = try XCTUnwrap(URL(string: "ws://127.0.0.1:\(try XCTUnwrap(started))/"))
        let key = WishChannel.random(32)
        relay.configureRoom("wish:controller", key: key, apps: ["tv": ("tv", "TV"), "mac": ("mac", "Mac"), "iphone": ("iphone", "iPhone"), "android": ("android", "Android")])
        let tv = try await WishPeer.join(address, as: "tv", device: "TV", key: key, wire: 3)
        _ = try await tv.next()
        var players: [WishPeer] = []
        for name in ["mac", "iphone", "android"] {
            let p = try await WishPeer.join(address, as: name, device: name, key: key, wire: 3)
            _ = try await p.next()
            _ = try await tv.next()
            for other in players { _ = try await other.next() }
            players.append(p)
        }
        // Each player counts the pads it hears, in the background.
        let counts = players.map { p in
            Task.detached { () -> Int in
                var n = 0
                while let m = try? await p.next() { if m["t"] as? String == "pad" { n += 1 } }
                return n
            }
        }
        // Everyone beats, as the libraries do, so nobody is let go for silence.
        let beating = ([tv] + players).map { p in
            Task.detached { while !Task.isCancelled { try? await p.socket.send(.string(#"{"t":"beat"}"#)); try? await Task.sleep(for: .seconds(2)) } }
        }
        defer { beating.forEach { $0.cancel() } }
        var closedEarly = false
        let frames = 60 * 12
        let begin = Date()
        for frame in 0..<frames {
            for name in ["mac", "iphone", "android"] {
                do { try await tv.send(["t": "pad", "to": name, "m": ["t": "message", "data": frame]]) } catch { closedEarly = true; break }
            }
            if closedEarly { break }
            let due = begin.addingTimeInterval(Double(frame + 1) / 60)
            if due > Date() { try await Task.sleep(for: .seconds(due.timeIntervalSinceNow)) }
        }
        try await Task.sleep(for: .seconds(1))
        for p in players { p.socket.cancel(with: .goingAway, reason: nil) }
        var heard: [Int] = []
        for c in counts { heard.append(await c.value) }
        let tvClose = tv.socket.closeCode.rawValue
        tv.socket.cancel(with: .goingAway, reason: nil)
        print("sent \(frames) frames x3, heard \(heard), tv closed early \(closedEarly), tv close code \(tvClose)")
        XCTAssertEqual(tvClose == 4008, false, "the TV app was let go from the room for speaking to its players")
        XCTAssertTrue(heard.allSatisfy { $0 >= frames * 9 / 10 }, "pads dropped: heard \(heard) of \(frames) each")
    }
}
