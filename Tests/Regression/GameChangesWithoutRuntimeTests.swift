import WebKit
import XCTest
@testable import Lamp

/// A web game's page that doesn't run on Lamp's game runtime takes a change while it's played where that's safe, and
/// holds the rest for Reload (lamp-live.js). The page is the real script in WebKit, given to the page before its own
/// scripts as `LampPageView.make` gives it, and changed through `window.__lampLive` as the app around the page does it.
@MainActor
final class GameChangesWithoutRuntimeTests: XCTestCase {
    private final class Files: NSObject, WKURLSchemeHandler {
        var text: [String: String] = [:]
        var asked: Set<String> = []
        /// Files answered only after this many seconds, for what happens while one is on its way.
        var slow: [String: Double] = [:]
        func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
            let path = String(task.request.url!.path.dropFirst())
            asked.insert(path)
            if let seconds = slow[path] {
                let body = text[path]
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                    task.didReceive(HTTPURLResponse(url: task.request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/javascript"])!)
                    task.didReceive(Data((body ?? "").utf8))
                    task.didFinish()
                }
                return
            }
            let type = path.hasSuffix("html") ? "text/html" : path.hasSuffix("css") ? "text/css" : path.hasSuffix("json") ? "application/json" : "text/javascript"
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

    private final class Live: NSObject, WKScriptMessageHandler {
        var told: [[String: Any]] = []
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any] { told.append(body) }
        }
    }

    private static func page(head: String = "") -> String {
        """
        <!doctype html><html><head>\(head)<link rel="stylesheet" href="style.css"></head>
        <body><script type="module" src="main.js"></script></body></html>
        """
    }

    private static let main = """
        import { Ball } from './ball.js';
        window.mainRuns = (window.mainRuns || 0) + 1;
        window.ball = new Ball();
        window.ball.x = 5;
        """

    /// The ball as the game started; `step` and `bump` as given.
    private static func ball(step: String = "this.x = clamp(this.x + SPEED, 0, 100); return this.x;", bump: String = "hits++; return hits;",
                             constructor: String = "this.x = 0;", extra: String = "") -> String {
        """
        import { clamp } from './util.js';
        const SPEED = 2;
        let hits = 0;
        window.ballRuns = (window.ballRuns || 0) + 1;
        export class Ball {
            constructor() { \(constructor) }
            step() { \(step) }
            bump() { \(bump) }
            \(extra)
        }
        """
    }

    private var files: Files!
    private var live: Live!
    private var view: WKWebView!

    private func open(head: String = "", main: String = GameChangesWithoutRuntimeTests.main, also: [String: String] = [:],
                      atStart: String? = nil, waitFor: String = "window.ball && window.ball.x === 5") async throws {
        files = Files()
        live = Live()
        files.text = ["index.html": Self.page(head: head), "main.js": main, "ball.js": Self.ball(), "style.css": "body { color: rgb(1, 2, 3); }",
                      "util.js": "export const clamp = (v, a, b) => Math.min(b, Math.max(a, v));"]
        files.text.merge(also) { $1 }
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(files, forURLScheme: "lamp-test")
        configuration.userContentController.add(live, contentWorld: .page, name: "lampLive")
        // What Lamp writes into the app around a game's page (`LampPageLive.gameScript`), and gives the page first.
        let script = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/GameKit/page/lamp-live.js"), encoding: .utf8)
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        if let atStart {
            configuration.userContentController.addUserScript(WKUserScript(source: atStart, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        }
        view = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 180), configuration: configuration)
        view.load(URLRequest(url: URL(string: "lamp-test://game/index.html")!))
        try await until("the game has started") { try await self.value("!!(\(waitFor))") as? Bool == true }
    }

    private func value(_ code: String) async throws -> Any? { try await view.evaluateJavaScript(code, in: nil, contentWorld: .page) }
    private func number(_ code: String) async throws -> Double { (try await value(code) as? NSNumber)?.doubleValue ?? -1 }

