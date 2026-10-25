import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct Card: View {
    @State private var taps = 3
    var body: some View {
        let _ = Log.add("taps=\(taps)!")
        Text("Card").onAppear { taps = 9 }
    }
}
