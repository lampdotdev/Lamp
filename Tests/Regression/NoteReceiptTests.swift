import XCTest
@testable import Lamp

/// A save of Lamp's notes shows in the chat as what it changed, and Undo there takes that change back out.
final class NoteReceiptTests: XCTestCase {
    private let before = Memory.Notes(summary: "How my apps should look", text: "- Dark backgrounds\n- Dates as 13 Oct")
    private let after = Memory.Notes(summary: "How my apps should look and sound",
                                     text: "- Dark backgrounds\n- Dates as 13 October 2026\n- No sounds")

    func testTheReceiptIsWhatTheSaveChanged() {
        let receipt = NoteReceipt(about: "you", before: before, after: after)
        XCTAssertEqual(receipt.added, ["Dates as 13 October 2026", "No sounds"])
        XCTAssertEqual(receipt.removed, ["Dates as 13 Oct"])
    }

    func testUndoPutsTheNotesBackAsTheyWere() {
        let receipt = NoteReceipt(about: "you", before: before, after: after)
        XCTAssertEqual(receipt.takenBack(from: after), before)
        // A first note, taken back, leaves no notes at all.
        let first = NoteReceipt(about: "app", before: Memory.Notes(), after: after)
        XCTAssertTrue(first.takenBack(from: after).isEmpty)
    }

    func testUndoLeavesWhatWasNotedSince() {
        let receipt = NoteReceipt(about: "you", before: before, after: after)
        let later = Memory.Notes(summary: "Look, sound and wording", text: after.text + "\n- Plain words, no jargon")
        let undone = receipt.takenBack(from: later)
        XCTAssertEqual(NoteReceipt.lines(undone.text), ["Dark backgrounds", "Plain words, no jargon", "Dates as 13 Oct"])
        XCTAssertEqual(undone.summary, "Look, sound and wording")
    }

    func testAReceiptSurvivesTheChatBeingSaved() throws {
        var line = LogLine(kind: .noted, text: "", noted: NoteReceipt(about: "app", before: before, after: after))
        line.noted?.undone = true
        XCTAssertEqual(try JSONDecoder().decode(LogLine.self, from: JSONEncoder().encode(line)), line)
    }
}
