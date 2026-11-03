import JavaScriptCore
import Network
import XCTest
@testable import Lamp

/// A game is checked in the window the person plays it in, never a copy of Lamp's own: `use_app` holds Lamp's own
/// controller there (lamp-game.js, "Lamp's hands on the controller"), a look with `reopen` starts it from its beginning
/// with its saves kept, and a game that reaches the person's devices is pressed or opened only on a device they allowed.
@MainActor
final class GameInWindowTests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        folders = []
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("game-window-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folders.append(url)
        return url
    }

    // MARK: Lamp's controller in the game's page

    /// The runtime with a clock, a controller of the person's (`testPad`), a phone's buttons (`testPhone`) and the
    /// message the page sends the app when the person takes the game back (`testTaken`); a game that keeps its first pad.
    private func playing() throws -> (JSContext, () -> [String: Any]) {
        var failed: String?
        let context = try GameRuntimePage.load(page: """
            var testNow = 1000, testTaken = [], testPad = null, testPhone = null;
            var performance = { now: function () { return testNow; } };
            navigator.getGamepads = function () { return testPad ? [testPad] : []; };
            window.webkit = { messageHandlers: { lampDriveTakenOver: { postMessage: function (why) { testTaken.push(why); } } } };
            var testAxis = null, testMessage = null;
            window.Lamp = { controllers: { onButton: function (fn) { testPhone = fn; }, onLeave: function () {}, players: function () { return []; },
                                           onAxis: function (fn) { testAxis = fn; }, onMessage: function (fn) { testMessage = fn; } } };
            var seen = { pad: null };
            """) { failed = failed ?? $0 }
        context.evaluateScript("game({ renderer: testRenderer, frame: function (f) { seen.pad = Object.assign({}, f.pads[0]); } });")
        let step = { () -> [String: Any] in
            context.evaluateScript("testNow += 16; testFrames.splice(0).forEach(function (fn) { fn(testNow); });")
            XCTAssertNil(failed)
            return context.evaluateScript("seen.pad")?.toDictionary() as? [String: Any] ?? [:]
        }
        _ = step()
        return (context, step)
    }

    private func taken(_ context: JSContext) -> [String] {
        context.evaluateScript("testTaken")?.toArray() as? [String] ?? []
    }

    /// Lamp's hold is the first player while it lasts, the press a press the frame it begins, and gone when the app
    /// lets go (a batch moving on, stopped or replaced): the frame after has nothing held.
    func testLampsHoldIsTheFirstPlayerUntilLetGo() throws {
        let (context, step) = try playing()
        context.evaluateScript("__lampDrive({ lx: 1, ly: 0.5, down: 1, seconds: 1 })")
        let held = step()
        XCTAssertEqual(held["lx"] as? Double, 1)
        XCTAssertEqual(held["ly"] as? Double, 0.5)
        XCTAssertEqual(held["down"] as? Int, 1)
        XCTAssertEqual(held["pressed"] as? Int, 1)
        XCTAssertEqual(step()["pressed"] as? Int, 0, "a press is a press for one frame")
        context.evaluateScript("__lampDrive(null)")
        let free = step()
        XCTAssertEqual(free["down"] as? Int, 0)
        XCTAssertEqual(free["lx"] as? Double, 0)
        XCTAssertEqual(free["released"] as? Int, 1)
        XCTAssertEqual(taken(context), [], "the app let go itself: nothing to tell it")
    }

    /// The person's controller moved while Lamp holds the first player: Lamp lets go at once, never mixing the two,
    /// the frame is the person's, and the app is told, which ends Lamp's batch.
    func testThePersonsControllerTakesTheGameBack() throws {
        let (context, step) = try playing()
        context.evaluateScript("__lampDrive({ rx: -1, seconds: 5 })")
        XCTAssertEqual(step()["rx"] as? Double, -1)
        context.evaluateScript("""
            testPad = { id: 'Xbox Wireless Controller', connected: true, axes: [0.9, 0, 0, 0],
                        buttons: Array.from({ length: 16 }, function () { return { pressed: false, value: 0 }; }) };
            """)
        let theirs = step()
        XCTAssertEqual(theirs["rx"] as? Double, 0, "Lamp's right stick is let go")
        XCTAssertGreaterThan(theirs["lx"] as? Double ?? 0, 0.8, "the person's left stick is what the game reads")
        XCTAssertEqual(taken(context), ["the person played"])
        // Their controller back at rest: nothing of Lamp's comes back.
        context.evaluateScript("testPad.axes = [0, 0, 0, 0];")
        XCTAssertEqual(step()["rx"] as? Double, 0)
    }

    /// A phone's button pressed while Lamp holds the controller takes the game back too.
    func testAPhonesPressTakesTheGameBack() throws {
        let (context, step) = try playing()
        context.evaluateScript("__lampDrive({ down: 2, seconds: 5 })")
        XCTAssertEqual(step()["down"] as? Int, 2)
        context.evaluateScript("testPhone(1, 'a', true)")
        XCTAssertEqual(step()["down"] as? Int, 0)
        XCTAssertEqual(taken(context), ["a phone played"])
    }

    /// The controller is Lamp's for the whole batch, not only while a move is held: the person's controller during a
    /// `wait`, or between two presses, takes the game back and ends the rest of the batch. Once the batch is over it's
    /// theirs, and their play says nothing to the app.
    func testThePersonsInputDuringAWaitTakesTheGameBack() throws {
        let (context, step) = try playing()
        context.evaluateScript("__lampOwn(20)")
        XCTAssertEqual(step()["lx"] as? Double, 0, "nothing held: a wait")
        context.evaluateScript("""
            testPad = { id: 'Xbox Wireless Controller', connected: true, axes: [0, 0, 0, 0],
                        buttons: Array.from({ length: 16 }, function (_, i) { return { pressed: i === 0, value: i === 0 ? 1 : 0 }; }) };
            """)
        XCTAssertEqual(step()["down"] as? Int, 1, "the person's press is what the game reads")
        XCTAssertEqual(taken(context), ["the person played"])
        // A later hold of the same batch, had the app not stopped it, would be refused by nothing here: the app's stop
        // is what ends it. With the batch over, the person's play is just theirs.
        context.evaluateScript("__lampOwn(null); testTaken = [];")
        _ = step()
        XCTAssertEqual(taken(context), [])
    }

    /// A phone's stick moved, or anything a phone sends, takes the game back as its buttons do; a phone held still at an
    /// angle, saying the same tilt again and again, doesn't.
    func testAPhonesStickOrMessageTakesTheGameBack() throws {
        let (context, _) = try playing()
        context.evaluateScript("testAxis(1, 'tilt', 0.5, 0); __lampOwn(20); testAxis(1, 'tilt', 0.5, 0); testAxis(1, 'tilt', 0.52, 0.01);")
        XCTAssertEqual(taken(context), [], "a phone lying tilted isn't someone playing")
        context.evaluateScript("testAxis(1, 'stick', 0, -0.9)")
        XCTAssertEqual(taken(context), ["a phone played"])
        context.evaluateScript("testTaken = []; __lampOwn(20); testMessage(1, { pick: 'red' });")
        XCTAssertEqual(taken(context), ["a phone sent something"])
    }

    /// The batch's own hold on the controller ends by itself, a while after the time it was given, should the app never
    /// say: the person's later play is then theirs and stops nothing.
    func testABatchsHoldOnTheControllerEndsByItself() throws {
        let (context, step) = try playing()
        context.evaluateScript("__lampOwn(1); testNow += 3100;")
        _ = step()
        context.evaluateScript("testPhone(1, 'a', true)")
        XCTAssertEqual(taken(context), [])
    }

    /// Should the app never say (it quit, or hung), a hold ends by itself a second after it was due.
    func testAHoldEndsByItselfWhenTheAppNeverLetsGo() throws {
        let (context, step) = try playing()
        context.evaluateScript("__lampDrive({ ly: 1, seconds: 0.5 })")
        XCTAssertEqual(step()["ly"] as? Double, 1)
        context.evaluateScript("testNow += 1200")
        XCTAssertEqual(step()["ly"] as? Double, 1, "still within its second of grace")
        context.evaluateScript("testNow += 400")
        XCTAssertEqual(step()["ly"] as? Double, 0)
        XCTAssertEqual(taken(context), [])
    }

    /// The buttons Lamp holds are the runtime's own bits, by the names the agent uses.
    func testTheButtonsLampHoldsAreTheRuntimes() throws {
        let context = try GameRuntimePage.load { XCTFail($0) }
        let runtime = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/GameKit/web/lamp-game.js"), encoding: .utf8)
        let line = try XCTUnwrap(runtime.range(of: #"export const BUTTON = \{[^}]*\}"#, options: .regularExpression))
        let bits = try XCTUnwrap(context.evaluateScript("(" + runtime[line].dropFirst("export const BUTTON = ".count) + ")")?.toDictionary() as? [String: Int])
        let names = ["a": "A", "b": "B", "x": "X", "y": "Y", "lb": "LB", "rb": "RB", "menu": "MENU", "view": "VIEW", "up": "UP",
                     "down": "DOWN", "left": "LEFT", "right": "RIGHT", "ls": "LSTICK", "rs": "RSTICK"]
        XCTAssertEqual(Set(GameKit.buttons.keys), Set(names.keys))
        for (name, bit) in GameKit.buttons { XCTAssertEqual(bits[names[name]!], Int(bit), name) }

        let moves = GameKit.controls(for: [["action": "stick", "target": "right", "x": -1.0, "y": 0.5, "key": "rt", "amount": 2.0],
                                           ["action": "button", "key": "menu"], ["action": "wait", "amount": 30.0]])
        XCTAssertNil(moves.problem)
        XCTAssertEqual(moves.actions[0]["controller"] as? [String: Double], ["rx": -1, "ry": 0.5, "rt": 1])
        XCTAssertEqual(moves.actions[1]["controller"] as? [String: Double], ["down": 64])
        XCTAssertEqual(moves.actions[2]["amount"] as? Double, 10, "a hold is at most ten seconds, as a Mac app's key is")
        XCTAssertNotNil(GameKit.controls(for: [["action": "click", "x": 3.0, "y": 4.0]]).problem)
        XCTAssertNotNil(GameKit.controls(for: [["action": "button", "key": "start"]]).problem)
    }

    // MARK: A fresh start

    /// Opened for a fresh start (`lampFreshStart`, a launch Lamp asked for one), the game starts from its beginning:
    /// neither the place kept for its reopening nor the snapshot an older build left is restored, and both are gone, but
    /// the game's saves are the person's and stay. Without the flag the same page starts where the player was.
    func testAFreshStartKeepsTheSavesAndNothingElse() throws {
        func open(fresh: Bool) throws -> [String: Any] {
            var failed: String?
            let context = try GameRuntimePage.load(page: """
                var testSession = { 'lamp.live': JSON.stringify({ state: { level: 3 }, gen: 2 }) };
                var testLocal = { 'lamp.save.best': '42', 'lamp.live.last': JSON.stringify({ build: 'old', at: Date.now(), state: { level: 5 } }) };
                function testStore(kept) { return { getItem: function (k) { return k in kept ? kept[k] : null; },
                    setItem: function (k, v) { kept[k] = v; }, removeItem: function (k) { delete kept[k]; } }; }
                var sessionStorage = testStore(testSession), localStorage = testStore(testLocal);
                var location = { reload: function () {} };
                window.lampFreshStart = \(fresh);
                var seen = {};
                """) { failed = failed ?? $0 }
            context.evaluateScript("game({ renderer: testRenderer, init: function () { seen.place = pendingRestore(); }, frame: function () {} });")
            context.evaluateScript("if (testFrames.length) testFrames.shift()(1000);")
            context.evaluateScript("seen.session = testSession; seen.local = testLocal;")
            XCTAssertNil(failed)
            return context.evaluateScript("seen")?.toDictionary() as? [String: Any] ?? [:]
        }
        let fresh = try open(fresh: true)
        XCTAssertTrue(fresh["place"] is NSNull, "\(fresh)")
        XCTAssertNil((fresh["session"] as? [String: Any])?["lamp.live"])
        XCTAssertNil((fresh["local"] as? [String: Any])?["lamp.live.last"])
        XCTAssertEqual((fresh["local"] as? [String: Any])?["lamp.save.best"] as? String, "42")

        let kept = try open(fresh: false)
        XCTAssertEqual((kept["place"] as? [String: Any])?["level"] as? Int, 3, "an ordinary opening keeps the player's place")
    }

    // MARK: The person's devices

    /// An app that declares the local network, as one that controls the person's devices does.
    private func app(platform: Platform, marker: String?, declares: Bool = true) throws -> LampProject {
        let dir = try folder()
        if declares {
            try #"{"localNetwork":"Finds your lights to switch them."}"#.write(to: dir.appendingPathComponent(Template.Capabilities.file), atomically: true, encoding: .utf8)
        }
        if let marker { try marker.write(to: dir.appendingPathComponent(GameKit.marker), atomically: true, encoding: .utf8) }
        return LampProject(id: "lights", name: "Lights", exe: "Lights", dir: dir, platform: platform)
    }

    /// A web game that reaches devices is played in the window the person plays it in, on the real network: a use is
    /// refused unless it names a device they allowed, as any app's is.
    func testAWebGameThatReachesDevicesNeedsAnAllowedDevice() throws {
        let game = try app(platform: .game, marker: "A game made with Lamp.\nengine: web\n")
        XCTAssertTrue(DevicePermissions.reachesDevices(game))
        XCTAssertTrue(DevicePermissions.useNeedsDevice(game))
        XCTAssertTrue(DevicePermissions.useNeedsDevice(try app(platform: .game, marker: "A game made with Lamp.\n")))
        XCTAssertTrue(DevicePermissions.useNeedsDevice(try app(platform: .mac, marker: nil)))
    }

    /// Opening such a game, or starting it again, runs its device code with no one pressing anything: a look that does
    /// is held to the same device. Other apps' looks aren't, as before.
    func testOpeningAGameThatReachesDevicesNeedsAnAllowedDevice() throws {
        XCTAssertTrue(DevicePermissions.openNeedsDevice(try app(platform: .game, marker: "A game made with Lamp.\nengine: web\n")))
        XCTAssertFalse(DevicePermissions.openNeedsDevice(try app(platform: .mac, marker: nil)))
    }

    /// A game's phones join a relay of Lamp's own in the game, which declares nothing: a game with a phone page and no
    /// declaration of its own reaches no devices.
    func testAGamesPhonesArentDevices() throws {
        let game = try app(platform: .game, marker: "A game made with Lamp.\nengine: web\n", declares: false)
        let phone = game.dir.appendingPathComponent(TVTemplate.phoneFolder)
        try FileManager.default.createDirectory(at: phone, withIntermediateDirectories: true)
        try "<!doctype html><button>Go</button>".write(to: phone.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        XCTAssertFalse(DevicePermissions.reachesDevices(game))
        XCTAssertFalse(DevicePermissions.useNeedsDevice(game))
        XCTAssertFalse(DevicePermissions.openNeedsDevice(game))
    }

    /// A game made while its phones joined through a relay it declared the local network for: the declaration is for its
    /// phones, and pressing or opening the game needs no allowed device. Anything a device controller has and a phone host
    /// doesn't (an address on the home network in its page, Bonjour types to look for, Lamp's device blocks in its Swift,
    /// or no phone page at all) and it reaches devices again. The declaration itself is left as it is.
    func testAGameThatDeclaredTheNetworkForItsPhonesNeedsNoDevice() throws {
        func game(page code: String = "game({ renderer });", bonjour: Bool = false, phonePage: Bool = true, swift: String? = nil) throws -> LampProject {
            let dir = try folder()
            let capabilities = bonjour ? #"{"localNetwork":"Phones on your Wi-Fi join the game as controllers.","bonjourServices":["_sonos._tcp"]}"#
                : #"{"localNetwork":"Phones on your Wi-Fi join the game as controllers."}"#
            try capabilities.write(to: dir.appendingPathComponent(Template.Capabilities.file), atomically: true, encoding: .utf8)
            try "A game made with Lamp.\nengine: web\n".write(to: dir.appendingPathComponent(GameKit.marker), atomically: true, encoding: .utf8)
            let web = dir.appendingPathComponent(GameKit.webFolder)
            try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
            try "<script type=\"module\" src=\"game.js\"></script>".write(to: web.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
            try ("import { game } from './lamp-game.js';\n" + code).write(to: web.appendingPathComponent("game.js"), atomically: true, encoding: .utf8)
            if phonePage {
                let phone = dir.appendingPathComponent(TVTemplate.phoneFolder)
                try FileManager.default.createDirectory(at: phone, withIntermediateDirectories: true)
                try "<!doctype html><button>Go</button>".write(to: phone.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
            }
            if let swift {
                let sources = dir.appendingPathComponent("Sources")
                try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
                try swift.write(to: sources.appendingPathComponent("Native.swift"), atomically: true, encoding: .utf8)
            }
            return LampProject(id: "pad", name: "Pad", exe: "Pad", dir: dir, platform: .game)
        }
        let phones = try game()
        XCTAssertTrue(DevicePermissions.declaresNetworkOnlyForPhones(phones))
        XCTAssertFalse(DevicePermissions.reachesDevices(phones))
        XCTAssertFalse(DevicePermissions.useNeedsDevice(phones))
        XCTAssertFalse(DevicePermissions.openNeedsDevice(phones))
        XCTAssertNotNil(Template.Capabilities.load(phones).checked.localNetwork, "the declaration stays")

        XCTAssertTrue(DevicePermissions.useNeedsDevice(try game(page: "fetch('http://192.168.1.20:1400/MediaRenderer/AVTransport/Control');")))
        XCTAssertTrue(DevicePermissions.useNeedsDevice(try game(page: "const tv = 'http://living-room.local:8001';")))
        XCTAssertTrue(DevicePermissions.useNeedsDevice(try game(bonjour: true)))
        XCTAssertTrue(DevicePermissions.useNeedsDevice(try game(phonePage: false)))
        XCTAssertTrue(DevicePermissions.useNeedsDevice(try game(swift: "import Foundation\nlet tv = LampRoku.self")))
    }

    // MARK: Stopping a batch

    /// A turn's Stop reaches the `use_app` batch it has running: what the app is pressing is let go.
    func testStoppingTheTurnStopsItsBatch() {
        let turn = Store.Turn()
        var stopped = 0
        turn.stopUse = { stopped += 1 }
        turn.cancel()
        XCTAssertEqual(stopped, 1)
    }

    /// The stop sent to the app is the one its driver accepts: signed with the app's token over the batch it names.
    func testTheStopSentIsSignedForTheBatch() throws {
        let dir = try folder()
        let project = LampProject(id: "stop-" + UUID().uuidString, name: "Pad", exe: "Pad", dir: dir, platform: .game)
        let heard = expectation(description: "the stop")
        var info: [AnyHashable: Any] = [:]
        let watch = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Edition.notificationPrefix + "useAppStop.\(project.id)"), object: nil, queue: .main) { note in
            info = note.userInfo ?? [:]
            heard.fulfill()
        }
        defer { DistributedNotificationCenter.default().removeObserver(watch) }
        Store.stopUse("batch-1", in: project)
        wait(for: [heard], timeout: 5)
        let expected = Store.signature(over: "stop\nbatch-1", token: Template.token(for: project))
        XCTAssertEqual(info["id"] as? String, "batch-1")
        XCTAssertEqual(info["lampUseAppStopSignature"] as? String, expected)
        XCTAssertEqual(info["lampUseAppStop"] as? String, expected)
    }

    // MARK: A TypeScript game's build

    /// What a TypeScript game's build runs under: a Bun macro is the game's code run at build time, so this is what keeps
    /// a game that declares the local network from pressing a device as it's built.
    func testAnOfflineCommandReachesNoNetwork() async throws {
        let (listener, port, heard) = try await listen()
        defer { listener.cancel() }
        let project = LampProject(id: "pad", name: "Pad", exe: "Pad", dir: try folder(), platform: .game)
        let request = "/usr/bin/curl -s -m 3 -o /dev/null http://127.0.0.1:\(port)/keypress/Home"
        _ = await Sandbox.run(request, for: project, offline: true) { _ in }
        XCTAssertEqual(heard.count, 0, "an offline command reached the network")
        _ = await Sandbox.run(request, for: project) { _ in }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertGreaterThan(heard.count, 0, "the same command should be heard online, or this proves nothing")
    }

    private final class Heard: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func add() { lock.withLock { value += 1 } }
    }

    private func listen() async throws -> (NWListener, UInt16, Heard) {
        let listener = try NWListener(using: .tcp, on: .any)
        let heard = Heard()
        listener.newConnectionHandler = { connection in
            heard.add()
            connection.start(queue: .main)
            connection.send(content: Data("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { done in
            nonisolated(unsafe) var answered = false
            listener.stateUpdateHandler = { state in
                guard !answered else { return }
                switch state {
                case .ready: answered = true; done.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error): answered = true; done.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: .main)
        }
        return (listener, port, heard)
    }
}
