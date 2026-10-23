import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
func logged(_ text: String) -> String { Log.add(text); return text }
// A toolbar of the app's own, as agents split one out of a view.
struct MainToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem {
            Button(logged("toolbar=Share")) {}
        }
    }
}
struct ContentView: View {
    var body: some View {
        Text(logged("title=Share"))
            .frame(width: 300, height: 200)
            .toolbar { MainToolbar() }
    }
}
