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
struct Root: View {
    var body: some View { Row { Text("a") } }
}
