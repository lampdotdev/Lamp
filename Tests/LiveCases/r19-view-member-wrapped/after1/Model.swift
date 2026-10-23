import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
func logged(_ text: String) -> String { Log.add(text); return text }
// A view split into parts as agents write them: members returning `some View`, not marked private.
struct ContentView: View {
    var body: some View {
        VStack {
            hero
            Text("Today")
        }
    }
    var hero: some View {
        Text(logged("hero v2"))
            .padding()
            .background(.orange)
    }
}
