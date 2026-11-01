import WebKit
import XCTest
@testable import Lamp

/// A part let go of is taken apart once nothing is deciding what the game goes on with (lamp-game.js, `emptyRetired`),
/// and only what's its alone: what the game still holds through anything else stays whole. The page is the real
/// lamp-game.js and three.js in WebKit, changed through `window.__lampLive` as the app around the page does it.
@MainActor
final class GameRetiredPartTests: XCTestCase {
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

    /// Says the page takes changes (`host()` in lamp-game.js).
    private final class Live: NSObject, WKScriptMessageHandler {
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {}
    }

    private static let page = """
        <!doctype html><html><head>
        <script>
        // A page in no window draws no frames, and its timers are slowed to a few a second: frames come from a message
        // channel, which isn't, since how many frames go by decides when a scene counts as no longer drawn.
        (function () {
            const channel = new MessageChannel(), waiting = [];
            let last = 0;
            channel.port1.onmessage = function () {
                if (performance.now() - last < 16) { channel.port2.postMessage(0); return; }
                last = performance.now();
                for (const fn of waiting.splice(0)) fn(last);
            };
            window.requestAnimationFrame = function (fn) { waiting.push(fn); channel.port2.postMessage(0); return 1; };
        })();
        window.opens = 1 + Number(sessionStorage.opens || 0); sessionStorage.opens = window.opens;
        window.addEventListener('error', e => { window.failed = e.message; });
        window.addEventListener('unhandledrejection', e => { window.failed = String(e.reason); });
        </script>
        <script src="lamp.js"></script>
        <script type="importmap">{ "imports": { "three": "./three.module.js" } }</script>
        </head><body></body><script type="module" src="game.js"></script></html>
        """

    /// A game around `body`: a stand-in renderer (three.js's own would need a GPU here), a kept scene and what's shared
    /// made once, counting its disposals. The renderer caches what it draws as three.js's does: a geometry or material
    /// is registered when first drawn and forgotten only by its `dispose` event, so one drawn again after a disposal is
    /// cached again. `frame` runs each frame.
    private static func game(_ body: String, top: String = "", frame: String = "") -> String {
        """
        import * as THREE from 'three';
        import { game, hot } from './lamp-game.js';
        \(top)
        window.run = (window.run || 0) + 1;
        const live = hot(import.meta);
        const canvas = document.createElement('canvas');
        const cached = window.cached = window.cached || new Set();
        const cache = thing => {
            if (!thing || cached.has(thing)) return;
            cached.add(thing);
            const forget = () => { cached.delete(thing); thing.removeEventListener('dispose', forget); };
            thing.addEventListener('dispose', forget);
        };
        const draw = drawn => drawn.traverse(o => { cache(o.geometry); cache(o.material); });
        const renderer = live.renderer(() => ({ domElement: canvas, setPixelRatio() {}, setSize() {}, render(drawn) { draw(drawn); }, compileAsync() { return Promise.resolve(); } }));
        const camera = live.camera('main', () => new THREE.PerspectiveCamera(60, 16 / 9, 0.1, 500));
        const play = live.state('play', { version: 1, start: () => ({ x: 0 }) });
        const scene = live.keep('scene', () => new THREE.Scene());
        const shared = window.shared = window.shared || (() => {
            const s = { geo: new THREE.BoxGeometry(1, 1, 1), mat: new THREE.MeshBasicMaterial(), disposed: 0 };
            s.geo.addEventListener('dispose', () => s.disposed++);
            s.mat.addEventListener('dispose', () => s.disposed++);
            return s;
        })();
        window.THREE = THREE; window.scene = scene;
        const own = () => { const m = new THREE.Mesh(new THREE.BoxGeometry(2, 2, 2), new THREE.MeshBasicMaterial()); m.geometry.addEventListener('dispose', () => { window.ownDisposed = (window.ownDisposed || 0) + 1; }); return m; };
        \(body)
        game({ renderer, init() {}, frame() { renderer.render(scene, camera); \(frame) window.drawn = window.run; } });
        """
    }

