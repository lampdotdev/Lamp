import JavaScriptCore
import LampRelayKit
import XCTest
@testable import Lamp

/// The relay passes at most `ControllerWire.message` bytes in one message between devices and closes a socket that
/// sends more. A TV app whose phone sent a file in pieces too big for a message lost every one of them, and its builder
/// saw only a transfer that stopped: each library of Lamp's refuses such a message before it goes, says so with the
/// limit, and tells the TV app, whose log the builder reads. (A file goes with `sendFile` now, in pieces of its own.)
final class ControllerMessageSizeTests: XCTestCase {
    private static let limit = ControllerWire.message
    /// A message a little over the limit.
    private static let tooMany = limit + 600

    // MARK: The wish's iPhone or Mac app (LampController in LampSupport)

    func testTheNativeControllerRefusesAMessageOverTheLimitAndSaysSo() throws {
        let printed = try runNativeController()
        XCTAssertTrue(printed.contains("wasn't sent: a message between devices is at most \(Self.limit) bytes"), printed)
        XCTAssertFalse(printed.contains("server closed 1009"), "nothing over the limit reached Lamp: \(printed)")
        XCTAssertTrue(printed.contains("server heard too-big"), "the TV app is told: \(printed)")
        XCTAssertTrue(printed.contains("server heard message small on connection 1"), "the link stays up: \(printed)")
        XCTAssertTrue(printed.contains("big sent: false"), printed)
        XCTAssertTrue(printed.contains("small sent: true"), printed)
    }

