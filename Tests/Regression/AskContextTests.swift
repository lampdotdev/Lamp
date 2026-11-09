import XCTest
@testable import Lamp

/// A question card can say what it's about: a question naming a button and two of the person's own things
/// ("Add a Watch button that opens Orbit onto Vega?") meant nothing on a card with no line under it.
final class AskContextTests: XCTestCase {
    private func asked(_ question: [String: Any]) -> Swift.Result<Talk.Ask, Talk.Trouble> {
        Talk.ask(from: ["questions": [question]], hasSymbol: { _ in true })
    }

    private let options: [[String: Any]] = [["title": "Not now"], ["title": "Add it"]]

    func testTheQuestionKeepsItsLine() throws {
        let ask = try asked(["question": "Add a Watch button that opens Orbit onto Vega?", "options": options,
                             "detail": "  Orbit is the sky map you made; Vega is the star you saved. "]).get()
        XCTAssertEqual(ask.questions.first?.detail, "Orbit is the sky map you made; Vega is the star you saved.")
    }

    /// A question without its line goes back to the agent, as a long one does: the card is all the person reads.
    func testAQuestionWithoutItsLineIsTurnedBack() {
        for detail: Any? in [nil, " "] {
            var question: [String: Any] = ["question": "Add a Watch button that opens Orbit onto Vega?", "options": options]
            question["detail"] = detail
            guard case .failure(let trouble) = asked(question) else { return XCTFail("Taken without a line: \(String(describing: detail))") }
            XCTAssertTrue(trouble.text.contains("`detail`"), trouble.text)
            XCTAssertTrue(trouble.text.hasSuffix(Talk.askNotShown), trouble.text)
        }
    }

    /// A paragraph under the question goes back to the agent, as a long question does.
    func testALongLineIsTurnedBack() {
        let long = String(repeating: "word ", count: Talk.Words.questionDetail + 1)
        guard case .failure(let trouble) = asked(["question": "Who cooks?", "options": options, "detail": long]) else {
            return XCTFail("A \(Talk.Words.questionDetail + 1)-word line was taken")
        }
        XCTAssertTrue(trouble.text.contains("`detail`"), trouble.text)
        XCTAssertTrue(trouble.text.hasSuffix(Talk.askNotShown), trouble.text)
    }

    /// A question can be a normal sentence; a paragraph goes back to the agent.
    func testAQuestionIsASentenceNotAParagraph() throws {
        let sentence = "Should the reminder come the evening before, or on the morning of the bin day?"
        XCTAssertNoThrow(try asked(["question": sentence, "options": options, "detail": "Bins go out on Tuesdays."]).get())
        let paragraph = String(repeating: "word ", count: Talk.Words.question + 1)
        guard case .failure(let trouble) = asked(["question": paragraph, "options": options, "detail": "A line."]) else {
            return XCTFail("A \(Talk.Words.question + 1)-word question was taken")
        }
        XCTAssertTrue(trouble.text.contains("a question to \(Talk.Words.question) words"), trouble.text)
    }

    /// The tool tells every engine the line is needed and how long it may be.
    func testTheToolOffersTheLine() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/lamp-tools.json")
        let tools = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let ask = try XCTUnwrap(tools.first { $0["name"] as? String == "ask" })
        let schema = try XCTUnwrap(ask["inputSchema"] as? [String: Any])
        let questions = try XCTUnwrap((schema["properties"] as? [String: Any])?["questions"] as? [String: Any])
        let item = try XCTUnwrap(questions["items"] as? [String: Any])
        XCTAssertTrue((item["required"] as? [String])?.contains("detail") == true)
        let detail = try XCTUnwrap((item["properties"] as? [String: Any])?["detail"] as? [String: Any])
        XCTAssertTrue((detail["description"] as? String)?.contains("\(Talk.Words.questionDetail) words") == true)
        let question = try XCTUnwrap((item["properties"] as? [String: Any])?["question"] as? [String: Any])
        XCTAssertTrue((question["description"] as? String)?.contains("\(Talk.Words.question) words") == true)
    }

    private func shown(_ lines: [LogLine]) -> [String] { LogLine.visible(lines, details: false).map(\.text) }

    /// Everything the agent writes after its card shows, a line pointing at the card as much as one saying what
    /// the question is about: no list of words tells the two apart.
    func testWhatTheAgentWritesAfterTheCardShows() {
        let card = LogLine(kind: .ask, text: "Add a Watch button that opens Orbit onto Vega?")
        for said in ["Orbit is your sky map, and Vega the star you saved there.", "Waiting for your answers.",
                     "Pick an option on the card and I'll add it."] {
            let lines = [LogLine(kind: .user, text: "Make it nicer"), card, LogLine(kind: .agent, text: said),
                         LogLine(kind: .summary, text: "Worked for 9 s")]
            XCTAssertTrue(shown(lines).contains(said), "\(shown(lines))")
        }
    }

    /// An engine switched to, or a fresh conversation, is told the card with its lines, as the person read it: the
    /// choice they made means what the line said, not just the question's words.
    func testTheLineGoesWithTheCardToAnotherEngine() throws {
        let ask = try asked(["question": "Enable reminders?", "options": options,
                             "detail": "A notification ten minutes before Vega rises, even while Orbit is closed."]).get()
        let note = CatchUp.note([LogLine(kind: .user, text: "Make it nicer"), LogLine(kind: .ask, text: ask.text, ask: ask),
                                 LogLine(kind: .user, text: "Enable reminders? Add it.")])
        XCTAssertTrue(note.contains("A notification ten minutes before Vega rises, even while Orbit is closed."), note)
        // A card whose text was logged without its line is told from the card all the same.
        let logged = CatchUp.note([LogLine(kind: .ask, text: "Enable reminders?\n- Not now\n- Add it", ask: ask)])
        XCTAssertTrue(logged.contains("ten minutes before Vega rises"), logged)
    }
}
