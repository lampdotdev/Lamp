import XCTest
@testable import Lamp

/// The question card across engines, relaunches and the shape it was first saved in.
final class AskCardTests: XCTestCase {
    func testTheToolReadsNaturallyFromClaudeCodeAndCodex() {
        let claude = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__lamp__ask","input":{"questions":[]}}]}}"#
        let codex = #"{"type":"item.started","item":{"type":"mcp_tool_call","tool":"ask","arguments":{"questions":[]}}}"#

        for line in [claude, codex] {
            guard case .tool(let label, _) = Agent.parse(line, engine: line == claude ? .claude : .codex).first else {
                return XCTFail("The ask call was not parsed as a tool")
            }
            XCTAssertEqual(label, "ask")
            XCTAssertEqual(TurnProgress.activity(for: ToolCall(label)), "Asking you")
        }
    }

    /// A chat kept while a card's options were plain words has to open: one line that can't be read
    /// loses the whole chat.
    func testAChatSavedInTheFirstShapeStillOpens() throws {
        let saved = Data(#"""
        [{"id":"6F3C1D0E-5B0A-4C55-9E57-0B8C6C1F5A01","kind":"user","text":"A tracker"},
         {"id":"6F3C1D0E-5B0A-4C55-9E57-0B8C6C1F5A02","kind":"ask","text":"","ask":{"questions":[
            {"question":"Who is it for?","options":["Just me","My team"]},
            {"question":"How should it sync?","options":["iCloud","No sync"]}]}},
         {"id":"6F3C1D0E-5B0A-4C55-9E57-0B8C6C1F5A03","kind":"ask","text":"","ask":{"questions":[
            {"question":"Who is it for?","options":["Just me","My team"]}],"answers":["My team"],"dismissed":true}},
         {"id":"6F3C1D0E-5B0A-4C55-9E57-0B8C6C1F5A04","kind":"ask","text":"","ask":{"questions":[
            {"question":"Who is it for?","options":["Just me","My team"]}],"dismissed":true}},
         {"id":"6F3C1D0E-5B0A-4C55-9E57-0B8C6C1F5A05","kind":"ask","text":"","ask":{"questions":[
            {"question":"How should deals be organised?","options":["One list","A pipeline board"],"chosen":"One list"}]}}]
        """#.utf8)

        let lines = try JSONDecoder().decode([LogLine].self, from: saved)

        XCTAssertEqual(lines[1].ask?.questions.map { $0.options.map(\.title) }, [["Just me", "My team"], ["iCloud", "No sync"]])
        // Unanswered, it still waits; answered by a click or in words, it doesn't.
        XCTAssertEqual(Talk.open(in: Array(lines[...1]))?.id, lines[1].id)
        XCTAssertEqual(lines[2].ask?.answers, ["My team"])
        XCTAssertNil(Talk.open(in: Array(lines[...3])))
        // What the agent had chosen reads as chosen.
        XCTAssertEqual(lines[4].ask?.answers, ["One list"])
        // And the chat is kept in today's shape from then on.
        XCTAssertEqual(try JSONDecoder().decode([LogLine].self, from: JSONEncoder().encode(lines)), lines)
    }

    /// An answer waiting for setup is kept with the card it answers, under either name the card has had.
    func testAWaitingAnswerKeepsItsCardAcrossARelaunch() {
        let card = UUID()
        let kept = QueuedMessage(saved: QueuedMessage(text: "Who is it for? Just me.", card: card).saved, attachments: [])
        XCTAssertEqual(kept.card, card)
        XCTAssertEqual(QueuedMessage(saved: ["text": "Just me", "ask": card.uuidString], attachments: []).card, card)
        XCTAssertNil(QueuedMessage(saved: ["text": "Make it blue"], attachments: []).card)
    }
}
