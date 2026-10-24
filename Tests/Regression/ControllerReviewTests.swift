import CryptoKit
import JavaScriptCore
@testable import LampRelayKit
import XCTest
@testable import Lamp

/// What a phone and a TV are owed when things go wrong around them: a button let go reaches the TV however far behind
/// it is, a phone hears that the host it was sending to has gone when another takes its place, a file too big to send
/// is refused before it's read, and a wish's iPhone app stops listening once nothing holds its controller.
final class ControllerReviewTests: XCTestCase {
    private let key = SymmetricKey(size: .bits256)

    // MARK: Through the relay

    private func relay() async throws -> (Relay, URL) {
        let relay = Relay(key: key)
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        relay.configure(app: "game", Relay.Session(generation: 0, pagePort: nil, page: nil, hosts: []))
        return (relay, try XCTUnwrap(URL(string: "ws://127.0.0.1:\(port)/")))
    }

    private func join(_ address: URL, as kind: ControllerToken.Kind, preview: Bool = false) async throws -> URLSessionWebSocketTask {
        let socket = URLSession.shared.webSocketTask(with: address)
        socket.resume()
        try await socket.send(.string(Self.json(["t": "hello", "app": "game",
                                                 "credential": ControllerToken.issue(kind: kind, app: "game", generation: 0, preview: preview, key: key)])))
        _ = try await Self.text(socket, until: "welcome")
        return socket
    }

    /// A TV that has fallen behind loses what phones send meanwhile, but never a button let go: the TV would otherwise
    /// go on believing it held, with nothing ever saying otherwise.
    func testAButtonLetGoReachesATVThatIsBehind() async throws {
        let (relay, address) = try await relay()
        defer { relay.stop(); Relay.hostBehind = 128 }
        let host = try await join(address, as: .host)
        let phone = try await join(address, as: .join)
        _ = try await Self.text(host, until: "joined")
        Relay.hostBehind = -1   // the TV counts as behind whatever it has waiting
        try await phone.send(.string(Self.json(["t": "button", "name": "fire", "down": true, "seq": 1])))
        try await phone.send(.string(Self.json(["t": "button", "name": "fire", "down": false, "seq": 2])))
        let pressed = try await Self.text(host, until: "button", within: 3)
        let released = try await Self.text(host, until: "button", within: 3)
        XCTAssertEqual(pressed["down"] as? Bool, true)
        XCTAssertEqual(released["down"] as? Bool, false, "the button was let go on the TV too")
    }

    /// The preview taking the game from a TV (or any host replacing another) ends every file on its way to or from the
    /// old one: the phones are told the host left before they're told it's back, which is what ends their transfers.
    func testPhonesHearTheirHostLeftWhenAnotherTakesItsPlace() async throws {
        let (relay, address) = try await relay()
        defer { relay.stop() }
        let tv = try await join(address, as: .host)
        let phone = try await join(address, as: .join)
        _ = try await Self.text(tv, until: "joined")
        _ = try await join(address, as: .host, preview: true)
        var heard: [Bool] = []
        while heard.count < 2 {
            let state = try await Self.text(phone, until: "state", within: 3)
            heard.append(state["host"] as? Bool == true)
        }
        XCTAssertEqual(heard, [false, true], "the phone heard the old host go before the new one came")
    }

    // MARK: The libraries

    /// A file over the limit is refused by its size, before it's read: reading a phone's whole video into memory first
    /// could end the page before it said why.
    func testAFileTooBigIsRefusedBeforeItIsRead() throws {
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, value in failure = value?.toString() }
        context.evaluateScript("""
            var window = this, reads = 0, refused = null;
            function Blob(size) { this.size = size; this.name = 'video.mov'; }
            function FileReader() {}
            FileReader.prototype.readAsArrayBuffer = function () { reads++; };
            function setTimeout() { return 0; } function clearTimeout() {}
            """)
        let files = TVTemplate.filesJS
        context.evaluateScript(files + """
            var engine = lampFiles(function () {});
            var route = { key: 'tv', place: 0, text: function () { return true; }, binary: function () { return true; }, buffered: function () { return 0; } };
            var sending = engine.send(route, new Blob(1024 * 1024 * 1024));
            sending.done.then(null, function (e) { refused = e.message; });
            """)
        XCTAssertNil(failure)
        XCTAssertEqual(context.evaluateScript("reads")?.toInt32(), 0, "the file wasn't read")
        XCTAssertTrue(context.evaluateScript("String(refused)")?.toString().contains("64 MB") == true)
    }

    /// A wish's iPhone app keeps telling Lamp where it listens only while something holds its controller: released, it
    /// stops, and so does its listener.
    func testAReleasedPhoneControllerStopsListening() throws {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "@MainActor final class LampController"))
        let end = try XCTUnwrap(support.range(of: "// MARK: - Mac building blocks", range: start.upperBound..<support.endIndex))
        // Made to listen as it does on the phone, with Lamp's answers stood in for.
        let controller = String(support[start.lowerBound..<end.lowerBound]).replacingOccurrences(
            of: #"#if os\(iOS\)\s*pad\.listen\(\)\s*#else\s*pad\.open\(\)\s*#endif"#, with: "pad.listen()", options: .regularExpression)
        XCTAssertFalse(controller.contains("pad.open()\n"), "the controller is made to listen")
        let program = """
        import CryptoKit
        import Foundation
        import Network
        import SwiftUI
        nonisolated(unsafe) var registrations = 0
        enum LampAI {
            struct Failure: Error { let message: String }
            static func post(_ path: String, _ body: [String: Any], timeout: Double) async throws -> [String: Any] {
                registrations += 1
                return ["key": "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=", "renew": 0.2]
            }
        }
        \(controller)
        @main struct Harness {
            @MainActor static func main() {
                setvbuf(stdout, nil, _IONBF, 0)
                func spin(_ seconds: Double) {
                    let end = Date().addingTimeInterval(seconds)
                    while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
                }
                var pad: LampController? = LampController.connect()
                spin(1)
                print("registered while held: \\(registrations > 1)")
                _ = pad
                pad = nil
                spin(0.5)
                let after = registrations
                spin(1.5)
                print("registrations after release: \\(registrations - after)")
            }
        }
        """
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-controller-release-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try program.write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let built = TestShell.run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o pad main.swift 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)
        let printed = TestShell.run("./pad 2>&1", in: work).output
        XCTAssertTrue(printed.contains("registered while held: true"), printed)
        XCTAssertTrue(printed.contains("registrations after release: 0"), "nothing registers once the controller is let go: \(printed)")
    }

    // MARK: Helpers

    /// The next text message of a kind on a socket, past everything else.
    private static func text(_ socket: URLSessionWebSocketTask, until kind: String, within seconds: Double = 10) async throws -> [String: Any] {
        try await withThrowingTaskGroup(of: [String: Any].self) { group in
            group.addTask {
                while true {
                    if case .string(let text) = try await socket.receive(),
                       let message = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any], message["t"] as? String == kind {
                        return message
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                socket.cancel(with: .goingAway, reason: nil)   // a receive can't be cancelled otherwise
                throw URLError(.timedOut)
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private static func json(_ value: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: value)) ?? Data(), as: UTF8.self)
    }
}
