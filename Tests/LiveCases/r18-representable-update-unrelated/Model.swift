import SwiftUI
import AppKit
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    nonisolated(unsafe) static var loads = 0
    nonisolated(unsafe) static var controlLoads = 0
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
// A web view as agents write one: the page is loaded in the update.
struct Web: NSViewRepresentable {
    let url: String
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        Log.loads += 1
    }
}
// The same, spelt so the copy step passes its update by: what SwiftUI does without the generation read.
struct Control: NSViewRepresentable {
    let url: String
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView/**/(_ view: NSView, context: Context) {
        Log.controlLoads += 1
    }
}
struct Caption: View {
    var body: some View {
        let _ = Log.add("label v1")
        Text("v1")
    }
}
struct Root: View {
    var body: some View {
        VStack {
            Web(url: "https://example.com").frame(width: 100, height: 50)
            Control(url: "https://example.com").frame(width: 100, height: 50)
            Caption()
        }
    }
}
