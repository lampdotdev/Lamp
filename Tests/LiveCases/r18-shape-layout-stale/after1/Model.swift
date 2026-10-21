import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct Wave: Shape {
    func path(in rect: CGRect) -> Path { Log.add("wave v2"); return Path(rect.insetBy(dx: 1, dy: 1)) }
}
// The same, with a field the copy step could add: the generation when the value was made.
struct MadeWave: Shape {
    var made: Int = MainActor.assumeIsolated { LampLive.generation }
    func path(in rect: CGRect) -> Path { Log.add("made wave v2"); return Path(rect.insetBy(dx: 1, dy: 1)) }
}
struct Flow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { CGSize(width: 100, height: 20) }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        Log.add("flow v2")
        for s in subviews { s.place(at: bounds.origin, proposal: .unspecified) }
    }
}
struct MadeFlow: Layout {
    var made: Int = MainActor.assumeIsolated { LampLive.generation }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { CGSize(width: 100, height: 20) }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        Log.add("made flow v2")
        for s in subviews { s.place(at: bounds.origin, proposal: .unspecified) }
    }
}
struct Root: View {
    var body: some View {
        VStack {
            Wave().stroke(lineWidth: 1).frame(width: 40, height: 20)
            MadeWave().stroke(lineWidth: 1).frame(width: 40, height: 20)
            Flow { Text("a") }
            MadeFlow { Text("b") }
        }
    }
}
