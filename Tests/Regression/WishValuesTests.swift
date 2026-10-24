import CryptoKit
import JavaScriptCore
import LampRelayKit
import XCTest
@testable import Lamp

/// `LampWish.values` in LampSupport, built as a plain program with the wish's key in its Info.plist as Lamp installs a
/// Mac app, and run against a real relay: a value set while the other app is closed reaches it when they next meet, the
/// later of two settings made apart wins in both, a removal goes too, and what each app keeps is still there with no
/// Lamp. An app built before values is shown as out of date and is sent none. A TV page and a Mac app share values on
/// the link straight between them, with Lamp gone.
@MainActor
final class WishValuesTests: XCTestCase {
    /// Sets what `LAMP_SET` says as it opens ("name=JSON;…", "nil" removing), waits for `LAMP_TO` to be open if given,
    /// then sets `LAMP_THEN`, and says every change it hears and what it ends with.
    static let harness = """
        @main struct Harness {
            @MainActor static func main() {
                setvbuf(stdout, nil, _IONBF, 0)
                let env = ProcessInfo.processInfo.environment
                let wish = LampWish.shared
                func text(_ value: Any?) -> String {
                    guard let value else { return "nil" }
                    return (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])).map { String(decoding: $0, as: UTF8.self) } ?? "?"
                }
                func spin(_ seconds: Double, until done: () -> Bool = { false }) {
                    let end = Date().addingTimeInterval(seconds)
                    while Date() < end, !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
                }
                func set(_ list: String?) {
                    for pair in (list ?? "").split(separator: ";") {
                        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                        let value = parts[1] == "nil" ? nil : try? JSONSerialization.jsonObject(with: Data(parts[1].utf8), options: .fragmentsAllowed)
                        print("set \\(parts[0]) \\(wish.set(parts[0], value))")
                    }
                }
                wish.onChange { key, value, from in print("change \\(key) = \\(text(value)) from \\(from)") }
                set(env["LAMP_SET"])
                if let other = env["LAMP_TO"] {
                    spin(15) { wish.peer(other)?.isOpen == true }
                    print("met \\(other) \\(wish.peer(other)?.isOpen == true)")
                    if let peer = wish.peer(other) { print("peer \\(other) \\(peer.status.state.rawValue): \\(peer.status.reason)") }
                    spin(Double(env["LAMP_WAIT"] ?? "2")!)
                    set(env["LAMP_THEN"])
                    spin(Double(env["LAMP_WAIT"] ?? "2")!)
                } else {
                    spin(1)
                }
                print("values \\(text(wish.values))")
            }
        }
        """

