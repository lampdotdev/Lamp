import SwiftUI
import AppKit
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct Meter: View {
    var label: String
    var level: Double
    var body: some View {
        let _ = Log.add(reading)
        Text(reading)
    }
    var reading: String { "\(label) level=\(level)" }
}
enum Keep { @MainActor static var windows: [NSWindow] = [] }
// A detail panel the app opens from a view, as menu bar and utility apps do.
@MainActor func openPanel() {
    let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
    panel.contentView = NSHostingView(rootView: Meter(label: "panel", level: 4))
    Keep.windows.append(panel)
}
struct Root: View {
    var body: some View {
        Meter(label: "root", level: 3)
            .onAppear { openPanel() }
    }
}
