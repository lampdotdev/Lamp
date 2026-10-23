import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct ContentView: View {
    var body: some View {
        ListView()
    }
}
struct ListView: View {
    @AppStorage("r20-view-parameter-unsteady-hide") private var hideDone = false
    @Environment(\.openURL) private var openURL
    var body: some View {
        let _ = Log.add("list hideDone=\(hideDone) help")
        VStack {
            Toggle("Hide done", isOn: $hideDone)
            Button("Help") { openURL(URL(string: "https://example.com")!) }
            Row(title: "Milk")
        }
    }
}
struct Row: View {
    let title: String
    var token = UUID().uuidString
    var body: some View {
        let _ = Log.add("row \(title) token=\(token.count)")
        Text(title)
    }
}
