import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
func initialColumns() -> Int { 3 }
func baseShade() -> String { "light" }
struct ShadeKey {}
extension ShadeKey: EnvironmentKey { static var defaultValue: String { baseShade() } }
extension EnvironmentValues {
    var shade: String {
        get { self[ShadeKey.self] }
        set { self[ShadeKey.self] = newValue }
    }
}
struct ContentView: View {
    private let columns = initialColumns()
    @Environment(\.shade) private var shade
    var body: some View {
        let _ = Log.add("columns=\(columns) shade=\(shade)")
        Text("\(columns)")
    }
}
