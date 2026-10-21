import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct Row: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { Self.measured("size v1") }
    static func measured(_ tag: String) -> CGSize { Log.add(tag); return CGSize(width: 100, height: 20) }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for s in subviews { s.place(at: bounds.origin, proposal: .unspecified) }
    }
}
// Bodies whose braces and returns aren't this method's own: a brace in a string, a nested closure's return, and
// one that returns with `return` after a statement.
struct Quoted: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { Row.measured("} v1") }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
}
struct Summed: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { subviews.reduce(CGSize.zero) { _, subview in return subview.sizeThatFits(proposal) } }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
}
struct Stepped: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = 100.0 // a comment with a brace }
        return CGSize(width: width, height: 20)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
}
struct Root: View {
    var body: some View { VStack { Row { Text("a") }; Quoted { Text("b") }; Summed { Text("c") }; Stepped { Text("d") } } }
}
