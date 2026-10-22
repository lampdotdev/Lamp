import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
import Observation
@Observable final class Store { var count = 3 }
struct ContentView: View {
    var body: some View { Row(title: "Milk").environment(Store()).environment(\.lineLimit, 2).environment(\.colorScheme, .dark) }
}
struct Row: View {
    let title: String
    @Environment(\.lineLimit) private var limit
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let _ = Log.add("row \(title) limit=\(limit ?? 0) scheme=\(scheme == .dark ? "dark" : "light")")
        Text(title)
    }
}
