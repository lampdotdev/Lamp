import XCTest
@testable import Lamp

/// What the chat says of a command Codex ran or its reviewer refused, read from Codex's own output.
final class CodexCommandsTests: XCTestCase {
    /// Captured from `codex exec --json` (codex-cli 0.163.0-alpha.10.2, 20 October 2026): Auto-review refused it.
    static let declined = #"{"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"/bin/zsh -lc 'rm -rf -- ../old-build'","aggregated_output":"","exit_code":null,"status":"declined"}}"#
    /// How Codex reported that command starting, before its reviewer refused it.
    static let started = #"{"type":"item.started","item":{"id":"item_2","type":"command_execution","command":"/bin/zsh -lc 'rm -rf -- ../old-build'","aggregated_output":"","exit_code":null,"status":"in_progress"}}"#
    /// The same run's command before it, which ran.
    static let completed = #"{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/zsh -lc 'ls -ld ../old-build; du -sh ../old-build'","aggregated_output":"drwxr-xr-x@ 3 someone  staff  96 Oct 20 13:22 ../old-build\n4.0K\t../old-build\n","exit_code":0,"status":"completed"}}"#
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
