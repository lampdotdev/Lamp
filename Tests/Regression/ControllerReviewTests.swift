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
