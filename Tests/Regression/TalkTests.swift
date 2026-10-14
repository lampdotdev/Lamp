import XCTest
@testable import Lamp

/// A result card saved before there were rows for what's new still reads.
final class TalkTests: XCTestCase {
    func testAnEarlierResultStillReads() throws {
        let saved = Data(#"{"summary":"Done","guesses":[]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(Talk.Result.self, from: saved).news)
    }

    /// The card a real new-app turn sent on 2026-10-14 (pi, Opus 5.5, "I wish I had something to help my family
    /// plan dinners for the week"): its summary was shown as a bold paragraph over long chips. It goes back to the
    /// agent to say shorter; the same card with short words is shown.
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
}
