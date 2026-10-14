import XCTest
@testable import Lamp

/// A result card saved before there were rows for what's new still reads.
final class TalkTests: XCTestCase {
    func testAnEarlierResultStillReads() throws {
        let saved = Data(#"{"summary":"Done","guesses":[]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(Talk.Result.self, from: saved).news)
    }

    /// A result card as an agent really wrote one, for a wish to plan a family's dinners: its summary was shown as
    /// a bold paragraph over long chips. It goes back to the agent to say shorter; the same card with short words
    /// is shown.
    func testALongCardIsTurnedBack() {
        func card(_ summary: String, _ guess: String) -> [String: Any] {
            ["summary": summary,
             "guesses": [["guess": guess, "instead": "Group by store aisle", "request": "Group the grocery list by store aisle."]]]
        }
        let sent = card("A week of dinner nights to fill in, a set of family favorites to choose from, and a grocery list that builds itself from the plan.",
                        "Plans dinner only, one per night")
        guard case .failure = Talk.result(from: sent) else { return XCTFail("a 27-word summary was shown") }
        let longChip = card("A week of dinners and a grocery list.",
                            "Grocery list combines all the week's ingredients alphabetically")
        guard case .failure = Talk.result(from: longChip) else { return XCTFail("a 7-word guess was shown") }
        guard case .success = Talk.result(from: card("A week of dinners and a grocery list.", "One A–Z grocery list")) else {
            return XCTFail("a short card was turned back")
        }
    }

    /// A card answered by clicking folds to a line that reads on its own: two questions both answered "Both"
    /// must still say what each "Both" was for.
    func testAFoldedCardSaysWhatWasAsked() {
        let options = [Talk.Option(title: "Grocery list"), Talk.Option(title: "Both")]
        let ask = Talk.Ask(layout: .steps,
                           questions: [Talk.Question(question: "Where should dinner ideas come from?", options: options),
                                       Talk.Question(question: "What else should it do?", options: options)],
                           answers: ["Both", "Both"])
        XCTAssertEqual(ask.folded, "Where should dinner ideas come from? Both\nWhat else should it do? Both")
    }
}
