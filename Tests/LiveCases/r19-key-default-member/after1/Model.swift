import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct Theme {
    var accent = "teal"
}
// A theme in the environment, its default written as a computed property, as agents often do.
struct ThemeKey: EnvironmentKey {
    static var defaultValue: Theme { Theme() }
}
extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
struct ContentView: View {
    var body: some View {
        Card()
    }
}
struct Card: View {
    @Environment(\.theme) private var theme
    var body: some View {
        let _ = Log.add("card accent=\(theme.accent)")
        Text(theme.accent)
    }
}
