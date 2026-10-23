import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
enum Tab: String, CaseIterable, Identifiable {
    case today, history, stats
    var id: String { rawValue }
}
struct ContentView: View {
    @State private var tab: Tab = .today
    var body: some View {
        let _ = Log.add("tab=\(tab.rawValue) tabs=\(Tab.allCases.count)")
        Picker("Tab", selection: $tab) {
            ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
        }
    }
}
