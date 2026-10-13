import XCTest
import SwiftUI
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

    /// An answer waiting for setup is kept with the card it answers.
    func testAWaitingAnswerKeepsItsCardAcrossARelaunch() {
        let card = UUID()
        let kept = QueuedMessage(saved: QueuedMessage(text: "Who is it for? Just me.", card: card).saved, attachments: [])
        XCTAssertEqual(kept.card, card)
        XCTAssertNil(QueuedMessage(saved: ["text": "Make it blue"], attachments: []).card)
    }

    /// A typed answer folds the card as it's sent, and taken back out of the line opens it again.
    func testATypedAnswerTakenBackOpensTheCardAgain() {
        let ask = Talk.Ask(layout: .steps, questions: [
            Talk.Question(question: "Who is it for?", options: [.init(title: "Just me"), .init(title: "My team")]),
        ], typed: true)
        let card = LogLine(kind: .ask, text: ask.text, ask: ask)
        var lines = [card]
        XCTAssertNil(Talk.open(in: lines))
        XCTAssertFalse(Talk.shows(card))

        let answer = QueuedMessage(text: "My family", card: card.id)
        var queue = [answer]
        XCTAssertTrue(Talk.unqueue(answer, from: &queue, lines: &lines))
        XCTAssertEqual(Talk.open(in: lines)?.id, card.id)
    }

    /// A guess turned the other way is shown by its card; taken back before it's sent, the card offers it again.
    func testAGuessTurnedThenTakenBackIsOfferedAgain() {
        var result = Talk.Result(summary: "Done", guesses: [
            Talk.Guess(guess: "One list", instead: "A pipeline board", request: "Make it a pipeline board."),
        ])
        result.switched = [0]
        let card = LogLine(kind: .result, text: result.text, result: result)
        var lines = [card]
        XCTAssertTrue(Talk.shows(card))

        let turned = QueuedMessage(text: "Make it a pipeline board.", card: card.id)
        var queue = [turned]
        XCTAssertTrue(Talk.unqueue(turned, from: &queue, lines: &lines))
        XCTAssertNil(lines[0].result?.switched)
    }

    func testTheSameOptionTwiceIsNotAChoice() {
        guard case .failure = Talk.ask(from: ["questions": [
            ["question": "Who is it for?", "options": [["title": "Me"], ["title": "Me"]]],
        ]]) else { return XCTFail("Two options that say the same were taken") }
    }
}

/// Typing an answer of one's own beside a question's chips: the chips stay where they are.
final class OwnAnswerLayoutTests: XCTestCase {
    @MainActor
    func testTheChipsStayPutHoweverLongTheTypedAnswer() {
        func height(typing text: String) -> CGFloat {
            let row = ChipRow(options: [.init(title: "A fixed list", symbol: "list.bullet"), .init(title: "I make my own", symbol: "plus.circle")],
                              chosen: nil, own: .constant(text)) { _ in }
            return NSHostingController(rootView: row).sizeThatFits(in: CGSize(width: 540, height: 2000)).height
        }
        XCTAssertEqual(height(typing: "Start with Work and Personal, and let me add more"), height(typing: ""))
    }
}
