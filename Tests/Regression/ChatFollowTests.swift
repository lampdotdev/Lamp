import AppKit
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

    /// Going back to the end after the chat got shorter is a move up, and it's the chat's own.
    func testTheChatsOwnMoveUpDoesNotStopTheFollowing() {
        let follow = ChatFollow()
        follow.moved(to: 501, fromEnd: 0)
        follow.byItself { follow.moved(to: 481, fromEnd: 16) }
        XCTAssertTrue(follow.atEnd)
        // The same move made by the person does.
        follow.moved(to: 461, fromEnd: 36)
        XCTAssertFalse(follow.atEnd)
    }

    /// The agent's questions are followed into view as they arrive, then the chat holds still until they're
    /// answered.
    func testWaitingQuestionsAreFollowedInAndThenHeldStill() {
        let follow = ChatFollow()
        let questions = UUID(), arrived = Date()
        follow.waiting(for: questions, at: arrived)
        XCTAssertTrue(follow.followsEnd(at: arrived.addingTimeInterval(0.1)))
        XCTAssertFalse(follow.followsEnd(at: arrived.addingTimeInterval(ChatFollow.arrival + 0.1)))
        // Hearing of the same questions again doesn't start the following again.
        follow.waiting(for: questions, at: arrived.addingTimeInterval(5))
        XCTAssertFalse(follow.followsEnd(at: arrived.addingTimeInterval(5.1)))
        follow.waiting(for: nil)
        XCTAssertTrue(follow.followsEnd())
    }

    // MARK: With a scroll view

    private final class Rows: NSView {
        override var isFlipped: Bool { true }
    }

    /// A chat 400 points tall holding 1000 points of rows, at its end.
    private func chat() -> (NSScrollView, Rows, ChatFollow, EarlierOnScroll.Probe, NSWindow) {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        let rows = Rows(frame: NSRect(x: 0, y: 0, width: 300, height: 1000))
        scroll.documentView = rows
        let follow = ChatFollow()
        let probe = EarlierOnScroll.Probe()
        probe.follow = follow
        rows.addSubview(probe)
        let window = NSWindow(contentRect: scroll.frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = scroll
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
        return (scroll, rows, follow, probe, window)
    }

    private func fromEnd(_ scroll: NSScrollView) -> CGFloat {
        scroll.documentView!.frame.height - scroll.contentView.bounds.maxY
    }

    /// What stopped the following: the agent's message gave way to a shorter one, and then its card arrived.
    func testTheEndStaysInViewWhenTheChatGetsShorterAndThenLonger() {
        let (scroll, rows, follow, _, window) = chat()
        rows.setFrameSize(NSSize(width: 300, height: 1020))
        XCTAssertEqual(fromEnd(scroll), 0)
        rows.setFrameSize(NSSize(width: 300, height: 980))
        XCTAssertEqual(fromEnd(scroll), 0)
        XCTAssertTrue(follow.atEnd)
        rows.setFrameSize(NSSize(width: 300, height: 1216))
        XCTAssertEqual(fromEnd(scroll), 0)
        withExtendedLifetime(window) {}
    }

    func testSomeoneScrolledUpToReadStaysThereAsTheChatGrows() {
        let (scroll, rows, follow, _, window) = chat()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        XCTAssertFalse(follow.atEnd)
        rows.setFrameSize(NSSize(width: 300, height: 1400))
        XCTAssertEqual(scroll.contentView.bounds.minY, 200)
        // Back at the end, it follows again.
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 1000))
        rows.setFrameSize(NSSize(width: 300, height: 1500))
        XCTAssertEqual(fromEnd(scroll), 0)
        withExtendedLifetime(window) {}
    }

    func testTheEndStaysInViewWhenTheChatAreaGetsShorter() {
        let (scroll, _, _, _, window) = chat()
        scroll.setFrameSize(NSSize(width: 300, height: 380))
        scroll.tile()
        XCTAssertEqual(fromEnd(scroll), 0)
        withExtendedLifetime(window) {}
    }
}
