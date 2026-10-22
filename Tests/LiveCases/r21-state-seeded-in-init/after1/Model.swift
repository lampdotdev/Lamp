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
    @State private var draft: String
    init(title: String) { self.title = title; _draft = State(initialValue: title) }
    var body: some View {
        let _ = Log.add("row \(title) draft=\(draft)")
        Text(title)
    }
}
