import XCTest

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
}
