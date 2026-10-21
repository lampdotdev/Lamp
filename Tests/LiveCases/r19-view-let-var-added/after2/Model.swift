import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct ContentView: View {
    var body: some View { Card(title: "Milk") }
}
struct Card: View {
    let title: String
    private let spacing: CGFloat = 8
    private var padding: CGFloat = 12
    var body: some View {
        let _ = Log.add("card spacing=\(spacing) padding=\(padding)")
        VStack(spacing: spacing) { Text(title) }.padding(padding)
    }
}
