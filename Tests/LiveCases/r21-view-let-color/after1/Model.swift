import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct ContentView: View {
    var body: some View { Row(title: "Milk") }
}
struct Row: View {
    let title: String
    private let tint = Color.blue
    var body: some View {
        let _ = Log.add("row \(title) tint=\(tint == .blue)")
        Text(title)
    }
}
