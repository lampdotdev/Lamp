import Foundation
// Not a SwiftUI modifier: a page template whose method happens to be called body(content:).
struct Page {
    func body(content: String) -> String { "<body>\(content)</body>" }
}
func show() -> String { Page().body(content: "milk") }
