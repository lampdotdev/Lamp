import XCTest
@testable import Lamp

/// Steps named in the engine's own words: what Claude Code or pi says each shell command is for, and the heading of a
/// Codex reasoning summary. The lines are the engines' own output, recorded on 2026-10-19 (Claude Code 2.1.280 with
/// Sonnet 5.5, the app's path shortened; ChatGPT Codex with reasoning summaries on; pi 1.0.0 with Opus 5.5 through
/// OpenRouter and Lamp's extension), cut to the fields Lamp reads.
final class StepNamesTests: XCTestCase {
    static let claudeBash = "{\"type\":\"assistant\",\"message\":{\"model\":\"claude-sonnet-5-5\",\"id\":\"msg_011CgCFmhCxLiHDaSTPgnSdK\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_01KynBXeCfyBy6AZLr4ost2z\",\"name\":\"Bash\",\"input\":{\"command\":\"cd \\\"/Users/me/Library/Application Support/Lamp/Apps/hotshelf\\\" && wc -l Sources/*.swift\",\"description\":\"Count lines in each Swift file\"},\"caller\":{\"type\":\"direct\"}}]}}"
    static let codexReasoning = "{\"type\":\"item.completed\",\"item\":{\"id\":\"item_11\",\"type\":\"reasoning\",\"text\":\"**Considering UI design**\\n\\nI'm thinking about how to handle the empty rows in my patch design. Should I show a small message in those rows, or maybe a hint? I wonder if I can duplicate the \\\"favorite\\\" rows and move them to the top for a more natural flow. If I'm excluding certain families, it'll be interesting to see how that affects the layout. I’ll implement a fixed-sized text in the empty row, but I want to avoid cluttering it!\"}}"

    static let piBash = "{\"type\":\"tool_execution_start\",\"toolCallId\":\"toolu_01B98vbsKpjWVqP2spw4EgB2\",\"toolName\":\"bash\",\"args\":{\"command\":\"wc -l Sources/*.swift | sort -n; echo; git log -n 5 --format='%h · %ad · %s' --date=format:'%b %d, %Y %H:%M'\",\"description\":\"Counting code lines and listing recent versions\"}}"

    func testClaudeCodeNamesACommandByItsDescription() {
        let events = Agent.parseClaude(Self.claudeBash)
        guard case .naming(let words)? = events.first else { return XCTFail("no name: \(events)") }
        XCTAssertEqual(words, "Count lines in each Swift file")
        guard case .tool(let text, _, _, _, _)? = events.last else { return XCTFail("no tool call") }
        XCTAssertEqual(ToolCall(text).action, .run)
    }

    /// pi's own bash takes only the command; Lamp's extension gives it a description, which the model fills in.
    func testPiNamesACommandByTheDescriptionLampsExtensionAsksFor() {
        let events = Agent.parse(Self.piBash, engine: .pi)
        guard case .naming(let words)? = events.first else { return XCTFail("no name: \(events)") }
        XCTAssertEqual(words, "Counting code lines and listing recent versions")
        guard case .tool(let text, _, _, _, _)? = events.last else { return XCTFail("no tool call") }
        XCTAssertEqual(ToolCall(text).action, .run)
    }

    func testCodexNamesWhatFollowsByItsReasoningHeading() {
        let events = Agent.parseCodex(Self.codexReasoning)
        guard case .naming(let words)? = events.first, events.count == 1 else { return XCTFail("no name: \(events)") }
        XCTAssertEqual(words, "Considering UI design")
    }

    func testASummaryWithoutAHeadingNamesNothing() {
        XCTAssertNil(Agent.heading(of: "I'm thinking about how to handle the empty rows."))
    }

    /// Commands one after another under one name are one step in the chat, the name once and the
    /// commands under it; unnamed ones stay a step each, as they were.
    func testCommandsGivenOneNameAreOneStep() {
        let named = { (command: String, said: String?) in LogLine(kind: .status, text: "Ran: \(command)", said: said) }
        let items = ChatItem.items([
            named("cat starter.md", "Reading how the shelf works"),
            named("cat App.swift Model.swift", "Reading how the shelf works"),
            named("cat ShelfView.swift", "Reading how the shelf works"),
            named("swift build", "Checking it builds"),
            named("ls", nil),
            named("ls Sources", nil),
        ])
        guard case .statuses(let lines)? = items.first, items.count == 1 else { return XCTFail("\(items)") }
        XCTAssertEqual(lines.map(\.said), ["Reading how the shelf works", "Checking it builds", nil, nil])
        XCTAssertEqual(lines[0].text, "Ran: cat starter.md\ncat App.swift Model.swift\ncat ShelfView.swift")
    }
}
