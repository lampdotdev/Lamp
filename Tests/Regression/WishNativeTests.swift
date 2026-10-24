import CryptoKit
import LampRelayKit
import XCTest
@testable import Lamp

/// `LampWish` in LampSupport, as a wish's Swift apps have it, built as a plain program with the wish's key in its
/// Info.plist, as Lamp installs a Mac app, and run twice against a real relay: a Mac app and an iPhone app of one wish
/// prove they hold the key, see each other, and the message one sends arrives at the other, sealed, with who sent it. A
/// copy with another key gets in nowhere.
final class WishNativeTests: XCTestCase {
    func testTwoSwiftAppsOfAWishSeeEachOtherAndAMessageArrives() async throws {
        let relay = Relay(key: SymmetricKey(size: .bits256))
        defer { relay.stop() }
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        let key = WishChannel.random(32)
        relay.configureRoom("wish:native", key: key, apps: ["mac": ("mac", "the Mac app"), "iphone": ("iphone", "the iPhone app")])

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-wish-native-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try Self.program().write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        // The key where Lamp writes it into an installed app's Info.plist (`Template.wishKeyName`), here in the program.
        for (name, given) in [("wish", key), ("stranger", WishChannel.random(32))] {
            let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>dev.lamp.test.\(name)</string>"
                + Template.wishKeyPlistLines(given) + "</dict></plist>"
            try plist.write(to: work.appendingPathComponent("\(name).plist"), atomically: true, encoding: .utf8)
            let built = TestShell.run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o \(name) main.swift -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker \(name).plist 2>&1", in: work)
            XCTAssertEqual(built.status, 0, built.output)
        }

        let suite = "lamp-wish-native-\(UUID().uuidString)"
        defer { for each in ["phone", "mac", "stranger"] { UserDefaults.standard.removePersistentDomain(forName: "\(suite)-\(each)") } }
        let common = "LAMP_SOCKET='ws://127.0.0.1:\(port)/'"
        // The iPhone app waits for a message; the Mac app waits for the iPhone app to be there, then sends one.
        async let phone = Task.detached { TestShell.run("\(common) LAMP_DEFAULTS=\(suite)-phone LAMP_PEER=iphone LAMP_ROLE=listen ./wish 2>&1", in: work).output }.value
        try await Task.sleep(for: .milliseconds(500))
        // The Mac app is first told a relay that isn't there (Lamp restarted, the relay moved): it asks Lamp again.
        async let mac = Task.detached { TestShell.run("\(common) LAMP_DEFAULTS=\(suite)-mac LAMP_DEAD_SOCKET='ws://127.0.0.1:1/' LAMP_PEER=mac LAMP_ROLE=send ./wish 2>&1", in: work).output }.value
        // A copy that has another key, as one Lamp didn't put there would.
        async let stranger = Task.detached { TestShell.run("\(common) LAMP_DEFAULTS=\(suite)-stranger LAMP_PEER=mac LAMP_ROLE=stranger ./stranger 2>&1", in: work).output }.value
        let (phoneSaid, macSaid, strangerSaid) = try await (phone, mac, stranger)
        XCTAssertTrue(strangerSaid.contains("stranger state connecting") || strangerSaid.contains("stranger state away"),
                      "a copy with another key never gets in: \(strangerSaid)")
        XCTAssertFalse(strangerSaid.contains("heard from"), strangerSaid)
        XCTAssertTrue(macSaid.contains("LampWish: "), "the first try failed and was said: \(macSaid)")
        XCTAssertTrue(macSaid.contains("me mac state connected"), "then it asked Lamp again and joined: \(macSaid)")
        XCTAssertTrue(macSaid.contains("sees iphone (the iPhone app on iPhone simulator)"), "the Mac app sees the iPhone app: \(macSaid)")
        XCTAssertTrue(macSaid.contains("sent true"), macSaid)
        XCTAssertTrue(phoneSaid.contains("heard from mac: {\"score\":3}"), "the message arrived with who sent it: \(phoneSaid)")
        XCTAssertTrue(phoneSaid.contains("refused false"), "a message to an app that isn't open isn't sent: \(phoneSaid)")
        XCTAssertTrue(phoneSaid.contains("isn't open now"), phoneSaid)
        XCTAssertTrue(phoneSaid.contains("status connected reason []"), "connected, nothing to say: \(phoneSaid)")
        XCTAssertTrue(phoneSaid.contains("mac now notOpen: The Mac app isn't open. seen true"),
                      "the Mac app that left is still known, with why and when it was last seen: \(phoneSaid)")
    }

