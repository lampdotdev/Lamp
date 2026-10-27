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

    /// The 1 MB an app may set in shared collections is its own: what the wish's other apps set doesn't use it up. Each of
    /// two apps (a Mac app and a TV page) sets about 600 KB of the wish's own list, the second once it has the first's,
    /// then edits and deletes the other's items, and the Mac app fills its own 1 MB and still deletes one of the page's.
    func testEachAppsLimitCountsOnlyWhatItSet() async throws {
        let relay = Relay(key: SymmetricKey(size: .bits256))
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        let key = WishChannel.random(32)
        relay.configureRoom("wish:limits", key: key, apps: ["mac": ("mac", "the Mac app"), "tv": ("tv", "the TV app")])
        defer { relay.stop() }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-wish-limits-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let bundle = "dev.lamp.test.limits-\(UUID().uuidString.prefix(8))"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(bundle)
        defer { try? FileManager.default.removeItem(at: support) }
        let suite = "lamp-wish-limits-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let main = """
            struct Event: Codable, Identifiable { let id: String; var title: String }
            @main struct Mac {
                @MainActor static func main() {
                    setvbuf(stdout, nil, _IONBF, 0)
                    let events = LampStore.shared("events", of: Event.self, wish: true)
                    let big = String(repeating: "m", count: 7900)
                    print("put \\(events.put((0..<75).map { Event(id: "m\\($0)", title: big) }))")
                    let end = Date().addingTimeInterval(Double(ProcessInfo.processInfo.environment["LAMP_SECONDS"]!)!)
                    var count = 0, still = Date(), done = false
                    while Date() < end, !done {
                        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                        if events.count != count { count = events.count; still = Date() }
                        // Once the page's items have come and no more for two seconds, the page's items are changed here.
                        guard (0..<3).allSatisfy({ events.get("t\\($0)") != nil }), Date().timeIntervalSince(still) > 2 else { continue }
                        done = true
                        let edited = events.put(Event(id: "t0", title: "edited on the Mac"))
                        let theirs = LampWish.shared.putItems(in: "wish:events", [("t1", nil)])
                        let mine = LampWish.shared.putItems(in: "wish:events", [("m0", nil)])
                        var filled = 0
                        while filled < 200, events.put(Event(id: "f\\(filled)", title: big)) { filled += 1 }
                        let full = LampWish.shared.putItems(in: "wish:events", [("t2", nil)])
                        print("mac edited \\(edited) theirs \\(theirs) mine \\(mine) full \\(full) filled \\(filled)")
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
        let command = "LAMP_SOCKET='ws://127.0.0.1:\(port)/' LAMP_APPS=mac,tv LAMP_DEFAULTS=\(suite) LAMP_PEER=mac LAMP_SECONDS=40 ./mac 2>&1"
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
            var events = LampStore.shared('events', { wish: true }), big = new Array(7901).join('t');
            function haveAll(prefix) { for (var i = 0; i < 75; i++) if (!events.get(prefix + i)) return false; return true; }
            """)
        func js(_ script: String) -> String { page.context.evaluateScript(script)?.toString() ?? "" }
        for _ in 0..<300 where js("haveAll('m')") != "true" { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(js("haveAll('m')"), "true", "the Mac app's items reached the page: \(js("JSON.stringify(Lamp.wish.state())"))")
        let put = js("events.put(Array.from({ length: 75 }, function (_, i) { return { id: 't' + i, title: big }; }))")
        let edited = js("events.put({ id: 'm5', title: 'edited on the TV' })")
        let deleted = js("events.delete('m6')")
        XCTAssertEqual([put, edited, deleted], ["true", "true", "true"], "the page sets its own 600 KB, and edits and deletes the Mac app's items")
        let said = await swift.value
        XCTAssertTrue(said.contains("put true"), said)
        XCTAssertTrue(said.contains("mac edited true theirs true mine true full true"),
                      "the Mac app edits and deletes the page's items, and still deletes one at its own limit: \(said.suffix(600))")
        // About 430 KB of its 1 MB is left after its own 600 KB, whatever the page set: room for some 50 more items.
        let filled = said.components(separatedBy: "filled ").last.flatMap { Int($0.prefix { $0.isNumber }) } ?? 0
        XCTAssertGreaterThan(filled, 40, "the Mac app's room is what it set itself, not the page's items too: \(said.suffix(600))")
        page.end()
    }

    /// Publishing items that change one and leave another out deletes the one left out, on a page well within its limit
    /// and on one that has used all of it.
    func testAPageThatPublishesFewerItemsDeletesTheOnesLeftOut() {
        let page = PageWithSockets()
        page.context.evaluateScript("""
            window.webkit = { messageHandlers: { lampGateway: {} } };
            window.LampStore = {};
            LampAI = { _post: function () { return new Promise(function () {}); } };
            """)
        page.context.evaluateScript(TVTemplate.wishJS)
        func js(_ script: String) -> String { page.context.evaluateScript(script)?.toString() ?? "" }
        _ = js("""
            var chores = LampStore.shared('chores');
            function held() { return JSON.stringify(chores.all()); }
            chores.put([{ id: 'a', title: 'wash' }, { id: 'b', title: 'dry' }]);
            """)
        XCTAssertEqual(js("chores.publish([{ id: 'a', title: 'wash up' }])"), "true")
        XCTAssertEqual(js("held()"), #"[{"id":"a","title":"wash up"}]"#, "b was left out, so it's deleted")

        _ = js("""
            chores.put([{ id: 'c', title: 'sweep' }, { id: 'd', title: 'dust' }]);
            var fill = LampStore.shared('fill'), big = new Array(7901).join('f'), filled = 0;
            while (filled < 200 && fill.put({ id: 'f' + filled, title: big })) filled++;
            """)
        XCTAssertLessThan(Int(js("filled")) ?? 200, 200, "the page used all of its limit")
        XCTAssertEqual(js("chores.publish([{ id: 'c', title: 'sweep' }, { id: 'd', title: 'dust off' }])"), "true")
        XCTAssertEqual(js("held()"), #"[{"id":"c","title":"sweep"},{"id":"d","title":"dust off"}]"#, "a and b were left out, so they're deleted, at the limit too")
        page.end()
    }
}
