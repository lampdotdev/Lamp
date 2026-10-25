import CryptoKit
import JavaScriptCore
import LampRelayKit
import XCTest
@testable import Lamp

/// Files between a wish's apps, and a wish's own app playing its TV app's game, on the wish's own link: built as plain
/// programs with the wish's key in their Info.plist, as Lamp installs a Mac app, beside a TV page running lamp.js, against
/// a real relay. A file goes whole between two Swift apps through Lamp's room and straight between them with Lamp gone; a
/// Mac app joins the TV page's `Lamp.controllers` with `LampController`, presses, sends, and trades files with it with no
/// Lamp at all; and a TV page and a Mac app trade files through Lamp's room.
@MainActor
final class WishFilesTests: XCTestCase {
    /// Sends `LAMP_FILES` files of `LAMP_SIZE` bytes to `LAMP_TO` once it's open (when given), and says each file it gets.
    static let filesHarness = """
        @main struct Harness {
            @MainActor static func main() {
                setvbuf(stdout, nil, _IONBF, 0)
                let env = ProcessInfo.processInfo.environment
                let wish = LampWish.shared
                func spin(_ seconds: Double, until done: () -> Bool = { false }) {
                    let end = Date().addingTimeInterval(seconds)
                    while Date() < end, !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
                }
                func digest(_ data: Data) -> String { SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined() }
                wish.onFile { from, file in print("got \\(file.name) \\(file.type) \\(file.data.count) \\(digest(file.data)) from \\(from)") }
                if let other = env["LAMP_TO"] {
                    spin(20) { wish.peer(other)?.isOpen == true }
                    spin(Double(env["LAMP_SETTLE"] ?? "0.5")!)
                    var transfers: [LampTransfer] = []
                    for i in 0..<Int(env["LAMP_FILES"] ?? "1")! {
                        var data = Data(count: Int(env["LAMP_SIZE"]!)!)
                        for j in stride(from: 0, to: data.count, by: 97) { data[j] = UInt8((j / 97 + i) & 0xff) }
                        print("sending file\\(i).bin \\(data.count) \\(digest(data))")
                        transfers.append(wish.sendFile(data, name: "file\\(i).bin", type: "application/test", to: other))
                    }
                    spin(30) { transfers.allSatisfy { $0.state != .sending } }
                    for t in transfers { print("transfer \\(t.name) \\(t.state) \\(t.sent)/\\(t.size)") }
                }
                spin(Double(env["LAMP_WAIT"] ?? "3")!)
            }
        }
        """

    /// A wish's Mac app as a game controller: joins the TV app's game, presses a button, sends a message, one too big,
    /// and a file, then says what the TV app sent it and lets the controller go.
    static let padHarness = """
        @main struct Harness {
            @MainActor static func main() {
                setvbuf(stdout, nil, _IONBF, 0)
                func spin(_ seconds: Double, until done: () -> Bool = { false }) {
                    let end = Date().addingTimeInterval(seconds)
                    while Date() < end, !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
                }
                var pad: LampController? = LampController.connect()
                pad!.onMessage { data in print("pad heard \\((try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "?")") }
                pad!.onFile { file in print("pad got \\(file.name) \\(file.data.count) \\(file.data.first ?? 0)") }
                spin(40) { pad!.state == .connected && pad!.player != nil }
                print("pad state \\(pad!.state.rawValue) player \\(pad!.player.map(String.init) ?? "none")")
                pad!.press("a")
                print("small sent: \\(pad!.send(["hi": 1]))")
                print("big sent: \\(pad!.send(["text": String(repeating: "x", count: 17000)]))")
                let sending = pad!.sendFile(Data(repeating: 7, count: 300_000), name: "rom.bin")
                spin(30) { sending.state != .sending }
                print("pad file \\(sending.state) \\(sending.sent)")
                spin(4)
                pad = nil
                spin(2)
                print("released")
            }
        }
        """

