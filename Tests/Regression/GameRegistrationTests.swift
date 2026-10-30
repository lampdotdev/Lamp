import WebKit
import XCTest
@testable import Lamp

/// What a game registers lasts through a change of its code (lamp-game.js, "What the game registers"). The page is the
/// real lamp-game.js and three.js in WebKit, changed through `window.__lampLive` as the app around the page does it.
@MainActor
final class GameRegistrationTests: XCTestCase {
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

    /// Says the page takes changes (`host()` in lamp-game.js), and keeps what it told Lamp.
    private final class Live: NSObject, WKScriptMessageHandler {
        var told: [[String: Any]] = []
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any] { told.append(body) }
        }
    }

    private static let page = """
        <!doctype html><html><head>
        <script>
        // A page in no window draws no frames: they come from a timer. What's kept here lasts as long as the page does.
        window.requestAnimationFrame = function (fn) { return window.setTimeout(function () { fn(performance.now()); }, 16); };
        window.opens = 1 + Number(sessionStorage.opens || 0); sessionStorage.opens = window.opens;
        </script>
        <script src="lamp.js"></script>
        <script type="importmap">{ "imports": { "three": "./three.module.js" } }</script>
        </head><body></body><script type="module" src="game.js"></script></html>
        """

    /// A stand-in renderer, for what a test counts of it: three.js's own would need a GPU in the test's process.
    private static let builds = """
        window.madeRenderers = window.madeRenderers || 0;
        const canvas = document.createElement('canvas');
        const makeRenderer = () => { window.madeRenderers++; return { domElement: canvas, setPixelRatio() {}, setSize() {}, render() {} }; };
        """

    private static func game(lens: String = "60", start: String = "{ mode: 'title', level: 1, player: { x: 0, z: 0 } }",
                             version: Int = 1, extra: String = "", body: String = "") -> String {
        """
        import * as THREE from 'three';
        import { game, hot } from './lamp-game.js';
        import { rocks } from './rocks.js';
        \(builds)
        const live = hot(import.meta);
        const renderer = live.renderer(makeRenderer);
        let controls = { target: new THREE.Vector3(0, 0, 0) };
        const camera = live.camera('main', () => { const c = new THREE.PerspectiveCamera(\(lens), 16 / 9, 0.1, 500); c.position.set(0, 2, 8); return c; },
                                   { target: () => controls.target });
        const play = live.state('play', { version: \(version), start: () => (\(start)) \(extra) });
        window.run = (window.run || 0) + 1;
        window.play = play; window.camera = camera; window.controls = controls; window.renderer = renderer;
        \(body)
        game({
            renderer,
            init() {
                // A start that sets the camera as a game's would: the player's place wins at the first frame.
                camera.position.set(0, 2, 8);
                window.levelAtInit = play.level;
                window.modeAtInit = play.mode;
            },
            frame() {
                if (window.drawn !== window.run) { window.firstFrameLevel = play.level; window.firstFrameX = camera.position.x; }
                window.drawn = window.run;
                window.rocks = rocks;
            },
        });
        """
    }

    private var view: WKWebView!
    private var files: Files!
    private var live: Live!

    private func open(_ game: String? = nil, also: [String: String] = [:]) async throws {
        files = Files()
        live = Live()
        let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources")
        func read(_ path: String) throws -> String { try String(contentsOf: base.appendingPathComponent(path), encoding: .utf8) }
        let mac = try XCTUnwrap(Places.builtIn.first { $0.id == "mac" })
        files.text = ["index.html": Self.page, "game.js": game ?? Self.game(), "rocks.js": "export const rocks = 1;",
                      "lamp.js": GameKit.controllersJS, "lamp-game.js": try read("GameKit/web/lamp-game.js"),
                      "lamp-device.js": try GamePage.descriptor(for: mac), "lamp-controllers.js": Controllers.pageJS,
                      "lamp-build.js": "export default 'test';",
                      "three.module.js": try read("WebLibraries/three/three.module.js"), "three.core.js": try read("WebLibraries/three/three.core.js")]
        files.text.merge(also) { $1 }
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(files, forURLScheme: "lamp-test")
        configuration.userContentController.add(live, contentWorld: .page, name: "lampLive")
        view = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 180), configuration: configuration)
        view.load(URLRequest(url: URL(string: "lamp-test://game/index.html")!))
        try await until("the game has drawn") { try await self.number("window.drawn || 0") == 1 }
    }

    private func value(_ code: String) async throws -> Any? { try await view.evaluateJavaScript(code, in: nil, contentWorld: .page) }
    private func js(_ code: String) async throws { _ = try await value(code + "; 0") }
    private func number(_ code: String) async throws -> Double { (try await value(code) as? NSNumber)?.doubleValue ?? -1 }
    private func text(_ code: String) async throws -> String { try await value(code) as? String ?? "" }

    private func until(_ what: String, seconds: Double = 8, _ done: () async throws -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if try await done() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Never: \(what)")
    }

    /// The player goes somewhere away from the start.
    private func wander() async throws {
        try await js("""
            play.mode = 'playing'; play.level = 7; play.player.x = 42;
            camera.position.set(11, 12, 13); camera.lookAt(1, 2, 3); camera.fov = 35; camera.updateProjectionMatrix();
            controls.target.set(4, 5, 6);
            """)
    }

    private func change(_ changed: String...) async throws {
        let run = try await number("window.run")
        try await js("window.__lampLive({ changed: \(changed), gen: \(Int(run)), now: true, why: 'test' })")
        try await until("the new run has drawn") { try await self.number("window.drawn") == run + 1 }
    }

    func testARerunKeepsTheRendererCameraAndState() async throws {
        try await open()
        try await wander()
        let turned = try await number("camera.quaternion.x")
        let rendererBefore = try await value("window.firstRenderer = renderer; 1")
        XCTAssertNotNil(rendererBefore)
        files.text["rocks.js"] = "export const rocks = 2;"
        files.text["game.js"] = Self.game(start: "{ mode: 'title', level: 1, player: { x: 0, z: 0, hp: 9 }, coins: 3 }")
        try await change("game.js", "rocks.js")

        let made = try await number("window.madeRenderers")
        XCTAssertEqual(made, 1, "the new code got the renderer the game had, before it could make one")
        let same = try await number("window.firstRenderer === window.renderer ? 1 : 0")
        XCTAssertEqual(same, 1)
        let rocks = try await number("window.rocks")
        XCTAssertEqual(rocks, 2, "the new code is what's running")

        // Back before init and before the first frame, the fields the change added at their start values.
        let levelAtInit = try await number("window.levelAtInit")
        XCTAssertEqual(levelAtInit, 7)
        let mode = try await text("window.modeAtInit")
        XCTAssertEqual(mode, "playing", "no title first")
        let firstX = try await number("window.firstFrameX")
        XCTAssertEqual(firstX, 11, "init set the camera, and the first frame has it where the player left it")
        let state = try await text("JSON.stringify(play)")
        XCTAssertEqual(state, #"{"mode":"playing","level":7,"player":{"x":42,"z":0,"hp":9},"coins":3}"#)

        let pose = try await text("JSON.stringify([camera.position.toArray(), camera.fov, controls.target.toArray()])")
        XCTAssertEqual(pose, "[[11,12,13],35,[4,5,6]]")
        let turnedAfter = try await number("camera.quaternion.x")
        XCTAssertEqual(turnedAfter, turned)
    }

    func testAChangedCameraBuildGivesTheNewLensAtTheOldPose() async throws {
        try await open()
        try await wander()
        files.text["game.js"] = Self.game(lens: "90")
        try await change("game.js")
        let pose = try await text("JSON.stringify([camera.position.toArray(), camera.fov, controls.target.toArray()])")
        XCTAssertEqual(pose, "[[11,12,13],90,[4,5,6]]")
    }

    func testAChangedRendererBuildMakesANewOne() async throws {
        try await open()
        files.text["game.js"] = Self.game().replacingOccurrences(of: "live.renderer(makeRenderer)", with: "live.renderer(() => makeRenderer())")
        try await change("game.js")
        let made = try await number("window.madeRenderers")
        XCTAssertEqual(made, 2)
    }

    func testARaisedVersionMigratesOrStartsOver() async throws {
        try await open()
        try await wander()
        files.text["game.js"] = Self.game(version: 2, extra: ", migrate: (old, from) => ({ ...old, level: old.level * 10, from })")
        try await change("game.js")
        let migrated = try await text("JSON.stringify([play.level, play.from])")
        XCTAssertEqual(migrated, "[70,1]")

        files.text["game.js"] = Self.game(version: 3)
        try await change("game.js")
        let reset = try await text("JSON.stringify(play)")
        XCTAssertEqual(reset, #"{"mode":"title","level":1,"player":{"x":0,"z":0}}"#, "no migrate: that state starts over")
        let camera = try await number("camera.position.x")
        XCTAssertEqual(camera, 11, "and only that state")

        files.text["game.js"] = Self.game(version: 4, extra: ", migrate: () => { throw new Error('no') }")
        try await js("play.level = 5")
        try await change("game.js")
        let failed = try await number("play.level")
        XCTAssertEqual(failed, 1, "a migrate that fails starts over rather than stopping the game")
    }

    /// Lamp's own file changed, so the page really opens again: all that's left is what it kept for its opening.
    func testThePageOpeningAgainPutsItAllBackBeforeTheFirstFrame() async throws {
        try await open()
        try await wander()
        try await js("window.__lampLive({ changed: ['lamp-game.js'], gen: 1, now: true, why: 'test' })")
        try await until("the page opened again") { try await self.number("window.opens === 2 && window.drawn === 1 ? 1 : 0") == 1 }
        let level = try await number("window.firstFrameLevel")
        XCTAssertEqual(level, 7)
        let atInit = try await number("window.levelAtInit")
        XCTAssertEqual(atInit, 7, "registered before game() found out where it starts, and back by init")
        let pose = try await text("JSON.stringify([camera.position.toArray(), camera.fov, controls.target.toArray(), play.player.x])")
        XCTAssertEqual(pose, "[[11,12,13],35,[4,5,6],42]")
    }

    /// The scaffold every new game starts from, as Lamp writes it.
    func testANewGamesScaffoldRegistersWhatItNeeds() async throws {
        let scaffold = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/GameKit/scaffold-web/Web")
        func read(_ name: String) throws -> String {
            try String(contentsOf: scaffold.appendingPathComponent(name), encoding: .utf8).replacingOccurrences(of: "{{NAME}}", with: "Test")
        }
        // Three.js's renderer stands in for a GPU the test's page may not have; everything else is the scaffold's.
        let game = try read("game.js").replacingOccurrences(of: "new THREE.WebGLRenderer({ antialias: true })", with: "(window.made = (window.made || 0) + 1, { domElement: document.createElement('canvas'), setPixelRatio() {}, setSize() {}, render() {} })")
            + "\nwindow.play = play; window.camera = camera; window.world = world; window.drawn = 1;\n"
        try await open(game, also: ["world.js": try read("world.js"), "making.js": try read("making.js")])
        try await js("camera.position.set(3, 3, 3); window.worldBefore = world; play.time = 100; window.drawn = 0")
        let run = "window.drawn"
        try await js("window.__lampLive({ changed: ['game.js'], gen: 1, now: true, why: 'test' })")
        try await until("the code ran again") { try await self.number(run) == 1 }
        try await until("it's going") { try await self.number("play.time") > 100 }
        let kept = try await text("JSON.stringify([window.made, camera.position.toArray(), window.world === window.worldBefore])")
        XCTAssertEqual(kept, "[1,[3,3,3],true]")
    }
}
