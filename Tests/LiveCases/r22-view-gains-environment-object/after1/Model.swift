import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
import Observation
@Observable final class Store { var count = 3 }
struct ContentView: View {
    var body: some View { Row(title: "Milk").environment(Store()).environment(\.lineLimit, 2) }
}
struct Row: View {
    let title: String
    @Environment(Store.self) private var store
    var body: some View {
        let _ = Log.add("row \(title) count=\(store.count)")
        Text(title)
    }
}
