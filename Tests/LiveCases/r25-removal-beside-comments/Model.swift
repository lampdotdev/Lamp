import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct ContentView: View {
    @State private var gone = "x"
    /* count; kept across draws */ var count = 7
    var body: some View {
        let _ = Log.add("count=\(count) gone=\(gone)")
        Panel()
    }
}
struct Panel: View {
    @State private var dropped = 1.5
    // made private
    private
    var total = 3
    var body: some View {
        let _ = Log.add("total=\(total) dropped=\(dropped)")
        Text("Panel")
    }
}
