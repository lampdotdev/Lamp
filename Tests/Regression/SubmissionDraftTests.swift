import XCTest
@testable import Lamp

final class SubmissionDraftTests: XCTestCase {
    func testLaterWordsAndFilesStayForTheNextDraft() {
        let first = URL(fileURLWithPath: "/tmp/first.txt"), second = URL(fileURLWithPath: "/tmp/second.txt")
        let captured = Store.Draft(text: "Submitted", attachments: [first])
        let newer = Store.Draft(text: "Next request", attachments: [first, second])
        XCTAssertEqual(newer.afterSubmission(captured, sent: true), newer)
        XCTAssertEqual(captured.attachments, [first])
    }

    func testCancelDoesNotOverwriteEdits() {
        let captured = Store.Draft(text: "Submitted")
        let newer = Store.Draft(text: "Edited while checking")
        XCTAssertEqual(newer.afterSubmission(captured, sent: false), newer)
    }
}
