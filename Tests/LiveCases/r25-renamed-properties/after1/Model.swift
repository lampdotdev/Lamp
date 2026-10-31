import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
import Observation
struct Item { var name: String; var note = "" }
@Observable final class Store {
    var items = [Item(name: "Milk", note: "2 liters")]
    var name = "Weekly"
}
struct ContentView: View {
    @State private var store = Store()
    var body: some View {
        let _ = Log.add("\(store.name): \(store.items.map(\.name))")
        Row(title: "Milk", detail: "2 liters")
    }
}
struct Row: View {
    let title: String
    let detail: String
    var body: some View {
        let _ = Log.add("row \(title) detail=\(detail)")
        Text(title)
    }
}
