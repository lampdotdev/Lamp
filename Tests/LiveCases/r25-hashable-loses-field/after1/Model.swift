import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct Item: Hashable { var name: String }
struct ContentView: View {
    var body: some View {
        let _ = Log.add("items=\(Set([Item(name: "Milk")]).count)")
        Text("Items")
    }
}
