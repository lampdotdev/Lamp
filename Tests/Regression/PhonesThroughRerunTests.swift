import WebKit
import XCTest
@testable import Lamp

/// A game's code run again in place keeps its phones: the session is the page's, and only what the game's code asked to
/// hear belongs to the run. The page is the real lamp-game.js and `Lamp.controllers` in WebKit, run again through
/// `window.__lampLive`, with a stand-in for the relay's socket so the test can be the two phones.
@MainActor
final class PhonesThroughRerunTests: XCTestCase {
    /// Serves the page's files, as the app around a page does.
    private final class Files: NSObject, WKURLSchemeHandler {
        var text: [String: String] = [:]
        func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
            let path = String(task.request.url!.path.dropFirst())
            let type = path.hasSuffix("html") ? "text/html" : "text/javascript"
            guard let body = text[path] else {
                task.didReceive(HTTPURLResponse(url: task.request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
                task.didFinish()
                return
            }
            task.didReceive(HTTPURLResponse(url: task.request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": type])!)
            task.didReceive(Data(body.utf8))
            task.didFinish()
        }
        func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
    }

    /// What says the page takes changes (`host()` in lamp-game.js), and tells when one went in.
    private final class Live: NSObject, WKScriptMessageHandler {
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {}
    }

    private static let page = """
        <!doctype html><html><head>
        <script>
        // The relay: a socket the test speaks for. Frames come from a timer, since a page in no window draws none.
        window.sockets = [];
        window.WebSocket = function (url) {
          var s = this; s.sent = []; s.readyState = 1; s.send = function (m) { s.sent.push(m); }; s.close = function () { s.readyState = 3; if (s.onclose) s.onclose({ code: 1000 }); };
          window.sockets.push(s);
          window.setTimeout(function () { s.onopen && s.onopen({}); }, 0);
        };
        window.fromRelay = function (m) { window.sockets[0].onmessage({ data: JSON.stringify(m) }); };
        // Stands in for what happens while a run about to start reads its page, after the snapshot is taken.
        var fetched = window.fetch;
        window.fetch = function (url, options) {
          if (String(url).indexOf('index.html') >= 0 && window.whileReading) { var then = window.whileReading; window.whileReading = null; then(); }
          return fetched.call(window, url, options);
        };
        window.requestAnimationFrame = function (fn) { return window.setTimeout(function () { fn(performance.now()); }, 16); };
        window.LampAI = { _post: function () { window.asks = (window.asks || 0) + 1; return Promise.resolve({ renew: 1, links: [{ kind: 'relay', socket: 'ws://relay.invalid/', app: 'duel', credential: 'host' }] }); } };
        </script>
        <script src="lamp.js"></script>
        </head><body></body><script type="module" src="game.js"></script></html>
        """

    /// The game each run: who it has, what it hears, and its slots as a snapshot keeps them.
    private static let game = """
        import { game, pendingRestore } from './lamp-game.js';
        const run = window.runs = (window.runs || 0) + 1;
        if (window.failsOnce || sessionStorage.failsOnce) { sessionStorage.failsOnce = sessionStorage.failsOnce ? '' : '1'; if (sessionStorage.failsOnce) throw new Error('broken'); }
        const heard = window.heard = window.heard || [];
        const renderer = { domElement: document.createElement('canvas'), setPixelRatio() {}, setSize() {}, render() {} };
        let slots = {};
        const say = line => heard.push(`run ${run}: ${line}`);
        await game({
          renderer, fill: true,
          snapshot: () => ({ slots }),
          dispose: () => { if (window.stopsInDispose) Lamp.controllers.stop(); },
          init: async () => {
            slots = (pendingRestore() || {}).slots || {};
            Lamp.controllers.onJoin(p => { if (!slots[p]) slots[p] = 'seat ' + (Object.keys(slots).length + 1); say(`join ${p} in ${slots[p]}`); });
            Lamp.controllers.onLeave(p => { delete slots[p]; say(`leave ${p}`); });
            Lamp.controllers.onButton((p, name, down) => say(`button ${p} ${name} ${down}`));
            Lamp.controllers.onLink(url => say(`link ${url}`));
            Lamp.controllers.start();
            await new Promise(r => window.setTimeout(r, 50));
            if (window.whileStarting) window.whileStarting();
          },
          frame() { window.drawn = run; }
        });
        """

    private var view: WKWebView!
    private var files: Files!
    private var live: Live!

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
        try await until("the first run has drawn") { try await self.number("window.failsOnce ? 0 : window.drawn || 0") == 1 }
        try await js("fromRelay({ t: 'welcome', players: [] }); fromRelay({ t: 'link', url: 'http://join/' });")
        try await js("fromRelay({ t: 'joined', player: 5 }); fromRelay({ t: 'joined', player: 2 });")
        try await until("two phones are in") { try await self.number("Lamp.controllers.players().length") == 2 }
    }

    private func value(_ code: String) async throws -> Any? { try await view.evaluateJavaScript(code, in: nil, contentWorld: .page) }
    private func js(_ code: String) async throws { _ = try await value(code + "; 0") }
    private func number(_ code: String) async throws -> Int { (try await value(code) as? NSNumber)?.intValue ?? 0 }
    private func heard() async throws -> [String] { try await value("window.heard") as? [String] ?? [] }

    private func until(_ what: String, seconds: Double = 8, _ done: () async throws -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if try await done() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Never: \(what)")
    }
    private func runAgain() async throws {
        let runs = try await number("window.runs")
        try await js("window.__lampLive({ changed: ['game.js'], gen: \(runs), now: true, why: 'test' })")
        try await until("the new run has drawn") { try await self.number("window.drawn") == runs + 1 }
    }

    func testPhonesStayJoinedAndTheNewRunIsToldWhoIsHere() async throws {
        try await open()
        try await js("window.stopsInDispose = true; fromRelay({ t: 'button', player: 5, name: 'a', down: true, seq: 1 });")
        try await runAgain()
        let links = try await number("window.sockets.length")
        XCTAssertEqual(links, 1, "the session was never started again")
        let open = try await number("window.sockets[0].readyState")
        XCTAssertEqual(open, 1)
        let joined = try await number("Lamp.controllers.players().length")
        XCTAssertEqual(joined, 2)
        let held = try await number("Lamp.controllers.isHeld(5, 'a') ? 1 : 0")
        XCTAssertEqual(held, 1, "what's held stays held")

        let second = try await heard().filter { $0.hasPrefix("run 2:") }
        XCTAssertEqual(second, ["run 2: link http://join/", "run 2: join 2 in seat 2", "run 2: join 5 in seat 1"],
                       "the slots come back from the snapshot, and the old press isn't sent again")

        // Input reaches the new run alone.
        try await js("fromRelay({ t: 'button', player: 2, name: 'a', down: true, seq: 1 });")
        let last = try await heard().filter { $0.contains("button 2") }
        XCTAssertEqual(last, ["run 2: button 2 a true"])
    }

    func testTheSessionsTimersOutliveTheRun() async throws {
        try await open()
        try await runAgain()
        let asked = try await number("window.asks")
        let beats = "window.sockets[0].sent.filter(function (m) { return m === '{\"t\":\"beat\"}'; }).length"
        let before = try await number(beats)
        // A beat is every 5 s and the renewal here every second, so both come within this if they're still running.
        try await until("the beat and the renewal go on", seconds: 7) {
            let beat = try await self.number(beats), ask = try await self.number("window.asks")
            return beat > before && ask > asked
        }
    }

    func testARunThatFailsOpensThePageAndThePhonesComeBackToTheirSlots() async throws {
        try await open()
        try await js("window.failsOnce = true; window.__lampLive({ changed: ['game.js'], gen: 1, now: true, why: 'test' })")
        try await until("the page opened again and drew") { try await self.number("window.failsOnce ? 0 : window.drawn || 0") == 1 }
        try await js("fromRelay({ t: 'welcome', players: [2, 5] });")
        let back = try await heard().filter { $0.contains(": join") }
        XCTAssertEqual(back, ["run 1: join 2 in seat 2", "run 1: join 5 in seat 1"])
    }

    func testAFileThatStartsWhileTheNewRunStartsIsTurnedDown() async throws {
        try await open()
        let refused = "window.sockets[0].sent.filter(function (m) { return JSON.parse(m).t === 'file-refuse'; }).length"
        try await js("window.whileStarting = function () { fromRelay({ t: 'file', player: 5, id: 1, name: 'late.txt', type: 'text/plain', size: 4 }); };")
        try await runAgain()
        let during = try await number(refused)
        XCTAssertEqual(during, 1, "the phone is told, rather than sending all of it for nobody")
        try await js("fromRelay({ t: 'file', player: 5, id: 2, name: 'fine.txt', type: 'text/plain', size: 4 });")
        let after = try await number(refused)
        XCTAssertEqual(after, 1, "a file from the running game's time isn't turned down")
    }

    func testAPlayerWhoLeavesAfterTheSnapshotIsToldToTheNewRun() async throws {
        try await open()
        try await js("window.whileReading = function () { fromRelay({ t: 'left', player: 2 }); };")
        try await runAgain()
        let second = try await heard().filter { $0.hasPrefix("run 2:") }
        XCTAssertEqual(second, ["run 2: link http://join/", "run 2: leave 2", "run 2: join 5 in seat 1"],
                       "the snapshot still has their seat, so the new run has to hear they've gone")
    }

    func testWhatHappensWhileTheNewRunStartsIsToldAsItIsThen() async throws {
        try await open()
        try await js("""
            window.whileStarting = function () {
              fromRelay({ t: 'left', player: 2 });
              fromRelay({ t: 'joined', player: 7 });
              fromRelay({ t: 'button', player: 5, name: 'b', down: true, seq: 1 });
              fromRelay({ t: 'message', player: 5, data: { old: true } });
            };
            """)
        try await runAgain()
        let second = try await heard().filter { $0.hasPrefix("run 2:") }
        XCTAssertEqual(second, ["run 2: link http://join/", "run 2: leave 2", "run 2: join 5 in seat 1", "run 2: join 7 in seat 2"])
        let held = try await number("Lamp.controllers.isHeld(5, 'b') ? 1 : 0")
        XCTAssertEqual(held, 1)
    }
}
