import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
import Observation
@Observable final class Basket {
    var items: [String]
    var limit = 0
    init() { items = ["Milk"]; limit = 3 }
}
struct ContentView: View {
    @State private var basket = Basket()
    var body: some View {
        let _ = Log.add("items=\(basket.items.count) limit=\(basket.limit)")
        Text("Basket")
    }
}
