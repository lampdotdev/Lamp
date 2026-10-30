import XCTest
@testable import Lamp

/// A request Claude Code couldn't make. The lines are its own output, recorded on 2026-10-30 (Claude Code 2.1.310, sent
/// to a local port that doesn't speak TLS), cut to the fields Lamp reads and the ones that mark the failure.
final class ClaudeFailureTests: XCTestCase {
    static let errorMessage = #"{"type":"assistant","message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"API Error: Unable to connect to API (EPROTO)"}]},"parent_tool_use_id":null,"error":"server_error","is_api_error_message":true}"#
    static let result = #"{"type":"result","subtype":"success","is_error":true,"result":"API Error: Unable to connect to API (EPROTO)","terminal_reason":"api_error"}"#

    /// The failure reaches the chat once, as the error card the `result` line makes, not as a message too.
    func testAFailedRequestIsNotAMessage() {
        let events = [Self.errorMessage, Self.result].flatMap(Agent.parseClaude)
        XCTAssertFalse(events.contains { if case .text = $0 { true } else { false } })
        XCTAssertEqual(events.compactMap { if case .failed(let text) = $0 { text } else { nil } },
                       ["API Error: Unable to connect to API (EPROTO)"])
    }

    func testAModelsMessageIsStillOne() {
        let line = #"{"type":"assistant","message":{"model":"claude-sonnet-5-5","role":"assistant","content":[{"type":"text","text":"Done."}]},"parent_tool_use_id":null}"#
        XCTAssertEqual(Agent.parseClaude(line).compactMap { if case .text(let text) = $0 { text } else { nil } }, ["Done."])
    }

    func testAConnectionFailureIsSaidPlainly() {
        XCTAssertEqual(Provider.friendlyError("API Error: Unable to connect to API (EPROTO)", from: "Claude Code"),
                       ErrorMessages.connectionFailed)
        XCTAssertEqual(Provider.friendlyError("Connection error.", from: "OpenRouter"), ErrorMessages.connectionFailed)
    }

    func testARefusedProviderIsntTheLocalServer() {
        XCTAssertEqual(Provider.friendlyError("API Error: Unable to connect to API (ECONNREFUSED)", from: "Claude Code"),
                       ErrorMessages.connectionFailed)
        XCTAssertEqual(Provider.friendlyError("connect ECONNREFUSED 127.0.0.1:8000", from: "OpenRouter"),
                       ErrorMessages.localServerUnreachable)
    }
}
