import SwiftUI
import AppKit
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct Meter: View {
    var level: Double
    var body: some View {
        let _ = Log.add("level=\(level)")
        Text("level=\(level)")
    }
}
func makeMeter() -> Meter { Meter(level: 3) }
struct Root: View {
    var body: some View { makeMeter() }
}
@MainActor func openPanel() -> NSView { NSHostingView(rootView: makeMeter()) }
