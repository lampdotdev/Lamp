import JavaScriptCore
import LampRelayKit
import XCTest
@testable import Lamp

/// A game on an LG TV runs its own phones: Lamp packages the game's phone service beside it, and the game's page starts
/// its phones there, never asking Lamp. The service itself is checked on real sockets under each Node an LG TV has
/// (Tests/LGPhones/relay-test.js); here, what Lamp puts in the package and what the page does with it.
final class LGPhonesTests: XCTestCase {
    private var folder: URL!
    private let service = "dev.lamp.app.pong.phones"
    private static let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/LGPhones")

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lg-phones-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: The package

    func testThePackageCarriesTheServiceWithThePhonePageAndTheGameNamesIt() async throws {
        let staged = folder.appendingPathComponent("web")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try Data("<script src=\"lamp.js\"></script>".utf8).write(to: staged.appendingPathComponent("index.html"))
        try Data(GameKit.controllersJS.utf8).write(to: staged.appendingPathComponent("lamp.js"))
        let page = ControllerSnapshot(files: [.init(path: "index.html", data: Data("<p>pad</p>".utf8)),
                                              .init(path: "lamp-controller.js", data: Data(TVTemplate.phoneControllerJS.utf8))])
        let phones = LGPhones.Service(id: service, files: try LGPhones.files(id: service, owner: "dev.lamp.app.pong", page: page, source: Self.source))
        let project = LampProject(id: "pong", name: "Pong", exe: "Pong", dir: folder.appendingPathComponent("pong"))

        let ipk = try await TVPackage.ipk(for: project, staged: staged, phones: phones)
        defer { try? FileManager.default.removeItem(at: ipk.deletingLastPathComponent()) }
        let out = folder.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let unpacked = await Subprocess.run("/usr/bin/tar", ["-xf", ipk.path], cwd: out, timeout: 30).ok
        let untarred = await Subprocess.run("/usr/bin/tar", ["-xzf", "data.tar.gz"], cwd: out, timeout: 30).ok
        XCTAssertTrue(unpacked && untarred)

        let app = TVTemplate.webOSID(for: project)
        let info = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("usr/palm/packages/\(app)/packageinfo.json"))) as? [String: Any]
        XCTAssertEqual(info?["services"] as? [String], [service], "the TV installs the service with the game")
        let root = out.appendingPathComponent("usr/palm/services/\(service)")
        for path in ["service.js", "relay.js", "node_modules/ws/index.js", "services.json", "phone/index.html", "phone/lamp-controller.js"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), path)
        }
        let package = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("package.json"))) as? [String: Any]
        XCTAssertEqual((package?["lamp"] as? [String: String])?["owner"], "dev.lamp.app.pong", "only the game may start it")
        let lampJS = try String(contentsOf: out.appendingPathComponent("usr/palm/applications/\(app)/lamp.js"), encoding: .utf8)
        XCTAssertTrue(lampJS.contains("var lgService = /*LAMP_LG_SERVICE*/\"\(service)\""))
        XCTAssertEqual(try String(contentsOf: staged.appendingPathComponent("lamp.js"), encoding: .utf8), GameKit.controllersJS,
                       "the staged copy, which the preview and a Samsung TV take, still asks Lamp")
    }

    func testAGameBuiltBeforeTheServiceGoesAsItAlwaysHas() async throws {
        let staged = folder.appendingPathComponent("web")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try Data("<script src=\"lamp.js\"></script>".utf8).write(to: staged.appendingPathComponent("index.html"))
        let earlier = GameKit.controllersJS.replacingOccurrences(of: TVTemplate.lgServiceMarker, with: "null")
        try Data(earlier.utf8).write(to: staged.appendingPathComponent("lamp.js"))
        let page = ControllerSnapshot(files: [.init(path: "index.html", data: Data("<p>pad</p>".utf8))])
        let phones = LGPhones.Service(id: service, files: try LGPhones.files(id: service, owner: "dev.lamp.app.pong", page: page, source: Self.source))
        let project = LampProject(id: "pong", name: "Pong", exe: "Pong", dir: folder.appendingPathComponent("pong"))

        let ipk = try await TVPackage.ipk(for: project, staged: staged, phones: phones)
        defer { try? FileManager.default.removeItem(at: ipk.deletingLastPathComponent()) }
        let out = folder.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let unpacked = await Subprocess.run("/usr/bin/tar", ["-xf", ipk.path], cwd: out, timeout: 30).ok
        let untarred = await Subprocess.run("/usr/bin/tar", ["-xzf", "data.tar.gz"], cwd: out, timeout: 30).ok
        XCTAssertTrue(unpacked && untarred)
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.appendingPathComponent("usr/palm/services").path),
                       "its page asks Lamp, so no service goes with it")
        let app = TVTemplate.webOSID(for: project)
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("usr/palm/applications/\(app)/lamp.js"), encoding: .utf8), earlier)
    }

    func testOnlyATVWhoseWebOSRunsTheServiceGetsIt() {
        XCTAssertFalse(LGPhones.runs(on: ""), "a TV whose version Lamp hasn't read keeps Lamp's phones")
        XCTAssertFalse(LGPhones.runs(on: "4.9.0"), "webOS TV 4.x has Node 0.12")
        XCTAssertTrue(LGPhones.runs(on: "5.2.0"))
        XCTAssertTrue(LGPhones.runs(on: "9.2.1"))
        XCTAssertTrue(LGPhones.isServiceName("dev.lamp.app.pong.phones"))
        XCTAssertFalse(LGPhones.isServiceName("dev.lamp.dev.my-tree.app.pong.phones"), "LG's names take no minus sign")
        XCTAssertFalse(LGPhones.isServiceName("dev.lamp.app.2048.phones"), "nor a period followed by a digit")
    }

    // MARK: The game's page

    /// lamp.js's controllers in a context of their own, with the TV's service bridge, Lamp's gateway, sockets and timers
    /// stood in for. `posted` holds each ask of Lamp (`path`, `body`), answered by hand with `reply(i, ...)`/`refuse(i, ...)`.
    private func page(_ lampJS: String) throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, value in XCTFail(value?.toString() ?? "a script failed") }
        context.evaluateScript("""
            var window = this, posted = [], bridges = [], sockets = [], timers = [], errors = [];
            var console = { error: function () {}, log: function () {} };
            window.Lamp = {};
            var LampAI = { _post: function (path, body) {
              var ask = { path: path, body: body };
              posted.push(ask);
              return new Promise(function (resolve, reject) { ask.resolve = resolve; ask.reject = reject; });
            } };
            function PalmServiceBridge() { this.cancelled = false; bridges.push(this); }
            PalmServiceBridge.prototype.call = function (uri, params) { this.uri = uri; this.params = JSON.parse(params); };
            PalmServiceBridge.prototype.cancel = function () { this.cancelled = true; };
            function WebSocket(url) { this.url = url; this.readyState = 1; this.sent = []; sockets.push(this); }
            WebSocket.prototype.send = function (text) { this.sent.push(text); };
            WebSocket.prototype.close = function () {};
            function setTimeout(fn) { timers.push(fn); return timers.length; }
            function clearTimeout() {} function setInterval() { return 0; } function clearInterval() {}
            function flush() { var now = timers; timers = []; now.forEach(function (fn) { fn(); }); }
            function links(credential, port) {
              return { returnValue: true, renew: 15,
                links: [{ kind: 'relay', socket: 'ws://127.0.0.1:' + port + '/', app: 'dev.lamp.app.pong', credential: credential }] };
            }
            function answer(bridge, credential, port) { bridge.onservicecallback(JSON.stringify(links(credential, port))); }
            function lampAnswers(i, credential, port) { posted[i].resolve(links(credential, port)); }
            function lampRefuses(i, message) { posted[i].reject(new Error(message)); }
            """)
        context.evaluateScript(lampJS)
        context.evaluateScript("Lamp.controllers.onError(function (m) { errors.push(m); });")
        return context
    }

    private func packaged() throws -> String {
        String(decoding: try LGPhones.naming(Data(GameKit.controllersJS.utf8), service: service), as: UTF8.self)
    }

    private func settle(_ context: JSContext) {
        // Promise callbacks run once the script that settled them returns: a second evaluation sees them done.
        context.evaluateScript("flush();")
        context.evaluateScript("flush();")
    }

    func testOneBuildStartsItsPhonesOnWhicheverHostItChooses() throws {
        let context = try page(packaged())

        context.evaluateScript("Lamp.controllers.start({ host: 'game' }); flush();")
        XCTAssertEqual(context.evaluateScript("bridges[0].uri")?.toString(), "luna://\(service)/start")
        XCTAssertEqual(context.evaluateScript("bridges[0].params.subscribe")?.toBool(), true, "the subscription is the session")
        context.evaluateScript("answer(bridges[0], 'game-host', 41000); sockets[0].onopen();")
        XCTAssertEqual(context.evaluateScript("sockets[0].url")?.toString(), "ws://127.0.0.1:41000/")
        XCTAssertEqual(context.evaluateScript("JSON.parse(sockets[0].sent[0]).credential")?.toString(), "game-host")
        XCTAssertEqual(context.evaluateScript("posted.length")?.toInt32(), 0, "the game's own host never asks Lamp")
        context.evaluateScript("Lamp.controllers.stop();")
        XCTAssertEqual(context.evaluateScript("bridges[0].cancelled")?.toBool(), true, "stopping ends the game's session")

        // The same build, the other host: Lamp's relay, with the service packaged and left alone.
        context.evaluateScript("Lamp.controllers.start({ host: 'lamp' }); flush();")
        XCTAssertEqual(context.evaluateScript("posted[0].path")?.toString(), "/app/controller")
        XCTAssertEqual(context.evaluateScript("posted[0].body.host")?.toString(), "lamp")
        context.evaluateScript("lampAnswers(0, 'lamp-host', 47000);")
        settle(context)
        context.evaluateScript("sockets[1].onopen();")
        XCTAssertEqual(context.evaluateScript("sockets[1].url")?.toString(), "ws://127.0.0.1:47000/")
        XCTAssertEqual(context.evaluateScript("JSON.parse(sockets[1].sent[0]).credential")?.toString(), "lamp-host")
        XCTAssertEqual(context.evaluateScript("bridges.length")?.toInt32(), 1, "Lamp's host never touches the service")
        context.evaluateScript("Lamp.controllers.stop();")
        XCTAssertEqual(context.evaluateScript("JSON.stringify(posted[posted.length - 1].body)")?.toString(), #"{"stop":true,"host":"lamp"}"#,
                       "stopping ends Lamp's session")
        XCTAssertEqual(context.evaluateScript("posted.every(function (p) { return p.body.host === 'lamp'; })")?.toBool(), true,
                       "every ask while Lamp hosts, renewals included, is for Lamp")

        // No host: as before, whoever answers /app/controller where it runs.
        context.evaluateScript("var asked = posted.length; Lamp.controllers.start(); flush();")
        XCTAssertEqual(context.evaluateScript("posted[asked].path")?.toString(), "/app/controller")
        XCTAssertEqual(context.evaluateScript("JSON.stringify(posted[asked].body)")?.toString(), "{}")
        XCTAssertEqual(context.evaluateScript("bridges.length")?.toInt32(), 1)
    }

    func testAGameHostThatFailsIsSaidAndTriedAgainNeverLamp() throws {
        let context = try page(packaged())
        context.evaluateScript("""
            Lamp.controllers.start({ host: 'game' }); flush();
            bridges[0].onservicecallback(JSON.stringify({ returnValue: false, errorText: 'The link for phones couldn\\'t open on this TV.' }));
            flush();
            """)
        XCTAssertEqual(context.evaluateScript("errors[0]")?.toString(), "The link for phones couldn't open on this TV.")
        XCTAssertEqual(context.evaluateScript("bridges[0].cancelled")?.toBool(), true)
        XCTAssertEqual(context.evaluateScript("bridges[1].uri")?.toString(), "luna://\(service)/start", "it subscribes again")
        XCTAssertEqual(context.evaluateScript("posted.length")?.toInt32(), 0, "and never turns to Lamp")
    }

    func testALampHostThatFailsIsSaidAndTriedAgainNeverTheGame() throws {
        let context = try page(packaged())
        context.evaluateScript("Lamp.controllers.start({ host: 'lamp' }); flush(); lampRefuses(0, \"Couldn't reach Lamp on your Mac.\");")
        settle(context)
        XCTAssertEqual(context.evaluateScript("errors[0]")?.toString(), "Couldn't reach Lamp on your Mac.")
        XCTAssertEqual(context.evaluateScript("posted.length")?.toInt32(), 2, "Lamp is asked again")
        XCTAssertEqual(context.evaluateScript("posted[1].body.host")?.toString(), "lamp")
        XCTAssertEqual(context.evaluateScript("bridges.length")?.toInt32(), 0, "the packaged service is never used instead")
    }

    func testAGameHostWhereTheBuildHasNoneIsAskedForAndRefusedNotReplaced() throws {
        // No service packaged (a Samsung TV, an older LG TV, the TV preview): the ask says which host it wants, and the one
        // answering, Lamp, refuses it rather than host the phones itself.
        let context = try page(GameKit.controllersJS)
        context.evaluateScript("Lamp.controllers.start({ host: 'game' }); flush();")
        XCTAssertEqual(context.evaluateScript("posted[0].body.host")?.toString(), "game")
        context.evaluateScript("lampRefuses(0, 'This copy of the game has no host of its own for phones here.');")
        settle(context)
        XCTAssertEqual(context.evaluateScript("errors[0]")?.toString(), "This copy of the game has no host of its own for phones here.")
        XCTAssertEqual(context.evaluateScript("posted[1].body.host")?.toString(), "game", "asked again for the same host")
        XCTAssertEqual(context.evaluateScript("sockets.length + bridges.length")?.toInt32(), 0)
    }

    func testAnAnswerToAnEarlierStartIsNeverTaken() throws {
        let context = try page(packaged())
        // Lamp's answer arrives after the game stopped and started again on its own host: no socket to Lamp's relay.
        context.evaluateScript("Lamp.controllers.start({ host: 'lamp' }); flush(); Lamp.controllers.stop(); Lamp.controllers.start({ host: 'game' }); flush();")
        context.evaluateScript("lampAnswers(0, 'stale', 47000);")
        settle(context)
        XCTAssertEqual(context.evaluateScript("sockets.length")?.toInt32(), 0, "an answer for the session that ended is dropped")

        // The service's refresh for a subscription that's been replaced can't end the new one.
        context.evaluateScript("""
            answer(bridges[0], 'first', 41000); sockets[0].onopen();
            sockets[0].onclose({ code: 4005 }); flush();
            var lookup = bridges[1];
            Lamp.controllers.stop(); Lamp.controllers.start({ host: 'game' }); flush();
            lookup.onservicecallback(JSON.stringify({ returnValue: false, errorText: 'gone' }));
            """)
        XCTAssertEqual(context.evaluateScript("lookup.uri")?.toString(), "luna://\(service)/session")
        XCTAssertEqual(context.evaluateScript("bridges[2].uri")?.toString(), "luna://\(service)/start")
        XCTAssertEqual(context.evaluateScript("bridges[2].cancelled")?.toBool(), false, "the new subscription stands")
        XCTAssertEqual(context.evaluateScript("errors.length")?.toInt32(), 0)
    }

    func testAnUnknownHostOrASecondHostIsRefused() throws {
        let context = try page(packaged())
        context.evaluateScript("var refused = []; Lamp.controllers.start({ host: 'cloud' }).catch(function (e) { refused.push(e.message); });")
        context.evaluateScript("Lamp.controllers.start({ host: 'game' }); Lamp.controllers.start({ host: 'lamp' }).catch(function (e) { refused.push(e.message); });")
        settle(context)
        XCTAssertEqual(context.evaluateScript("refused.length")?.toInt32(), 2)
        XCTAssertEqual(context.evaluateScript("posted.length")?.toInt32(), 0, "the running game host is kept, Lamp isn't asked")
    }
}
