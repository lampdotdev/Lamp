import XCTest
@testable import Lamp

/// Which blocked site a shared page shows a bar for (`LampPageRefusals` in LampPage.swift), compiled from its own source
/// and run: one bar at a time, each site once; a site whose bar the person closed brings no bar back for the rest of the
/// launch, in this page or any other, however often the page asks for it again; a site waiting its turn that the
/// person has allowed meanwhile (that site, or every site) gets no bar.
final class BlockedSiteBarTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func run(_ driver: String) throws -> [String] {
        let page = try String(contentsOf: root.appendingPathComponent("Resources/GameKit/apple/LampPage.swift"), encoding: .utf8)
        let start = try XCTUnwrap(page.range(of: "@MainActor struct LampPageRefusals {"))
        let end = try XCTUnwrap(page.range(of: "\n}\n", range: start.upperBound..<page.endIndex))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("blocked-bar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let main = "import Foundation\n" + page[start.lowerBound..<end.upperBound] + """
            var allowed: Set<String> = [], every = false
            func blocked(_ site: String) -> Bool { !every && !allowed.contains(site) }
            func say(_ shown: String?) { print(shown ?? "-") }
            MainActor.assumeIsolated {
            \(driver)
            }
            """
        try main.write(to: dir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let built = Process(), out = Pipe()
        built.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        built.arguments = ["swiftc", dir.appendingPathComponent("main.swift").path, "-o", dir.appendingPathComponent("bars").path]
        built.standardOutput = out
        built.standardError = out
        try built.run()
        let log = out.fileHandleForReading.readDataToEndOfFile()
        built.waitUntilExit()
        XCTAssertEqual(built.terminationStatus, 0, String(decoding: log, as: UTF8.self))
        let ran = Process(), said = Pipe()
        ran.executableURL = dir.appendingPathComponent("bars")
        ran.standardOutput = said
        try ran.run()
        let text = String(decoding: said.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ran.waitUntilExit()
        return text.split(separator: "\n").map(String.init)
    }

    /// The first refusal shows one bar; once it's closed, two more refusals of that site show none, and neither does a
    /// page made afresh (another window, the page opened again) that's refused it.
    func testAClosedSiteStaysQuietForTheLaunch() throws {
        let said = try run("""
            var bars = LampPageRefusals()
            say(bars.heard("https://tiles.example", blocked: blocked))
            say(bars.gone(closed: true, blocked: blocked))
            say(bars.heard("https://tiles.example", blocked: blocked))
            say(bars.heard("https://tiles.example", blocked: blocked))
            var other = LampPageRefusals()
            say(other.heard("https://tiles.example", blocked: blocked))
            """)
        XCTAssertEqual(said, ["https://tiles.example", "-", "-", "-", "-"])
    }

    /// One bar at a time: a second site waits for the first to go, and is shown once, however often it's refused meanwhile.
    func testSitesWaitTheirTurn() throws {
        let said = try run("""
            var bars = LampPageRefusals()
            say(bars.heard("https://a.example", blocked: blocked))
            say(bars.heard("https://b.example", blocked: blocked))
            say(bars.heard("https://b.example", blocked: blocked))
            say(bars.heard("https://a.example", blocked: blocked))
            say(bars.gone(closed: true, blocked: blocked))
            say(bars.gone(closed: true, blocked: blocked))
            """)
        XCTAssertEqual(said, ["https://a.example", "-", "-", "-", "https://b.example", "-"])
    }

    /// Allow All before the bar goes: the site waiting behind it is let in too, so no bar follows. Allowing one site
    /// lets the next blocked one have its turn, and a closed bar's site isn't taken for allowed.
    func testWhatThePersonAllowedGetsNoBar() throws {
        let said = try run("""
            var bars = LampPageRefusals()
            say(bars.heard("https://a.example", blocked: blocked))
            say(bars.heard("https://b.example", blocked: blocked))
            every = true
            say(bars.gone(closed: false, blocked: blocked))
            every = false
            var more = LampPageRefusals()
            say(more.heard("https://c.example", blocked: blocked))
            say(more.heard("https://d.example", blocked: blocked))
            allowed.insert("https://c.example")
            say(more.gone(closed: false, blocked: blocked))
            say(more.heard("https://c.example", blocked: blocked))
            """)
        XCTAssertEqual(said, ["https://a.example", "-", "-", "https://c.example", "-", "https://d.example", "-"])
    }

    /// Two windows already showing bars: closing a site's bar in one takes the same site's bar away in the other, Allow
    /// All in one takes every other window's bar away, and allowing a site lets the other window's next site have its
    /// turn. A bar for a site nothing was decided about stays.
    func testWhatThePersonDoesInOneWindowSettlesTheOthers() throws {
        let said = try run("""
            func says(_ s: (dropped: Bool, next: String?)) { print((s.dropped ? "dropped " : "kept ") + (s.next ?? "-")) }
            var one = LampPageRefusals(), two = LampPageRefusals(), three = LampPageRefusals()
            say(one.heard("https://tiles.example", blocked: blocked))
            say(two.heard("https://tiles.example", blocked: blocked))
            say(three.heard("https://feed.example", blocked: blocked))
            say(one.gone(closed: true, blocked: blocked))
            says(two.settle(blocked: blocked))
            says(three.settle(blocked: blocked))
            var four = LampPageRefusals(), five = LampPageRefusals()
            say(four.heard("https://x.example", blocked: blocked))
            say(five.heard("https://x.example", blocked: blocked))
            say(five.heard("https://y.example", blocked: blocked))
            allowed.insert("https://x.example")
            say(four.gone(closed: false, blocked: blocked))
            says(five.settle(blocked: blocked))
            every = true
            say(five.gone(closed: false, blocked: blocked))
            says(three.settle(blocked: blocked))
            """)
        XCTAssertEqual(said, ["https://tiles.example", "https://tiles.example", "https://feed.example", "-", "dropped -", "kept -",
                              "https://x.example", "https://x.example", "-", "-", "dropped https://y.example", "-", "dropped -"])
    }

    /// Allowing a site opens every page again so the new rules reach it (`LampPageGuard.retirePages`), and each opens as
    /// Lamp's Reload opens it (`LampPageView.reopen`, cut from LampPage.swift and run in a real web view): a page that
    /// keeps its place over a reload the way a game's runtime does (`__lampReloadNow`) comes back where it was, and one
    /// without opens again from its files. A bare reload of the same page loses the place, which is what this guards.
    func testAPageOpenedAgainForNewRulesKeepsItsPlace() throws {
        let page = try String(contentsOf: root.appendingPathComponent("Resources/GameKit/apple/LampPage.swift"), encoding: .utf8)
        let start = try XCTUnwrap(page.range(of: "    // begin LampPageView.reopen"))
        let end = try XCTUnwrap(page.range(of: "    // end LampPageView.reopen", range: start.upperBound..<page.endIndex))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reopen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let main = """
            import AppKit
            import WebKit
            @MainActor enum LampPageView {
            \(page[start.upperBound..<end.lowerBound])
            }
            // A game's page in miniature: where the player is lives in the page, and its own reload saves it for the session.
            let game = \"\"\"
              <script>
              var opened = Number(sessionStorage.getItem('opened') || 0) + 1; sessionStorage.setItem('opened', opened);
              var place = sessionStorage.getItem('kept') || 'start'; sessionStorage.removeItem('kept');
              window.__lampReloadNow = function () { sessionStorage.setItem('kept', place); location.reload(); return true; };
              </script>
              \"\"\"
            let plain = "<script>var opened = Number(sessionStorage.getItem('opened') || 0) + 1; sessionStorage.setItem('opened', opened); var place = 'start';</script>"
            final class Files: NSObject, WKURLSchemeHandler {
                func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
                    let html = task.request.url?.path == "/game.html" ? game : plain
                    task.didReceive(URLResponse(url: task.request.url!, mimeType: "text/html", expectedContentLength: -1, textEncodingName: "utf-8"))
                    task.didReceive(Data(html.utf8))
                    task.didFinish()
                }
                func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
            }
            final class Loads: NSObject, WKNavigationDelegate {
                var count = 0
                func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { count += 1 }
            }
            @MainActor func wait(_ done: () -> Bool) {
                let limit = Date().addingTimeInterval(10)
                while !done(), Date() < limit { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            }
            @MainActor func ask(_ view: WKWebView, _ script: String) -> String {
                var said: String?
                view.evaluateJavaScript(script, in: nil, in: .page) { said = (try? $0.get()).map { "\\($0)" } ?? "error" }
                wait { said != nil }
                return said ?? "no answer"
            }
            @MainActor func run(_ file: String, reopen: (WKWebView) -> Void) -> String {
                let configuration = WKWebViewConfiguration()
                configuration.setURLSchemeHandler(Files(), forURLScheme: "test-page")
                let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 200), configuration: configuration)
                let loads = Loads()
                view.navigationDelegate = loads
                view.load(URLRequest(url: URL(string: "test-page://app/\\(file)")!))
                wait { loads.count == 1 }
                _ = ask(view, "place = 'level 3'")
                reopen(view)
                wait { loads.count == 2 }
                return ask(view, "place + ' ' + opened")
            }
            MainActor.assumeIsolated {
                _ = NSApplication.shared
                print(run("game.html") { LampPageView.reopen($0) })
                print(run("plain.html") { LampPageView.reopen($0) })
                print(run("game.html") { $0.reload() })
            }
            """
        try main.write(to: dir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let built = TestShell.run(Shell.compatibleSDK + "xcrun swiftc -o reopen main.swift 2>&1", in: dir)
        XCTAssertEqual(built.status, 0, built.output)
        let ran = TestShell.run("./reopen", in: dir)
        XCTAssertEqual(ran.output.split(separator: "\n").map(String.init), ["level 3 2", "start 2", "start 2"], ran.output)
    }
}