    private func runNativeController() throws -> String {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "@MainActor final class LampController"))
        let end = try XCTUnwrap(support.range(of: "// MARK: - Mac building blocks", range: start.upperBound..<support.endIndex))
        let program = """
        import CryptoKit
        import Foundation
        import Network
        import SwiftUI
        nonisolated(unsafe) var socketAddress = ""
        enum LampAI {
            struct Failure: Error { let message: String }
            static func post(_ path: String, _ body: [String: Any], timeout: Double) async throws -> [String: Any] {
                ["socket": socketAddress, "join": "made-up-join"]
            }
        }
        let limit = \(Self.limit)
        \(support[start.lowerBound..<end.lowerBound])
        \(Self.harness)
        """
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-controller-size-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try program.write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let built = TestShell.run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o pad main.swift 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)
        return TestShell.run("./pad 2>&1", in: work).output
    }

    /// A stand-in for the relay's socket that holds to its limit as the relay does, and a piece over it.
    private static let harness = #"""
    @main struct Harness {
        @MainActor static func main() throws {
            setvbuf(stdout, nil, _IONBF, 0)   // in order with what the controller says on stderr
            let parameters = NWParameters.tcp
            parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
            let listener = try NWListener(using: parameters, on: .any)
            nonisolated(unsafe) var connections = 0
            listener.newConnectionHandler = { connection in
                connections += 1
                let number = connections
                connection.start(queue: .main)
                func send(_ text: String) {
                    let context = NWConnection.ContentContext(identifier: "text", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
                    connection.send(content: Data(text.utf8), contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
                }
                func receive() {
                    connection.receiveMessage { data, _, _, error in
                        guard let data, error == nil else { return }
                        if data.count > limit {
                            print("server closed 1009")
                            let close = NWProtocolWebSocket.Metadata(opcode: .close)
                            close.closeCode = .protocolCode(.messageTooBig)
                            connection.send(content: nil, contentContext: NWConnection.ContentContext(identifier: "close", metadata: [close]),
                                            isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
                            return
                        }
                        let m = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                        switch m["t"] as? String {
                        case "hello": send(#"{"t":"welcome","player":1,"host":true,"credential":"made-up-kept"}"#)
                        case "too-big": print("server heard too-big \(m["bytes"] ?? "")")
                        case "message": print("server heard message \((m["data"] as? [String: Any])?["chunk"] as? String ?? "?") on connection \(number)")
                        default: break
                        }
                        receive()
                    }
                }
                receive()
            }
            listener.start(queue: .main)
            func spin(_ seconds: Double, until done: () -> Bool = { false }) {
                let end = Date().addingTimeInterval(seconds)
                while Date() < end, !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            }
            spin(5) { (listener.port?.rawValue ?? 0) != 0 }   // 0 until it listens
            socketAddress = "ws://127.0.0.1:\(listener.port!.rawValue)/socket"

            let pad = LampController.connect()
            spin(10) { pad.state == .connected }
            print("state \(pad.state.rawValue)")
            let big = pad.send(["chunk": String(repeating: "A", count: limit + 600)])
            print("big sent: \(big)")
            spin(0.5)
            let small = pad.send(["chunk": "small"])
            print("small sent: \(small)")
            spin(1.5)
        }
    }
    """#

    // MARK: The phone's page (lamp-controller.js) and the TV's (lamp.js)

    func testThePhonePageRefusesAMessageOverTheLimitAndTellsTheTV() throws {
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, value in failure = value?.toString() }
        context.evaluateScript("""
            var window = this, sent = [], errors = [], sockets = [], store = {};
            var console = { error: function (m) { errors.push(String(m)); }, log: function () {} };
            var location = { hash: '#join', pathname: '/', search: '', protocol: 'http:', host: '192.168.1.20:47860', hostname: '192.168.1.20' };
            var history = { replaceState: function () { location.hash = ''; } };
            var sessionStorage = {
              getItem: function (k) { return store.hasOwnProperty(k) ? store[k] : null; },
              setItem: function (k, v) { store[k] = String(v); }, removeItem: function (k) { delete store[k]; }
            };
            function WebSocket(url) { this.readyState = 1; sockets.push(this); }
            WebSocket.prototype.send = function (text) { sent.push(text); };
            WebSocket.prototype.close = function () {};
            function fetch() { return Promise.resolve({ ok: true, json: function () { return { port: 47900, app: 'padgame' }; } }); }
            function setInterval() { return 0; } function clearInterval() {} function setTimeout() { return 0; }
            """)
        context.evaluateScript(TVTemplate.phoneControllerJS)
        context.evaluateScript("var pad = LampController.connect({});")
        context.evaluateScript("""
            sockets[0].onopen();
            sockets[0].onmessage({ data: JSON.stringify({ t: 'welcome', place: 2, host: true, credential: 'kept' }) });
            var big = pad.send({ chunk: new Array(\(Self.tooMany)).join('A') });
            var small = pad.send({ chunk: 'small' });
            """)
        XCTAssertNil(failure)
        XCTAssertEqual(context.evaluateScript("big")?.toBool(), false)
        XCTAssertEqual(context.evaluateScript("small")?.toBool(), true)
        XCTAssertEqual(context.evaluateScript("sent.filter(function (s) { return s.length > \(Self.limit); }).length")?.toInt32(), 0,
                       "nothing over the limit goes to Lamp")
        XCTAssertEqual(context.evaluateScript("sent.filter(function (s) { return JSON.parse(s).t === 'too-big'; }).length")?.toInt32(), 1,
                       "the TV app is told")
        XCTAssertTrue(context.evaluateScript("errors.join(' ')")?.toString().contains("at most \(Self.limit) bytes") == true)
    }

    /// A page that says it's ready as soon as it's given its number, on the welcome that says the TV app is there:
    /// that message goes, on the first link and after a reconnect (Roomote's review of 2f7b3ede).
    func testAMessageSentWhenThePhoneIsGivenItsNumberGoes() throws {
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, value in failure = value?.toString() }
        context.evaluateScript("""
            var window = this, sent = [], sockets = [], store = {}, later = [], results = [];
            var location = { hash: '#join', pathname: '/', search: '', protocol: 'http:', host: '192.168.1.20:47860', hostname: '192.168.1.20' };
            var history = { replaceState: function () { location.hash = ''; } };
            var sessionStorage = {
              getItem: function (k) { return store.hasOwnProperty(k) ? store[k] : null; },
              setItem: function (k, v) { store[k] = String(v); }, removeItem: function (k) { delete store[k]; }
            };
            function WebSocket(url) { this.readyState = 1; sockets.push(this); }
            WebSocket.prototype.send = function (text) { sent.push(text); };
            WebSocket.prototype.close = function () {};
            function fetch() { return Promise.resolve({ ok: true, json: function () { return { port: 47900, app: 'padgame' }; } }); }
            function setInterval() { return 0; } function clearInterval() {}
            function setTimeout(fn) { later.push(fn); return later.length; } function clearTimeout() {}
            """)
        context.evaluateScript(TVTemplate.phoneControllerJS)
        // The relay welcomes the phone, saying the TV app is there, and the TV app gives it its number.
        context.evaluateScript("""
            var pad = LampController.connect({ onPlayer: function (n) { results.push(pad.send({ ready: n })); } });
            var welcome = JSON.stringify({ t: 'welcome', place: 2, host: true, credential: 'kept' });
            var number = JSON.stringify({ t: 'player', number: 2 });
            """)
        context.evaluateScript("""
            sockets[0].onopen(); sockets[0].onmessage({ data: welcome }); sockets[0].onmessage({ data: number });
            sockets[0].onclose({ code: 1006 });   // the Wi-Fi dropped, and the page joins again
            later.shift()();
            """)
        context.evaluateScript("sockets[1].onopen(); sockets[1].onmessage({ data: welcome }); sockets[1].onmessage({ data: number });")
        XCTAssertNil(failure)
        XCTAssertEqual(context.evaluateScript("results.join(',')")?.toString(), "true,true")
        XCTAssertEqual(context.evaluateScript("sent.filter(function (s) { return JSON.parse(s).t === 'message'; }).length")?.toInt32(), 2)
    }

    func testTheTVPageRefusesAMessageOverTheLimitAndLogsAPhonesRefusedOne() throws {
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, value in failure = value?.toString() }
        context.evaluateScript("""
            var window = this, sent = [], errors = [], heardErrors = [], sockets = [], later = [];
            var console = { error: function (m) { errors.push(String(m)); }, log: function () {} };
            window.Lamp = {};
            var LampAI = { _post: function () {
              return Promise.resolve({ links: [{ kind: 'relay', socket: 'ws://127.0.0.1:47900/', app: 'padgame', credential: 'host' }] });
            } };
            function WebSocket(url) { this.readyState = 1; sockets.push(this); }
            WebSocket.prototype.send = function (text) { sent.push(text); };
            WebSocket.prototype.close = function () {};
            function setInterval() { return 0; } function clearInterval() {}
            function setTimeout(fn) { later.push(fn); return later.length; } function clearTimeout() {}
            """)
        context.evaluateScript(TVTemplate.controllersJS)
        context.evaluateScript("""
            Lamp.controllers.onError(function (m) { heardErrors.push(m); });
            Lamp.controllers.start();
            later.shift()();   // asks Lamp who the players are
            """)
        context.evaluateScript("""
            sockets[0].onopen();
            sockets[0].onmessage({ data: JSON.stringify({ t: 'welcome', role: 'host', players: [2], now: Date.now() }) });
            var big = Lamp.controllers.send(2, { chunk: new Array(\(Self.tooMany)).join('A') });
            var small = Lamp.controllers.send(2, { chunk: 'small' });
            sockets[0].onmessage({ data: JSON.stringify({ t: 'too-big', player: 2, bytes: 17000 }) });
            """)
        XCTAssertNil(failure)
        XCTAssertEqual(context.evaluateScript("big")?.toBool(), false)
        XCTAssertEqual(context.evaluateScript("small")?.toBool(), true)
        XCTAssertEqual(context.evaluateScript("sent.filter(function (s) { return JSON.parse(s).t === 'send'; }).length")?.toInt32(), 1,
                       "only the small one went")
        let errors = context.evaluateScript("errors.join('\\n')")?.toString() ?? ""
        XCTAssertTrue(errors.contains("A message of"), errors)
        XCTAssertTrue(errors.contains("Player 2's message of 17000 bytes was not sent: a message between devices is at most \(Self.limit) bytes"), errors)
        XCTAssertEqual(context.evaluateScript("heardErrors.length")?.toInt32(), 2)
    }
}
