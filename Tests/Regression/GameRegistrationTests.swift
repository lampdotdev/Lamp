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

    // MARK: What isn't registered

    /// A game that keeps nothing of the player's place, on its way to being told so.
    private static let unadopted = """
        import { game } from './lamp-game.js';
        \(builds)
        const renderer = makeRenderer();
        window.run = (window.run || 0) + 1;
        window.score = window.run === 1 ? 5 : 0;
        game({ renderer, frame() { window.drawn = window.run; } });
        """

    private func held() -> [String: Any]? { live.told.last { $0["state"] as? String == "held" } }

    func testAChangeThatWouldStartPlayOverWaitsForReloadAndSaysWhatIsMissing() async throws {
        try await open(Self.unadopted)
        files.text["game.js"] = Self.unadopted + "\nwindow.changed = 1;"
        try await js("window.__lampLive({ changed: ['game.js'], gen: 1, why: 'test' })")
        try await until("the page said it holds it") { self.held() != nil }
        let why = held()?["why"] as? String ?? ""
        XCTAssertTrue(why.contains("its gameplay state (live.state)") && why.contains("its renderer (live.renderer)") && why.contains("its camera (live.camera)"), why)
        try await Task.sleep(nanoseconds: 300_000_000)
        let run = try await number("window.run")
        XCTAssertEqual(run, 1, "play wasn't started over")

        // The person's Reload always goes in, and the run says what started again.
        try await js("window.__lampLive({ changed: ['game.js'], gen: 2, now: true, why: 'test' })")
        try await until("Reload took it") { try await self.number("window.drawn") == 2 }
        try await until("the page said what came through") { self.live.told.contains { $0["state"] as? String == "report" } }
        let said = live.told.last { $0["state"] as? String == "report" }?["why"] as? String ?? ""
        XCTAssertTrue(said.contains("not registered, so started again") && said.contains("its gameplay state"), said)
    }

    func testAGameThatReadsItsSnapshotBackGoesOn() async throws {
        let game = """
            import { game, pendingRestore } from './lamp-game.js';
            \(Self.builds)
            const renderer = makeRenderer();
            window.run = (window.run || 0) + 1;
            let level = 1;
            game({ renderer, snapshot: () => ({ level }), init() { const was = pendingRestore(); if (was) level = was.level; window.level = level; },
                   frame() { window.drawn = window.run; } });
            """
        try await open(game)
        files.text["game.js"] = game + "\nwindow.changed = 1;"
        try await js("window.__lampLive({ changed: ['game.js'], gen: 1, why: 'test' })")
        try await until("the code ran again by itself") { try await self.number("window.drawn") == 2 }
        XCTAssertNil(held())
    }

    func testARunSaysWhatItKeptBuiltAndReset() async throws {
        try await open(Self.game(body: "live.keep('rock', () => ({ a: window.run }));"))
        try await wander()
        files.text["game.js"] = Self.game(version: 2, body: "live.keep('rock', () => ({ a: window.run, b: 1 }));")
        try await js("window.__lampLive({ changed: ['game.js'], gen: 1, why: 'test' })")
        try await until("the page said what came through") { self.live.told.contains { $0["state"] as? String == "report" } }
        let said = live.told.last { $0["state"] as? String == "report" }?["why"] as? String ?? ""
        XCTAssertTrue(said.contains("kept renderer, camera main"), said)
        XCTAssertTrue(said.contains("built again rock"), said)
        XCTAssertTrue(said.contains("reset state play"), said)
        XCTAssertTrue(said.contains("not registered, so started again") == false, said)
    }

    func testTheRequestSaysWhatTheCodeDoesntRegister() async throws {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-game-registered-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Web"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var project = LampProject(id: "duck", name: "Duck", exe: "Duck", dir: root, platform: .game, family: .iphone, chosen: .mac, places: [.mac])
        project.engine = "web"
        func write(_ code: String) throws { try code.write(to: root.appendingPathComponent("Web/game.js"), atomically: true, encoding: .utf8) }
        try write("const renderer = new THREE.WebGLRenderer(); game({ renderer });")
        XCTAssertEqual(GameKit.unregistered(project).count, 3)
        XCTAssertTrue(GameKit.unregisteredNote(project).contains("its gameplay state"))
        try write("const renderer = live.renderer(() => make()); const c = live.camera('main', build); const p = live.state('play', {});")
        XCTAssertEqual(GameKit.unregistered(project), [])
        XCTAssertEqual(GameKit.unregisteredNote(project), "")
        try write("import { phaser } from './lamp-phaser.js'; const p = hot(import.meta).state('play', {});")
        XCTAssertEqual(GameKit.unregistered(project), [], "a 2D game's renderer and cameras are Phaser's")

        // What the page said came through reaches a look in the hidden copy, where the agent mostly looks.
        _ = PageLive.shared.state(["place": "mac", "state": "report", "why": "kept renderer; reset state play"], for: project)
        XCTAssertTrue(GameKit.openGameNote(project).contains("reset state play"))
        // Another copy's run is that copy's: the note is about the game open on the Mac.
        _ = PageLive.shared.state(["place": "simulator", "state": "report", "why": "kept nothing"], for: project)
        XCTAssertTrue(GameKit.openGameNote(project).contains("reset state play"))
        _ = PageLive.shared.state(["place": "simulator", "state": "swapped"], for: project)
        XCTAssertTrue(GameKit.openGameNote(project).contains("reset state play"))
        _ = PageLive.shared.state(["place": "mac", "state": "swapped"], for: project)
        XCTAssertFalse(GameKit.openGameNote(project).contains("reset state play"), "a later change has its own word")

        // Open, with its state registered and a camera of its own: a change goes in by itself, and the agent hears only that
        // the camera starts again. Without the state, the change waits for Reload.
        let asking = Task { _ = await PageLive.shared.poll(["place": "mac"], for: project) }
        defer { asking.cancel() }
        await Task.yield()
        try write("const renderer = live.renderer(() => make()); const p = live.state('play', {});")
        XCTAssertTrue(GameKit.openGameNote(project).contains("its camera"))
        XCTAssertFalse(GameKit.openGameNote(project).contains("Reload"), GameKit.openGameNote(project))
        XCTAssertFalse(GameKit.unregisteredNote(project).contains("Reload"), GameKit.unregisteredNote(project))
        try write("const renderer = live.renderer(() => make()); const c = live.camera('main', build);")
        XCTAssertTrue(GameKit.openGameNote(project).contains("Reload"))
        XCTAssertTrue(GameKit.unregisteredNote(project).contains("Reload"))
    }

    // MARK: A module that takes its changes

    /// The game's state, declared in a module that takes its changes. `then` is what its new version does as it goes in.
    private static func stateModule(version: Int = 1, start: String = "{ level: 1 }", extra: String = "", then: String = "") -> String {
        """
        import { hot } from './lamp-game.js';
        export const play = hot(import.meta).state('play', { version: \(version), start: () => (\(start)) \(extra) });
        window.stateVersion = \(version);
        hot(import.meta).accept(() => { \(then) });
        """
    }

    private static let gameOfModules = """
        import { game } from './lamp-game.js';
        import { play } from './state.js';
        \(builds)
        window.run = (window.run || 0) + 1;
        window.play = play;
        game({ renderer: makeRenderer(), frame() { window.drawn = window.run; } });
        """

    /// The runtime knows a module takes changes once it has read its source and first version.
    private func openOfModules() async throws {
        try await open(Self.gameOfModules, also: ["state.js": Self.stateModule()])
        try await Task.sleep(nanoseconds: 300_000_000)
        try await js("play.level = 7")
    }

    func testAChangedStateDeclarationInAModuleThatTakesChangesStillTakesEffect() async throws {
        try await openOfModules()
        files.text["state.js"] = Self.stateModule(version: 2, start: "{ level: 1, lives: 3 }", extra: ", migrate: old => ({ ...old, level: old.level * 10 })")
        try await js("window.__lampLive({ changed: ['state.js'], gen: 1, why: 'test' })")
        try await until("the code ran again") { try await self.number("window.drawn") == 2 }
        let state = try await text("JSON.stringify(play)")
        XCTAssertEqual(state, #"{"level":70,"lives":3}"#, "the new start and the migrate both took effect")
    }

    func testASwapThatFailsPutsTheStateBackAsItWasBeforeTheSwap() async throws {
        try await openOfModules()
        files.text["state.js"] = Self.stateModule(then: "window.play.level = 99; throw new Error('no');")
        try await js("window.__lampLive({ changed: ['state.js'], gen: 1, why: 'test' })")
        try await until("the code ran again") { try await self.number("window.drawn") == 2 }
        let level = try await number("play.level")
        XCTAssertEqual(level, 7, "what the failed swap did to it doesn't come through")
    }

    /// A part declared as built from a file is built again in place when it changes, even where the module it's read
    /// through would take the change by a swap; and a file the game uses that nothing read again waits for Reload.
    func testAPartBuiltFromAChangedFileIsBuiltAgainAndWhatNothingReadWaits() async throws {
        let paint = """
            import { LANES } from './map.js';
            import { hot } from './lamp-game.js';
            export class Painter { lanes() { return LANES; } }
            hot(import.meta).accept();
            """
        let body = """
            import { Painter } from './paint.js';
            window.paint = live.keep('roadPaint', () => ({ lanes: new Painter().lanes() }), { from: ['map.js'] });
            window.readStreets = () => fetch('streets.json');
            window.levels = live.keep('levels', () => ({ built: (window.levelBuilds = (window.levelBuilds || 0) + 1) }), { from: ['levels/'] });
            """
        try await open(Self.game(body: body), also: ["paint.js": paint, "map.js": "export const LANES = 2;", "streets.json": "[1]"])
        try await Task.sleep(nanoseconds: 300_000_000)
        try await wander()
        files.text["map.js"] = "export const LANES = 3;"
        try await js("window.__lampLive({ changed: ['map.js'], gen: 1, why: 'test' })")
        try await until("the code ran again") { try await self.number("window.drawn") == 2 }
        let lanes = try await number("window.paint.lanes")
        XCTAssertEqual(lanes, 3, "the part was built again from the new file, not swapped around")
        let report = try XCTUnwrap(live.told.last { $0["state"] as? String == "report" })
        XCTAssertEqual((report["built"] as? [[String: Any]])?.compactMap { $0["part"] as? String }, ["roadPaint"])
        let level = try await number("play.level")
        XCTAssertEqual(level, 7, "the player's place is kept")

        // A folder it's built from: any file in it.
        try await js("window.__lampLive({ changed: ['levels/one.json'], gen: 2, why: 'test' })")
        try await until("the code ran again") { try await self.number("window.drawn") == 3 }
        let levelBuilds = try await number("window.levelBuilds")
        XCTAssertEqual(levelBuilds, 2, "built once at the start, and again for the file in its folder only")

        try await js("window.readStreets()")
        files.text["streets.json"] = "[2]"
        try await js("window.__lampLive({ changed: ['streets.json'], gen: 3, why: 'test' })")
        try await until("the code ran again") { try await self.number("window.drawn") == 4 }
        try await until("the report came") { self.live.told.last { $0["state"] as? String == "report" }?["gen"] as? Int == 3 }
        let waits = live.told.last { $0["state"] as? String == "report" }?["waits"] as? [String]
        XCTAssertEqual(waits, ["streets.json"], "the game uses it, and nothing read it again")
    }

    // MARK: A file taken away

    /// Tells the page a change that took files away, as `LampPageLive` does, and waits for its first word.
    private func removal(_ removed: [String], changed: [String]? = nil, gen: Int) async throws -> String {
        for path in removed { files.text[path] = nil }
        let changes = try String(decoding: JSONSerialization.data(withJSONObject: changed ?? removed), as: UTF8.self)
        let gone = try String(decoding: JSONSerialization.data(withJSONObject: removed), as: UTF8.self)
        try await js("window.__lampLive({ changed: \(changes), removed: \(gone), gen: \(gen), why: 'test' })")
        var said = ""
        try await until("the page said what it did") {
            said = self.live.told.last { ($0["gen"] as? Int) == gen && ["swapped", "rerun", "held", "reloading"].contains($0["state"] as? String) }?["state"] as? String ?? ""
            return !said.isEmpty
        }
        return said
    }

    /// A stray file whose name is the end of a module's: nothing uses it, so taking it away goes in with nothing run.
    func testTakingAwayAnUnusedFileNamedLikeAModuleRunsNothingAndHoldsNothing() async throws {
        try await open(Self.game(body: "import('./world.js');"), also: ["world.js": "export const world = 1;", "orld.js": ""])
        try await wander()
        let run = try await number("window.run")
        let said = try await removal(["orld.js"], gen: 1)
        XCTAssertEqual(said, "swapped")
        let after = try await number("window.run")
        XCTAssertEqual(after, run, "the game's code didn't run again")
        try await Task.sleep(nanoseconds: 200_000_000)
        let waits = live.told.compactMap { $0["waits"] as? [String] }.flatMap { $0 }
        XCTAssertEqual(waits, [], "world.js doesn't name orld.js")
        XCTAssertFalse(live.told.contains { $0["state"] as? String == "report" }, "no run, so nothing to report")
    }

    /// A module the game imports can't go quietly: the change never says it went in by itself.
    func testTakingAwayAnImportedModuleIsNoQuietSwap() async throws {
        try await open(Self.game(body: "import { helper } from './helper.js'; window.helper = helper;"), also: ["helper.js": "export const helper = 1;"])
        try await wander()
        let said = try await removal(["helper.js"], gen: 1)
        XCTAssertNotEqual(said, "swapped")
    }

    /// A file the game fetched (here by a name built in its code) and a worker it started: what the running game holds
    /// came from them, so taking one away isn't nothing.
    func testTakingAwayAFileTheGameReadOrAWorkerItStartedIsHonest() async throws {
        try await open(Self.game(body: """
            window.ready = fetch(['lev', 'els.json'].join('')).then(r => r.text());
            new Worker(['job', 's.js'].join(''));
            """), also: ["levels.json": "[1]", "jobs.js": ""])
        try await js("window.ready.then(text => { window.readText = text; })")
        try await until("the game read it") { try await self.text("window.readText || ''") == "[1]" }
        let data = try await removal(["levels.json"], gen: 1)
        XCTAssertNotEqual(data, "swapped")
        try await until("the code ran again") { try await self.number("window.drawn") == 2 }
        let worker = try await removal(["jobs.js"], gen: 2)
        XCTAssertNotEqual(worker, "swapped")
    }

    /// Named only as a whole name counts: `world.js` isn't `orld.js`, and `orld.js` in a comment is.
    func testANameInTheCodeHoldsWhenItIsTheWholeName() async throws {
        try await open(Self.game(body: "// the old map, orld.js, went away"), also: ["orld.js": ""])
        try await wander()
        let said = try await removal(["orld.js"], gen: 1)
        XCTAssertNotEqual(said, "swapped", "Lamp can't tell a comment from a use, so it doesn't call this one unused")
    }

    /// An edit and an unused file taken away together: the edit goes in, and the file doesn't hold anything back.
    func testAnEditAndAnUnusedFileTakenAwayTogether() async throws {
        try await open(Self.game(body: "import('./world.js');"), also: ["world.js": "export const world = 1;", "orld.js": ""])
        try await wander()
        files.text["rocks.js"] = "export const rocks = 2;"
        let said = try await removal(["orld.js"], changed: ["rocks.js", "orld.js"], gen: 1)
        XCTAssertEqual(said, "rerun")
        try await until("the new code has drawn") { try await self.number("window.rocks") == 2 }
        try await until("the report came") { self.live.told.contains { $0["state"] as? String == "report" } }
        let waits = live.told.last { $0["state"] as? String == "report" }?["waits"] as? [String]
        XCTAssertEqual(waits, [])
    }

    /// A file taken away while a change waits for a pause stays out of what waits, and that change still goes in.
    func testAFileTakenAwayJoinsAChangeThatWaits() async throws {
        try await open(Self.game(body: "window.busy = true; import('./world.js');").replacingOccurrences(of: "frame() {", with: "busy: () => window.busy, frame() {"),
                       also: ["world.js": "export const world = 1;", "orld.js": ""])
        try await wander()
        files.text["rocks.js"] = "export const rocks = 2;"
        try await js("window.__lampLive({ changed: ['rocks.js'], gen: 1, why: 'test' })")
        try await until("the change waits") { self.live.told.contains { $0["state"] as? String == "held" } }
        let said = try await removal(["orld.js"], gen: 2)
        XCTAssertEqual(said, "held", "what waited still waits")
        try await js("window.busy = false; window.__lampLive({ changed: [], gen: 3, why: 'test' })")
        try await until("the waiting change went in") { try await self.number("window.rocks") == 2 }
        try await until("the report came") { self.live.told.contains { $0["state"] as? String == "report" } }
        let waits = live.told.last { $0["state"] as? String == "report" }?["waits"] as? [String]
        XCTAssertEqual(waits, [])
    }

    /// Taken away while a change waits, then made again: it's a changed file again, not a removal.
    func testAFileMadeAgainWhileItsRemovalWaitsIsAChange() async throws {
        try await open(Self.game(body: "window.busy = true;").replacingOccurrences(of: "frame() {", with: "busy: () => window.busy, frame() {"), also: ["rocks2.js": ""])
        try await wander()
        files.text["rocks.js"] = "export const rocks = 2;"
        try await js("window.__lampLive({ changed: ['rocks.js'], gen: 1, why: 'test' })")
        try await until("the change waits") { self.live.told.contains { $0["state"] as? String == "held" } }
        _ = try await removal(["rocks2.js"], gen: 2)
        files.text["rocks2.js"] = "export const back = 1;"
        try await js("window.busy = false; window.__lampLive({ changed: ['rocks2.js'], gen: 3, why: 'test' })")
        try await until("the code ran again") { try await self.number("window.rocks") == 2 }
        try await until("the report came") { self.live.told.contains { $0["state"] as? String == "report" } }
        XCTAssertFalse(live.told.contains { $0["state"] as? String == "swapped" }, "it went in as a change, not as nothing")
    }
}
