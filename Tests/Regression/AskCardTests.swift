import XCTest
import SwiftUI
@testable import Lamp

final class AskCardTests: XCTestCase {
    func testPayloadKeepsQuestionsChoicesAndAnswers() throws {
        let questions = [
            AskQuestion(question: "Who is it for?", options: ["Just me", "My team"], chosen: nil),
            AskQuestion(question: "How should it sync?", options: ["iCloud", "No sync"], chosen: nil),
        ]
        let line = LogLine(kind: .ask, text: "", ask: AskCardPayload(
            questions: questions, answers: ["Just me", "iCloud"], dismissed: true))

        let read = try JSONDecoder().decode(LogLine.self, from: JSONEncoder().encode(line))

        XCTAssertEqual(read, line)
        XCTAssertTrue(read.ask?.isReadOnly == true)
        XCTAssertFalse(read.ask?.isAssumption == true)
    }

    func testQuestionAnswersMakeOneReadableMessage() {
        let questions = [
            AskQuestion(question: "Who is it for?", options: ["Just me", "My team"], chosen: nil),
            AskQuestion(question: "How should it sync?", options: ["iCloud", "No sync"], chosen: nil),
        ]

        XCTAssertEqual(AskCardPayload.answerMessage(questions: questions, answers: ["Just me", "iCloud"]),
                       "Who is it for? Just me. / How should it sync? iCloud.")
    }

    func testChangingAnAssumptionMakesARequest() {
        let question = AskQuestion(question: "How should deals be organised?",
                                   options: ["One list", "A pipeline board"], chosen: "One list")

        XCTAssertEqual(AskCardPayload.assumptionMessage(question: question, answer: "A pipeline board"),
                       "How should deals be organised? Use a pipeline board instead of one list.")
    }

    func testRemovingAQueuedAnswerCanReopenItsCard() {
        var payload = AskCardPayload(questions: [
            AskQuestion(question: "Who is it for?", options: ["Just me", "My team"], chosen: nil),
        ], answers: ["My team"], dismissed: true)

        payload.reopen()

        XCTAssertNil(payload.answers)
        XCTAssertNil(payload.dismissed)
        XCTAssertFalse(payload.isReadOnly)
    }

    func testTheToolReadsNaturallyFromClaudeCodeAndCodex() {
        let claude = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__lamp__ask","input":{"questions":[]}}]}}"#
        let codex = #"{"type":"item.started","item":{"type":"mcp_tool_call","tool":"ask","arguments":{"questions":[]}}}"#

        for line in [claude, codex] {
            guard case .tool(let label, _) = Agent.parse(line, engine: line == claude ? .claude : .codex).first else {
                return XCTFail("The ask call was not parsed as a tool")
            }
            XCTAssertEqual(label, "ask")
            XCTAssertEqual(TurnProgress.activity(for: ToolCall(label)), "Preparing choices")
        }
    }

    func testAComposerAnswerMakesTheQuestionReadOnly() {
        var payload = AskCardPayload(questions: [
            AskQuestion(question: "Who is it for?", options: ["Just me", "My team"], chosen: nil),
        ])
        XCTAssertFalse(payload.isReadOnly)

        payload.dismissed = true

        XCTAssertTrue(payload.isReadOnly)
    }

    @MainActor
    func testTheCardRendersInLightAndDark() {
        let line = LogLine(kind: .ask, text: "", ask: AskCardPayload(questions: [
            AskQuestion(question: "Who is it for?", options: ["Just me", "My team"], chosen: nil),
            AskQuestion(question: "How should it sync?", options: ["iCloud", "No sync"], chosen: nil),
        ]))
        for scheme in [ColorScheme.light, .dark] {
            let view = AskCard(line: line, dir: URL(fileURLWithPath: "/tmp/ask-card-render"))
                .environment(\.colorScheme, scheme)
                .frame(width: 620, height: 280)
            XCTAssertNotNil(ImageRenderer(content: view).nsImage)
        }
    }
}
