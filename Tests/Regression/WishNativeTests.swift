import CryptoKit
import LampRelayKit
import XCTest
@testable import Lamp

/// `LampWish` in LampSupport, as a wish's Swift apps have it, built as a plain program and run twice against a real
/// relay: a Mac app and an iPhone app of one wish join the room, see each other, and the message one sends arrives at
/// the other with who sent it.
final class WishNativeTests: XCTestCase {
    func testTwoSwiftAppsOfAWishSeeEachOtherAndAMessageArrives() async throws {
        let key = SymmetricKey(size: .bits256)
        let relay = Relay(key: key)
        defer { relay.stop() }
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        let room = "wish:native"
        relay.configureRoom(room, generation: 0, apps: ["mac": ("mac", "the Mac app"), "iphone": ("iphone", "the iPhone app")])

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-wish-native-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try Self.program().write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let built = TestShell.run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o wish main.swift 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)

        func credential(_ peer: String) -> String { ControllerToken.issue(kind: .peer, app: room, generation: 0, peer: peer, key: key) }
        let common = "LAMP_SOCKET='ws://127.0.0.1:\(port)/' LAMP_ROOM='\(room)'"
        // The iPhone app waits for a message; the Mac app waits for the iPhone app to be there, then sends one.
        async let phone = Task.detached { TestShell.run("\(common) LAMP_PEER=iphone LAMP_CREDENTIAL='\(credential("iphone"))' LAMP_ROLE=listen ./wish 2>&1", in: work).output }.value
        try await Task.sleep(for: .milliseconds(500))
        // The Mac app is first told a relay that isn't there (Lamp restarted, the relay moved): it asks Lamp again.
        async let mac = Task.detached { TestShell.run("\(common) LAMP_DEAD_SOCKET='ws://127.0.0.1:1/' LAMP_PEER=mac LAMP_CREDENTIAL='\(credential("mac"))' LAMP_ROLE=send ./wish 2>&1", in: work).output }.value
        let (phoneSaid, macSaid) = try await (phone, mac)
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
    /// from the environment, and says "iPhone simulator" for the device so both apps can run on this Mac.
    private static func program() throws -> String {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "@MainActor final class LampWish"))
        let end = try XCTUnwrap(support.range(of: "// MARK: - The wish's TV app", range: start.upperBound..<support.endIndex))
        let block = String(support[start.lowerBound..<end.lowerBound])
            .replacingOccurrences(of: "#if os(macOS)\n            return \"Mac\"", with: "#if os(macOS)\n            return \"iPhone simulator\"")
        return """
        import Foundation
        import SwiftUI
        enum LampAI {
            struct Failure: Error, LocalizedError { let message: String; var errorDescription: String? { message } }
            nonisolated(unsafe) static var asked = 0
            static func post(_ path: String, _ body: [String: Any], timeout: Double) async throws -> [String: Any] {
                let env = ProcessInfo.processInfo.environment
                asked += 1
                let socket = asked == 1 ? (env["LAMP_DEAD_SOCKET"] ?? env["LAMP_SOCKET"]!) : env["LAMP_SOCKET"]!
                return ["socket": socket, "room": env["LAMP_ROOM"]!, "peer": env["LAMP_PEER"]!, "credential": env["LAMP_CREDENTIAL"]!]
            }
        }
        \(block)
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
                if role == "send" {
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
}
