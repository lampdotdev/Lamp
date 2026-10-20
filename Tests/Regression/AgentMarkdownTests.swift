import XCTest
import SwiftUI
import LampSidebarKit

/// An agent's reply with a table used to come out in the chat as its pipes and dashes.
@MainActor
final class AgentMarkdownTests: XCTestCase {
    /// Each piece as words: what it says and, for a table, how its columns line up.
    private func shape(_ pieces: [ChatLook.Piece]) -> [String] {
        pieces.map { piece in
            switch piece {
            case .text(let text): "text:" + String(text.characters)
            case .code(let code): "code:" + code
            case .rule: "rule"
            case .table(let columns, let header, let rows):
                "table:" + columns.map { $0 == .trailing ? "trailing" : $0 == .center ? "center" : "leading" }.joined(separator: ",")
                    + ([header] + rows).map { "|" + $0.map { String($0.characters) }.joined(separator: ",") }.joined()
            }
        }
    }

    func testATableInAReplyIsATable() {
        let reply = """
        Here's where the time goes:

        | Lines | File |
        |------:|------|
        | 412 | `TodayView.swift` |
        | 96 | `Theme.swift` |

        The view is the place to start.
        """
        XCTAssertEqual(shape(ChatLook.pieces(reply)), [
            "text:Here's where the time goes:",
            "table:trailing,leading|Lines,File|412,TodayView.swift|96,Theme.swift",
            "text:The view is the place to start.",
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
        XCTAssertEqual(shape(ChatLook.pieces(reply)), ["code:```swift\nlet x = 1\n```"])
    }

    /// Only hashes after a space close a heading; one that's part of a word stays.
    func testAHashInAHeadingsWordStays() {
        XCTAssertEqual(shape(ChatLook.pieces("## C#")), ["text:C#"])
        XCTAssertEqual(shape(ChatLook.pieces("## Done ##")), ["text:Done"])
    }
}
