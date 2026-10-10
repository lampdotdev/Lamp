import XCTest
@testable import Lamp

/// A wish is written into a box a word at a time, but only for the eye: the box holds the whole wish from the
/// first moment. Four ways that went wrong when the words were written into the draft itself (review of #206).
final class WishArrivalTests: XCTestCase {
    private let wish = "A menu bar app that watches my downloads folder. Nothing moves until I say yes."

    /// Send or Return while the words were still arriving sent only the words so far.
    func testSendDuringTheWritingHasTheWholeWish() {
        let draft = Store.Draft().taking(wish: wish)
        var arrival = Wish.Arrival(wish)
        arrival.advance(to: Wish.steps(wish)[1])
        // The box shows two words; what Send reads is the draft, and that is all of it.
        XCTAssertEqual(arrival.text(over: draft.text), "A menu")
        XCTAssertEqual(draft.text, wish)
    }

    /// A file dropped while the wish arrived was dropped from the draft by the next word.
    func testAFileAddedToTheBoxStaysThroughTheWriting() {
        let file = URL(fileURLWithPath: "/tmp/receipt.png")
        var held = Store.Draft()
        held.attachments = [file]
        let draft = held.taking(wish: wish)
        XCTAssertEqual(draft.attachments, [file])
        XCTAssertEqual(draft.text, wish)
    }

    /// A second link reused the first one's app while its request was waiting on setup or in line.
    func testAnAppWithARequestOnItsWayIsNotTakenForAnotherWish() throws {
        var pending = PendingSubmissions()
        XCTAssertTrue(Store.nothingAsked(lines: 0, busy: false, pending: pending.contains("untitled"), queued: false))
        // Sent for an iPhone app: reserved while Xcode is checked, with no line in the chat and no turn yet.
        _ = try XCTUnwrap(pending.begin("untitled"))
        XCTAssertFalse(Store.nothingAsked(lines: 0, busy: false, pending: pending.contains("untitled"), queued: false))
        // Sent while what builds apps isn't set up: the request waits in line.
        XCTAssertFalse(Store.nothingAsked(lines: 0, busy: false, pending: false, queued: true))
        XCTAssertFalse(Store.nothingAsked(lines: 1, busy: false, pending: false, queued: false))
        XCTAssertFalse(Store.nothingAsked(lines: 0, busy: true, pending: false, queued: false))
    }

    /// In the welcome, an idea picked (or words dictated) mid-writing left the site's wish on show while
    /// Continue took the idea.
    func testWhatThePersonChoseShowsAtOnce() {
        var arrival = Wish.Arrival(wish)
        arrival.advance(to: "A menu")
        let idea = "Names and files the 40 screenshots on your desktop."
        XCTAssertEqual(arrival.text(over: idea), idea)
        XCTAssertEqual(arrival.text(over: wish + " And a sound."), wish + " And a sound.")
        // Untouched, the wish goes on being written.
        XCTAssertEqual(arrival.text(over: wish), "A menu")
    }
}
