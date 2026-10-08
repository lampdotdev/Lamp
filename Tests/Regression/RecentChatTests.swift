import XCTest
@testable import Lamp

/// A long chat shows only its end until asked for more. Where that end starts must be the start of a turn,
/// and must not move while the latest turn is being written.
final class RecentChatTests: XCTestCase {
    /// `turns` requests, each followed by `replies` lines from the agent.
    private func chat(turns: Int, replies: Int) -> [LogLine] {
        (0..<turns).flatMap { turn in
            [LogLine(kind: .user, text: "Request \(turn)")] + (0..<replies).map { LogLine(kind: .agent, text: "Reply \(turn).\($0)") }
        }
    }

    func testAShortChatIsShownWhole() {
        XCTAssertEqual(LogLine.recentStart(in: [], atLeast: 60), 0)
        XCTAssertEqual(LogLine.recentStart(in: chat(turns: 5, replies: 3), atLeast: 60), 0)
    }

    func testALongChatStartsAtARequest() {
        let lines = chat(turns: 100, replies: 3)
        let start = LogLine.recentStart(in: lines, atLeast: 60)
        XCTAssertEqual(lines[start].kind, .user)
        // The latest request is line 396; fifteen turns of four lines come before it.
        XCTAssertEqual(start, 396 - 60)
        XCTAssertEqual(LogLine.recentStart(in: lines, atLeast: 120), 396 - 120)
        XCTAssertEqual(LogLine.recentStart(in: lines, atLeast: 10_000), 0)
    }

    func testTheStartStaysPutWhileTheLatestTurnIsWritten() {
        var lines = chat(turns: 100, replies: 3)
        let start = LogLine.recentStart(in: lines, atLeast: 60)
        lines += (0..<500).map { LogLine(kind: .detail, text: "Step \($0)") }
        XCTAssertEqual(LogLine.recentStart(in: lines, atLeast: 60), start)
    }

    /// A turn longer than one lot takes the chat further back than asked. The next lot starts from there:
    /// asking again must always show something more.
    func testShowingEarlierAlwaysShowsMore() {
        let lines = chat(turns: 3, replies: 2) + chat(turns: 1, replies: 180) + chat(turns: 1, replies: 1)
        var start = LogLine.recentStart(in: lines, atLeast: 60)
        XCTAssertEqual(start, 9)
        var steps = 0
        while start > 0 {
            let next = LogLine.recentStart(in: lines, atLeast: LogLine.reach(in: lines, from: start) + 60)
            XCTAssertLessThan(next, start)
            start = next
            steps += 1
        }
        XCTAssertEqual(steps, 1)
    }

    func testLinesBeforeTheFirstRequestComeWithIt() {
        let lines = [LogLine(kind: .status, text: "Imported")] + chat(turns: 3, replies: 2)
        XCTAssertEqual(LogLine.recentStart(in: lines, atLeast: 60), 0)
    }
}
