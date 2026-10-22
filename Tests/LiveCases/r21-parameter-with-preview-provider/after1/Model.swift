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
    let isDone: Bool
    var body: some View {
        let _ = Log.add("row \(title) done=\(isDone)")
        Text(title)
    }
}
struct Row_Previews: PreviewProvider {
    static var previews: some View { Row(title: "Preview", isDone: false) }
}
