import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct ContentView: View {
    /* count; kept across draws */ var count = 7
    var body: some View {
        let _ = Log.add("count=\(count)")
        Panel()
    }
}
struct Panel: View {
    // made private
    private
    var total = 3
    var body: some View {
        let _ = Log.add("total=\(total)")
        Text("Panel")
    }
}
