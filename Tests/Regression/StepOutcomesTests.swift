import XCTest
@testable import Lamp
import LampSidebarKit

/// A step says what happened to it, not only what the agent meant it to do: a command or tool call that failed says
/// so in its row and to the model that titles its fold, a command stopped before it ran says so to that model, and
/// a command's words never name the file work after it, which would read as part of a command that had failed.
final class StepOutcomesTests: XCTestCase {
    /// A turn whose command to share a page failed: the wheel page server started, the share didn't.
    private var shareFailed: [LogLine] {
        var share = LogLine(kind: .status, text: "Ran: tailscale serve --bg 8080", said: "Share wheel page over Tailscale")
        share.failed = true
        return [LogLine(kind: .user, text: "Let me open the wheel page on my phone"),
                LogLine(kind: .status, text: "Ran: python3 -m http.server 8080", said: "Start the wheel page server"),
                share,
                LogLine(kind: .status, text: ChatLook.notRun + "sudo tailscale up", said: "Sign this Mac in to Tailscale"),
                LogLine(kind: .agent, text: "Tailscale isn't set up on this Mac, so the page isn't shared yet."),
                LogLine(kind: .summary, text: "Worked for 40s · $0.05")]
    }

    func testAFailedCommandSaysSoInItsRow() {
        let rows = LogLine.visible(shareFailed, details: false).filter { ChatLook.ranCommand(in: $0.text) != nil }
        XCTAssertEqual(rows.map(\.said), ["Start the wheel page server", "Share wheel page over Tailscale (failed)",
                                          "Sign this Mac in to Tailscale"])
    }

    /// The model that titles the fold is told which steps failed and which never ran, so it can't title the fold
    /// "Shared wheel page over Tailscale".
    @MainActor func testTheTitleModelIsToldWhatFailedAndWhatDidntRun() {
        let (_, groups, _) = StepTitles.groups(in: LogLine.visible(shareFailed, details: false))
        XCTAssertEqual(groups.map(\.steps), [["Start the wheel page server", "Share wheel page over Tailscale (failed)",
                                              "Sign this Mac in to Tailscale (not run)"]])
    }

    /// One of Lamp's tools or a file change that failed is a step that says so too.
    func testAFailedToolCallSaysSo() {
        var edit = LogLine(kind: .tool, text: "edit ContentView.swift", said: "Adding the sort button")
        edit.failed = true
        let steps = LogLine.visible([LogLine(kind: .user, text: "Add a sort button"), edit], details: false)
        XCTAssertEqual(steps.last?.text, "Adding the sort button (failed)")
    }

    /// Claude Code's and pi's words for a command name that command only: a read after it is a step of its own.
    /// Codex's reasoning heading says what the work after it is for, so it still names that work.
    func testFileWorkAfterACommandIsNotNamedAfterIt() {
        let read = ToolCall("read ContentView.swift")
        let naming = "Share wheel page over Tailscale"
        XCTAssertNil(Store.stepName(of: read, said: nil, naming: naming, engine: .claude))
        XCTAssertNil(Store.stepName(of: read, said: nil, naming: naming, engine: .pi))
        XCTAssertEqual(Store.stepName(of: read, said: nil, naming: naming, engine: .codex), naming)
        XCTAssertEqual(Store.stepName(of: read, said: "Reading the wheel", naming: naming, engine: .claude), "Reading the wheel")
    }

    /// Commands the agent gave one name are one step; when every one of them was stopped, the title model is still told
    /// the step didn't run, both for a fold of several steps and for the answer's fold of that one step.
    @MainActor func testGroupedStoppedCommandsStayNotRun() {
        let stopped = [LogLine(kind: .status, text: ChatLook.notRun + "rm -rf build", said: "Clearing out the old build"),
                       LogLine(kind: .status, text: ChatLook.notRun + "rm -rf .build", said: "Clearing out the old build")]
        let request = LogLine(kind: .user, text: "Clean up the old builds")
        let end = [LogLine(kind: .agent, text: "I wasn't allowed to delete them."), LogLine(kind: .summary, text: "Worked for 9s · $0")]
        let listed = LogLine(kind: .status, text: "Ran: ls", said: "Listing the app folder")
        let (_, groups, _) = StepTitles.groups(in: LogLine.visible([request] + stopped + [listed] + end, details: false))
        XCTAssertEqual(groups.map(\.steps), [["Clearing out the old build (not run)", "Listing the app folder"]])
        let (_, _, own) = StepTitles.groups(in: LogLine.visible([request] + stopped + end, details: false))
        XCTAssertEqual(own, [stopped[0].id: "Clearing out the old build (not run)"])
        // One of them stopped and one run: the step says only some of it wasn't.
        let mixed = [stopped[0], LogLine(kind: .status, text: "Ran: rm -rf .build", said: "Clearing out the old build")]
        let (_, _, partly) = StepTitles.groups(in: LogLine.visible([request] + mixed + end, details: false))
        XCTAssertEqual(partly, [stopped[0].id: "Clearing out the old build (some not run)"])
    }

    /// Two calls of the same command, each with its row: the call that failed marks its own row, by the engine's id for
    /// it, not the latest row of that command.
    func testAFailedCallMarksItsOwnRowOfTheSameCommand() {
        let first = LogLine(kind: .tool, text: "Bash: rm -rf build"), second = LogLine(kind: .tool, text: "Bash: rm -rf build")
        var firstRow = LogLine(kind: .status, text: "Ran: rm -rf build", said: "Clearing the build")
        firstRow.call = "toolu_A"
        var secondRow = LogLine(kind: .status, text: "Ran: rm -rf build", said: "Clearing it again")
        secondRow.call = "toolu_B"
        let lines = [LogLine(kind: .user, text: "Clean up"), first, second, firstRow, secondRow]
        XCTAssertEqual(Store.failedRows(in: lines, line: first.id, id: "toolu_A", command: "rm -rf build"), [1, 3])
        XCTAssertEqual(Store.failedRows(in: lines, line: second.id, id: "toolu_B", command: "rm -rf build"), [2, 4])
        // Rows an engine gave no id are found by their command, the latest since the call.
        let untied = [LogLine(kind: .user, text: "Clean up"), first, LogLine(kind: .status, text: "Ran: rm -rf build")]
        XCTAssertEqual(Store.failedRows(in: untied, line: first.id, id: "toolu_A", command: "rm -rf build"), [1, 2])
    }
}
