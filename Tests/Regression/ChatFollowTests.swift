import XCTest
@testable import Lamp

/// The chat follows a reply to its end only while it's at the end: scrolled up to read, it stays there until
/// it's scrolled back down.
final class ChatFollowTests: XCTestCase {
    func testScrollingUpStopsTheFollowing() {
        XCTAssertFalse(ChatFollow.following(was: true, movedUp: true, fromEnd: 300))
        // Even a small step: a reply written quickly would otherwise undo each one before the next.
        XCTAssertFalse(ChatFollow.following(was: true, movedUp: true, fromEnd: 6))
    }

    func testItStaysStoppedWhileScrolledUp() {
        XCTAssertFalse(ChatFollow.following(was: false, movedUp: false, fromEnd: 300))
        XCTAssertFalse(ChatFollow.following(was: false, movedUp: true, fromEnd: 900))
    }

    func testScrollingBackToTheEndStartsItAgain() {
        XCTAssertTrue(ChatFollow.following(was: false, movedUp: false, fromEnd: 0))
        XCTAssertTrue(ChatFollow.following(was: false, movedUp: false, fromEnd: ChatFollow.slack))
    }

    /// The chat getting shorter at its end (the activity row going away) moves the scroll view up with it,
    /// and the chat is still at its end.
    func testAMoveUpThatEndsAtTheEndKeepsFollowing() {
        XCTAssertTrue(ChatFollow.following(was: true, movedUp: true, fromEnd: 0))
    }

    func testFollowingDownKeepsFollowing() {
        XCTAssertTrue(ChatFollow.following(was: true, movedUp: false, fromEnd: 140))
    }

    /// A slow scroll moves the scroll view by less than a point at a time. The steps add up: a hundred of
    /// half a point leave the chat fifty points from its end, and no longer following.
    func testSmallStepsUpAddUp() {
        let follow = ChatFollow()
        follow.moved(to: 1000, fromEnd: 0)
        for step in 1...100 { follow.moved(to: 1000 - 0.5 * CGFloat(step), fromEnd: 0.5 * CGFloat(step)) }
        XCTAssertFalse(follow.atEnd)
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