    /// LampWish out of the support library, with a stand-in for LampAI.post that answers as Lamp's `/app/wish` does,
    /// from the environment (and as an unreachable Lamp does without `LAMP_SOCKET`), says "iPhone simulator" for the
    /// device so both apps can run on this Mac, and keeps what it keeps in defaults of its own (`LAMP_DEFAULTS`), as
    /// two apps would.
    static func program(main: String = harness) throws -> String {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "@MainActor final class LampWish"))
        let end = try XCTUnwrap(support.range(of: "// MARK: - The wish's TV app", range: start.upperBound..<support.endIndex))
        let block = String(support[start.lowerBound..<end.lowerBound])
            .replacingOccurrences(of: "#if os(macOS)\n            return \"Mac\"", with: "#if os(macOS)\n            return \"iPhone simulator\"")
            .replacingOccurrences(of: "UserDefaults.standard", with: "UserDefaults(suiteName: ProcessInfo.processInfo.environment[\"LAMP_DEFAULTS\"] ?? \"lamp-wish-test\")!")
        return """
        import AppKit
        import CryptoKit
        import Foundation
        import Network
        import SwiftUI
        enum LampAI {
            struct Failure: Error, LocalizedError { let message: String; var errorDescription: String? { message } }
            nonisolated(unsafe) static var asked = 0
            static func post(_ path: String, _ body: [String: Any], timeout: Double) async throws -> [String: Any] {
                let env = ProcessInfo.processInfo.environment
                asked += 1
                guard let live = env["LAMP_SOCKET"] else { throw Failure(message: "Couldn't reach Lamp.") }
                let socket = asked == 1 ? (env["LAMP_DEAD_SOCKET"] ?? live) : live
                // The wish's apps, as Lamp would say them: a Mac app and an iPhone app, unless the test says others.
                let apps = (env["LAMP_APPS"] ?? "mac,iphone").split(separator: ",").map { ["peer": String($0), "kind": String($0), "name": "the " + String($0) + " app"] }
                return ["socket": socket, "peer": env["LAMP_PEER"]!, "apps": apps]
            }
        }
        \(block)
        \(main)
        """
    }

    static let harness = """
        @main struct Harness {
            @MainActor static func main() {
                setvbuf(stdout, nil, _IONBF, 0)
                let role = ProcessInfo.processInfo.environment["LAMP_ROLE"] ?? ""
                let wish = LampWish.shared
                var heard: [String] = []
                wish.onMessage { from, data in
                    let text = (try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "?"
                    heard.append("heard from \\(from): \\(text)")
                }
                func spin(_ seconds: Double, until done: () -> Bool) {
                    let end = Date().addingTimeInterval(seconds)
                    while Date() < end, !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
                }
                spin(10) { wish.state == .connected }
                print("me \\(wish.me) state \\(wish.state.rawValue)")
                if role == "stranger" {
                    spin(4) { false }
                    print("stranger state \\(wish.state.rawValue)")
                    for line in heard { print(line) }
                } else if role == "send" {
                    spin(10) { wish.peer("iphone")?.isOpen == true }
                    for peer in wish.peers { print("sees \\(peer.id) (\\(peer.name) on \\(peer.device))") }
                    print("sent \\(wish.send(["score": 3], to: "iphone"))")
                    spin(1) { false }
                } else {
                    spin(15) { !heard.isEmpty }
                    for line in heard { print(line) }
                    print("refused \\(wish.send(["x": 1], to: "android"))")
                    print("status \\(wish.status.state.rawValue) reason [\\(wish.status.reason)]")
                    spin(10) { wish.peer("mac")?.isOpen == false }
                    if let mac = wish.peer("mac") { print("mac now \\(mac.status.state.rawValue): \\(mac.status.reason) seen \\(mac.status.lastSeen != nil)") }
                }
            }
        }
        """
}
