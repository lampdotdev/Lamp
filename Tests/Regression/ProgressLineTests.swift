import XCTest
@testable import Lamp
import LampSidebarKit

/// The agent's `progress` lines: shown as a turn goes on, staying messages once it's over while its steps are
/// gathered, and held to the same short words for every engine.
final class ProgressLineTests: XCTestCase {
    private func shape(_ items: [ChatItem]) -> [String] {
        items.map { item in
            switch item {
            case .line(let line): line.kind == .progress ? "progress:" + line.text : line.text
            case .statuses(let run): "statuses:" + run.map(\.text).joined(separator: ",")
            case .tools: "tools"
            case .work(_, let title, let steps): "\(title):" + steps.map(\.text).joined(separator: ",")
            }
        }
    }

    func testAFinishedTurnsProgressStaysAndOnlyItsStepsFold() {
        let lines = [LogLine(kind: .user, text: "add a week view"), LogLine(kind: .progress, text: "Columns are in."),
                     LogLine(kind: .status, text: "Ran: ls"), LogLine(kind: .progress, text: "Now the tasks."),
                     LogLine(kind: .agent, text: "Done."), LogLine(kind: .summary, text: "Worked for 9s · $0"),
                     LogLine(kind: .user, text: "more"), LogLine(kind: .progress, text: "Starting on it.")]
        XCTAssertEqual(shape(ChatItem.items(lines, gather: true)),
                       ["add a week view", "progress:Columns are in.", "progress:Now the tasks.", "Done.",
                        "Worked for 9 s:Ran: ls", "more", "progress:Starting on it."])
    }

    /// Every progress line and message stays in the chat while the turn goes on, not only the latest; what's said
    /// after the agent's questions is left out, since the card says it.
    func testEverythingSaidIsShownAsItIsSaid() {
        let lines = [LogLine(kind: .user, text: "go"), LogLine(kind: .agent, text: "I'll start."),
                     LogLine(kind: .progress, text: "One."), LogLine(kind: .agent, text: "Now the week."),
                     LogLine(kind: .progress, text: "Two."), LogLine(kind: .ask, text: "which?"),
                     LogLine(kind: .agent, text: "Waiting for you.")]
        XCTAssertEqual(LogLine.visible(lines, details: false).map(\.text), ["go", "I'll start.", "One.", "Now the week.", "Two.", "which?"])
    }

    /// Once the turn is over, what was said on the way stays a message; the steps fold under it, where the live line was.
    func testWhatWasSaidOnTheWayStaysAMessage() {
        let lines = [LogLine(kind: .user, text: "go"), LogLine(kind: .agent, text: "I'll start."),
                     LogLine(kind: .progress, text: "Layout's in."), LogLine(kind: .agent, text: "Now the week."),
                     LogLine(kind: .status, text: "Ran: ls"), LogLine(kind: .agent, text: "Done."),
                     LogLine(kind: .summary, text: "Worked for 9s · $0")]
        XCTAssertEqual(shape(ChatItem.items(LogLine.visible(lines, details: false), gather: true)),
                       ["go", "I'll start.", "progress:Layout's in.", "Now the week.", "Done.", "Worked for 9 s:Ran: ls"])
    }

    func testWordsAreCheckedAndARepeatIsntShown() {
        let lines = [LogLine(kind: .user, text: "go"), LogLine(kind: .progress, text: "Layout's in.")]
        XCTAssertEqual(try Talk.progress(from: ["text": " Now the timer. "], after: lines).get(), "Now the timer.")
        XCTAssertEqual(try Talk.progress(from: ["text": "Layout's in."], after: lines).get(), nil)
        // A line from an earlier request isn't a repeat.
        XCTAssertEqual(try Talk.progress(from: ["text": "Layout's in."], after: lines + [LogLine(kind: .user, text: "again")]).get(),
                       "Layout's in.")
        XCTAssertThrowsError(try Talk.progress(from: ["text": ""], after: lines).get())
        let long = Array(repeating: "word", count: Talk.Words.progress + 1).joined(separator: " ")
        XCTAssertThrowsError(try Talk.progress(from: ["text": long], after: lines).get())
    }

    /// The same tool for every engine: in the shared definitions, pi's list, Claude Code's allowed tools and the
    /// prompt that tells them all when to use it.
    @MainActor func testEveryEngineHasIt() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let json = try Data(contentsOf: root.appendingPathComponent("Resources/lamp-tools.json"))
        let tools = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [[String: Any]])
        XCTAssertTrue(tools.contains { $0["name"] as? String == "progress" })
        let extensionCode = try String(contentsOf: root.appendingPathComponent("Resources/lamp-tools.ts"), encoding: .utf8)
        XCTAssertTrue(extensionCode.contains(#""ask", "progress", "write_wish""#))
        let engines = try String(contentsOf: root.appendingPathComponent("Sources/Lamp/Engines.swift"), encoding: .utf8)
        XCTAssertTrue(engines.contains("mcp__lamp__progress"))
        let agent = try String(contentsOf: root.appendingPathComponent("Sources/Lamp/Agent.swift"), encoding: .utf8)
        XCTAssertTrue(agent.contains(",ask,progress,write_wish,"))
        XCTAssertTrue(Agent.tryRules.contains("`progress`"))
        XCTAssertEqual(ToolCall("mcp__lamp__progress".replacingOccurrences(of: "mcp__lamp__", with: "")).action, .progress)
    }

    /// The sidebar gets it as a message while the turn goes on, and as a status line with the progress mark once
    /// it's folded, so a sidebar from before it still reads the chat.
    @MainActor func testTheSidebarGetsAMessageThenAMarkedStatusLine() {
        let going = SidebarServer.progress(LogLine(kind: .progress, text: "Columns are in."), gap: 8)
        XCTAssertEqual(going.kind, .agent)
        XCTAssertNil(going.symbol)
        let folded = SidebarServer.progress(LogLine(kind: .progress, text: "x"), gap: 4, folded: true)
        XCTAssertEqual(folded.kind, .status)
        XCTAssertEqual(folded.symbol, ChatLook.progressSymbol)
    }

    /// A run that ended on a question still waiting isn't gathered when its summary arrives, so nothing above the
    /// card moves; once it's answered, it is.
    func testNothingAboveAWaitingCardFolds() {
        var lines = [LogLine(kind: .user, text: "go"), LogLine(kind: .agent, text: "I'll look."),
                     LogLine(kind: .progress, text: "One."), LogLine(kind: .ask, text: "which?",
                                                                    ask: Talk.Ask(layout: .steps, questions: [])),
                     LogLine(kind: .summary, text: "Worked for 9s · $0")]
        XCTAssertEqual(shape(ChatItem.items(lines, gather: true)), ["go", "I'll look.", "progress:One.", "which?"])
        lines[3].ask?.answers = ["A"]
        XCTAssertEqual(shape(ChatItem.items(lines, gather: true)), ["go", "I'll look.", "progress:One.", "which?"])
    }

    /// Spaced as the agent's messages are, two in a row close together.
    func testSpacedAsMessages() {
        let progress = ChatItem.line(LogLine(kind: .progress, text: "One."))
        let agent = ChatItem.line(LogLine(kind: .agent, text: "Two."))
        XCTAssertEqual(ChatItem.gap(after: progress, before: agent, isFinalAnswer: false),
                       ChatItem.gap(after: agent, before: agent, isFinalAnswer: false))
    }
}
