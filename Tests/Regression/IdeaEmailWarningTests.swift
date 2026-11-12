import XCTest
@testable import Lamp

/// A Send or It's In that lamp.dev keeps without confirming the email its sender was promised leaves a warning on the
/// idea; only a later Send that's confirmed takes it away, and Done and Dismiss neither make nor clear one.
final class IdeaEmailWarningTests: XCTestCase {
    private func after(_ answer: WishIdeas.Answer, wantsNews: Bool = true, notified: Bool, had: WishIdeas.Unconfirmed? = nil) -> WishIdeas.Unconfirmed? {
        WishIdeas.unconfirmed(after: answer, wantsNews: wantsNews, notified: notified, had: had)
    }

    func testSendNotEmailedWarns() {
        XCTAssertEqual(after(.send, notified: false), .reply)
    }

    func testSendEmailedClearsTheWarning() {
        XCTAssertNil(after(.send, notified: true, had: .reply))
        XCTAssertNil(after(.send, notified: true, had: .itsIn))
    }

    func testItsInNotEmailedWarnsEvenWithoutANote() {
        XCTAssertEqual(after(.itsIn, notified: false), .itsIn)
    }

    func testItsInEmailedLeavesAnEarlierWarning() {
        XCTAssertEqual(after(.itsIn, notified: true, had: .reply), .reply)
        XCTAssertNil(after(.itsIn, notified: true))
    }

    func testDoneAndDismissNeitherWarnNorClear() {
        for answer in [WishIdeas.Answer.done, .dismiss] {
            XCTAssertNil(after(answer, notified: false))
            XCTAssertEqual(after(answer, notified: false, had: .reply), .reply)
        }
    }

    func testNoEmailPromisedNoWarning() {
        XCTAssertNil(after(.send, wantsNews: false, notified: false))
        XCTAssertNil(after(.itsIn, wantsNews: false, notified: false))
    }
}
