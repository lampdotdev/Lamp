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

    /// A TV app in the room speaking to three players at 60 frames a second each (what `Lamp.controllers.send(0, …)`
    /// does: one `pad` message per player) is neither held back nor let go, whether they're three apps or three
    /// controllers in one app; each player is held to a phone's rate on its own.
    func testATVSpeakingToThreePlayersThroughTheRoomIsNotDroppedNorLetGo() async throws {
        try await speak(to: [("mac", nil), ("iphone", nil), ("android", nil)])
    }

    func testATVSpeakingToThreeControllersInOneAppIsNotDroppedNorLetGo() async throws {
        try await speak(to: [("mac", "a1"), ("mac", "b2"), ("mac", "c3")])
    }

    private func speak(to players: [(peer: String, pad: String?)]) async throws {
        let relay = Relay(key: SymmetricKey(size: .bits256))
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        defer { relay.stop() }
        let address = try XCTUnwrap(URL(string: "ws://127.0.0.1:\(try XCTUnwrap(started))/"))
        let key = WishChannel.random(32)
        relay.configureRoom("wish:controller", key: key, apps: ["tv": ("tv", "TV"), "mac": ("mac", "Mac"), "iphone": ("iphone", "iPhone"), "android": ("android", "Android")])
        let tv = try await WishPeer.join(address, as: "tv", device: "TV", key: key, wire: 3)
        _ = try await tv.next()
        var peers: [String: WishPeer] = [:]
        for name in Array(Set(players.map(\.peer))).sorted() {
            let p = try await WishPeer.join(address, as: name, device: name, key: key, wire: 3)
            _ = try await p.next()
            _ = try await tv.next()
            for other in peers.values { _ = try await other.next() }
            peers[name] = p
        }
        // Each app counts the pads it hears for each of its players, in the background.
        let counts = peers.map { name, p in
            Task.detached { () -> [String: Int] in
                var n: [String: Int] = [:]
                while let m = try? await p.next() {
                    if m["t"] as? String == "pad" { n[name + ":" + ((m["m"] as? [String: Any])?["pad"] as? String ?? ""), default: 0] += 1 }
                }
                return n
            }
        }
        // Everyone beats, as the libraries do, so nobody is let go for silence.
        let beating = ([tv] + Array(peers.values)).map { p in
            Task.detached { while !Task.isCancelled { try? await p.socket.send(.string(#"{"t":"beat"}"#)); try? await Task.sleep(for: .seconds(2)) } }
        }
        defer { beating.forEach { $0.cancel() } }
        var closedEarly = false
        let frames = 60 * 12
        let begin = Date()
        for frame in 0..<frames {
            for player in players {
                var m: [String: Any] = ["t": "message", "data": frame]
                if let pad = player.pad { m["pad"] = pad }
                do { try await tv.send(["t": "pad", "to": player.peer, "m": m]) } catch { closedEarly = true; break }
            }
            if closedEarly { break }
            let due = begin.addingTimeInterval(Double(frame + 1) / 60)
            if due > Date() { try await Task.sleep(for: .seconds(due.timeIntervalSinceNow)) }
        }
        try await Task.sleep(for: .seconds(1))
        for p in peers.values { p.socket.cancel(with: .goingAway, reason: nil) }
        var heard: [String: Int] = [:]
        for c in counts { heard.merge(await c.value) { $0 + $1 } }
        let tvClose = tv.socket.closeCode.rawValue
        tv.socket.cancel(with: .goingAway, reason: nil)
        print("sent \(frames) frames to each of \(players.count), heard \(heard), tv closed early \(closedEarly), tv close code \(tvClose)")
        XCTAssertEqual(tvClose == 4008, false, "the TV app was let go from the room for speaking to its players")
        for player in players {
            let got = heard[player.peer + ":" + (player.pad ?? ""), default: 0]
            XCTAssertGreaterThanOrEqual(got, frames * 9 / 10, "pads dropped for \(player): heard \(heard) of \(frames) each")
        }
    }

    /// A controller closed the moment it has asked to play, before the TV app's welcome, still leaves the game: the TV
    /// app is left with no player for it.
    func testAControllerClosedBeforeItsWelcomeLeavesTheGame() async throws {
        let relay = Relay(key: SymmetricKey(size: .bits256))
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        let key = WishChannel.random(32)
        relay.configureRoom("wish:controller", key: key, apps: ["mac": ("mac", "the Mac app"), "tv": ("tv", "the TV app")])
        let work = try built(key, main: Self.closedEarlyHarness)
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
        // Looked at while the Mac app is still open: an app that closes takes its players with it anyway.
        for _ in 0..<400 where page.context.evaluateScript("events.indexOf('join 1') >= 0")?.toBool() != true { try await Task.sleep(for: .milliseconds(100)) }
        try await Task.sleep(for: .seconds(2))
        let players = page.context.evaluateScript("Lamp.controllers.players().length")?.toInt32()
        let events = page.context.evaluateScript("events.join(',')")?.toString() ?? ""
        let said = await mac.value
        XCTAssertTrue(said.contains("closed"), said)
        XCTAssertTrue(events.contains("join 1"), "it asked to play: \(events) / \(said)")
        XCTAssertEqual(players, 0, "no player is left for it while its app is open: \(events)")
    }

    /// Waits for the TV app to be open, makes a controller, which asks to play at once, and closes it straight away.
    static let closedEarlyHarness = """
        @main struct Harness {
            @MainActor static func main() {
                setvbuf(stdout, nil, _IONBF, 0)
                func spin(_ seconds: Double, until done: () -> Bool = { false }) {
                    let end = Date().addingTimeInterval(seconds)
                    while Date() < end, !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
                }
                spin(40) { LampWish.shared.peer("tv")?.isOpen == true }
                spin(1)
                let pad = LampController.connect()
                pad.close()
                print("closed \\(pad.state.rawValue)")
                spin(10)
            }
        }
        """
}
