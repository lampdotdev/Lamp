import XCTest
@testable import Lamp

final class SubmissionDraftTests: XCTestCase {
    func testUnchangedSubmittedInputClears() {
        let captured = Store.Draft(text: "Submitted", attachments: [URL(fileURLWithPath: "/tmp/first.txt")])
        XCTAssertEqual(captured.afterSubmission(captured, sent: true), Store.Draft())
    }

    func testStarterIdeaSelectedDuringAttachmentSubmissionIsKept() {
        let file = URL(fileURLWithPath: "/tmp/first.txt")
        let captured = Store.Draft(attachments: [file])
        let newer = Store.Draft(text: "A newly selected starter idea", attachments: [file])
        XCTAssertEqual(newer.afterSubmission(captured, sent: true), newer)
        XCTAssertEqual(captured.text, "")
    }

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
