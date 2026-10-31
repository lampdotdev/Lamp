import LampRelayKit
import WebKit
import XCTest
@testable import Lamp

/// A phone's page already open takes a newer page as the game is played: the game's own host serves it in place of the
/// one in the bundle (`ControllerRuntime.use`), and the real lamp-controller.js, in WebKit against the real page server
/// and relay, finds the new version and opens again as the same player, at a moment that loses nothing.
@MainActor
final class PhonePageUpdateTests: XCTestCase {
    private var folder: URL!
    private var runtime: ControllerRuntime!
    private var view: WKWebView!
    private var host: URLSessionWebSocketTask!
    private let game = "padgame"

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("phone-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try page("first").write(to: folder.appendingPathComponent("first"))
        runtime = ControllerRuntime(app: game, page: folder.appendingPathComponent("first"))
        runtime.hosts = { ["127.0.0.1", "localhost", "::1"] }
        runtime.linkHost = { "127.0.0.1" }
        let (status, answer) = runtime.startNow()
        XCTAssertEqual(status, 200)
        let link = try XCTUnwrap((answer["links"] as? [[String: Any]])?.first)
        // The game's side: the host, which asks for a phone's link.
        host = URLSession.shared.webSocketTask(with: URL(string: link["socket"] as! String)!)
        host.resume()
        try await host.send(.string(Self.json(["t": "hello", "app": game, "credential": link["credential"] as Any])))
        _ = try await host.receive()
        try await host.send(.string(#"{"t":"link"}"#))
        var url: URL?
        while url == nil {
            if case .string(let text) = try await host.receive(),
               let said = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], let address = said["url"] as? String {
                url = URL(string: address)
            }
        }
        view = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: WKWebViewConfiguration())
        view.load(URLRequest(url: try XCTUnwrap(url)))
        try await until("the phone has joined") { try await self.read("window.state") as? String == "connected" }
        try await until("the first page is showing") { try await self.read("document.title") as? String == "first" }
    }

    override func tearDown() {
        host?.cancel()
        runtime?.stop()
        try? FileManager.default.removeItem(at: folder)
    }

    /// `document.hidden` is held false: a web view in no window counts as hidden, and a page that's hidden doesn't check.
    private func page(_ name: String) -> ControllerSnapshot {
        let html = """
            <!doctype html><title>\(name)</title>
            <script>Object.defineProperty(document, 'hidden', { get: function () { return false; } });</script>
            <script src="lamp-controller.js"></script>
            <script>window.pad = LampController.connect({ onState: function (s) { window.state = s; }, busy: function () { return !!window.drawing; } });</script>
            """
        return ControllerSnapshot(files: [.init(path: "index.html", data: Data(html.utf8)),
                                          .init(path: "lamp-controller.js", data: Data(TVTemplate.phoneControllerJS.utf8))])
    }

    private func publish(_ name: String) throws {
        let snapshot = page(name)
        let target = folder.appendingPathComponent(name)
        try snapshot.write(to: target)
        runtime.useNow(page: target, version: snapshot.version)
    }

    private func read(_ script: String) async throws -> Any? { try await view.evaluateJavaScript(script) }

    private func until(_ what: String, seconds: Double = 12, _ done: () async throws -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if (try? await done()) == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        let seen = try? await read("document.documentElement.outerHTML.slice(0, 200) + ' | ' + location.href")
        XCTFail("Never: \(what); showing \(String(describing: seen))")
    }

    func testAnOpenPageOpensAgainFromANewerOneAsTheSamePlayer() async throws {
        try publish("second")
        try await until("the newer page is showing") { try await self.read("document.title") as? String == "second" }
        try await until("the phone is back") { try await self.read("window.state") as? String == "connected" }
        // Its player number stays: the game hears the same one back, and no new phone.
        let joined = try await heardByTheGame()
        XCTAssertEqual(Set(joined), [joined[0]], "the same player: \(joined)")
    }

    func testANewerPageWaitsForTheButtonHeldAndWhatThePageSaysIsBusy() async throws {
        _ = try await read("window.pad.button('a', true); window.drawing = true; 0")
        try publish("second")
        // Two checks' time, with the button held.
        try await Task.sleep(for: .seconds(7))
        var title = try await read("document.title") as? String
        XCTAssertEqual(title, "first", "a page doesn't open again under a held button")
        _ = try await read("window.pad.button('a', false); 0")
        try await Task.sleep(for: .seconds(4))
        title = try await read("document.title") as? String
        XCTAssertEqual(title, "first", "nor while the page says it's busy")
        _ = try await read("window.drawing = false; 0")
        try await until("the newer page is showing once nothing would be lost") { try await self.read("document.title") as? String == "second" }
    }

