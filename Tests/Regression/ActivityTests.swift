import XCTest
import LampSidebarKit

/// How a turn's activity reads as the wait goes on: thinking phrases that turn over every 3.5 seconds and grow
/// stronger, a build that says when it runs long, and a named step shown as it is.
final class ActivityTests: XCTestCase {
    func testThinkingTurnsOverEveryFewSeconds() {
        XCTAssertEqual(Activity.words("Thinking", waited: 0), "Rubbing the lamp")
        XCTAssertEqual(Activity.words("Thinking", waited: 3.4), "Rubbing the lamp")
        XCTAssertEqual(Activity.words("Thinking", waited: 3.5), "Mulling it over")
        XCTAssertEqual(Activity.words("Thinking", waited: 7), "Picturing it")
    }

    /// The line never says a bare "Thinking", however short the think or whichever phrase it opens on.
    func testAThinkNeverSaysPlainThinking() {
        for start in [0, 1, 2, 3, 7, -5, 802_000_000] {
            for second in stride(from: 0.0, through: 400, by: 0.5) {
                XCTAssertNotEqual(Activity.words("Thinking", waited: second, start: start), "Thinking",
                                  "at \(second)s, opening on \(start)")
            }
        }
    }

    /// Thinks that begin at different moments open on different phrases, so a turn of short ones isn't one phrase.
    func testShortThinksOpenOnDifferentPhrases() {
        let openers = Set((0..<4).map { Activity.words("Thinking", waited: 0, start: $0) })
        XCTAssertEqual(openers, ["Rubbing the lamp", "Mulling it over", "Picturing it", "Turning it over"])
    }

    func testThinkingGrowsStrongerTheLongerItGoes() {
        XCTAssertEqual(Activity.words("Thinking", waited: 21), "Polishing the lamp")
        XCTAssertEqual(Activity.words("Thinking", waited: 63), "The genie is squinting at this one")
        XCTAssertEqual(Activity.words("Thinking", waited: 182), "Still on it, nothing's stuck")
        // Past the last tier it keeps turning over within it.
        let late = Set((0..<12).map { Activity.words("Thinking", waited: 600 + Double($0) * 3.5) })
        XCTAssertEqual(late, ["Still on it, nothing's stuck", "Big wishes take a few minutes", "The genie hasn't wandered off"])
    }

    func testBuildingSaysWhenItRunsLong() {
        XCTAssertEqual(Activity.words("Building…", waited: 29), "Building…")
        XCTAssertEqual(Activity.words("Building…", waited: 30), "Still building…")
        XCTAssertEqual(Activity.words("Building…", waited: 90), "Taking a little longer…")
    }

    /// Putting a change into the open app can compile for a minute and more; one phrase that long reads as stuck.
    func testUpdatingInPlaceSaysWhenItRunsLong() {
        XCTAssertEqual(Activity.words("Updating Hot Shelf in place…", waited: 29), "Updating Hot Shelf in place…")
        XCTAssertEqual(Activity.words("Updating Hot Shelf in place…", waited: 30), "Still updating…")
        XCTAssertEqual(Activity.words("Updating Hot Shelf in place…", waited: 90), "Taking a little longer…")
    }

    func testANamedStepStaysAsItIs() {
        XCTAssertEqual(Activity.words("Working on the interface", waited: 0), "Working on the interface")
        XCTAssertEqual(Activity.words("Working on the interface", waited: 300), "Working on the interface")
    }
}
