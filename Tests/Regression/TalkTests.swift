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

    func testAResultsButtonsLastUntilTheNextRequest() {
        let result = LogLine(kind: .result, text: "", result: Talk.Result(summary: "Done", guesses: []))
        XCTAssertEqual(Talk.current(in: [result])?.id, result.id)
        XCTAssertNil(Talk.current(in: [result, LogLine(kind: .user, text: "Make it blue")]))
    }
}