    /// The harness built with the wish's key in its Info.plist; `straightOnly: false` makes it reach the others only
    /// through Lamp's room (no listening, no dialling), as an app whose network look is turned down would.
    private func built(_ key: Data, main: String, roomOnly: Bool = false) throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-wish-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        var program = try WishNativeTests.program(main: main)
        if roomOnly {
            program = program.replacingOccurrences(of: "        private func reach() {\n", with: "        private func reach() {\n            return;\n")
        }
        try program.write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>dev.lamp.test.files</string>"
            + Template.wishKeyPlistLines(key) + "</dict></plist>"
        try plist.write(to: work.appendingPathComponent("wish.plist"), atomically: true, encoding: .utf8)
        let made = TestShell.run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o app main.swift -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker wish.plist 2>&1", in: work)
        XCTAssertEqual(made.status, 0, made.output)
        return work
    }

    private func room(_ apps: [String: (kind: String, name: String)]) async throws -> (Relay, UInt16, Data) {
        let relay = Relay(key: SymmetricKey(size: .bits256))
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let key = WishChannel.random(32)
        relay.configureRoom("wish:files", key: key, apps: apps)
        return (relay, try XCTUnwrap(started), key)
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined() }

    /// A file of a megabyte and more goes whole from one Swift app to another through Lamp's room, past the window ahead of
    /// what's acknowledged, and a third sent while two are on their way is turned down with why; then, with Lamp gone,
    /// one goes straight between them.
    func testAFileGoesBetweenTwoSwiftAppsThroughLampsRoomAndStraight() async throws {
        let (relay, port, key) = try await room(["mac": ("mac", "the Mac app"), "iphone": ("iphone", "the iPhone app")])
        defer { relay.stop() }
        let roomOnly = try built(key, main: Self.filesHarness, roomOnly: true)
        let both = try built(key, main: Self.filesHarness)
        defer { for work in [roomOnly, both] { try? FileManager.default.removeItem(at: work) } }
        let suite = "lamp-wish-files-\(UUID().uuidString)"
        defer { for each in ["mac", "iphone"] { UserDefaults.standard.removePersistentDomain(forName: "\(suite)-\(each)") } }
        func run(_ work: URL, _ settings: String) -> Task<String, Never> {
            Task.detached { TestShell.run("LAMP_SOCKET='ws://127.0.0.1:\(port)/' \(settings) ./app 2>&1", in: work).output }
        }

        // Through Lamp's room: neither app listens nor dials.
        let phone = run(roomOnly, "LAMP_DEFAULTS=\(suite)-iphone LAMP_PEER=iphone LAMP_WAIT=25")
        let mac = run(roomOnly, "LAMP_DEFAULTS=\(suite)-mac LAMP_PEER=mac LAMP_TO=iphone LAMP_FILES=3 LAMP_SIZE=1300000")
        let (phoneSaid, macSaid) = await (phone.value, mac.value)
        let sent = macSaid.split(separator: "\n").filter { $0.hasPrefix("sending ") }.map { $0.split(separator: " ") }
        XCTAssertEqual(sent.count, 3, macSaid)
        XCTAssertTrue(macSaid.contains("transfer file0.bin done 1300000/1300000"), macSaid)
        XCTAssertTrue(macSaid.contains("transfer file1.bin done 1300000/1300000"), macSaid)
        XCTAssertTrue(macSaid.contains("LampWish: the file \"file2.bin\" wasn't sent: Another file to the iPhone app is still on its way"), macSaid)
        XCTAssertTrue(macSaid.contains("transfer file2.bin failed("), macSaid)
        for line in sent.prefix(2) {
            XCTAssertTrue(phoneSaid.contains("got \(line[1]) application/test 1300000 \(line[3]) from mac"), "arrived whole through the room: \(phoneSaid)")
        }
        XCTAssertFalse(phoneSaid.contains("got file2.bin"), phoneSaid)

        // Straight between them, with Lamp gone once they've met.
        let phone2 = run(both, "LAMP_DEFAULTS=\(suite)-iphone LAMP_PEER=iphone LAMP_WAIT=25")
        let mac2 = run(both, "LAMP_DEFAULTS=\(suite)-mac LAMP_PEER=mac LAMP_TO=iphone LAMP_SETTLE=4 LAMP_FILES=1 LAMP_SIZE=700000")
        try await Task.sleep(for: .seconds(3))
        relay.stop()
        let (phoneSaid2, macSaid2) = await (phone2.value, mac2.value)
        let sent2 = try XCTUnwrap(macSaid2.split(separator: "\n").first { $0.hasPrefix("sending ") }?.split(separator: " "), macSaid2)
        XCTAssertTrue(macSaid2.contains("transfer file0.bin done 700000/700000"), macSaid2)
        XCTAssertTrue(phoneSaid2.contains("got file0.bin application/test 700000 \(sent2[3]) from mac"), "arrived whole with Lamp gone: \(phoneSaid2)")
    }

    /// A TV page running lamp.js, with the wish's key it claimed and what it kept of the wish; `room` is where Lamp's
    /// relay is, when Lamp is there.
    private func tvPage(key: Data, room port: UInt16?) -> PageWithSockets {
        let page = PageWithSockets()
        let tag = WishChannel.tag(for: SymmetricKey(data: key)).map { String(format: "%02x", $0) }.joined()
        let apps = #"[{ peer: 'mac', kind: 'mac', name: 'the Mac app' }, { peer: 'tv', kind: 'tv', name: 'the TV app' }]"#
        page.context.evaluateScript("""
            store['lamp:install.wish'] = JSON.stringify({ app: 'wishapp', key: '\(key.base64EncodedString())' });
            store['lamp:wish.\(tag)'] = JSON.stringify({ me: 'tv', apps: \(apps), at: {} });
            window.tizen = { systeminfo: { getPropertyValue: function (kind, ok) { if (kind === 'WIFI_NETWORK') ok({ ipAddress: '127.0.0.1' }); } } };
            LampAI._post = function (path) {
              // Lamp says where the wish's room is, when it's there; the game has no phones' page, so no relay link for it.
              if (path === '/app/wish') return \(port.map { "Promise.resolve({ socket: 'ws://127.0.0.1:\($0)/', peer: 'tv', apps: \(apps) })" } ?? "Promise.reject(new Error(\"Couldn't reach Lamp.\"))");
              return Promise.resolve({ links: [], renew: 60 });
            };
            """)
        page.context.evaluateScript(TVTemplate.controllersJS)
        page.context.evaluateScript(TVTemplate.wishJS.replacingOccurrences(of: DeviceSupport.webMarker, with: #"/*LAMP_INSTALL*/{"app":"wishapp","routes":[]}"#))
        return page
    }

    private func wait(_ page: PageWithSockets, _ condition: String, seconds: Double = 40) async throws {
        for _ in 0..<Int(seconds * 10) where page.context.evaluateScript(condition)?.toBool() != true { try await Task.sleep(for: .milliseconds(100)) }
    }

    /// With no Lamp at all, a wish's Mac app joins the TV page's game with `LampController`, the page finding it on its
    /// network: the page numbers it, hears its button and message, takes its file and sends one back with a message; a
    /// message over the limit isn't sent, the app says why and the page is told; and the controller let go leaves the
    /// game.
    func testAWishsMacAppPlaysTheTVAppsGameWithNoLamp() async throws {
        let (relay, port, key) = try await room(["mac": ("mac", "the Mac app"), "tv": ("tv", "the TV app")])
        let work = try built(key, main: Self.padHarness)
        defer { try? FileManager.default.removeItem(at: work) }
        let suite = "lamp-wish-files-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: "\(suite)-mac") }
        // The Mac app learns its wish from Lamp's room, then Lamp goes.
        let mac = Task.detached { TestShell.run("LAMP_SOCKET='ws://127.0.0.1:\(port)/' LAMP_APPS=mac,tv LAMP_DEFAULTS=\(suite)-mac LAMP_PEER=mac ./app 2>&1", in: work).output }
        try await Task.sleep(for: .seconds(3))
        relay.stop()

        let page = tvPage(key: key, room: nil)
        defer { page.end() }
        page.context.evaluateScript("""
            var events = [];
            Lamp.controllers.onJoin(function (n) {
              events.push('join ' + n);
              Lamp.controllers.send(n, { welcome: n });
              var save = new Uint8Array(200000); save[0] = 9;
              Lamp.controllers.sendFile(n, save, { name: 'save.dat' }).done.then(function () { events.push('sent save'); }, function (e) { events.push('save failed ' + e.message); });
            });
            Lamp.controllers.onLeave(function (n) { events.push('leave ' + n); });
            Lamp.controllers.onButton(function (n, name, down) { events.push('button ' + n + ' ' + name + ' ' + down); });
            Lamp.controllers.onMessage(function (n, data) { events.push('message ' + n + ' ' + JSON.stringify(data)); });
            Lamp.controllers.onFile(function (n, file) { file.done.then(function (b) { events.push('file ' + n + ' ' + file.name + ' ' + b.byteLength + ' ' + new Uint8Array(b)[0]); }); });
            Lamp.controllers.onError(function (m) { events.push('error ' + m); });
            Lamp.wish.start();
            Lamp.controllers.start();
            """)
        try await wait(page, "events.indexOf('leave 1') >= 0", seconds: 60)
        let events = page.context.evaluateScript("events.join('\\n')")?.toString() ?? ""
        let said = await mac.value
        XCTAssertTrue(said.contains("pad state connected player 1"), said)
        XCTAssertTrue(events.contains("join 1"), events)
        XCTAssertTrue(events.contains("button 1 a true") && events.contains("button 1 a false"), events)
        XCTAssertTrue(events.contains(#"message 1 {"hi":1}"#), events)
        XCTAssertTrue(said.contains("small sent: true"), said)
        XCTAssertTrue(said.contains("big sent: false"), said)
        XCTAssertTrue(said.contains("wasn't sent: a message between devices is at most 16384 bytes"), said)
        XCTAssertTrue(events.contains("error Lamp.controllers: Player 1's message of"), "the page is told of the message too big: \(events)")
        XCTAssertTrue(events.contains("file 1 rom.bin 300000 7"), events)
        XCTAssertTrue(said.contains("pad file done 300000"), said)
        XCTAssertTrue(said.contains(#"pad heard {"welcome":1}"#), said)
        XCTAssertTrue(said.contains("pad got save.dat 200000 9"), said)
        XCTAssertTrue(events.contains("sent save"), events)
        XCTAssertTrue(events.contains("leave 1"), "the controller let go left the game: \(events)")
    }

    /// Through Lamp's room, a TV page and a Mac app that doesn't reach it straight trade files with `Lamp.wish.sendFile`
    /// and `LampWish.sendFile`, each arriving whole with who sent it.
    func testATVPageAndAMacAppTradeFilesThroughLampsRoom() async throws {
        let (relay, port, key) = try await room(["mac": ("mac", "the Mac app"), "tv": ("tv", "the TV app")])
        defer { relay.stop() }
        let work = try built(key, main: Self.filesHarness, roomOnly: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let suite = "lamp-wish-files-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: "\(suite)-mac") }
        let mac = Task.detached { TestShell.run("LAMP_SOCKET='ws://127.0.0.1:\(port)/' LAMP_APPS=mac,tv LAMP_DEFAULTS=\(suite)-mac LAMP_PEER=mac LAMP_TO=tv LAMP_SETTLE=2 LAMP_SIZE=150000 LAMP_WAIT=15 ./app 2>&1", in: work).output }

        let page = tvPage(key: key, room: port)
        defer { page.end() }
        page.context.evaluateScript("""
            var events = [], sentPicture = false;
            Lamp.wish.onFile(function (from, file) { file.done.then(function (b) { events.push('file ' + from + ' ' + file.name + ' ' + file.type + ' ' + b.byteLength); }); });
            Lamp.wish.onPeers(function (list) {
              if (sentPicture || !list.some(function (p) { return p.peer === 'mac'; })) return;
              sentPicture = true;
              var picture = new Uint8Array(90000); for (var i = 0; i < picture.length; i++) picture[i] = i % 251;
              Lamp.wish.sendFile(picture, 'mac', { name: 'picture.png', type: 'image/png' }).done.then(function () { events.push('sent picture'); }, function (e) { events.push('picture failed ' + e.message); });
            });
            Lamp.wish.start();
            """)
        try await wait(page, "events.length >= 2")
        let events = page.context.evaluateScript("events.join('\\n')")?.toString() ?? ""
        let said = await mac.value
        XCTAssertTrue(events.contains("file mac file0.bin application/test 150000"), "the page got the Mac app's file: \(events) / \(said)")
        XCTAssertTrue(events.contains("sent picture"), events)
        var picture = Data(count: 90000)
        for i in 0..<picture.count { picture[i] = UInt8(i % 251) }
        XCTAssertTrue(said.contains("got picture.png image/png 90000 \(Self.digest(picture)) from tv"), "the Mac app got the page's file, whole: \(said)")
        XCTAssertTrue(said.contains("transfer file0.bin done 150000/150000"), said)
    }
}
