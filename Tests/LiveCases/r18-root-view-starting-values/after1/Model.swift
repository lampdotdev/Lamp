import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
// The app's main view, as agents write one: its layout constants kept as properties of the view.
struct ContentView: View {
    @AppStorage("r18-root-size") private var size = 20
    private let columns = 3
    private let title = "Pantry"
    var body: some View {
        let _ = Log.add("root columns=\(columns) title=\(title) size=\(size)")
        VStack {
            Text(title)
            Shelves()
        }
    }
}
struct Shelves: View {
    private let columns = 3
    private let title = "Pantry"
    var body: some View {
        let _ = Log.add("child columns=\(columns) title=\(title)")
        Text("\(columns)")
    }
}
