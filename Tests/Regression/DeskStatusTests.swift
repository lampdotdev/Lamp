import XCTest
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
