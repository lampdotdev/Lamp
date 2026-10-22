import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct ContentView: View {
    var body: some View { Row(title: "Milk", subtitle: "2 litres") }
}
struct Row: View {
    let title: String
    let subtitle: String
    @State private var expanded = false
    @State private var draft = ""
    var body: some View {
        let _ = Log.add("row \(title) \(subtitle) expanded=\(expanded)")
        Text(title).onAppear { if !expanded { expanded = true } }
    }
}
