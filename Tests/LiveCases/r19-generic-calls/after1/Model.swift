import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
// A helper written generically, as agents do for small utilities.
func ranked<T: Comparable>(_ values: [T]) -> [T] { values.sorted(by: >) }
enum Board {
    static let order = ranked([3, 1, 2])
}
// A card that wraps any content, as agents write one for a consistent look.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack { Badge(); content }
    }
}
struct Badge: View {
    let size = 12
    var body: some View {
        let _ = Log.add("badge size=\(size)")
        Text("\(size)")
    }
}
struct ContentView: View {
    var body: some View {
        Card { Text("Milk") }
    }
}
