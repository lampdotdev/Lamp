import XCTest
import LampSidebarKit

/// The chat beside an app gives up waiting on Lamp once nothing it could show has come for a while, however often it
/// reconnected meanwhile: a sidebar Lamp turns away is tried again twice a second, and the spinner used to turn for
/// good because each new try started the wait afresh.
final class ChatWaitTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    /// Turned away on every try: the drops don't start the count again.
    func testRefusedOverAndOverStopsWaiting() {
        var wait = ChatWait(from: start)
        for tenth in stride(from: 5, through: 120, by: 5) {
            wait.dropped(at: start.addingTimeInterval(Double(tenth) / 10))
        }
        XCTAssertFalse(wait.isStuck(at: start.addingTimeInterval(ChatWait.patience - 1)))
        XCTAssertTrue(wait.isStuck(at: start.addingTimeInterval(ChatWait.patience)))
    }

    /// Connected, with nothing readable ever sent: no drop at all, and still it stops waiting.
    func testConnectedWithNothingReadableStopsWaiting() {
        let wait = ChatWait(from: start)
        XCTAssertTrue(wait.isStuck(at: start.addingTimeInterval(ChatWait.patience + 1)))
    }

    /// A chat that's read ends the wait; losing the connection after it starts a new one from then.
    func testAChatReadEndsTheWaitAndALaterDropStartsANewOne() {
        var wait = ChatWait(from: start)
        wait.read()
        XCTAssertFalse(wait.isStuck(at: start.addingTimeInterval(60)))
        wait.dropped(at: start.addingTimeInterval(60))
        wait.dropped(at: start.addingTimeInterval(65))
        XCTAssertFalse(wait.isStuck(at: start.addingTimeInterval(69)))
        XCTAssertTrue(wait.isStuck(at: start.addingTimeInterval(70)))
        wait.read()
        XCTAssertFalse(wait.isStuck(at: start.addingTimeInterval(80)))
    }
}
