import SwiftUI
import AppKit
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct Framed: ViewModifier {
    func body(content: Content) -> some View {
        let _ = Log.add("modifier v1")
        content.padding(1)
    }
}
struct Wave: Shape {
    func path(in rect: CGRect) -> Path {
        Log.add("shape v1")
        return Path(rect.insetBy(dx: 1, dy: 1))
    }
}
struct Pill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let _ = Log.add("style v1")
        configuration.label.padding(2)
    }
}
struct Row: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        Log.add("layout v1")
        return CGSize(width: 100, height: 20)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for s in subviews { s.place(at: bounds.origin, proposal: .unspecified) }
    }
}
struct Blur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView { NSVisualEffectView() }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { Log.add("representable v1") }
}
struct Root: View {
    var body: some View {
        let _ = Log.add("root v1")
        VStack {
            Text("hi").modifier(Framed())
            Wave().stroke(lineWidth: 1).frame(width: 40, height: 20)
            Button("Go") {}.buttonStyle(Pill())
            Row { Text("a") }
            Blur().frame(width: 10, height: 10)
        }
    }
}
