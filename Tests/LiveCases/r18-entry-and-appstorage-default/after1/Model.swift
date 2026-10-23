import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.joined(separator: ", ") }
}
extension EnvironmentValues {
    @Entry var accent: String = "red"
}
struct ShadeKey: EnvironmentKey { static var defaultValue: String { "light" } }
extension EnvironmentValues {
    var shade: String {
        get { self[ShadeKey.self] }
        set { self[ShadeKey.self] = newValue }
    }
}
struct Panel: View {
    @Environment(\.accent) private var accent
    @Environment(\.shade) private var shade
    @AppStorage("r18-panel-size") private var size = 10
    var body: some View {
        let _ = Log.add("accent=\(accent) shade=\(shade) size=\(size)")
        Text("x")
    }
}
// The panel is made by a body, as every view below a window's root is.
struct Root: View { var body: some View { Panel() } }
