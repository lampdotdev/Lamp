import CryptoKit
import LampRelayKit
import XCTest
@testable import Lamp

/// Two Swift apps of one wish go on talking without Lamp: they meet in Lamp's room, each listens and is found on the
/// network, and when the relay goes (Lamp quit, the Mac asleep) their messages keep arriving over the link straight
/// between them, sealed with the wish's key. Opened again with no Lamp at all, they find each other from what they kept.
final class WishDirectTests: XCTestCase {
    /// Each app sends the other a number every half second and says what it heard, for as long as it's told to run.
    static let talker = """
        @main struct Talker {
            @MainActor static func main() {
                setvbuf(stdout, nil, _IONBF, 0)
                let env = ProcessInfo.processInfo.environment
                let to = env["LAMP_TO"]!, seconds = Double(env["LAMP_SECONDS"] ?? "20")!
                let wish = LampWish.shared
                wish.onMessage { from, data in
                    print("heard \\((data as? [String: Any])?["n"] as? Int ?? -1) from \\(from)")
                }
                let end = Date().addingTimeInterval(seconds)
                var n = 0, last = Date.distantPast
                while Date() < end {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                    if Date().timeIntervalSince(last) > 0.5, wish.peer(to)?.isOpen == true {
                        last = Date()
                        n += 1
                        _ = wish.send(["n": n], to: to)
                    }
                }
                print("state \\(wish.state.rawValue)")
            }
        }
        """

    func testTwoAppsGoOnTalkingWithLampGoneAndFindEachOtherWithoutIt() async throws {
        let relay = Relay(key: SymmetricKey(size: .bits256))
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        let key = WishChannel.random(32)
        relay.configureRoom("wish:direct", key: key, apps: ["mac": ("mac", "the Mac app"), "iphone": ("iphone", "the iPhone app")])

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-wish-direct-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try WishNativeTests.program(main: Self.talker).write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>dev.lamp.test.direct</string>"
            + Template.wishKeyPlistLines(key) + "</dict></plist>"
        try plist.write(to: work.appendingPathComponent("wish.plist"), atomically: true, encoding: .utf8)
        let built = TestShell.run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o talker main.swift -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker wish.plist 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)

        let suite = "lamp-wish-direct-\(UUID().uuidString)"
        defer { for each in ["mac", "iphone"] { UserDefaults.standard.removePersistentDomain(forName: "\(suite)-\(each)") } }
        func run(_ me: String, to: String, seconds: Int, lamp: Bool, log: String) -> Task<Void, Never> {
            let socket = lamp ? "LAMP_SOCKET='ws://127.0.0.1:\(port)/' " : ""
            let command = "\(socket)LAMP_DEFAULTS=\(suite)-\(me) LAMP_PEER=\(me) LAMP_TO=\(to) LAMP_SECONDS=\(seconds) ./talker > \(log) 2>&1"
            return Task.detached { _ = TestShell.run(command, in: work) }
        }
        func heard(_ log: String) -> [Int] {
            ((try? String(contentsOf: work.appendingPathComponent(log), encoding: .utf8)) ?? "").split(separator: "\n")
                .compactMap { $0.hasPrefix("heard ") ? Int($0.split(separator: " ")[1]) : nil }
        }

        // With Lamp: they meet in the room, and find each other straight too.
        let phone = run("iphone", to: "mac", seconds: 30, lamp: true, log: "phone.txt")
        let mac = run("mac", to: "iphone", seconds: 30, lamp: true, log: "mac.txt")
        for _ in 0..<200 where heard("phone.txt").count < 4 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(heard("phone.txt").isEmpty, "they talked while Lamp was there")

        // Lamp goes.
        relay.stop()
        let before = heard("phone.txt").max() ?? 0
        try await Task.sleep(for: .seconds(8))
        let after = heard("phone.txt").filter { $0 > before }
        XCTAssertGreaterThan(after.count, 5, "messages kept arriving after the relay went: \(heard("phone.txt"))")
        _ = await (phone.value, mac.value)

        // Opened again with no Lamp at all: they find each other from what they kept.
        let phone2 = run("iphone", to: "mac", seconds: 15, lamp: false, log: "phone2.txt")
        let mac2 = run("mac", to: "iphone", seconds: 15, lamp: false, log: "mac2.txt")
        _ = await (phone2.value, mac2.value)
        XCTAssertGreaterThan(heard("phone2.txt").count, 5, "no Lamp: \((try? String(contentsOf: work.appendingPathComponent("phone2.txt"), encoding: .utf8)) ?? "")")
        XCTAssertGreaterThan(heard("mac2.txt").count, 5, "both ways")
    }
}