    private func until(_ what: String, seconds: Double = 8, _ done: () async throws -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if try await done() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Never: \(what)")
    }

    /// Hands the page a change of these files, as the app around it does, and waits for what it says of it.
    @discardableResult
    private func change(_ gen: Int, _ changed: [String] = [], removed: [String] = []) async throws -> [String: Any] {
        // With every file the page asked for, as the app around it says (`LampPageFiles.asked`).
        let json = String(decoding: try JSONSerialization.data(withJSONObject: ["gen": gen, "changed": changed, "removed": removed, "now": false, "pill": false,
                                                                                "read": files.asked.sorted()]), as: UTF8.self)
        let taken = try await value("window.__lampLive(\(json))") as? Bool
        XCTAssertEqual(taken, true)
        var said: [String: Any] = [:]
        try await until("the page says how change \(gen) went") {
            guard let last = self.live.told.last(where: { $0["gen"] as? Int == gen && ($0["pause"] as? Bool) != true }) else { return false }
            said = last
            return true
        }
        return said
    }

    private func ready() async throws {
        // The sources are read, and the page loaded: a first change can be put in.
        try await until("the page has loaded") { try await self.value("document.readyState") as? String == "complete" }
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    func testAChangedMethodGoesIntoTheRunningGameWithItsObjectsKept() async throws {
        try await open()
        try await ready()
        files.text["ball.js"] = Self.ball(step: "this.x = clamp(this.x + SPEED * 10, 0, 100); return this.x;")
        let said = try await change(1, ["ball.js"])
        XCTAssertEqual(said["state"] as? String, "swapped", "\(said)")
        // The ball the game made, with its x of 5, runs the new step, which reads the module's import and constant.
        let got1 = try await number("ball.step()")
        XCTAssertEqual(got1, 25)
        // Nothing of the game ran again.
        let got2 = try await number("window.ballRuns")
        XCTAssertEqual(got2, 1)
        let got3 = try await number("window.mainRuns")
        XCTAssertEqual(got3, 1)
        // And a second change of the same method goes in after the first.
        files.text["ball.js"] = Self.ball(step: "this.x = clamp(this.x + 1, 0, 100); return -this.x;")
        let got4 = try await change(2, ["ball.js"])["state"] as? String
        XCTAssertEqual(got4, "swapped")
        let got5 = try await number("ball.step()")
        XCTAssertEqual(got5, -26)
    }

    func testAMethodWithAColorWrittenWithAHashGoesIn() async throws {
        // A color in a string is no private member: `#ffffff` is drawn with, not read off the object.
        try await open()
        try await ready()
        files.text["ball.js"] = Self.ball(step: "const color = '#ffffff'; return color + this.x;")
        let said = try await change(1, ["ball.js"])
        XCTAssertEqual(said["state"] as? String, "swapped", "\(said)")
        let got = try await value("ball.step()") as? String
        XCTAssertEqual(got, "#ffffff5")
    }

    func testAWordThatIsAKeywordOnlySomewhereIsANameWhereItStandsAsOne() async throws {
        try await open()
        try await ready()
        // Where they are keywords, the method goes in and runs.
        files.text["ball.js"] = Self.ball(step: "let total = 0; for (const v of [1, 2]) total += v; const f = async () => total; return total + this.x;")
        let said = try await change(1, ["ball.js"])
        XCTAssertEqual(said["state"] as? String, "swapped", "\(said)")
        let got = try await number("ball.step()")
        XCTAssertEqual(got, 8)
        // Each is a name here, declared nowhere: the new method would fail as it ran, so it waits.
        var gen = 1
        for (code, word) in [("return target + this.x;", "target"), ("const t = get; return t;", "get"), ("return of;", "of"),
                             ("return async;", "async"), ("return meta;", "meta"), ("const s = set\n(1); return s;", "set")] {
            gen += 1
            files.text["ball.js"] = Self.ball(step: code)
            let said = try await change(gen, ["ball.js"])
            XCTAssertEqual(said["state"] as? String, "held", "\(code): \(said)")
            XCTAssertTrue((said["why"] as? String ?? "").contains(word), "\(code): \(said)")
        }
        // None of them went in: the method is the one before.
        let still = try await number("ball.step()")
        XCTAssertEqual(still, 8)
    }

    func testAGlobalsNameTheModuleDeclaresIsTheModules() async throws {
        // A module may declare Infinity, NaN or undefined for itself: the new method reads the module's.
        let constant = Self.ball().replacingOccurrences(of: "const SPEED = 2;", with: "const SPEED = 2;\nconst Infinity = 7;")
        try await open(also: ["ball.js": constant])
        try await ready()
        files.text["ball.js"] = constant.replacingOccurrences(of: "this.x = clamp(this.x + SPEED, 0, 100); return this.x;", with: "return Infinity;")
        let first = try await change(1, ["ball.js"])
        XCTAssertEqual(first["state"] as? String, "swapped", "\(first)")
        let got = try await number("ball.step()")
        XCTAssertEqual(got, 7)
        // One it may change as it runs is its own state: that waits.
        let variable = Self.ball().replacingOccurrences(of: "let hits = 0;", with: "let hits = 0;\nlet NaN = 3;")
        files.text["ball.js"] = variable.replacingOccurrences(of: "this.x = clamp(this.x + SPEED, 0, 100); return this.x;", with: "return NaN;")
        let said = try await change(2, ["ball.js"])
        XCTAssertEqual(said["state"] as? String, "held", "\(said)")
    }

    func testAMethodThatImportsWaits() async throws {
        try await open()
        try await ready()
        files.text["ball.js"] = Self.ball(step: "return import('./util.js').then(m => m.clamp(this.x, 0, 1));")
        let said = try await change(1, ["ball.js"])
        XCTAssertEqual(said["state"] as? String, "held", "\(said)")
        XCTAssertTrue((said["why"] as? String ?? "").contains("import()"), "\(said)")
    }

    func testAComputedKeyIsNotWorkedOutAgain() async throws {
        let spin = Self.ball(extra: "[(window.keyRuns = (window.keyRuns || 0) + 1, 'spin')]() { return 1; }")
        try await open(also: ["ball.js": spin])
        try await ready()
        files.text["ball.js"] = spin.replacingOccurrences(of: "'spin')]() { return 1; }", with: "'spin')]() { return 2; }")
        let said = try await change(1, ["ball.js"])
        XCTAssertEqual(said["state"] as? String, "swapped", "\(said)")
        let spun = try await number("ball.spin()"), runs = try await number("window.keyRuns"), name = try await value("ball.spin.name") as? String
        XCTAssertEqual(spun, 2)
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(name, "spin")
    }

    func testReloadGoesInAtOnceWhileTheGameIsStarting() async throws {
        try await open(head: "<script>lampLive.waitForReady(); window.opens = 1 + Number(sessionStorage.opens || 0); sessionStorage.opens = window.opens;</script>")
        try await ready()
        _ = try await value(#"window.__lampLive({ gen: 1, changed: ['ball.js'], removed: [], now: false })"#)
        try await until("the change waits for the game") { self.live.told.contains { $0["gen"] as? Int == 1 && $0["pause"] as? Bool == true } }
        _ = try await value(#"window.__lampLive({ gen: 2, changed: [], removed: [], now: true })"#)
        try await until("the page opens again for Reload") { self.live.told.contains { $0["gen"] as? Int == 2 && $0["state"] as? String == "reloading" } }
        try await until("the page opened again") { try await self.number("window.opens || 0") == 2 }
    }

    func testTheRuntimeIsHandedAChangeBeingPutIn() async throws {
        try await open()
        try await ready()
        files.text["ball.js"] = Self.ball(step: "return 99;")
        files.slow["ball.js"] = 1
        _ = try await value(#"window.__lampLive({ gen: 7, changed: ['ball.js'], removed: [], now: false })"#)
        try await Task.sleep(nanoseconds: 300_000_000)
        // The runtime arrives while the change's file is still on its way.
        _ = try await value("window.got = []; window.__lampLive = change => { window.got.push(change.gen); return true; }; 0")
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let got = try await value("window.got") as? [Int]
        XCTAssertEqual(got, [7])
        XCTAssertFalse(live.told.contains { $0["gen"] as? Int == 7 && ["swapped", "held"].contains($0["state"] as? String) && $0["pause"] == nil }, "\(live.told)")
        let step = try await number("ball.step()")
        XCTAssertEqual(step, 7, "the helper put it in after the runtime took over")
    }

    func testWhatCouldRunTheModuleAgainOrReachItsStateWaitsForReload() async throws {
        try await open()
        try await ready()
        let cases: [(String, String, String)] = [
            ("its module's own state", Self.ball(bump: "hits += 2; return hits;"), "hits"),
            ("the constructor", Self.ball(constructor: "this.x = 1;"), "outside the body of one method"),
            ("a new method", Self.ball(extra: "jump() { return 1; }"), "outside the body of one method"),
            ("code outside the class", Self.ball().replacingOccurrences(of: "const SPEED = 2;", with: "const SPEED = 3;"), "outside the body of one method"),
            ("a private member", Self.ball(step: "return this.#x;", extra: "#x = 1;"), "outside the body of one method"),
            ("super", Self.ball(step: "return super.toString();"), "super"),
            ("a name nothing declares", Self.ball(step: "return missingThing;"), "missingThing"),
        ]
        var gen = 0
        for (what, text, why) in cases {
            gen += 1
            files.text["ball.js"] = text
            let said = try await change(gen, ["ball.js"])
            XCTAssertEqual(said["state"] as? String, "held", "\(what): \(said)")
            XCTAssertTrue((said["why"] as? String ?? "").contains(why), "\(what): \(said)")
        }
        // The game runs on as it was: its module never ran again, and its methods are the old ones.
        let got6 = try await number("window.ballRuns")
        XCTAssertEqual(got6, 1)
        let got7 = try await number("ball.step()")
        XCTAssertEqual(got7, 7)
        let got8 = try await number("ball.bump()")
        XCTAssertEqual(got8, 1)
    }

    func testAPrivateMemberInTheChangedMethodWaits() async throws {
        let withPrivate = Self.ball(step: "return this.x;", extra: "#secret = 4; reveal() { return this.#secret; }")
        try await open(also: ["ball.js": withPrivate])
        try await ready()
        files.text["ball.js"] = withPrivate.replacingOccurrences(of: "return this.#secret;", with: "return this.#secret + 1;")
        let said = try await change(1, ["ball.js"])
        XCTAssertEqual(said["state"] as? String, "held", "\(said)")
        XCTAssertTrue((said["why"] as? String ?? "").contains("private"), "\(said)")
        let got9 = try await number("ball.reveal()")
        XCTAssertEqual(got9, 4)
    }

    func testAStylesheetGoesInAndAFileNothingUsesIsNoPartOfTheChange() async throws {
        try await open()
        try await ready()
        files.text["style.css"] = "body { color: rgb(9, 8, 7); }"
        files.text["notes.txt"] = "made up"
        let said = try await change(1, ["style.css", "notes.txt"])
        XCTAssertEqual(said["state"] as? String, "swapped", "\(said)")
        try await until("the new stylesheet is in") { try await self.value("getComputedStyle(document.body).color") as? String == "rgb(9, 8, 7)" }
        let got10 = try await number("window.ballRuns")
        XCTAssertEqual(got10, 1)
    }

    func testAFileTheGameReadWaitsEvenWhenNothingNamesIt() async throws {
        // The game reads its level by a name it puts together, so only what the page fetched says it's in use.
        let main = Self.main + "\nfetch('lev' + 'el.json').then(r => r.json()).then(l => { window.level = l.n; });"
        try await open(main: main, also: ["level.json": "{\"n\": 1}"], waitFor: "window.level === 1")
        try await ready()
        files.text["level.json"] = "{\"n\": 2}"
        let said = try await change(1, ["level.json"])
        XCTAssertEqual(said["state"] as? String, "held", "\(said)")
        XCTAssertTrue((said["why"] as? String ?? "").contains("level.json"), "\(said)")
    }

    func testAChangeWaitsUntilTheGameSaysItIsReady() async throws {
        try await open(head: "<script>lampLive.waitForReady();</script>")
        try await ready()
        files.text["ball.js"] = Self.ball(step: "return 99;")
        let json = #"{"gen": 1, "changed": ["ball.js"], "removed": [], "now": false}"#
        _ = try await value("window.__lampLive(\(json))")
        try await until("the page says it waits for the game") { self.live.told.contains { $0["gen"] as? Int == 1 && $0["pause"] as? Bool == true } }
        try await Task.sleep(nanoseconds: 300_000_000)
        let got11 = try await number("ball.step()")
        XCTAssertEqual(got11, 7, "put in before the game said it was ready")
        _ = try await value("lampLive.ready(); 0")
        try await until("the change goes in once the game is ready") { self.live.told.contains { $0["gen"] as? Int == 1 && $0["state"] as? String == "swapped" } }
        let got12 = try await number("ball.step()")
        XCTAssertEqual(got12, 99)
    }

    func testAPageThatStoppedWithAnErrorAsItStartedOpensAgain() async throws {
        let main = "window.opens = 1 + Number(sessionStorage.opens || 0); sessionStorage.opens = window.opens;\nwindow.ball = { x: 5 };\nthrow new Error('made-up failure');"
        try await open(main: main)
        try await ready()
        files.text["ball.js"] = Self.ball(step: "return 99;")
        let said = try await change(1, ["ball.js"])
        XCTAssertEqual(said["state"] as? String, "reloading", "\(said)")
        try await until("the page opened again") { try await self.number("window.opens || 0") == 2 }
    }

    func testAModuleChangedBeforeItsSourceWasReadWaits() async throws {
        // Handed over as the page opens, before what it runs could be read: the file read later is the new one.
        let atStart = #"window.__lampLive({ gen: 1, changed: ['ball.js'], removed: [], now: false });"#
        try await open(atStart: atStart)
        let said = try await change(2, ["ball.js"])
        XCTAssertEqual(said["state"] as? String, "held", "\(said)")
        XCTAssertTrue((said["why"] as? String ?? "").contains("while the game was starting"), "\(said)")
    }

    func testTheGameRuntimeTakesOverWithWhatWasHandedMeanwhile() async throws {
        // A stand-in for lamp-game.js, which sets its own __lampLive as it loads.
        let runtime = "window.__lampRuntime = true; window.got = []; window.__lampLive = change => { window.got.push(change.gen); return true; };"
        let main = "import './runtime.js';\n" + Self.main
        let atStart = #"window.__lampLive({ gen: 3, changed: ['ball.js'], removed: [], now: false });"#
        try await open(main: main, also: ["runtime.js": runtime], atStart: atStart)
        let got13 = try await value("window.got") as? [Int]
        XCTAssertEqual(got13, [3])
        let got14 = try await value("!!window.__lampLive.lampHelper") as? Bool
        XCTAssertEqual(got14, false)
        _ = try await value(#"window.__lampLive({ gen: 4, changed: [], removed: [], now: false })"#)
        let got15 = try await value("window.got") as? [Int]
        XCTAssertEqual(got15, [3, 4])
    }
}
