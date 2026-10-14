import XCTest
@testable import Lamp

/// A wish is written into a box a word at a time, but only for the eye: the draft holds the whole wish from
/// the first moment, so what's sent is all of it and nothing already in the box is lost.
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
}
