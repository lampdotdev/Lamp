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

    /// A longer fence holds a shorter one as its text, as markdown does when a reply shows a code example in markdown.
    func testALongerFenceKeepsAShorterOneInside() {
        let reply = """
        ````markdown
        ```swift
        let x = 1
        ```
        ````
        """
        XCTAssertEqual(ChatLook.blocks(reply), [.code("```swift\nlet x = 1\n```")])
    }

    /// Only hashes after a space close a heading; one that's part of a word stays.
    func testAHashInAHeadingsWordStays() {
        XCTAssertEqual(ChatLook.blocks("## C#"), [.heading("C#")])
        XCTAssertEqual(ChatLook.blocks("## Done ##"), [.heading("Done")])
    }
}
