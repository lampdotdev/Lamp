import WebKit
import XCTest
@testable import Lamp

/// A phone's buttons as a frame reads them (`f.phones`). The page is the real lamp-game.js and `Lamp.controllers` in
/// WebKit, with a stand-in for the relay's socket and frames the test steps by hand, so what arrives between two frames
/// is exact.
@MainActor
final class PhoneFrameInputTests: XCTestCase {
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

    /// What says the page takes changes (`host()` in lamp-game.js), so its code can run again.
    private final class Live: NSObject, WKScriptMessageHandler {
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {}
    }

    private static let page = """
        <!doctype html><html><head>
        <script>
        window.sockets = [];
        window.WebSocket = function (url) {
          var s = this; s.sent = []; s.readyState = 1; s.send = function (m) { s.sent.push(m); }; s.close = function () { s.readyState = 3; };
          window.sockets.push(s);
          window.setTimeout(function () { s.onopen && s.onopen({}); }, 0);
        };
        window.fromRelay = function (m) { window.sockets[0].onmessage({ data: JSON.stringify(m) }); };
        // Frames go only when the test says.
        window.frames = [];
        window.requestAnimationFrame = function (fn) { window.frames.push(fn); return window.frames.length; };
        window.tick = function () { var now = window.frames.splice(0); now.forEach(function (fn) { fn(performance.now()); }); return now.length; };
        window.LampAI = { _post: function () { return Promise.resolve({ renew: 600, links: [{ kind: 'relay', socket: 'ws://relay.invalid/', app: 'duel', credential: 'host' }] }); } };
        </script>
        <script src="lamp.js"></script>
        </head><body></body><script type="module" src="game.js"></script></html>
        """

    /// Each frame's `f.phones` as text, and what `onButton` heard.
    private static let game = """
        import { game } from './lamp-game.js';
        const run = window.runs = (window.runs || 0) + 1;
        const seen = window.seen = window.seen || [];
        const heard = window.heard = window.heard || [];
        const names = o => Object.keys(o).sort().join(',');
        const renderer = { domElement: document.createElement('canvas'), setPixelRatio() {}, setSize() {}, render() {} };
        await game({
          renderer, fill: true,
          init() {
            Lamp.controllers.onButton((p, name, down) => heard.push(`${p} ${name} ${down}`));
            Lamp.controllers.start();
            if (window.whileStarting) window.whileStarting();
          },
          frame(f) {
            window.drawn = run;
            seen.push(`run ${run}: ` + f.phones.map(p => `${p.player} down[${names(p.down)}] pressed[${names(p.pressed)}] released[${names(p.released)}]`).join(' | '));
          }
        });
        """

    private var view: WKWebView!
    private var files: Files!
    private var live: Live!
    private var sequence = 0