    private func built(_ key: Data, old: Bool = false) throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-wish-values-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        var program = try WishNativeTests.program(main: Self.harness)
        // An app built before values says nothing of what it speaks.
        if old { program = program.replacingOccurrences(of: ", \"wire\": Self.wire]", with: "]") }
        try program.write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>dev.lamp.test.values</string>"
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
        relay.configureRoom("wish:values", key: key, apps: apps)
        return (relay, try XCTUnwrap(started), key)
    }

    func testAValueReachesAnAppThatWasClosedAndTheLaterSettingWins() async throws {
        let (relay, port, key) = try await room(["mac": ("mac", "the Mac app"), "iphone": ("iphone", "the iPhone app")])
        defer { relay.stop() }
        let work = try built(key)
        defer { try? FileManager.default.removeItem(at: work) }
        let suite = "lamp-wish-values-\(UUID().uuidString)"
        defer { for each in ["mac", "iphone"] { UserDefaults.standard.removePersistentDomain(forName: "\(suite)-\(each)") } }
        func run(_ me: String, lamp: Bool = true, _ settings: String) async -> String {
            let socket = lamp ? "LAMP_SOCKET='ws://127.0.0.1:\(port)/' " : ""
            return await Task.detached { TestShell.run("\(socket)LAMP_DEFAULTS=\(suite)-\(me) LAMP_PEER=\(me) \(settings) ./app 2>&1", in: work).output }.value
        }

        // Each sets values with the other closed: the Mac app first, then the iPhone app the score again, later.
        let mac1 = await run("mac", #"LAMP_SET='list=["milk"];score=1;gone="x"'"#)
        XCTAssertTrue(mac1.contains("set list true") && mac1.contains(#"values {"gone":"x","list":["milk"],"score":1}"#), mac1)
        let phone1 = await run("iphone", "LAMP_SET='score=2'")
        XCTAssertTrue(phone1.contains(#"values {"score":2}"#), phone1)

        // Open together: each gets what the other set, the later score wins in both, and a removal made now goes too.
        async let mac2 = run("mac", "LAMP_TO=iphone LAMP_THEN='gone=nil'")
        async let phone2 = run("iphone", "LAMP_TO=mac")
        let (macSaid, phoneSaid) = await (mac2, phone2)
        XCTAssertTrue(phoneSaid.contains("met mac true"), phoneSaid)
        XCTAssertTrue(phoneSaid.contains(#"change list = ["milk"] from mac"#), phoneSaid)
        XCTAssertTrue(phoneSaid.contains("change gone = nil from mac"), "the removal reached it: \(phoneSaid)")
        XCTAssertFalse(phoneSaid.contains("change score"), "its own later score stood: \(phoneSaid)")
        XCTAssertTrue(macSaid.contains("change score = 2 from iphone"), macSaid)
        XCTAssertTrue(phoneSaid.contains(#"values {"list":["milk"],"score":2}"#), phoneSaid)
        XCTAssertTrue(macSaid.contains(#"values {"list":["milk"],"score":2}"#), macSaid)
        XCTAssertTrue(phoneSaid.contains("peer mac connected: "), phoneSaid)

        // Opened again with no Lamp and the Mac app closed: what it has is kept on the device.
        let phone3 = await run("iphone", lamp: false, "")
        XCTAssertTrue(phone3.contains(#"values {"list":["milk"],"score":2}"#), phone3)

        // What can't be a value is refused, with why.
        let refused = await run("iphone", lamp: false, "LAMP_SET='big=\"\(String(repeating: "a", count: 9000))\"'")
        XCTAssertTrue(refused.contains("set big false") && refused.contains("at most 8192 bytes"), refused)
    }

    /// An app built before values says nothing of what it speaks: the other shows it as out of date, still open, and
    /// sends it no values, which it couldn't read.
    func testAnAppBuiltBeforeValuesIsOutOfDateAndSentNone() async throws {
        let (relay, port, key) = try await room(["mac": ("mac", "the Mac app"), "iphone": ("iphone", "the iPhone app")])
        defer { relay.stop() }
        let new = try built(key), old = try built(key, old: true)
        defer { try? FileManager.default.removeItem(at: new); try? FileManager.default.removeItem(at: old) }
        let suite = "lamp-wish-values-\(UUID().uuidString)"
        defer { for each in ["mac", "iphone"] { UserDefaults.standard.removePersistentDomain(forName: "\(suite)-\(each)") } }
        let common = "LAMP_SOCKET='ws://127.0.0.1:\(port)/'"
        async let mac = Task.detached { TestShell.run("\(common) LAMP_DEFAULTS=\(suite)-mac LAMP_PEER=mac LAMP_TO=iphone ./app 2>&1", in: old).output }.value
        async let phone = Task.detached { TestShell.run("\(common) LAMP_DEFAULTS=\(suite)-iphone LAMP_PEER=iphone LAMP_TO=mac LAMP_SET='score=3' ./app 2>&1", in: new).output }.value
        let (macSaid, phoneSaid) = await (mac, phone)
        XCTAssertTrue(phoneSaid.contains("met mac true"), "out of date is still open: \(phoneSaid)")
        XCTAssertTrue(phoneSaid.contains("peer mac outOfDate: The Mac app is out of date. Open it from Lamp on your Mac to update it."), phoneSaid)
        XCTAssertFalse(macSaid.contains("change score"), "nothing sent to the older app: \(macSaid)")
    }

    /// With Lamp gone, a TV page finds the Mac app on its network, and each gets the values the other set: lamp.js and
    /// LampSupport.swift read each other's settings, on the link straight between them.
    func testATVPageAndAMacAppShareValuesWithoutLamp() async throws {
        let (relay, port, key) = try await room(["mac": ("mac", "the Mac app"), "tv": ("tv", "the TV app")])
        let work = try built(key)
        defer { try? FileManager.default.removeItem(at: work) }
        let suite = "lamp-wish-values-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: "\(suite)-mac") }
        let command = "LAMP_SOCKET='ws://127.0.0.1:\(port)/' LAMP_APPS=mac,tv LAMP_DEFAULTS=\(suite)-mac LAMP_PEER=mac LAMP_TO=tv LAMP_WAIT=4 "
            + #"LAMP_SET='list=["milk","eggs"]' ./app 2>&1"#
        let mac = Task.detached { TestShell.run(command, in: work).output }
        try await Task.sleep(for: .seconds(3))
        relay.stop()

        let page = PageWithSockets()
        let tag = WishChannel.tag(for: SymmetricKey(data: key)).map { String(format: "%02x", $0) }.joined()
        page.context.evaluateScript("""
            store['lamp:install.wish'] = JSON.stringify({ app: 'wishapp', key: '\(key.base64EncodedString())' });
            store['lamp:wish.\(tag)'] = JSON.stringify({ me: 'tv', apps: [{ peer: 'mac', kind: 'mac', name: 'the Mac app' }, { peer: 'tv', kind: 'tv', name: 'the TV app' }], at: {} });
            window.tizen = { systeminfo: { getPropertyValue: function (kind, ok) { if (kind === 'WIFI_NETWORK') ok({ ipAddress: '127.0.0.1' }); } } };
            """)
        page.context.evaluateScript(TVTemplate.wishJS.replacingOccurrences(of: DeviceSupport.webMarker, with: #"/*LAMP_INSTALL*/{"app":"wishapp","routes":[]}"#))
        page.context.evaluateScript("""
            var changes = [];
            Lamp.wish.onChange(function (key, value, from) { changes.push(key + '=' + JSON.stringify(value) + ' from ' + from); });
            Lamp.wish.set('round', 4);
            Lamp.wish.start();
            """)
        for _ in 0..<200 where page.context.evaluateScript("changes.length")?.toInt32() ?? 0 < 2 { try await Task.sleep(for: .milliseconds(100)) }
        let changes = page.context.evaluateScript("changes.join('|')")?.toString() ?? ""
        XCTAssertTrue(changes.contains(#"list=["milk","eggs"] from mac"#), "the page got the Mac app's value: \(changes)")
        XCTAssertEqual(page.context.evaluateScript("JSON.stringify(Lamp.wish.values())")?.toString(), #"{"round":4,"list":["milk","eggs"]}"#)
        let said = await mac.value
        page.end()
        XCTAssertTrue(said.contains("change round = 4 from tv"), "the Mac app got the page's: \(said)")
        XCTAssertTrue(said.contains(#"values {"list":["milk","eggs"],"round":4}"#), said)
    }
}
