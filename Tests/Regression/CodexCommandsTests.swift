import XCTest
@testable import Lamp
import LampSidebarKit

/// What the chat says of a command Codex ran or its reviewer refused, read from Codex's own output.
final class CodexCommandsTests: XCTestCase {
    /// Captured from `codex exec --json` (codex-cli 0.163.0-alpha.10.2, 20 October 2026): Auto-review refused it.
    static let declined = #"{"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"/bin/zsh -lc 'rm -rf -- ../old-build'","aggregated_output":"","exit_code":null,"status":"declined"}}"#
    /// The same run's command before it, which ran.
    static let completed = #"{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/zsh -lc 'ls -ld ../old-build; du -sh ../old-build'","aggregated_output":"drwxr-xr-x@ 3 someone  staff  96 Oct 20 13:22 ../old-build\n4.0K\t../old-build\n","exit_code":0,"status":"completed"}}"#
    /// From another run that day, a command Codex quoted with double quotes.
    static let doubleQuoted = #"{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/zsh -lc \"curl --fail-with-body --show-error --form 'file=@upload.txt' http://127.0.0.1:63441/upload\"","aggregated_output":"","exit_code":null,"status":"declined"}}"#

    private func ran(_ line: String) -> (String, Bool)? {
        for event in Agent.parseCodex(line) { if case .ran(let command, let refused) = event { return (command, refused) } }
        return nil
    }

    func testARefusedCommandIsSaidAsNotRun() throws {
        let (command, refused) = try XCTUnwrap(ran(Self.declined))
        XCTAssertEqual(command, "rm -rf -- ../old-build")
        XCTAssertTrue(refused)
    }

    /// The step a command shows as, by the name the agent gave it: what each engine's commands come to in the chat,
    /// Codex's from its output and Claude Code's from its hooks, logged the same way (`Ran:` and `Not run:`).
    private func steps(_ lines: [LogLine]) -> [(said: String?, command: String?)] {
        ChatItem.items(lines).flatMap { item -> [LogLine] in
            if case .statuses(let lines) = item { return lines } else { return [] }
        }.map { ($0.said, ChatLook.ranCommand(in: $0.text)) }
    }

    /// A refused command is the step it was while it was judged, not a line of its own: by the agent's name for it,
    /// with "(not run)" only beside the command shown when the step is opened.
    func testARefusedCommandIsTheStepItWas() throws {
        let (command, refused) = try XCTUnwrap(ran(Self.declined))
        XCTAssertTrue(refused)
        let shown = steps([LogLine(kind: .status, text: ChatLook.notRun + command, said: "Clearing out the old build")])
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(shown.first?.said, "Clearing out the old build")
        XCTAssertEqual(shown.first?.command, "rm -rf -- ../old-build  (not run)")
    }

    /// Commands under one name are one step, each with its own mark, whichever came first.
    func testCommandsUnderOneNameKeepTheirOwnMarks() throws {
        let (ran, _) = try XCTUnwrap(self.ran(Self.completed))
        let (refused, _) = try XCTUnwrap(self.ran(Self.declined))
        let said = "Clearing out the old build"
        for (first, second, expected) in [
            ("Ran: " + ran, ChatLook.notRun + refused, ran + "\n" + refused + "  (not run)"),
            (ChatLook.notRun + refused, "Ran: " + ran, refused + "  (not run)\n" + ran),
        ] {
            let shown = steps([LogLine(kind: .status, text: first, said: said), LogLine(kind: .status, text: second, said: said)])
            XCTAssertEqual(shown.count, 1)
            XCTAssertEqual(shown.first?.command, expected)
        }
    }

    func testACommandThatRanIsSaidAsRun() throws {
        let (command, refused) = try XCTUnwrap(ran(Self.completed))
        XCTAssertEqual(command, "ls -ld ../old-build; du -sh ../old-build")
        XCTAssertFalse(refused)
    }

    func testDoubleQuotesAreTakenOff() throws {
        let (command, _) = try XCTUnwrap(ran(Self.doubleQuoted))
        XCTAssertEqual(command, "curl --fail-with-body --show-error --form 'file=@upload.txt' http://127.0.0.1:63441/upload")
    }
}
