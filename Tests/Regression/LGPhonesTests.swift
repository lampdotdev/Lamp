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

    /// lamp.js's controllers in a context of their own, with the TV's service bridge, sockets and timers stood in for.
    private func page(_ lampJS: String) throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, value in XCTFail(value?.toString() ?? "a script failed") }
        context.evaluateScript("""
            var window = this, posted = [], bridges = [], sockets = [], timers = [];
            var console = { error: function () {}, log: function () {} };
            window.Lamp = {};
            var LampAI = { _post: function (path) { posted.push(path); return new Promise(function () {}); } };
            function PalmServiceBridge() { this.cancelled = false; bridges.push(this); }
            PalmServiceBridge.prototype.call = function (uri, params) { this.uri = uri; this.params = JSON.parse(params); };
            PalmServiceBridge.prototype.cancel = function () { this.cancelled = true; };
            function WebSocket(url) { this.url = url; this.readyState = 1; this.sent = []; sockets.push(this); }
            WebSocket.prototype.send = function (text) { this.sent.push(text); };
            WebSocket.prototype.close = function () {};
            function setTimeout(fn) { timers.push(fn); return timers.length; }
            function clearTimeout() {} function setInterval() { return 0; } function clearInterval() {}
            function flush() { var now = timers; timers = []; now.forEach(function (fn) { fn(); }); }
            function answer(bridge, credential, port) {
              bridge.onservicecallback(JSON.stringify({ returnValue: true, renew: 15,
                links: [{ kind: 'relay', socket: 'ws://127.0.0.1:' + port + '/', app: 'dev.lamp.app.pong', credential: credential }] }));
            }
            """)
        context.evaluateScript(lampJS)
        return context
    }

    func testAPackagedGameStartsItsPhonesOnItsOwnServiceAndNeverAsksLamp() throws {
        let lampJS = String(decoding: try LGPhones.naming(Data(GameKit.controllersJS.utf8), service: service), as: UTF8.self)
        let context = try page(lampJS)
        context.evaluateScript("Lamp.controllers.start(); flush();")
        XCTAssertEqual(context.evaluateScript("bridges.length")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("bridges[0].uri")?.toString(), "luna://\(service)/start")
        XCTAssertEqual(context.evaluateScript("bridges[0].params.subscribe")?.toBool(), true, "the subscription is the session")

        context.evaluateScript("answer(bridges[0], 'first', 41000); sockets[0].onopen();")
        XCTAssertEqual(context.evaluateScript("sockets[0].url")?.toString(), "ws://127.0.0.1:41000/")
        XCTAssertEqual(context.evaluateScript("JSON.parse(sockets[0].sent[0]).credential")?.toString(), "first")

        // The session ended under the page (the service started afresh): it asks its service, not Lamp, for where things are now.
        context.evaluateScript("sockets[0].onclose({ code: 4005 }); flush();")
        XCTAssertEqual(context.evaluateScript("bridges[1].uri")?.toString(), "luna://\(service)/session")
        context.evaluateScript("answer(bridges[1], 'second', 41002); sockets[1].onopen();")
        XCTAssertEqual(context.evaluateScript("JSON.parse(sockets[1].sent[0]).credential")?.toString(), "second")

        context.evaluateScript("Lamp.controllers.stop();")
        XCTAssertEqual(context.evaluateScript("bridges[0].cancelled")?.toBool(), true, "stopping lets the service end the session")
        XCTAssertEqual(context.evaluateScript("posted.length")?.toInt32(), 0, "Lamp is never asked")
    }

    func testAServiceThatCannotStartIsSaidAndTriedAgain() throws {
        let lampJS = String(decoding: try LGPhones.naming(Data(GameKit.controllersJS.utf8), service: service), as: UTF8.self)
        let context = try page(lampJS)
        context.evaluateScript("""
            var errors = []; Lamp.controllers.onError(function (m) { errors.push(m); });
            Lamp.controllers.start(); flush();
            bridges[0].onservicecallback(JSON.stringify({ returnValue: false, errorText: 'The link for phones couldn\\'t open on this TV.' }));
            flush();
            """)
        XCTAssertEqual(context.evaluateScript("errors[0]")?.toString(), "The link for phones couldn't open on this TV.")
        XCTAssertEqual(context.evaluateScript("bridges[0].cancelled")?.toBool(), true)
        XCTAssertEqual(context.evaluateScript("bridges[1].uri")?.toString(), "luna://\(service)/start", "it subscribes again")
        XCTAssertEqual(context.evaluateScript("posted.length")?.toInt32(), 0, "and never turns to Lamp")
    }

    func testAGameWithoutTheServiceAsksLampAsBefore() throws {
        let context = try page(GameKit.controllersJS)
        context.evaluateScript("Lamp.controllers.start(); flush();")
        XCTAssertEqual(context.evaluateScript("posted[0]")?.toString(), "/app/controller")
        XCTAssertEqual(context.evaluateScript("bridges.length")?.toInt32(), 0)
    }
}
