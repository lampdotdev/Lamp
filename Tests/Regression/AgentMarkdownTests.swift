import XCTest
import SwiftUI
import LampSidebarKit

/// An agent's reply with a table used to come out in the chat as its pipes and dashes.
@MainActor
final class AgentMarkdownTests: XCTestCase {
    func testATableInAReplyIsATable() {
        let reply = """
        Here's where the time goes:

        | Lines | File |
        |------:|------|
        | 412 | `TodayView.swift` |
        | 96 | `Theme.swift` |

        The view is the place to start.
        """
        XCTAssertEqual(ChatLook.blocks(reply), [
            .prose("Here's where the time goes:"),
            .table(header: ["Lines", "File"], alignments: [.trailing, .leading],
                   rows: [["412", "`TodayView.swift`"], ["96", "`Theme.swift`"]]),
            .prose("The view is the place to start."),
        ])
    }
}
