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
    @AppStorage("r19-view-gains-appstorage-hide") private var hideDone = false
    var body: some View {
        let _ = Log.add("list hideDone=\(hideDone)")
        VStack {
            Toggle("Hide done", isOn: $hideDone)
            Row(title: "Milk")
        }
    }
}
struct Row: View {
    let title: String
    var body: some View {
        let _ = Log.add("row \(title)")
        Text(title)
    }
}
