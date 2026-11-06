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
        // Without one, or with only spaces, there's no line.
        XCTAssertNil(try asked(["question": "Who cooks?", "options": options]).get().questions.first?.detail)
        XCTAssertNil(try asked(["question": "Who cooks?", "options": options, "detail": " "]).get().questions.first?.detail)
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

    /// The tool tells every engine the line is there and how long it may be.
    func testTheToolOffersTheLine() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/lamp-tools.json")
        let tools = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let ask = try XCTUnwrap(tools.first { $0["name"] as? String == "ask" })
        let schema = try XCTUnwrap(ask["inputSchema"] as? [String: Any])
        let questions = try XCTUnwrap((schema["properties"] as? [String: Any])?["questions"] as? [String: Any])
        let item = try XCTUnwrap(questions["items"] as? [String: Any])
        let detail = try XCTUnwrap((item["properties"] as? [String: Any])?["detail"] as? [String: Any])
        XCTAssertTrue((detail["description"] as? String)?.contains("\(Talk.Words.questionDetail) words") == true)
    }

    private func shown(_ lines: [LogLine]) -> [String] { LogLine.visible(lines, details: false).map(\.text) }

    /// After the card, a line that only points at it goes; what the agent says about the question stays.
    func testOnlyALinePointingAtTheCardIsLeftOutAfterIt() {
        let card = LogLine(kind: .ask, text: "Add a Watch button that opens Orbit onto Vega?")
        let explained = [LogLine(kind: .user, text: "Make it nicer"), card,
                         LogLine(kind: .agent, text: "Orbit is your sky map, and Vega the star you saved there."),
                         LogLine(kind: .summary, text: "Worked for 9 s")]
        XCTAssertTrue(shown(explained).contains("Orbit is your sky map, and Vega the star you saved there."), "\(shown(explained))")

        for waiting in ["Waiting for your answers.", "Pick one above and I'll build it.", "Let me know!",
                        "Over to you: answer the card when you're ready."] {
            let lines = [LogLine(kind: .user, text: "Make it nicer"), card, LogLine(kind: .agent, text: waiting)]
            XCTAssertFalse(shown(lines).contains(waiting), waiting)
        }
        // Once they've answered, the agent's words are its own again.
        let answered = [LogLine(kind: .user, text: "Make it nicer"), card, LogLine(kind: .user, text: "Add it"),
                        LogLine(kind: .agent, text: "Waiting for the build to finish.")]
        XCTAssertTrue(shown(answered).contains("Waiting for the build to finish."))
    }
}
