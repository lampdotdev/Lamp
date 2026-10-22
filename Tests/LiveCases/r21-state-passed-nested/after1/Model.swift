import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct ContentView: View {
    var body: some View { Panel(child: Row()) }
}
struct Panel: View {
    let child: Row
    @State var open = false
    var body: some View {
        let _ = Log.add("panel")
        child
    }
}
struct Row: View {
    @State var open = false
    var body: some View {
        let _ = Log.add("row")
        Text("Row")
    }
}
