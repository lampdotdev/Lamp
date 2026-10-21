import SwiftUI
import Charts
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
func logged(_ text: String) -> String { Log.add(text); return text }
// Chart marks of the app's own, as agents split a chart's content out of a view.
struct SalesMarks: ChartContent {
    var body: some ChartContent {
        BarMark(x: .value("Day", logged("marks=Orders")), y: .value("Count", 3))
    }
}
struct ContentView: View {
    var body: some View {
        VStack {
            Text(logged("title=Orders"))
            Chart { SalesMarks() }
        }
    }
}
