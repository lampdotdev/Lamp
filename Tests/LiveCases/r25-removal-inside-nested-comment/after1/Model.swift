import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct ContentView: View {
    /* private /* temporarily disabled */ */ var count = 7
    var body: some View {
        let _ = Log.add("count=\(count)")
        Text("Count")
    }
}
