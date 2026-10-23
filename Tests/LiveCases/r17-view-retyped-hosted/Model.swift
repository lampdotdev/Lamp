import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct Meter: View {
    var label: String
    var level: Int
    var body: some View {
        let _ = Log.add(reading)
        Text(reading)
    }
    var reading: String { "\(label) level=\(level)" }
}
struct Badge: ViewModifier {
    func body(content: Content) -> some View { content.overlay(Meter(label: "badge", level: 3)) }
}
struct Root: View {
    var body: some View { Text("x").modifier(Badge()) }
}
