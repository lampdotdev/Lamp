import XCTest
@testable import Lamp

/// What a Claude Code turn counts as spent. Its `result` line carries `total_cost_usd`, which is the conversation's
/// running total at API prices: a resumed conversation's includes every earlier turn's. Lamp runs Claude Code with
/// the person's Claude sign-in, so nothing it does is billed per token. The lines are Claude Code's own output,
/// recorded on 2026-10-22 (Claude Code 2.1.306 with Sonnet 5.5, a one-word answer and then the same conversation
/// resumed for another), cut to the fields of its `result` line.
final class ClaudeCostTests: XCTestCase {
    static let firstTurn = "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"duration_ms\":8188,\"num_turns\":1,\"result\":\"one\",\"session_id\":\"00fab398-7f2a-497c-8ea8-e24bb41e74d1\",\"total_cost_usd\":0.12173699999999998}"
    static let resumedTurn = "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"duration_ms\":9085,\"num_turns\":1,\"result\":\"two\",\"session_id\":\"00fab398-7f2a-497c-8ea8-e24bb41e74d1\",\"total_cost_usd\":0.2262737}"

    /// Added up turn by turn, the running totals came to more than the conversation's own total, and each one
    /// counted money that was never spent.
    func testClaudeCodeTurnsCountNothingAsSpent() {
        let spent = [Self.firstTurn, Self.resumedTurn].map { line in
            Agent.parseClaude(line).reduce(0.0) { sum, event in
                if case .cost(let amount) = event { return sum + amount }
                return sum
            }
        }
        XCTAssertEqual(spent, [0, 0])
        XCTAssertTrue(Agent.parseClaude(Self.resumedTurn).contains { if case .finished = $0 { true } else { false } })
    }
}
