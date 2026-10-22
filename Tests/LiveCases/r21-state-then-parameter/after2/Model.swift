import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct ContentView: View {
    var body: some View { Row(title: "Milk", isDone: true) }
}
struct Row: View {
    let title: String
    @State var expanded = false
    let isDone: Bool
    var body: some View {
        let _ = Log.add("row \(title) expanded=\(expanded) done=\(isDone)")
        Text(title)
    }
}
