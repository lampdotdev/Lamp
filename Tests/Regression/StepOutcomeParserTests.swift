import XCTest
@testable import Lamp

/// Failed steps reach the chat through each engine's own event format. Keep the call's identity and outcome
/// together, including when results arrive in a different order or several calls use the same tool.
final class StepOutcomeParserTests: XCTestCase {
    private func assertOutcomes(_ events: [AgentEvent], ids: [String], failed: [Bool],
                                file: StaticString = #filePath, line: UInt = #line) {
        let outcomes = events.compactMap { event -> (String, Bool)? in
            if case .ended(let id, let failed) = event { return (id, failed) }
            return nil
        }
        XCTAssertEqual(outcomes.map { $0.0 }, ids, file: file, line: line)
        XCTAssertEqual(outcomes.map { $0.1 }, failed, file: file, line: line)
    }

    private func toolIDs(_ events: [AgentEvent]) -> [String] {
        events.compactMap { event in
            if case .tool(_, _, _, let id, _) = event { return id }
            return nil
        }
    }

    func testPiKeepsEachCallsIdentityAndOutcome() {
        let starts = [
            #"{"type":"tool_execution_start","toolCallId":"call_a","toolName":"edit","args":{"path":"Sources/App.swift","doing":"Adding a sort button"}}"#,
            #"{"type":"tool_execution_start","toolCallId":"call_b","toolName":"edit","args":{"path":"Sources/App.swift","doing":"Fixing the sort button"}}"#,
        ].flatMap { Agent.parse($0, engine: .pi) }
        XCTAssertEqual(toolIDs(starts), ["call_a", "call_b"])
        let results = [
            #"{"type":"tool_execution_end","toolCallId":"call_b","toolName":"edit","isError":false}"#,
            #"{"type":"tool_execution_end","toolCallId":"call_a","toolName":"edit","isError":true}"#,
        ].flatMap { Agent.parse($0, engine: .pi) }
        assertOutcomes(results, ids: ["call_b", "call_a"], failed: [false, true])
    }

    /// Claude Code can return several results in one message; an omitted is_error means the call succeeded.
    func testClaudeKeepsEveryResultInABatch() {
        let starts = Agent.parse(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"call_a","name":"mcp__lamp__look_at_app","input":{}},{"type":"tool_use","id":"call_b","name":"mcp__lamp__look_at_app","input":{}},{"type":"tool_use","id":"call_c","name":"Read","input":{"file_path":"Sources/App.swift"}}]}}"#, engine: .claude)
        XCTAssertEqual(toolIDs(starts), ["call_a", "call_b", "call_c"])
        let results = Agent.parse(#"{"type":"user","message":{"content":[{"type":"text","text":"Tool results follow"},{"type":"tool_result","tool_use_id":"call_b","is_error":false,"content":"App opened"},{"type":"tool_result","tool_use_id":"call_a","is_error":true,"content":"Build failed"},{"type":"tool_result","tool_use_id":"call_c","content":"App source"}]}}"#, engine: .claude)
        assertOutcomes(results, ids: ["call_b", "call_a", "call_c"], failed: [false, true, false])
    }

    func testCodexKeepsEachMCPCallsIdentityAndOutcome() {
        let starts = [
            #"{"type":"item.started","item":{"type":"mcp_tool_call","id":"call_a","server":"lamp","tool":"look_at_app","arguments":{}}}"#,
            #"{"type":"item.started","item":{"type":"mcp_tool_call","id":"call_b","server":"lamp","tool":"look_at_app","arguments":{}}}"#,
        ].flatMap { Agent.parse($0, engine: .codex) }
        XCTAssertEqual(toolIDs(starts), ["call_a", "call_b"])
        let results = [
            #"{"type":"item.completed","item":{"type":"mcp_tool_call","id":"call_b","status":"completed"}}"#,
            #"{"type":"item.completed","item":{"type":"mcp_tool_call","id":"call_a","status":"failed"}}"#,
        ].flatMap { Agent.parse($0, engine: .codex) }
        assertOutcomes(results, ids: ["call_b", "call_a"], failed: [false, true])
    }

    /// Codex reports the edit and its outcome together, without needing a tool-start event to create its row.
    func testCodexFileChangesCarryTheirOwnOutcome() {
        let events = [
            #"{"type":"item.completed","item":{"type":"file_change","id":"edit_a","status":"failed","changes":[{"path":"Sources/App.swift","kind":"update"}]}}"#,
            #"{"type":"item.completed","item":{"type":"file_change","id":"edit_b","status":"completed","changes":[{"path":"Sources/App.swift","kind":"update"}]}}"#,
        ].flatMap { Agent.parse($0, engine: .codex) }
        XCTAssertEqual(toolIDs(events), ["edit_a", "edit_b"])
        assertOutcomes(events, ids: ["edit_a", "edit_b"], failed: [true, false])
    }

    /// A command can fail by status or exit code. A refusal is separate: it never ran.
    func testCodexCommandsDistinguishFailureFromRefusal() {
        let events = [
            #"{"type":"item.completed","item":{"type":"command_execution","id":"command_a","command":"swift build","status":"completed","exit_code":0}}"#,
            #"{"type":"item.completed","item":{"type":"command_execution","id":"command_b","command":"swift build","status":"completed","exit_code":1}}"#,
            #"{"type":"item.completed","item":{"type":"command_execution","id":"command_c","command":"swift build","status":"failed","exit_code":null}}"#,
            #"{"type":"item.completed","item":{"type":"command_execution","id":"command_d","command":"swift build","status":"declined","exit_code":null}}"#,
        ].flatMap { Agent.parse($0, engine: .codex) }
        let commands = events.compactMap { event -> (String, Bool, Bool, String?)? in
            if case .ran(let command, let refused, let failed, let id) = event { return (command, refused, failed, id) }
            return nil
        }
        XCTAssertEqual(commands.map { $0.0 }, Array(repeating: "swift build", count: 4))
        XCTAssertEqual(commands.map { $0.1 }, [false, false, false, true])
        XCTAssertEqual(commands.map { $0.2 }, [false, true, true, false])
        XCTAssertEqual(commands.map { $0.3 }, ["command_a", "command_b", "command_c", "command_d"])
    }
}