    /// What every test's first version holds: a group of a mesh on what's shared and a mesh of its own.
    private static func goes(_ version: Int, extra: String = "", shares: Bool = true) -> String {
        """
        live.keep('goes', () => { /* \(version) */
            const g = new THREE.Group(), mine = own();
            \(shares ? "const common = new THREE.Mesh(shared.geo, shared.mat); g.add(common);" : "const common = null;")
            g.add(mine);
            scene.add(g);
            (window.made = window.made || []).push({ g, common, mine, geometry: mine.geometry });
            \(extra)
            return g;
        }, { inputs: [scene] });
        """
    }

    private var view: WKWebView!
    private var files: Files!
    private var live: Live!

    private func open(_ game: String, also: [String: String] = [:]) async throws {
        files = Files()
        live = Live()
        let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources")
        func read(_ path: String) throws -> String { try String(contentsOf: base.appendingPathComponent(path), encoding: .utf8) }
        let mac = try XCTUnwrap(Places.builtIn.first { $0.id == "mac" })
        files.text = ["index.html": Self.page, "game.js": game,
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
        try await until("the game has drawn", seconds: 15) { try await self.number("window.drawn || 0") == 1 }
        if let failed = try await value("window.failed") as? String { XCTFail(failed) }
    }

    private func value(_ code: String) async throws -> Any? { try await view.evaluateJavaScript(code, in: nil, contentWorld: .page) }
    private func js(_ code: String) async throws { _ = try await value(code + "; 0") }
    private func number(_ code: String) async throws -> Double { (try await value(code) as? NSNumber)?.doubleValue ?? -1 }
    private func yes(_ code: String) async throws -> Bool { try await value("!!(\(code))") as? Bool ?? false }

    private func until(_ what: String, seconds: Double = 8, _ done: () async throws -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if try await done() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let failed = try await value("window.failed || ''") as? String ?? ""
        XCTFail("Never: \(what) \(failed)")
    }

    /// Tells the page of a change and waits for the new run's first frame.
    private func change(_ changed: String...) async throws {
        let run = try await number("window.run")
        try await js("window.__lampLive({ changed: \(changed), gen: \(Int(run)), now: true, why: 'test' })")
        try await until("the new run has drawn", seconds: 10) { try await self.number("window.drawn") == run + 1 }
    }

    private func emptied(_ path: String) async throws {
        try await until("\(path) was taken apart") { try await self.yes("\(path).g.children.length === 0") }
    }

    /// Long enough for `emptyRetired`, which runs three seconds after a part goes.
    private func pastEmptying() async throws { try await Task.sleep(nanoseconds: 4_500_000_000) }

    func testWhatOtherMeshesShareStaysWhileARetiredMeshLetsGoOfIt() async throws {
        let stays = "live.keep('stays', () => { const m = new THREE.Mesh(shared.geo, shared.mat); scene.add(m); window.staying = m; return m; }, { inputs: [scene] });"
        try await open(Self.game(stays + Self.goes(1)))
        files.text["game.js"] = Self.game(stays + Self.goes(2, shares: false))
        try await change("game.js")
        try await emptied("made[0]")

        let disposed = try await number("shared.disposed"), own = try await number("window.ownDisposed")
        XCTAssertEqual(disposed, 0, "the mesh that stays still uses what was shared")
        XCTAssertEqual(own, 1, "what was the part's alone is disposed of, once")
        let whole = try await yes("staying.geometry === shared.geo && staying.material === shared.mat && staying.parent === scene")
        XCTAssertTrue(whole)
        let letGoOf = try await yes("made[0].common.geometry !== shared.geo && made[0].common.material !== shared.mat && made[0].mine.geometry !== made[0].geometry")
        XCTAssertTrue(letGoOf, "a retired mesh holds neither")
        let usable = try await yes("typeof made[0].mine.geometry.dispose === 'function' && typeof made[0].mine.material.dispose === 'function'")
        XCTAssertTrue(usable, "old code that still calls it finds an object, not null")
        let fresh = try await yes("made[1].g.parent === scene && made[1].g.children.length === 1")
        XCTAssertTrue(fresh, "the part that replaced it is untouched")
    }

    func testWhatASecondSceneDrawsIsSparedThoughNoPartKeepsIt() async throws {
        let other = """
            window.other = window.other || (() => { const s = new THREE.Scene(); s.add(new THREE.Mesh(shared.geo, shared.mat)); return s; })();
            """
        let frame = "renderer.render(window.other, camera);"
        try await open(Self.game(other + Self.goes(1), frame: frame))
        files.text["game.js"] = Self.game(other + Self.goes(2, shares: false), frame: frame)
        try await change("game.js")
        try await emptied("made[0]")
        let disposed = try await number("shared.disposed")
        XCTAssertEqual(disposed, 0)
        let whole = try await yes("other.children[0].geometry === shared.geo")
        XCTAssertTrue(whole)
    }

    func testAnObjectMovedOutOfAPartBeforeItGoesStaysWhole() async throws {
        try await open(Self.game(Self.goes(1)))
        files.text["game.js"] = Self.game(Self.goes(2, extra: "if (window.made[0]) scene.add(window.made[0].mine);"))
        try await change("game.js")
        try await emptied("made[0]")
        let whole = try await yes("made[0].mine.parent === scene && made[0].mine.geometry === made[0].geometry")
        XCTAssertTrue(whole)
    }

    func testAPartPutBackInASceneAfterItWentIsNotTakenApart() async throws {
        try await open(Self.game(Self.goes(1)))
        files.text["game.js"] = Self.game(Self.goes(2))
        try await change("game.js")
        try await until("the old part left the scene") { try await self.yes("made[0].g.parent === null") }
        try await js("scene.add(made[0].g)")
        try await pastEmptying()
        let whole = try await yes("made[0].g.parent === scene && made[0].g.children.length === 2 && made[0].mine.geometry === made[0].geometry")
        XCTAssertTrue(whole)
    }

    func testADetachedKeptPartsObjectsStayThoughARetiredTreeHoldsOne() async throws {
        // A pool in a class of its own, detached from every scene, one of its meshes lent to the part that goes.
        let pool = """
            class Pool { constructor() { this.meshes = [new THREE.Mesh(shared.geo, shared.mat), new THREE.Mesh(shared.geo, shared.mat)]; } }
            const pool = window.pool = live.keep('pool', () => new Pool());
            """
        try await open(Self.game(pool + Self.goes(1, extra: "g.add(pool.meshes[0]);")))
        files.text["game.js"] = Self.game(pool + Self.goes(2, shares: false))
        try await change("game.js")
        try await emptied("made[0]")
        let whole = try await yes("pool.meshes.every(m => m.geometry === shared.geo && m.material === shared.mat)")
        XCTAssertTrue(whole)
        let disposed = try await number("shared.disposed")
        XCTAssertEqual(disposed, 0)
    }

    func testAHeldChildOfARetiredGroupLeavesItCleanly() async throws {
        let pool = """
            const pool = window.pool = live.keep('pool', () => [new THREE.Mesh(shared.geo, shared.mat)]);
            """
        try await open(Self.game(pool + Self.goes(1, extra: "g.add(pool[0]); g.position.x = 10; g.updateMatrixWorld(true);")))
        files.text["game.js"] = Self.game(pool + Self.goes(2, shares: false))
        try await change("game.js")
        try await emptied("made[0]")
        let detached = try await yes("pool[0].parent === null")
        XCTAssertTrue(detached, "it can't go on pointing at a group that no longer lists it")
        let x = try await number("pool[0].updateWorldMatrix(true, false); pool[0].matrixWorld.elements[12]")
        XCTAssertEqual(x, 0, "and takes nothing from where the old group stood")
    }

    private static func stage(_ version: Int) -> String {
        """
        const stage = live.keep('stage', () => { /* \(version) */
            const s = new THREE.Scene(), mine = own();
            s.add(mine);
            (window.made = window.made || []).push({ g: s, mine, geometry: mine.geometry, material: mine.material });
            return s;
        });
        """
    }
    private static let drawsStage = "renderer.render(window.drawInstead || stage, camera);"

    func testAReplacedSceneNoLongerDrawnIsDisposedOfAndTakenApart() async throws {
        try await open(Self.game(Self.stage(1), frame: Self.drawsStage))
        files.text["game.js"] = Self.game(Self.stage(2), frame: Self.drawsStage)
        try await change("game.js")
        try await until("its own geometry was disposed of") { try await self.number("window.ownDisposed || 0") == 1 }
        try await until("it was taken apart", seconds: 12) { try await self.yes("made[0].g.children.length === 0") }
        let forgotten = try await yes("!cached.has(made[0].geometry) && !cached.has(made[0].material)")
        XCTAssertTrue(forgotten, "the renderer holds nothing of it")
        let fresh = try await yes("made[1].g.children.length === 1 && made[1].mine.geometry === made[1].geometry && cached.has(made[1].geometry)")
        XCTAssertTrue(fresh)
    }

    func testAReplacedSceneStillBeingDrawnWaitsUntilItStops() async throws {
        try await open(Self.game(Self.stage(1), frame: Self.drawsStage))
        try await js("window.drawInstead = made[0].g")
        files.text["game.js"] = Self.game(Self.stage(2), frame: Self.drawsStage)
        try await change("game.js")
        try await pastEmptying()
        let whole = try await yes("made[0].g.children.length === 1 && made[0].mine.geometry === made[0].geometry")
        XCTAssertTrue(whole, "something still draws it")
        let disposed = try await number("window.ownDisposed || 0")
        XCTAssertEqual(disposed, 0, "what's still drawn isn't disposed of, or the renderer would only make it again")
        try await js("window.drawInstead = null")
        try await until("it was taken apart once nothing drew it", seconds: 16) { try await self.yes("made[0].g.children.length === 0") }
        let once = try await number("window.ownDisposed || 0")
        XCTAssertEqual(once, 1)
        let forgotten = try await yes("!cached.has(made[0].geometry) && !cached.has(made[0].material)")
        XCTAssertTrue(forgotten, "the renderer holds nothing of it once it's gone")
    }

    func testAPartWithItsOwnDisposeIsLeftToIt() async throws {
        func custom(_ version: Int) -> String {
            """
            live.keep('goes', () => { /* \(version) */
                const g = new THREE.Group(), mine = own(); g.add(mine); scene.add(g);
                (window.made = window.made || []).push({ g, mine, geometry: mine.geometry });
                return g;
            }, { inputs: [scene], dispose(g) { g.removeFromParent(); window.customDisposed = (window.customDisposed || 0) + 1; } });
            """
        }
        try await open(Self.game(custom(1)))
        files.text["game.js"] = Self.game(custom(2))
        try await change("game.js")
        try await until("its dispose ran") { try await self.number("window.customDisposed || 0") == 1 }
        try await pastEmptying()
        let whole = try await yes("made[0].g.children.length === 1 && made[0].mine.geometry === made[0].geometry")
        XCTAssertTrue(whole, "what a part's own dispose owns isn't Lamp's to take apart")
    }

    func testAnAsyncPartThatArrivesLateTakesItsPredecessorApartOnlyThen() async throws {
        func slow(_ version: Int) -> String {
            """
            live.keep('slow', async () => { /* \(version) */
                if (window.run > 1) await new Promise(done => { window.release = done; });
                const g = new THREE.Group(), mine = own(); g.add(mine); scene.add(g);
                (window.made = window.made || []).push({ g, mine, geometry: mine.geometry });
                return g;
            }, { inputs: [scene] });
            """
        }
        try await open(Self.game(slow(1)))
        try await until("the first part arrived") { try await self.number("(window.made || []).length") == 1 }
        files.text["game.js"] = Self.game(slow(2))
        try await change("game.js")
        try await pastEmptying()
        let waiting = try await yes("made[0].g.children.length === 1 && made[0].mine.geometry === made[0].geometry")
        XCTAssertTrue(waiting, "the game has nothing else until the new one arrives")
        try await js("window.release()")
        try await emptied("made[0]")
        let fresh = try await yes("made[1].g.parent === scene && made[1].mine.geometry === made[1].geometry")
        XCTAssertTrue(fresh)
    }

    func testAPartBuiltInTheBackgroundReplacesTheOldOneWhole() async throws {
        let body = """
            live.keep('city', function* () {
                const seed = window.seed || 1, g = new THREE.Group(), mine = own(), common = new THREE.Mesh(shared.geo, shared.mat);
                yield;
                g.add(mine, common); scene.add(g);
                (window.made = window.made || []).push({ g, mine, common, geometry: mine.geometry, seed });
                return { group: g };
            }, { from: ['map.js'], background: true, inputs: [scene] });
            """
        try await open(Self.game(body), also: ["map.js": "export const SEED = 1;"])
        try await js("window.seed = 2")
        files.text["map.js"] = "export const SEED = 2;"
        try await js("window.__lampLive({ changed: ['map.js'], gen: 1, why: 'test' })")
        try await until("the new part went in", seconds: 15) { try await self.number("(window.made || []).length") == 2 }
        try await until("the old part was taken apart", seconds: 12) { try await self.yes("made[0].g.children.length === 0") }
        let fresh = try await yes("made[1].g.children.length === 2 && made[1].mine.geometry === made[1].geometry && made[1].common.geometry === shared.geo")
        XCTAssertTrue(fresh)
    }

    func testARunThatFailsOpensThePageAgainWithItsPartsWhole() async throws {
        try await open(Self.game(Self.goes(1)))
        files.text["game.js"] = Self.game(Self.goes(2), top: "if (window.opens === 1) throw new Error('no');")
        try await js("window.__lampLive({ changed: ['game.js'], gen: 1, now: true, why: 'test' })")
        try await until("the page opened again", seconds: 15) { try await self.yes("window.opens === 2 && window.drawn === 1") }
        let whole = try await yes("made.length === 1 && made[0].g.parent === scene && made[0].g.children.length === 2")
        XCTAssertTrue(whole)
    }

    func testATableInKeepIsReusedUntilItsModuleOrItsDataChanges() async throws {
        func tables(_ note: String = "") -> String {
            """
            import { hot } from './lamp-game.js';
            // Named outside the build: the runtime writes a module's import.meta out, differently each run.
            const address = new URL('./table.txt', import.meta.url);
            export const TABLE = await hot(import.meta).keep('table', async () => { /* \(note) */
                window.tableBuilds = (window.tableBuilds || 0) + 1;
                const answer = await fetch(address);
                return { rows: (await answer.text()).split(',') };
            }, { from: ['table.txt'] });
            """
        }
        func body(_ note: String) -> String { "window.seen = window.seen || []; window.seen.push(TABLE); /* \(note) */" }
        let top = "import { TABLE } from './tables.js';"
        try await open(Self.game(body("a"), top: top), also: ["tables.js": tables(), "table.txt": "1,2"])

        files.text["game.js"] = Self.game(body("b"), top: top)
        try await change("game.js")
        var builds = try await number("window.tableBuilds")
        XCTAssertEqual(builds, 1, "a change elsewhere doesn't build it again")
        let same = try await yes("seen[0] === seen[1]")
        XCTAssertTrue(same)

        files.text["table.txt"] = "1,2,3"
        try await change("table.txt")
        builds = try await number("window.tableBuilds")
        XCTAssertEqual(builds, 2, "the data it's built from changed")
        var rows = try await number("seen[seen.length - 1].rows.length")
        XCTAssertEqual(rows, 3)

        files.text["tables.js"] = tables("edited")
        files.text["table.txt"] = "1"
        try await change("tables.js", "table.txt")
        builds = try await number("window.tableBuilds")
        XCTAssertEqual(builds, 3, "its own code changed")
        rows = try await number("seen[seen.length - 1].rows.length")
        XCTAssertEqual(rows, 1)
    }
}
