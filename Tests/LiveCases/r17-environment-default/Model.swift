import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.joined(separator: ", ") }
}
struct AccentKey: EnvironmentKey { static let defaultValue = "blue" }
extension EnvironmentValues {
    var accent: String {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}
struct Panel: View {
    @Environment(\.accent) private var accent
    @AppStorage("r17-panel-size") private var size = 10
    var body: some View {
        let _ = Log.add("accent=\(accent) size=\(size)")
        Text("x")
    }
}
