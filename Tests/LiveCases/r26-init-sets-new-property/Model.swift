import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
import Observation
@Observable final class Basket {
    var items: [String]
    init() { items = ["Milk"] }
}
struct ContentView: View {
    @State private var basket = Basket()
    var body: some View {
        let _ = Log.add("items=\(basket.items.count)")
        Text("Basket")
    }
}
