import LampRelayKit
import Network
import WebKit
import XCTest
@testable import Lamp

/// A game whose phones join it isn't an app that controls devices, and the agent can see and press its real phone page in
/// the hidden preview.
@MainActor
final class GamePhonePreviewTests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        folders = []
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("game-phone-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folders.append(url)
        return url
    }

    /// An app that declares the local network, as a game does for the phones joining it.
    private func app(platform: Platform, marker: String?) throws -> LampProject {
        let dir = try folder()
        try #"{"localNetwork":"Phones on your Wi-Fi join the game as controllers."}"#.write(to: dir.appendingPathComponent(Template.Capabilities.file), atomically: true, encoding: .utf8)
        if let marker { try marker.write(to: dir.appendingPathComponent(GameKit.marker), atomically: true, encoding: .utf8) }
        return LampProject(id: "pad", name: "Pad", exe: "Pad", dir: dir, platform: platform)
    }

    func testAWebGameThatDeclaresTheLocalNetworkIsUsedInItsPreview() throws {
        let game = try app(platform: .game, marker: "A game made with Lamp.\nengine: web\n")
        XCTAssertTrue(DevicePermissions.reachesDevices(game))
        XCTAssertFalse(DevicePermissions.useNeedsDevice(game))
        XCTAssertEqual(GameKit.previewPolicy(game), NetworkPolicy(), "the exemption rests on the preview reaching no network")
    }

    func testOtherAppsThatDeclareTheLocalNetworkStillNeedAnAllowedDevice() throws {
        XCTAssertTrue(DevicePermissions.useNeedsDevice(try app(platform: .mac, marker: nil)))
        // A compiled game's preview is a process nothing holds off the network.
        XCTAssertTrue(DevicePermissions.useNeedsDevice(try app(platform: .game, marker: "A game made with Lamp.\n")))
    }

    func testAGameThatDeclaresNothingIsNotHeldBack() throws {
        let dir = try folder()
        try "engine: web\n".write(to: dir.appendingPathComponent(GameKit.marker), atomically: true, encoding: .utf8)
        XCTAssertNil(GameKit.previewPolicy(LampProject(id: "pad", name: "Pad", exe: "Pad", dir: dir, platform: .game)))
    }

    /// A real request from a real page: a web view held as the preview holds it must not reach an address on this Mac,
    /// and the same page unheld does, which is what shows the listener would have heard it.
    func testAHeldPreviewReachesNoNetwork() async throws {
        let (listener, port, heard) = try await listen()
        defer { listener.cancel() }
        func play(_ policy: NetworkPolicy?) async throws {
            let page = try folder()
            try """
                <!doctype html><script>
                fetch('http://127.0.0.1:\(port)/keypress/Home', { method: 'POST', mode: 'no-cors' }).catch(function () {}).finally(function () {
                  window.webkit.messageHandlers.lampPreview.postMessage({ done: true, logs: [] });
                });
                </script>
                """.write(to: page.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
            let played = await WebGamePreview.play(page, script: [], for: UUID().uuidString, policy: policy)
            XCTAssertNotNil(played)
        }
        try await play(NetworkPolicy())
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(heard.count, 0, "the held page reached the network")
        try await play(nil)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertGreaterThan(heard.count, 0, "the unheld page should have been heard, or this proves nothing")
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

    // MARK: The real page in real WebKit

    /// A controller as a game's Phone/ has one: a held button, a thumb stick that captures its pointer, a name field, and
    /// what it does when the link goes.
    private func page() throws -> URL {
        let dir = try folder()
        try """
            <!doctype html><meta name="viewport" content="width=device-width, viewport-fit=cover">
            <style>
              body { margin: 0; }
              #go { position: absolute; left: 600px; top: 100px; width: 200px; height: 200px; touch-action: none; }
              #stick { position: absolute; left: 40px; top: 100px; width: 200px; height: 200px; touch-action: none; background: #ccc; }
              #turn { display: none; }
              @media (orientation: portrait) { #turn { display: block; } #go, #stick { display: none; } }
            </style>
            <div id="state">starting</div><div id="turn">Turn your phone sideways</div>
            <input id="name"><button id="go">Hop</button><div id="stick"></div>
            <script src="lamp-controller.js"></script>
            <script>
              var pad = LampController.connect({
                onState: function (s) { document.getElementById('state').textContent = s; },
                onPlayer: function (n) { pad.send({ hello: n }); }
              });
              var go = document.getElementById('go'), stick = document.getElementById('stick'), held = false;
              go.addEventListener('pointerdown', function () { held = true; pad.button('a', true); });
              go.addEventListener('pointerup', function () { held = false; pad.button('a', false); });
              window.addEventListener('orientationchange', function () { if (held) { held = false; pad.button('a', false); } });
              stick.addEventListener('pointerdown', function (e) { stick.setPointerCapture(e.pointerId); });
              stick.addEventListener('pointermove', function (e) { if (stick.hasPointerCapture(e.pointerId)) pad.axis('stick', (e.clientX - 140) / 100, 0); });
              document.getElementById('name').addEventListener('change', function (e) { pad.send({ name: e.target.value }); });
            </script>
            """.write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try Data(TVTemplate.phoneControllerJS.utf8).write(to: dir.appendingPathComponent("lamp-controller.js"))
        try Data(#"{"port":1,"app":"preview"}"#.utf8).write(to: dir.appendingPathComponent("lamp-relay.json"))
        return dir
    }

    private func messages(_ answer: String) -> [[String: Any]] {
        ((try? JSONSerialization.jsonObject(with: Data(answer.utf8))) as? [String: Any])?["messages"] as? [[String: Any]] ?? []
    }

    func testTheRealPageJoinsAndItsControlsReachTheGame() async throws {
        let phone = PhonePreview()
        let opened = await phone.open(try page())
        XCTAssertTrue(opened)
        defer { phone.close() }

        var said = messages(await phone.step(["do": "sync"], inbox: "[]", hosted: true))
        XCTAssertEqual(said.first?["t"] as? String, "hello", "lamp-controller.js opened its link through the stand-in")
        said = messages(await phone.step(["do": "sync"], inbox: #"[{"t":"player","number":2}]"#, hosted: true))
        XCTAssertEqual((said.first?["data"] as? [String: Any])?["hello"] as? Int, 2, "the page heard its player number")

        said = messages(await phone.step(["do": "down", "target": "#go"], inbox: "[]", hosted: true))
        XCTAssertEqual(said.first?["t"] as? String, "button")
        XCTAssertEqual(said.first?["down"] as? Bool, true)
        said = messages(await phone.step(["do": "up"], inbox: "[]", hosted: true))
        XCTAssertEqual(said.first?["down"] as? Bool, false)

        // A thumb stick that captures its finger, which WebKit refuses a synthetic finger on its own.
        _ = await phone.step(["do": "down", "x": 140.0, "y": 200.0], inbox: "[]", hosted: true)
        said = messages(await phone.step(["do": "move", "x": 240.0, "y": 200.0], inbox: "[]", hosted: true))
        XCTAssertEqual(said.last?["t"] as? String, "axis")
        XCTAssertEqual(try XCTUnwrap(said.last?["x"] as? Double), 1, accuracy: 0.01)
        _ = await phone.step(["do": "up"], inbox: "[]", hosted: true)

        said = messages(await phone.step(["do": "type", "target": "#name", "text": "Ada"], inbox: "[]", hosted: true))
        XCTAssertEqual((said.first?["data"] as? [String: Any])?["name"] as? String, "Ada")

        let report = await phone.report()
        XCTAssertEqual(report.link, "joined")
        XCTAssertEqual(report.player, 2)
        XCTAssertEqual(report.size.width, 844, "the phone preview opens sideways")
        XCTAssertEqual(report.size.height, 390)
        XCTAssertTrue(report.screen.contains { $0.contains("#go") && $0.contains("600 100 200 200") }, report.screen.joined(separator: "\n"))
        XCTAssertTrue(report.sent.contains("button a down"))
    }

    func testTurningUprightMidPressReachesThePageAndItsCSS() async throws {
        let phone = PhonePreview()
        let opened = await phone.open(try page())
        XCTAssertTrue(opened)
        defer { phone.close() }
        _ = await phone.step(["do": "sync"], inbox: "[]", hosted: true)
        _ = await phone.step(["do": "down", "target": "#go"], inbox: "[]", hosted: true)

        let said = messages(await phone.step(["do": "rotate", "direction": "up"], inbox: "[]", hosted: true))
        XCTAssertEqual(said.first?["t"] as? String, "button", "the page let go of what was held as it turned")
        XCTAssertEqual(said.first?["down"] as? Bool, false)

        let report = await phone.report()
        XCTAssertEqual(report.size.width, 390)
        XCTAssertEqual(report.size.height, 844)
        XCTAssertTrue(report.screen.contains { $0.contains("Turn your phone sideways") }, report.screen.joined(separator: "\n"))
        XCTAssertFalse(report.screen.contains { $0.contains("#go") }, "the page's own portrait rule hid its controls")
    }

    func testALostLinkIsSeenByThePageAndTheGameAndComesBack() async throws {
        let phone = PhonePreview()
        let opened = await phone.open(try page())
        XCTAssertTrue(opened)
        defer { phone.close() }
        _ = await phone.step(["do": "sync"], inbox: "[]", hosted: true)

        let lost = messages(await phone.step(["do": "link", "what": "lost"], inbox: "[]", hosted: true))
        XCTAssertEqual(lost.first?["t"] as? String, "bye")
        let dropped = await phone.report()
        XCTAssertEqual(dropped.link, "link lost")

        let back = messages(await phone.step(["do": "link", "what": "back"], inbox: "[]", hosted: true))
        XCTAssertEqual(back.first?["t"] as? String, "hello", "the page's own retry found the link again")
    }

    func testThePictureIsOnePixelToACSSPixel() async throws {
        let phone = PhonePreview()
        let opened = await phone.open(try page())
        XCTAssertTrue(opened)
        defer { phone.close() }
        let taken = await phone.picture()
        let picture = try XCTUnwrap(taken)
        let image = try XCTUnwrap(NSBitmapImageRep(data: picture))
        XCTAssertEqual(image.pixelsWide, 844)
        XCTAssertEqual(image.pixelsHigh, 390)
    }

    // MARK: use_app's moves

    func testAPhoneActionPlaysAmongTheFramesAndEndsInAPicture() throws {
        let moves = GameKit.script(for: [["action": "click", "phone": true, "target": "Hop"]], startingAt: 3)
        XCTAssertNil(moves.problem)
        XCTAssertEqual(moves.lines.first, #"phone {"do":"down","target":"Hop"}"#)
        XCTAssertTrue(moves.lines.contains(#"phone {"do":"up"}"#))
        XCTAssertEqual(moves.lines.last, "shot 4")
    }

    func testAPhoneActionSaysWhatItLacks() {
        XCTAssertNotNil(GameKit.script(for: [["action": "click", "phone": true]], startingAt: 0).problem)
        XCTAssertNotNil(GameKit.script(for: [["action": "rotate", "phone": true, "direction": "sideways"]], startingAt: 0).problem)
        XCTAssertNotNil(GameKit.script(for: [["action": "stick", "phone": true]], startingAt: 0).problem)
    }
}
