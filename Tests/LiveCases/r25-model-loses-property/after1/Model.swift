import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
import Observation
@Observable final class Store {
    var items = ["Milk"]
    var count = 3
}
struct ContentView: View {
    @State private var store = Store()
    var body: some View {
        let _ = Log.add("items=\(store.items.count) count=\(store.count)")
        Text("Store").onAppear { if store.count == 3 { store.count = 4 } }
    }
}
