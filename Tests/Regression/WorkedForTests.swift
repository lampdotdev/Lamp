import XCTest
@testable import Lamp
import LampSidebarKit

/// A finished turn's steps are gathered into one "Worked for …" line above its answer; a turn still going isn't.
final class WorkedForTests: XCTestCase {
    func testAFinishedTurnsStepsGoAboveItsAnswer() {
        let lines = [LogLine(kind: .user, text: "make it"), LogLine(kind: .status, text: "Ran: ls"),
                     LogLine(kind: .status, text: "Building…"), LogLine(kind: .status, text: ChatLook.reloaded),
                     LogLine(kind: .agent, text: "Done."), LogLine(kind: .status, text: "Puzzle is ready"),
                     LogLine(kind: .summary, text: "Worked for 2m 3s · $0.12"),
                     LogLine(kind: .user, text: "more"), LogLine(kind: .status, text: "Ran: pwd")]
        let items = ChatItem.items(lines, gather: true)
        let shape = items.map { item -> String in
            switch item {
            case .line(let line): line.text
            case .statuses(let run): "statuses:" + run.map(\.text).joined(separator: ",")
            case .tools: "tools"
            case .work(_, let title, let steps): "\(title):" + steps.map(\.text).joined(separator: ",")
            }
        }
        XCTAssertEqual(shape, ["make it", "statuses:\(ChatLook.reloaded)", "Worked for 2 min 3 s:Ran: ls,Puzzle is ready",
                               "Done.", "more", "statuses:Ran: pwd"])
    }

    func testHowLongItWorked() {
        XCTAssertEqual(ChatItem.workedFor("Worked for 8s · $0.01"), "Worked for 8 s")
        XCTAssertEqual(ChatItem.workedFor("Worked for 3m 0s · $0.01"), "Worked for 3 min")
        XCTAssertEqual(ChatItem.workedFor("Worked for 1m 5s · $0.01"), "Worked for 1 min 5 s")
    }
}
