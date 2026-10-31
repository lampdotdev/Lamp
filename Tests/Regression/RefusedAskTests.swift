import XCTest
@testable import Lamp

/// Questions Lamp turned back to the agent (too many words in an answer) never reach the person, and neither does
/// what the agent says to itself while it fixes them.
final class RefusedAskTests: XCTestCase {
    private func tool(_ text: String, failed: Bool? = nil) -> LogLine {
        var line = LogLine(kind: .tool, text: text)
        line.failed = failed
        return line
    }

    private func shown(_ lines: [LogLine]) -> [String] { LogLine.visible(lines, details: false).map(\.text) }

    /// A refused card, a remark about fixing it, the card asked again: line by line as the turn logs them, the
    /// person sees the reply, then the card, and at no moment the refusal or the remark.
    func testARefusedCardAndTheRemarkAfterItNeverShow() {
        let turn = [LogLine(kind: .user, text: "Make a native app for my LG"),
                    LogLine(kind: .agent, text: "Lamp can't make a native LG TV app yet."),
                    tool("ask"), tool("ask", failed: true),
                    LogLine(kind: .agent, text: "Counting \"Yes,\" too—shortening."),
                    tool("ask"), LogLine(kind: .ask, text: "Make it as a web app for your LG instead?"),
                    LogLine(kind: .summary, text: "Worked for 20 s")]
        var lines: [LogLine] = []
        var seen: [[String]] = []
        for line in turn {
            if line.kind == .tool, line.failed == true { lines.removeLast() }   // a call's line is marked failed when it ends
            lines.append(line)
            seen.append(shown(lines))
        }
        for (step, texts) in seen.enumerated() {
            XCTAssertFalse(texts.contains { $0.contains("(failed)") }, "step \(step): \(texts)")
            XCTAssertFalse(texts.contains { $0.hasPrefix("Counting") }, "step \(step): \(texts)")
        }
        XCTAssertEqual(seen.last, ["Make a native app for my LG", "Lamp can't make a native LG TV app yet.", "Asking you",
                                   "Make it as a web app for your LG instead?", "Worked for 20 s"])
        // Agent Details keeps all of it.
        let details = LogLine.visible(lines, details: true).map(\.text)
        XCTAssertTrue(details.contains("Counting \"Yes,\" too—shortening."))
        XCTAssertEqual(details.filter { $0 == "ask" }.count, 2)
    }

    /// Refused twice before the card lands: everything said in between stays out.
    func testRepeatedRefusals() {
        let lines = [LogLine(kind: .user, text: "wish"), tool("ask", failed: true), LogLine(kind: .agent, text: "Fewer words."),
                     tool("ask", failed: true), LogLine(kind: .agent, text: "Fewer options."), tool("ask"),
                     LogLine(kind: .ask, text: "card")]
        XCTAssertEqual(shown(lines), ["wish", "Asking you", "card"])
    }

    /// The agent gave up asking and went on working: what it said is its answer, and shows.
    func testAnAbandonedRetryShowsWhatWasSaid() {
        let lines = [LogLine(kind: .user, text: "wish"), tool("ask", failed: true),
                     LogLine(kind: .agent, text: "I'll make it as a web app."), tool("Write App.swift"),
                     LogLine(kind: .summary, text: "s")]
        XCTAssertTrue(shown(lines).contains("I'll make it as a web app."))
        let ended = [LogLine(kind: .user, text: "wish"), tool("ask", failed: true),
                     LogLine(kind: .agent, text: "Tell me which TV."), LogLine(kind: .summary, text: "s")]
        XCTAssertEqual(shown(ended), ["wish", "Tell me which TV.", "s"])
    }

    /// A refusal in one turn says nothing about the next one's words, and a card in the next turn doesn't hide them.
    func testATurnEndsTheRetry() {
        let lines = [LogLine(kind: .user, text: "wish"), tool("ask", failed: true), LogLine(kind: .agent, text: "first"),
                     LogLine(kind: .user, text: "again"), LogLine(kind: .agent, text: "second"), tool("ask"),
                     LogLine(kind: .ask, text: "card")]
        XCTAssertEqual(shown(lines), ["wish", "first", "again", "second", "Asking you", "card"])
    }

    /// A refused progress line is no step either, by the agent's own words for it as much as Lamp's; other work
    /// that failed still says so.
    func testOnlyRefusedTalkIsLeftOut() {
        var progress = tool("progress", failed: true)
        progress.said = "Checking the TV"
        let lines = [LogLine(kind: .user, text: "wish"), progress, tool("look_at_app", failed: true)]
        XCTAssertEqual(shown(lines), ["wish", "Checking how it looks (failed)"])
    }

    /// Every way `ask` is turned back tells the agent the person didn't see it; `progress`, which shares the word
    /// count, doesn't.
    func testTheRefusalSaysTheQuestionsWerentShown() {
        let long = ["questions": [["question": "Which?", "options": [["title": "Yes, a web app on LG"], ["title": "No"]]]]]
        guard case .failure(let trouble) = Talk.ask(from: long, hasSymbol: { _ in true }) else { return XCTFail() }
        XCTAssertTrue(trouble.text.hasSuffix(Talk.askNotShown), trouble.text)
        guard case .failure(let empty) = Talk.ask(from: [:], hasSymbol: { _ in true }) else { return XCTFail() }
        XCTAssertTrue(empty.text.hasSuffix(Talk.askNotShown))
        guard case .failure(let line) = Talk.progress(from: ["text": String(repeating: "word ", count: 20)], after: []) else { return XCTFail() }
        XCTAssertFalse(line.text.contains(Talk.askNotShown))
    }
}
