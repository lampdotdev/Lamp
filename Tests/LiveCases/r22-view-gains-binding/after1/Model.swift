import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct ContentView: View {
    var body: some View { ListView() }
}
struct ListView: View {
    @State private var done = false
    var body: some View {
        let _ = Log.add("list")
        Row(title: "Milk", isDone: $done)
    }
}
struct Row: View {
    let title: String
    @Binding var isDone: Bool
    var body: some View {
        let _ = Log.add("row \(title) done=\(isDone)")
        Toggle(title, isOn: $isDone).onAppear { if !isDone { isDone = true } }
    }
}
