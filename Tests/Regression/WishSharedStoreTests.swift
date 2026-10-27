import CryptoKit
import JavaScriptCore
import LampRelayKit
import XCTest
@testable import Lamp

/// Two copies of one app (a Swift app and a TV page, as a screen is on an iPad and on a TV) each change a shared
/// collection while apart, then meet: each ends with both copies' items, and the file the Swift copy shared arrives on
/// the page, which can't read it for itself.
@MainActor
final class WishSharedStoreTests: XCTestCase {
    func testTwoCopiesThatChangedDifferentItemsApartBothKeepBothOnceTheyMeet() async throws {
        let relay = Relay(key: SymmetricKey(size: .bits256))
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        let key = WishChannel.random(32)
        relay.configureRoom("wish:shared", key: key, apps: ["screen": ("screen", "the screen")])
        defer { relay.stop() }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-wish-shared-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let bundle = "dev.lamp.test.shared-\(UUID().uuidString.prefix(8))"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(bundle)
        defer { try? FileManager.default.removeItem(at: support) }
        let suite = "lamp-wish-shared-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let main = """
            struct Grocery: Codable, Identifiable { let id: String; var name: String }
            @main struct Copy {
                @MainActor static func main() {
                    setvbuf(stdout, nil, _IONBF, 0)
                    // Changed before this copy has met any other.
                    let list = LampStore.shared("groceries", of: Grocery.self)
                    print("put \\(list.put([Grocery(id: "m1", name: "milk"), Grocery(id: "m2", name: "eggs")]))")
                    print("file \\(LampStore.sharedFiles("photos").put("a.bin", Data(repeating: 7, count: 200_000), type: "image/jpeg"))")
                    let end = Date().addingTimeInterval(Double(ProcessInfo.processInfo.environment["LAMP_SECONDS"]!)!)
                    var said = ""
                    while Date() < end {
                        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                        let now = list.items.map { $0.id + "=" + $0.name }.joined(separator: ",")
                        if now != said { said = now; print("items \\(now)") }
                    }
                }
            }
            """
        try WishNativeTests.program(main: main).write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>\(bundle)</string>"
            + Template.wishKeyPlistLines(key) + "</dict></plist>"
        try plist.write(to: work.appendingPathComponent("wish.plist"), atomically: true, encoding: .utf8)
        let built = TestShell.run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o copy main.swift -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker wish.plist 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)
        let command = "LAMP_SOCKET='ws://127.0.0.1:\(port)/' LAMP_APPS=screen LAMP_DEFAULTS=\(suite) LAMP_PEER=screen LAMP_SECONDS=20 ./copy 2>&1"
        let swift = Task.detached { TestShell.run(command, in: work).output }

        // The other copy, a TV page, changes other items before it has met anyone, then joins.
        let page = PageWithSockets()
        page.context.evaluateScript("""
            window.webkit = { messageHandlers: { lampGateway: {} } };
            window.LampStore = {};
            var answer = { socket: 'ws://127.0.0.1:\(port)/', peer: 'screen', key: '\(key.base64EncodedString())', peers: [],
                           apps: [{ peer: 'screen', kind: 'tv', name: 'the screen' }] };
            LampAI = { _post: function () { return Promise.resolve(answer); } };
            """)
        page.context.evaluateScript(TVTemplate.wishJS)
        page.context.evaluateScript("""
            var list = LampStore.shared('groceries'), photo = null;
            list.put([{ id: 't1', name: 'bread' }, { id: 't2', name: 'apples' }]);
            function held() { return list.all().map(function (g) { return g.id + '=' + g.name; }).join(','); }
            LampStore.sharedFiles('photos').onChange(function (name) {
              LampStore.sharedFiles('photos').get(name).then(function (b) { if (b) photo = b.length + ':' + b[0] + ':' + b[b.length - 1]; });
            });
            """)
        func js(_ script: String) -> String { page.context.evaluateScript(script)?.toString() ?? "" }
        let all = "m1=milk,m2=eggs,t1=bread,t2=apples"
        for _ in 0..<150 where js("held()") != all || js("photo") != "200000:7:7" { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(js("held()"), all, "the page has both copies' items: \(js("JSON.stringify([Lamp.wish.state(), said.slice(0, 6)])"))")
        XCTAssertEqual(js("photo"), "200000:7:7", "the Swift copy's file reached the page")
        let said = await swift.value
        XCTAssertTrue(said.contains("put true") && said.contains("file true"), said)
        XCTAssertTrue(said.contains("items \(all)"), "the Swift copy has both copies' items: \(said)")
        page.end()
    }

    /// Two different apps of one wish (a Mac app and a TV page): the wish's own list (`wish: true`) ends the same in both,
    /// while each app's own list of the same name stays its own.
    func testTheWishsOwnListIsSharedByItsAppsAndEachAppsOwnListIsNot() async throws {
        let relay = Relay(key: SymmetricKey(size: .bits256))
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        let key = WishChannel.random(32)
        relay.configureRoom("wish:together", key: key, apps: ["mac": ("mac", "the Mac app"), "tv": ("tv", "the TV app")])
        defer { relay.stop() }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-wish-together-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let bundle = "dev.lamp.test.together-\(UUID().uuidString.prefix(8))"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(bundle)
        defer { try? FileManager.default.removeItem(at: support) }
        let suite = "lamp-wish-together-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let main = """
            struct Event: Codable, Identifiable { let id: String; var title: String }
            @main struct Mac {
                @MainActor static func main() {
                    setvbuf(stdout, nil, _IONBF, 0)
                    let events = LampStore.shared("events", of: Event.self, wish: true)
                    let own = LampStore.shared("events", of: Event.self)
                    print("put \\(events.put(Event(id: "m1", title: "dentist"))) \\(own.put(Event(id: "n1", title: "mine")))")
                    let end = Date().addingTimeInterval(Double(ProcessInfo.processInfo.environment["LAMP_SECONDS"]!)!)
                    var said = ""
                    while Date() < end {
                        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                        let now = events.items.map(\\.id).joined(separator: ",") + "|" + own.items.map(\\.id).joined(separator: ",")
                        if now != said { said = now; print("items \\(now)") }
                    }
                }
            }
            """
        try WishNativeTests.program(main: main).write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>\(bundle)</string>"
            + Template.wishKeyPlistLines(key) + "</dict></plist>"
        try plist.write(to: work.appendingPathComponent("wish.plist"), atomically: true, encoding: .utf8)
        let built = TestShell.run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o mac main.swift -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker wish.plist 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)
        let command = "LAMP_SOCKET='ws://127.0.0.1:\(port)/' LAMP_APPS=mac,tv LAMP_DEFAULTS=\(suite) LAMP_PEER=mac LAMP_SECONDS=18 ./mac 2>&1"
        let swift = Task.detached { TestShell.run(command, in: work).output }

        let page = PageWithSockets()
        page.context.evaluateScript("""
            window.webkit = { messageHandlers: { lampGateway: {} } };
            window.LampStore = {};
            var answer = { socket: 'ws://127.0.0.1:\(port)/', peer: 'tv', key: '\(key.base64EncodedString())', peers: [],
                           apps: [{ peer: 'mac', kind: 'mac', name: 'the Mac app' }, { peer: 'tv', kind: 'tv', name: 'the TV app' }] };
            LampAI = { _post: function () { return Promise.resolve(answer); } };
            """)
        page.context.evaluateScript(TVTemplate.wishJS)
        page.context.evaluateScript("""
            var events = LampStore.shared('events', { wish: true }), own = LampStore.shared('events');
            events.put({ id: 't1', title: 'football' });
            own.put({ id: 'x1', title: 'only here' });
            function held() { return events.all().map(function (e) { return e.id; }).join(',') + '|' + own.all().map(function (e) { return e.id; }).join(','); }
            """)
        func js(_ script: String) -> String { page.context.evaluateScript(script)?.toString() ?? "" }
        for _ in 0..<150 where js("held()") != "m1,t1|x1" { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(js("held()"), "m1,t1|x1", "the page has both apps' events and only its own list: \(js("JSON.stringify(Lamp.wish.state())"))")
        let said = await swift.value
        XCTAssertTrue(said.contains("put true true"), said)
        XCTAssertTrue(said.contains("items m1,t1|n1"), "the Mac app has both apps' events and only its own list: \(said)")
        XCTAssertFalse(said.contains("x1"), "the page's own list never reached the Mac app: \(said)")
        page.end()
    }
}