    /// The numbers the game was told joined, as the relay told it, in order.
    private func heardByTheGame() async throws -> [Int] {
        let listening = Task { [host] in
            var numbers: [Int] = []
            while let message = try? await host?.receive(), case .string(let text) = message {
                guard let said = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { continue }
                if said["t"] as? String == "joined", let number = said["player"] as? Int { numbers.append(number); self.joined.append(number) }
            }
            return numbers
        }
        try await Task.sleep(for: .seconds(1))
        listening.cancel()
        host.cancel()
        return joined
    }
    private var joined: [Int] = []

    private static func json(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}

/// What Lamp does with a change of a game's phone page: what's published is what was checked, and handing it to an open
/// game leaves alone a change of the game's own page that waits for Reload.
@MainActor
final class PhonePagePublishingTests: XCTestCase {
    private var work: URL!
    private var game: LampProject!
    private var web: URL { game.dir.appendingPathComponent("build/PadGame.app/Contents/Resources/Web") }
    private var source: URL { game.dir.appendingPathComponent(TVTemplate.phoneFolder) }

    override func setUpWithError() throws {
        work = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-phone-publish-test-\(UUID().uuidString)")
        let dir = work.appendingPathComponent("padgame")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try Data("engine: web".utf8).write(to: dir.appendingPathComponent(".lamp-game"))
        var game = LampProject(id: "padgame-\(UUID().uuidString.prefix(8))", name: "Pad Game", exe: "PadGame", dir: dir)
        game.platform = .game
        self.game = game
        try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try save("first")
        try TVs.publishPhone(try copyOfSource(), as: TVs.phoneFolder(for: game))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
        if let game { try? FileManager.default.removeItem(at: TVs.stagingFolder(for: game)) }
    }

    private func save(_ name: String) throws {
        try Data("<title>\(name)</title>".utf8).write(to: source.appendingPathComponent("index.html"))
    }

    private func copyOfSource() throws -> URL {
        let copy = work.appendingPathComponent("copy-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: source, to: copy)
        try FileManager.default.createDirectory(at: TVs.stagingFolder(for: game), withIntermediateDirectories: true)
        return copy
    }

    private func checkedVersion() throws -> String { try ControllerSnapshot.read(source).version }

    func testACopyThatIsntWhatWasCheckedStaysUnpublished() async throws {
        let before = TVs.phoneVersion(of: game)
        let checked = try checkedVersion()
        try save("saved after the check")
        let published = try await TVs.stagePhone(game, expecting: checked)
        XCTAssertFalse(published)
        XCTAssertEqual(TVs.phoneVersion(of: game), before)
        let now = try await TVs.stagePhone(game, expecting: try checkedVersion())
        XCTAssertTrue(now)
        XCTAssertEqual(TVs.phoneVersion(of: game), try checkedVersion())
    }

    /// One answer to the copy's ask, once Lamp has one for it.
    private func nextChange(after gen: Int) async -> [String: Any] {
        let (_, answer) = await PageLive.shared.poll(["place": "mac", "phone": true, "after": gen, "epoch": PageLive.shared.epoch], for: game)
        return answer
    }

    func testAPhonePageGoesInWithoutLettingGoOfAChangeHeldForReload() async throws {
        try Data("one".utf8).write(to: web.appendingPathComponent("game.js"))
        PageLive.shared.installed(game, at: .mac)
        let asking = Task { await nextChange(after: 0) }
        try await Task.sleep(for: .milliseconds(50))

        // A change the page holds for Reload.
        try Data("two".utf8).write(to: web.appendingPathComponent("game.js"))
        let held = Task { await PageLive.shared.put(game, at: .mac) }
        let first = await asking.value
        XCTAssertEqual(first["changed"] as? [String], ["game.js"])
        _ = PageLive.shared.state(["place": "mac", "state": "held", "gen": first["gen"] as Any], for: game)
        let heldOutcome = await held.value
        XCTAssertEqual(heldOutcome, .held)

        // Then only the phone page changes.
        try save("second")
        try TVs.publishPhone(try copyOfSource(), as: TVs.phoneFolder(for: game))
        let phoneAsk = Task { await nextChange(after: first["gen"] as? Int ?? 0) }
        try await Task.sleep(for: .milliseconds(50))
        let phone = Task { await PageLive.shared.put(game, at: .mac) }
        let second = await phoneAsk.value
        XCTAssertEqual(second["changed"] as? [String], [], "the game's page isn't told of a change of the phone page")
        XCTAssertNotNil(second["phone"])
        _ = PageLive.shared.state(["place": "mac", "state": "phone", "gen": second["gen"] as Any], for: game)
        let phoneOutcome = await phone.value
        XCTAssertEqual(phoneOutcome, .held, "the Reload stays")
        XCTAssertTrue(PageLive.shared.holds(game))

        // Reload still puts the page's own change in.
        XCTAssertTrue(PageLive.shared.putInNow(game))
        let third = await nextChange(after: second["gen"] as? Int ?? 0)
        XCTAssertEqual(third["changed"] as? [String], ["game.js"])
        XCTAssertEqual(third["now"] as? Bool, true)
    }
}
