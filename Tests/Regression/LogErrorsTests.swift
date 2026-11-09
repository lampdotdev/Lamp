import XCTest
@testable import Lamp

/// What a change brought to an app's log: only errors that came after the change and never before it reach the agent,
/// so a broken change is fixed in its turn without the agent being sent after errors that were already there.
final class LogErrorsTests: XCTestCase {
    func testOnlyErrorsNewSinceTheChange() {
        let before = """
        Launched Nov 4, 2026 at 10:00:00 AM
        [0.50 s] Error: WebGL Device Lost (main.js:12)
        [1.00 s] built the harbor

        """
        let known = LogErrors.keys(in: before)
        let mark = LogErrors.mark(of: Data(before.utf8))
        let after = before + """
        [9.10 s] boat rental open
        [9.20 s] road work placed
        [9.30 s] Error: All geometries must have compatible attributes; make sure index attribute exists among all geometries, or in none of them
        [9.31 s] Error: All geometries must have compatible attributes; make sure index attribute exists among all geometries, or in none of them
        [9.40 s] Error: WebGL Device Lost (main.js:15)
        [9.50 s] Warning: texture too big
        Refresh failed: Error Domain=NSURLErrorDomain Code=-1009

        """
        let found = LogErrors.errors(in: LogErrors.since(mark, in: Data(after.utf8)), besides: known)
        XCTAssertEqual(found.count, 1, "the error that was there before (at a line that moved) and the non-errors aren't new")
        XCTAssertEqual(found.first?.count, 2)
        XCTAssertEqual(found.first?.context, ["[9.10 s] boat rental open", "[9.20 s] road work placed"])

        // The app opened again: its new log is read whole, and what was there before still isn't new.
        let relaunched = "Launched Nov 4, 2026 at 10:05:00 AM\n[0.40 s] Error: WebGL Device Lost (main.js:12)\nFatal error: Unexpectedly found nil\n"
        let again = LogErrors.errors(in: LogErrors.since(mark, in: Data(relaunched.utf8)), besides: known)
        XCTAssertEqual(again.map(\.line), ["Fatal error: Unexpectedly found nil"])
    }
}
