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
}
