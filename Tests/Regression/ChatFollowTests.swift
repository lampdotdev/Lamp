import XCTest
@testable import Lamp

/// The chat follows a reply to its end only while it's at the end: scrolled up to read, it stays there until
/// it's scrolled back down.
final class ChatFollowTests: XCTestCase {
    func testScrollingUpStopsTheFollowing() {
        XCTAssertFalse(ChatFollow.following(was: true, move: .up, fromEnd: 300))
        // Even a small step: a reply written quickly would otherwise undo each one before the next.
        XCTAssertFalse(ChatFollow.following(was: true, move: .up, fromEnd: 6))
    }

    func testItStaysStoppedWhileScrolledUp() {
        XCTAssertFalse(ChatFollow.following(was: false, move: .down, fromEnd: 300))
        XCTAssertFalse(ChatFollow.following(was: false, move: .up, fromEnd: 900))
    }

    func testScrollingBackToTheEndStartsItAgain() {
        XCTAssertTrue(ChatFollow.following(was: false, move: .down, fromEnd: 0))
        XCTAssertTrue(ChatFollow.following(was: false, move: .down, fromEnd: ChatFollow.slack))
    }

    /// The chat getting shorter at its end (the activity row going away) moves the scroll view up with it,
    /// and the chat is still at its end.
    func testAMoveUpThatEndsAtTheEndKeepsFollowing() {
        XCTAssertTrue(ChatFollow.following(was: true, move: .up, fromEnd: 0))
    }

    func testFollowingDownKeepsFollowing() {
        XCTAssertTrue(ChatFollow.following(was: true, move: .down, fromEnd: 140))
    }

    /// A slow scroll moves the scroll view by less than a point at a time. The steps add up, and once they
    /// have stopped the following no later step of the same scroll starts it again, near the end or not.
    func testSmallStepsUpAddUpAndStayStopped() {
        let follow = ChatFollow()
        follow.moved(to: 1000, fromEnd: 0)
        var stopped = false
        for step in 1...100 {
            follow.moved(to: 1000 - 0.5 * CGFloat(step), fromEnd: 0.5 * CGFloat(step))
            if stopped { XCTAssertFalse(follow.atEnd, "following again at step \(step)") }
            stopped = stopped || !follow.atEnd
            // Two points up at the latest.
            if step >= 4 { XCTAssertTrue(stopped, "still following at step \(step)") }
        }
    }

    /// A move too small to say which way it went neither stops the following nor starts it.
    func testAMoveTooSmallToCountChangesNothing() {
        XCTAssertFalse(ChatFollow.following(was: false, move: .neither, fromEnd: 3))
        XCTAssertTrue(ChatFollow.following(was: true, move: .neither, fromEnd: 3))
    }

    func testAScrollUpThenBackToTheEnd() {
        let follow = ChatFollow()
        follow.moved(to: 1000, fromEnd: 0)
        follow.moved(to: 700, fromEnd: 300)
        XCTAssertFalse(follow.atEnd)
        // More arrives at the end: the scroll view doesn't move, and the chat stays where it is.
        follow.moved(to: 700, fromEnd: 520)
        XCTAssertFalse(follow.atEnd)
        follow.moved(to: 1210, fromEnd: 10)
        XCTAssertTrue(follow.atEnd)
    }
}
