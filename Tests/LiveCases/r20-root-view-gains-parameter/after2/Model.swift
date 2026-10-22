import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct ContentView: View {
    var compact = true
    var heading = makeHeading()
    var body: some View {
        let _ = Log.add("root compact=\(compact) heading=\(heading)")
        Card(title: "Milk")
    }
}
struct Card: View {
    let title: String
    var body: some View {
        let _ = Log.add("card")
        Text(title)
    }
}
func makeHeading() -> String { "Groceries" }
