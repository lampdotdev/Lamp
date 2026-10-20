import XCTest
import LampSidebarKit

/// How a turn's activity reads as the wait goes on: thinking phrases that turn over every 3.5 seconds and grow
/// stronger, a build that says when it runs long, and a named step shown as it is.
final class ActivityTests: XCTestCase {
    func testThinkingTurnsOverEveryFewSeconds() {
        XCTAssertEqual(Activity.words("Thinking", waited: 0), "Thinking")
        XCTAssertEqual(Activity.words("Thinking", waited: 3.4), "Thinking")
        XCTAssertEqual(Activity.words("Thinking", waited: 3.5), "Mulling it over")
        XCTAssertEqual(Activity.words("Thinking", waited: 7), "Picturing it")
    }

    func testThinkingGrowsStrongerTheLongerItGoes() {
        XCTAssertEqual(Activity.words("Thinking", waited: 21), "Still thinking")
        XCTAssertEqual(Activity.words("Thinking", waited: 63), "Thinking hard about this one")
        XCTAssertEqual(Activity.words("Thinking", waited: 182), "Still on it, nothing's stuck")
        // Past the last tier it keeps turning over within it.
        let late = Set((0..<12).map { Activity.words("Thinking", waited: 600 + Double($0) * 3.5) })
        XCTAssertEqual(late, ["Still on it, nothing's stuck", "Big wishes take a few minutes", "Still here, still thinking"])
    }

    func testBuildingSaysWhenItRunsLong() {
        XCTAssertEqual(Activity.words("Building…", waited: 29), "Building…")
        XCTAssertEqual(Activity.words("Building…", waited: 30), "Still building…")
        XCTAssertEqual(Activity.words("Building…", waited: 90), "Taking a little longer…")
    }

    func testANamedStepStaysAsItIs() {
        XCTAssertEqual(Activity.words("Working on the interface", waited: 0), "Working on the interface")
        XCTAssertEqual(Activity.words("Working on the interface", waited: 300), "Working on the interface")
    }
}
