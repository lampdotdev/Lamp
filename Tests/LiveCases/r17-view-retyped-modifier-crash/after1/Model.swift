import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct RankBadge: View {
    var rank: Int
    var body: some View {
        let names = ["none", "bronze", "silver", "gold"]
        let _ = Log.add("rank \(names[rank])")
        Text(names[rank])
    }
}
// A card style, as apps write one: the badge it adds is made by the modifier's body.
struct Ranked: ViewModifier {
    func body(content: Content) -> some View { content.overlay(RankBadge(rank: 2)) }
}
struct Root: View {
    var body: some View { Text("Ale").modifier(Ranked()) }
}
