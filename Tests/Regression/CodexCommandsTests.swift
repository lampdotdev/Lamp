import XCTest
@testable import Lamp
import LampSidebarKit

/// What the chat says of a command Codex ran or its reviewer refused, read from Codex's own output.
final class CodexCommandsTests: XCTestCase {
    /// Captured from `codex exec --json` (codex-cli 0.163.0-alpha.10.2, 20 October 2026): Auto-review refused it.
    static let declined = #"{"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"/bin/zsh -lc 'rm -rf -- ../old-build'","aggregated_output":"","exit_code":null,"status":"declined"}}"#
    /// How Codex reported that command starting, before its reviewer refused it.
    static let started = #"{"type":"item.started","item":{"id":"item_2","type":"command_execution","command":"/bin/zsh -lc 'rm -rf -- ../old-build'","aggregated_output":"","exit_code":null,"status":"in_progress"}}"#
    /// The same run's command before it, which ran.
    static let completed = #"{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/zsh -lc 'ls -ld ../old-build; du -sh ../old-build'","aggregated_output":"drwxr-xr-x@ 3 someone  staff  96 Oct 20 13:22 ../old-build\n4.0K\t../old-build\n","exit_code":0,"status":"completed"}}"#
    /// How Codex reported that command starting.
    static let completedStart = #"{"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"/bin/zsh -lc 'ls -ld ../old-build; du -sh ../old-build'","aggregated_output":"","exit_code":null,"status":"in_progress"}}"#
    /// From another run that day, a command Codex quoted with double quotes.
    static let doubleQuoted = #"{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/zsh -lc \"curl --fail-with-body --show-error --form 'file=@upload.txt' http://127.0.0.1:63441/upload\"","aggregated_output":"","exit_code":null,"status":"declined"}}"#

    private func ran(_ line: String) -> (String, Bool)? {
        for event in Agent.parseCodex(line) { if case .ran(let command, let refused, _) = event { return (command, refused) } }
        return nil
    }

    func testARefusedCommandIsSaidAsNotRun() throws {
        let (command, refused) = try XCTUnwrap(ran(Self.declined))
        XCTAssertEqual(command, "rm -rf -- ../old-build")
        XCTAssertTrue(refused)
    }

    /// The step shown when the command started is the one taken out of the chat when it's refused.
    func testARefusedCommandNamesTheStepItStartedAs() throws {
        guard case .tool(let shown, _, _)? = Agent.parseCodex(Self.started).first(where: { if case .tool = $0 { true } else { false } })
        else { return XCTFail("no step") }
        let call = Agent.parseCodex(Self.declined).compactMap { event -> String? in
            if case .ran(_, _, let call) = event { return call } else { return nil }
        }.first
        XCTAssertEqual(call, shown)
    }

    /// A refused command is a step that says it didn't run, in the agent's words or as a step outside the app, and
    /// never the command, folded under "Worked for…" or not. Agent Details keeps the command, and the step Codex
    /// showed as it started is gone there too, since nothing ran.
    func testARefusedCommandIsAStepThatSaysItDidntRun() throws {
        guard case .tool(let shown, _, _)? = Agent.parseCodex(Self.started).first(where: { if case .tool = $0 { true } else { false } }),
              case .ran(let command, let refused, let call)? = Agent.parseCodex(Self.declined).first(where: { if case .ran = $0 { true } else { false } }),
              refused else { return XCTFail("not parsed") }
        for (said, step) in [("Removing the old build folder", "Not run: Removing the old build folder"),
                             (nil, "Not run: " + LogLine.refusedStep)] as [(String?, String)] {
            let before = [LogLine(kind: .user, text: "Clean up the old build folder next to this project."),
                          LogLine(kind: .agent, text: "I'll remove the old build folder."),
                          LogLine(kind: .tool, text: shown)]
            let lines = LogLine.refusing(command, call: call, named: said, in: before) + [
                LogLine(kind: .agent, text: "I didn't delete the old build folder: it's outside this app."),
                LogLine(kind: .summary, text: "Worked for 13s · $0.00")]
            let read = LogLine.visible(lines, details: false)
            XCTAssertFalse(read.contains { $0.text.contains("old-build") }, read.map(\.text).joined(separator: "\n"))
            let steps = ChatItem.items(read, gather: true).flatMap { item -> [String] in
                if case .work(_, _, let steps) = item { return steps.map(\.text) } else { return [] }
            }
            XCTAssertEqual(steps, [step])
            let details = LogLine.visible(lines, details: true).map(\.text)
            XCTAssertTrue(details.contains("Refused: rm -rf -- ../old-build"), details.joined(separator: "\n"))
            XCTAssertFalse(details.contains(shown))
        }
    }

    /// A command that ran is a step the person reads in the agent's words (or as housekeeping when it gave none), with
    /// commands in a row under one name as one step, and never the command itself.
    func testACommandThatRanIsAStepInTheAgentsWords() throws {
        guard case .tool(let shown, _, _)? = Agent.parseCodex(Self.completedStart).first(where: { if case .tool = $0 { true } else { false } }),
              case .ran(_, let refused, _)? = Agent.parseCodex(Self.completed).first(where: { if case .ran = $0 { true } else { false } }),
              !refused else { return XCTFail("not parsed") }
        var lines = [LogLine(kind: .user, text: "Clean up the old build folder next to this project."), LogLine(kind: .tool, text: shown)]
        lines = LogLine.ran(named: "Looking at the old build folder", in: lines)
        lines.append(LogLine(kind: .tool, text: shown))
        lines = LogLine.ran(named: "Looking at the old build folder", in: lines)
        lines = LogLine.ran(named: nil, in: lines)
        lines += [LogLine(kind: .agent, text: "The old build folder is still there."), LogLine(kind: .summary, text: "Worked for 9s · $0.00")]
        let read = LogLine.visible(lines, details: false)
        XCTAssertFalse(read.contains { $0.text.contains("old-build") }, read.map(\.text).joined(separator: "\n"))
        let steps = ChatItem.items(read, gather: true).flatMap { item -> [String] in
            if case .work(_, _, let steps) = item { return steps.map(\.text) } else { return [] }
        }
        XCTAssertEqual(steps, ["Looking at the old build folder", ChatLook.unnamedStep])
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
