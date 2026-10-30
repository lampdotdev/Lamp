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

    /// A page that moved on while it was checked isn't sent: a copy never gets a file that's half written.
    func testACopyIsGivenOnlyThePageThatWasChecked() throws {
        let dir = folder.appendingPathComponent("wish")
        let web = dir.appendingPathComponent(TVTemplate.webFolder)
        try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
        try Data("<script src=\"lamp.js\"></script>".utf8).write(to: web.appendingPathComponent("index.html"))
        try Data("body { color: red }".utf8).write(to: web.appendingPathComponent("style.css"))
        var page = LampProject(id: "page-\(UUID().uuidString.prefix(8))", name: "Page", exe: "Page", dir: dir)
        page.platform = .tv
        let checked = PageCopies.hashes(of: page)
        XCTAssertNotNil(PageCopies.change(for: page, at: .tv, shell: "", given: nil, checked: checked))
        try Data("body { color: bl".utf8).write(to: web.appendingPathComponent("style.css"))
        XCTAssertNil(PageCopies.change(for: page, at: .tv, shell: "", given: nil, checked: checked))
    }

    private static func json(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}