    private func open() async throws {
        files = Files()
        live = Live()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/GameKit/web/lamp-game.js")
        let mac = try XCTUnwrap(Places.builtIn.first { $0.id == "mac" })
        files.text = ["index.html": Self.page, "game.js": Self.game, "lamp.js": GameKit.controllersJS,
                      "lamp-game.js": try String(contentsOf: root, encoding: .utf8),
                      "lamp-device.js": try GamePage.descriptor(for: mac), "lamp-controllers.js": Controllers.pageJS,
                      "lamp-build.js": "export default 'test';"]
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(files, forURLScheme: "lamp-test")
        configuration.userContentController.add(live, contentWorld: .page, name: "lampLive")
        view = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 180), configuration: configuration)
        view.load(URLRequest(url: URL(string: "lamp-test://game/index.html")!))
        try await until("the first frame") { _ = try await self.number("window.tick ? tick() : 0"); return try await self.number("window.drawn || 0") == 1 }
        try await until("the relay's link") { try await self.number("window.sockets.length") == 1 }
        try await js("fromRelay({ t: 'welcome', players: [] }); fromRelay({ t: 'joined', player: 1 }); fromRelay({ t: 'joined', player: 2 });")
        try await until("two phones are in") { try await self.number("Lamp.controllers.players().length") == 2 }
    }

    private func value(_ code: String) async throws -> Any? { try await view.evaluateJavaScript(code, in: nil, contentWorld: .page) }
    private func js(_ code: String) async throws { _ = try await value(code + "; 0") }
    private func number(_ code: String) async throws -> Int { (try await value(code) as? NSNumber)?.intValue ?? 0 }
    private func press(_ player: Int, _ name: String = "a", down: Bool) async throws {
        sequence += 1
        try await js("fromRelay({ t: 'button', player: \(player), name: '\(name)', down: \(down), seq: \(sequence) })")
    }
    /// What the next frame reads.
    private func frame() async throws -> String {
        _ = try await number("window.seen.length = 0; tick()")
        return (try await value("window.seen.join('\\n')")) as? String ?? ""
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

    func testAPressAndReleaseBetweenTwoFramesIsAPress() async throws {
        try await open()
        try await press(1, down: true)
        try await press(1, down: false)
        let next = try await frame()
        XCTAssertEqual(next, "run 1: 1 down[] pressed[a] released[a] | 2 down[] pressed[] released[]")
        let after = try await frame()
        XCTAssertEqual(after, "run 1: 1 down[] pressed[] released[] | 2 down[] pressed[] released[]", "an edge lasts one frame")
    }

    func testAHeldButtonIsDownUntilItsLetGoAndOnButtonGoesOnAsItWas() async throws {
        try await open()
        try await press(2, "x", down: true)
        var next = try await frame()
        XCTAssertEqual(next, "run 1: 1 down[] pressed[] released[] | 2 down[x] pressed[x] released[]")
        next = try await frame()
        XCTAssertEqual(next, "run 1: 1 down[] pressed[] released[] | 2 down[x] pressed[] released[]")
        try await press(2, "x", down: false)
        next = try await frame()
        XCTAssertEqual(next, "run 1: 1 down[] pressed[] released[] | 2 down[] pressed[] released[x]")
        let heard = try await value("window.heard") as? [String]
        XCTAssertEqual(heard, ["2 x true", "2 x false"])
    }

    func testAPhoneThatLeavesTakesWhatItDidWithIt() async throws {
        try await open()
        try await press(1, down: true)
        try await js("fromRelay({ t: 'left', player: 1 })")
        try await until("the phone has gone") { try await self.number("Lamp.controllers.players().length") == 1 }
        let next = try await frame()
        XCTAssertEqual(next, "run 1: 2 down[] pressed[] released[]")
        // Back with the number it had, before any frame: nothing from its last time is read as new.
        try await press(2, down: true)
        try await js("fromRelay({ t: 'left', player: 2 })")
        try await js("fromRelay({ t: 'joined', player: 2 })")
        try await until("the second phone is back") { try await self.number("Lamp.controllers.isHeld(2, 'a') ? 0 : Lamp.controllers.players().length") == 1 }
        let back = try await frame()
        XCTAssertEqual(back, "run 1: 2 down[] pressed[] released[]")
    }

    func testRunningAgainKeepsWhatsHeldAndDropsEveryEdge() async throws {
        try await open()
        try await press(1, "x", down: true)
        _ = try await frame()
        // Not yet read as the code starts to run again: a press the old run never took.
        try await press(2, "x", down: true)
        // While the new run starts: a press and a release, neither replayed, though what's held follows them.
        sequence += 2
        try await js("""
            window.whileStarting = function () {
              fromRelay({ t: 'button', player: 2, name: 'y', down: true, seq: \(sequence - 1) });
              fromRelay({ t: 'button', player: 1, name: 'x', down: false, seq: \(sequence) });
            };
            window.seen.length = 0;
            window.__lampLive({ changed: ['game.js'], gen: 1, now: true, why: 'test' })
            """)
        // No frame until the old run has stopped (it gives up on a last picture after a quarter of a second), so the
        // press it never took is still waiting.
        try await Task.sleep(nanoseconds: 500_000_000)
        try await until("the new run has drawn") { _ = try await self.number("tick()"); return try await self.number("window.drawn") == 2 }
        let first = try await value("window.seen.filter(function (s) { return s.indexOf('run 2') === 0; })[0]") as? String
        XCTAssertEqual(first, "run 2: 1 down[] pressed[] released[] | 2 down[x,y] pressed[] released[]")

        try await press(1, "x", down: true)
        let next = try await frame()
        XCTAssertEqual(next, "run 2: 1 down[x] pressed[x] released[] | 2 down[x,y] pressed[] released[]", "input goes on as the new run plays")
    }
}
