import SwiftUI
import AppKit
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    nonisolated(unsafe) static var configured = ""
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
// A text field from AppKit, as agents wrap one: how it looks is set up once, in makeNSView.
struct NoteField: NSViewRepresentable {
    var text: String
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Add a note…"
        field.isBordered = false
        Log.add("make v2")
        Log.configured = "placeholder=\(field.placeholderString ?? "") bordered=\(field.isBordered)"
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) { field.stringValue = text }
}
struct Root: View {
    var body: some View { NoteField(text: "milk").frame(width: 200, height: 24) }
}
