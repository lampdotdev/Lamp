import XCTest
import AppKit
import LampSidebarKit
@testable import Lamp

/// The status line under a building wish says only Lamp's own words: a command, named by the agent or not, reads as plain
/// work on the app, and Lamp's own steps read as the chat's line says them.
final class DeskStatusTests: XCTestCase {
    func testACommandTheAgentNamedIsPlainWork() {
        XCTAssertEqual(TurnProgress.deskWords("Run the test suite with swift test", named: true), "Working on your app")
    }

    func testCommandsAreNeverNamedOnTheDesk() {
        XCTAssertEqual(TurnProgress.deskWords("Running a command", named: false), "Working on your app")
        XCTAssertEqual(TurnProgress.deskWords("Checking a command", named: false), "Working on your app")
        XCTAssertEqual(TurnProgress.deskWords("Waiting for your OK to run a command", named: false), "Waiting for your OK")
    }

    func testLampsOwnWordsStayAsTheyAre() {
        for words in ["Thinking", "Working on the interface", "Building…", "Updating Packing List in place…",
                      "Opening Packing List…", "Waking the genie"] {
            XCTAssertEqual(TurnProgress.deskWords(words, named: false), words)
        }
    }
}

/// Every phrase the status under a building wish can show fits its two lines at a tile's width, measured in the font it
/// is drawn in, so none is cut short with "…". An app's own name in a phrase can still make one too long.
final class DeskStatusFitTests: XCTestCase {
    private func lines(_ text: String) -> Int {
        let font = NSFont.preferredFont(forTextStyle: .caption1)
        let height = (text as NSString).boundingRect(
            with: NSSize(width: DeskStatusLine.width, height: 1000), options: [.usesLineFragmentOrigin],
            attributes: [.font: font]).height
        return Int((height / NSLayoutManager().defaultLineHeight(for: font)).rounded())
    }

    func testEveryPhraseFitsTwoLines() {
        var phrases = Set<String>([DeskStatusLine.placeholder, TurnProgress.plainWork, "Waiting for your OK"])
        // The thinking phrases and the later words of a long build or update, as they turn over.
        for start in 0..<8 {
            for second in stride(from: 0.0, through: 400, by: 0.5) {
                for activity in ["Thinking", "Building…", "Updating Wedding Words in place…"] {
                    phrases.insert(Activity.words(activity, waited: second, start: start))
                }
            }
        }
        // What a step reads as, from the agent's tool calls and the files it writes.
        for call in ["read Notes.swift", "screenshot", "edit ThemeColors.swift", "write SettingsView.swift",
                     "write TaskRowView.swift", "write DataStore.swift", "write SyncService.swift", "write NotesApp.swift",
                     "write icon.json", "write APP.md", "write Helpers.swift", "delete Old.swift", "grep x", "plan",
                     "look_at_app", "use_app", "read_notes", "read_skill", "save_notes", "make_art", "offer_setup",
                     "make_app_for", "connectors", "ask", "list_versions", "web_search x"] {
            phrases.insert(TurnProgress.deskWords(TurnProgress.activity(for: ToolCall(call)), named: false))
        }
        for name in ["Wedding Words", "Packing List"] {
            phrases.formUnion(["Opening \(name)…", "Installing \(name)…", "Updating \(name) in place…"])
        }
        phrases.remove("")
        let tooLong = phrases.filter { lines($0) > DeskStatusLine.lines }
        XCTAssertEqual(tooLong, [], "too long for \(DeskStatusLine.lines) lines at \(DeskStatusLine.width) pt")
        XCTAssertGreaterThan(phrases.count, 30)
    }
}
