import WebKit
import XCTest
@testable import Lamp

/// lamp-game.js wraps `addEventListener` and `removeEventListener` to follow what the game's code leaves running. A call
/// written without `window.` reaches the wrapper with no receiver, as it reaches the browser's own function, and has to
/// mean what it means there. The page is the real lamp-game.js in WebKit, run again through `window.__lampLive`.
@MainActor
final class GameListenerReceiverTests: XCTestCase {
    /// Serves the page's files, as the app around a page does.
    private final class Files: NSObject, WKURLSchemeHandler {
        var text: [String: String] = [:]
        func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
            let path = String(task.request.url!.path.dropFirst())
            guard let body = text[path] else {
                task.didReceive(HTTPURLResponse(url: task.request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
                task.didFinish()
                return
            }
            let type = path.hasSuffix("html") ? "text/html" : "text/javascript"
            task.didReceive(HTTPURLResponse(url: task.request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": type])!)
            task.didReceive(Data(body.utf8))
            task.didFinish()
        }
        func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
    }

    /// What says the page takes changes (`host()` in lamp-game.js), which has the runtime watch listeners.
    private final class Live: NSObject, WKScriptMessageHandler {
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {}
    }

    private static let page = """
        <!doctype html><html><head>
        <script>
        // The browser's own functions, from before the runtime wraps them. Frames come from a timer, since a page in no
        // window draws none.
        window.native = { add: EventTarget.prototype.addEventListener, remove: EventTarget.prototype.removeEventListener };
        window.requestAnimationFrame = function (fn) { return window.setTimeout(function () { fn(performance.now()); }, 16); };
        window.tried = function (add, remove, receiver) {
          var heard = 0, hear = function () { heard++; }, threw = null;
          try { add.call(receiver, 'tried', hear); } catch (e) { threw = e.name; }
          window.dispatchEvent(new Event('tried'));
          var held = heard;
          try { remove.call(receiver, 'tried', hear); } catch (e) {}
          window.dispatchEvent(new Event('tried'));
          native.remove.call(window, 'tried', hear);
          return JSON.stringify({ threw: threw, heard: held, heardAfterRemove: heard - held });
        };
        window.fire = function (name) { window.dispatchEvent(new Event(name)); };
        </script>
        </head><body></body><script type="module" src="game.js"></script></html>
        """

    /// Every run listens with bare calls. What the first run adds and takes away again goes before the kept part listens
    /// with that same function, so a removal the runtime missed would have the part's listener taken away on the next run.
    private static let game = """
        import { game } from './lamp-game.js';
        import { keepListening } from './part.js';
        const run = window.runs = (window.runs || 0) + 1;
        const heard = window.heard = window.heard || [];
        const shared = window.shared = window.shared || (() => heard.push('shared'));
        const renderer = { domElement: document.createElement('canvas'), setPixelRatio() {}, setSize() {}, render() {} };
        await game({
          renderer, fill: true,
          init() {
            addEventListener('ping', () => heard.push(`run ${run}`));
            if (run === 1) { addEventListener('shared', shared); removeEventListener('shared', shared); }
            keepListening();
          },
          frame() { window.drawn = run; }
        });
        """

    /// In a module of its own, so a change of game.js leaves the part kept.
    private static let part = """
        import { hot } from './lamp-game.js';
        export function keepListening() {
          hot(import.meta).keep('listener', () => {
            window.builds = (window.builds || 0) + 1;
            addEventListener('ping', () => window.heard.push('kept'));
            addEventListener('shared', window.shared);
            return {};
          });
        }
        """

    private var view: WKWebView!
    private var files: Files!
    private var live: Live!

    private func open() async throws {
        files = Files()
        live = Live()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/GameKit/web/lamp-game.js")
        let mac = try XCTUnwrap(Places.builtIn.first { $0.id == "mac" })
        files.text = ["index.html": Self.page, "game.js": Self.game, "part.js": Self.part, "lamp-game.js": try String(contentsOf: root, encoding: .utf8),
                      "lamp-device.js": try GamePage.descriptor(for: mac), "lamp-controllers.js": Controllers.pageJS,
                      "lamp-build.js": "export default 'test';"]
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(files, forURLScheme: "lamp-test")
        configuration.userContentController.add(live, contentWorld: .page, name: "lampLive")
        view = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 180), configuration: configuration)
        view.load(URLRequest(url: URL(string: "lamp-test://game/index.html")!))
        try await until("the game has drawn") { try await self.number("window.drawn || 0") == 1 }
    }

    private func value(_ code: String) async throws -> Any? { try await view.evaluateJavaScript(code, in: nil, contentWorld: .page) }
    private func js(_ code: String) async throws { _ = try await value(code + "; 0") }
    private func number(_ code: String) async throws -> Int { (try await value(code) as? NSNumber)?.intValue ?? 0 }
    private func heard(after event: String) async throws -> [String] {
        try await js("window.heard.length = 0; fire('\(event)')")
        return try await value("window.heard") as? [String] ?? []
    }

    private func until(_ what: String, seconds: Double = 8, _ done: () async throws -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if try await done() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Never: \(what)")
        throw CancellationError()
    }

    func testTheWrappersTakeTheReceiversTheBrowsersFunctionsTake() async throws {
        try await open()
        for (name, receiver) in [("nothing", "undefined"), ("null", "null"), ("a number", "0"), ("a string", "'x'"), ("an object", "({})")] {
            let wrapped = try await value("tried(EventTarget.prototype.addEventListener, EventTarget.prototype.removeEventListener, \(receiver))") as? String
            let own = try await value("tried(native.add, native.remove, \(receiver))") as? String
            XCTAssertEqual(wrapped, own, "called on \(name)")
            let listens = name == "nothing" || name == "null"
            XCTAssertEqual(own, listens ? #"{"threw":null,"heard":1,"heardAfterRemove":0}"# : #"{"threw":"TypeError","heard":0,"heardAfterRemove":0}"#, "called on \(name)")
        }
    }

    func testRunningAgainTakesABareListenerAwayAndKeepsAKeptOne() async throws {
        try await open()
        let first = try await heard(after: "ping")
        XCTAssertEqual(first.sorted(), ["kept", "run 1"])

        try await js("window.__lampLive({ changed: ['game.js'], gen: 1, now: true, why: 'test' })")
        try await until("the new run has drawn") { try await self.number("window.drawn") == 2 }

        let second = try await heard(after: "ping")
        XCTAssertEqual(second.sorted(), ["kept", "run 2"], "the old run's listener is gone and the part's stays")
        let builds = try await number("window.builds")
        XCTAssertEqual(builds, 1, "the part was kept, not built again")
        let shared = try await heard(after: "shared")
        XCTAssertEqual(shared, ["shared"], "a bare remove is followed like any other, so it can't take the part's listener with it")
    }
}
