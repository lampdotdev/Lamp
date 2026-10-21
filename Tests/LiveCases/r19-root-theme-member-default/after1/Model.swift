import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
// A theme as agents write one: a struct of the app's look, its values as starting values.
struct Theme {
    var accent = "teal"
    var radius = 12
    static let standard = Theme()
}
struct ContentView: View {
    private let theme = Theme()
    private let standard = Theme.standard
    var body: some View {
        let _ = Log.add("root theme=\(theme.accent) standard=\(standard.accent)")
        VStack {
            Text(theme.accent)
            Card()
        }
    }
}
struct Card: View {
    private let theme = Theme()
    var body: some View {
        let _ = Log.add("card theme=\(theme.accent) standard=\(Theme.standard.accent)")
        Text(theme.accent)
    }
}
