import XCTest
@testable import Lamp

/// The agent's question card: a click and a typed message both answer it, and the agent can tell which
/// answer belongs to which question.
final class TalkTests: XCTestCase {
    private func asked(_ questions: Int = 2) -> LogLine {
        let ask = Talk.Ask(layout: .steps, questions: (0..<questions).map {
            Talk.Question(question: "Question \($0)?", options: [.init(title: "A"), .init(title: "B")])
        })
        return LogLine(kind: .ask, text: ask.text, ask: ask)
    }

    func testACardWaitsUntilThePersonSaysAnything() {
        let card = asked()
        XCTAssertEqual(Talk.open(in: [LogLine(kind: .user, text: "An app"), card])?.id, card.id)
        // Typing instead of clicking is an answer too.
        XCTAssertNil(Talk.open(in: [card, LogLine(kind: .user, text: "No, that's not what I want")]))
    }

    func testOnlyTheLatestCardWaits() {
        let first = asked(), second = asked()
        XCTAssertEqual(Talk.open(in: [first, LogLine(kind: .agent, text: "…"), second])?.id, second.id)
    }

    func testAClickedCardIsAnswered() {
        var card = asked()
        card.ask?.answers = ["A", "B"]
        XCTAssertNil(Talk.open(in: [card]))
    }

    /// Answers clicked while the agent was still ending its turn wait in line, where they can be removed.
    /// Removed, they were never given, so the card has to take a click again.
    func testACardWaitsAgainWhenItsAnswersAreRemovedBeforeTheyAreSent() {
        var card = asked()
        card.ask?.answers = ["A", "B"]
        var lines = [LogLine(kind: .user, text: "An app"), card]
        let answer = QueuedMessage(text: "A\nB", card: card.id)
        var queue = [answer]
        XCTAssertTrue(Talk.unqueue(answer, from: &queue, lines: &lines))
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(Talk.open(in: lines)?.id, card.id)
    }

    /// A typed message removed from the line leaves an answered card as it is, and so does a click on
    /// a message that has already gone out.
    func testOnlyAnswersStillInLineAreTakenBack() {
        var card = asked()
        card.ask?.answers = ["A", "B"]
        var lines = [card]
        let typed = QueuedMessage(text: "Make it blue")
        var queue = [typed]
        XCTAssertFalse(Talk.unqueue(typed, from: &queue, lines: &lines))
        XCTAssertEqual(lines[0].ask?.answers, ["A", "B"])
        XCTAssertFalse(Talk.unqueue(QueuedMessage(text: "A\nB", card: card.id), from: &queue, lines: &lines))
        XCTAssertEqual(lines[0].ask?.answers, ["A", "B"])
    }

    func testAnswersAreSentOneLineForEachQuestionInOrder() {
        XCTAssertEqual(Talk.message(for: asked(1).ask!, answers: ["Meals"]), "Meals")
        XCTAssertEqual(Talk.message(for: asked(2).ask!, answers: ["Meals", Talk.youDecide]), "Meals\nYou decide")
    }

    func testQuestionsNeedAnswersToClick() {
        guard case .failure = Talk.ask(from: ["questions": [["question": "Who is it for?", "options": [["title": "Me"]]]]]) else {
            return XCTFail("One option isn't a choice")
        }
        let ask = try? Talk.ask(from: ["layout": "together", "questions": [
            ["question": "Who is it for?", "options": [["title": "Me", "symbol": "no.such.symbol"], ["title": "My team", "symbol": "person.2"]]],
        ]], hasSymbol: { $0 == "person.2" }).get()
        XCTAssertEqual(ask?.layout, .together)
        XCTAssertEqual(ask?.questions.first?.options.map(\.symbol), [nil, "person.2"])
    }

    /// What the agent says after asking sits under a card that already asks it.
    func testNothingIsSaidUnderACard() {
        let lines = [LogLine(kind: .user, text: "An app"), LogLine(kind: .agent, text: "I'll ask first."), asked(),
                     LogLine(kind: .agent, text: "Waiting for your answers."),
                     LogLine(kind: .user, text: "A"), LogLine(kind: .agent, text: "I'll build it.")]
        XCTAssertEqual(LogLine.visible(lines, details: false).filter { $0.kind == .agent }.map(\.text), ["I'll build it."])
        XCTAssertEqual(LogLine.visible(lines, details: true).count, lines.count)
    }

    func testAResultsButtonsLastUntilTheNextRequest() {
        let result = LogLine(kind: .result, text: "", result: Talk.Result(summary: "Done", guesses: []))
        XCTAssertEqual(Talk.current(in: [result])?.id, result.id)
        XCTAssertNil(Talk.current(in: [result, LogLine(kind: .user, text: "Make it blue")]))
    }
}
