import XCTest
@testable import Lamp

/// A save of Lamp's notes shows in the chat as what it changed, and Undo there takes that change back out.
final class NoteReceiptTests: XCTestCase {
    private let before = Memory.Notes(summary: "How my apps should look", text: "- Dark backgrounds\n- Dates as 13 Oct")
    private let after = Memory.Notes(summary: "How my apps should look and sound",
                                     text: "- Dark backgrounds\n- Dates as 13 October 2026\n- No sounds")

    func testUndoLeavesWhatWasNotedSince() {
        let receipt = NoteReceipt(about: "you", before: before, after: after)
        let later = Memory.Notes(summary: "Look, sound and wording", text: after.text + "\n- Plain words, no jargon")
        let undone = receipt.takenBack(from: later)
        XCTAssertEqual(NoteReceipt.lines(undone.text), ["Dark backgrounds", "Plain words, no jargon", "Dates as 13 Oct"])
        // The summary in place was written for notes that held the lines now gone, so it is made again.
        XCTAssertEqual(undone.summary, "Dark backgrounds; Plain words, no jargon; Dates as 13 Oct")
    }

    func testAReceiptSurvivesTheChatBeingSaved() throws {
        var line = LogLine(kind: .noted, text: "", noted: NoteReceipt(about: "app", before: before, after: after))
        line.noted?.undone = true
        XCTAssertEqual(try JSONDecoder().decode(LogLine.self, from: JSONEncoder().encode(line)), line)
    }

    func testUndoingALaterSaveLeavesWhatWasAlreadyTakenBack() {
        // One save notes a line, a second replaces it, and the person takes the first back, then the second.
        let first = NoteReceipt(about: "you", before: Memory.Notes(), after: Memory.Notes(summary: "How apps should sound", text: "- No sounds"))
        let second = NoteReceipt(about: "you", before: first.after, after: Memory.Notes(summary: "How apps should sound", text: "- Quiet sounds"))
        let afterFirstUndo = first.takenBack(from: second.after)
        XCTAssertEqual(afterFirstUndo, second.after)
        XCTAssertTrue(second.takenBack(from: afterFirstUndo, rejected: Set(first.added)).isEmpty)
    }

    func testUndoLeavesALineThePersonPutBackThemselves() {
        // A line is taken back, then the person writes it into the notes again; undoing another save leaves it.
        let other = NoteReceipt(about: "you", before: Memory.Notes(), after: Memory.Notes(summary: "How apps should look", text: "- Dark backgrounds"))
        let now = Memory.Notes(summary: "Look and sound", text: "- Dark backgrounds\n- No sounds")
        XCTAssertEqual(NoteReceipt.lines(other.takenBack(from: now, rejected: ["No sounds"]).text), ["No sounds"])
    }
}
