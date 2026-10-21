import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    nonisolated(unsafe) static var made = 0
    static func next() -> Int { made += 1; return made }
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
final class Editor: ObservableObject { let serial = Log.next() }
struct Child: View {
    @State private var first = Log.next()
    @StateObject private var editor = Editor()
    var body: some View {
        let _ = Log.add("child first made \(first), model \(editor.serial)")
        Text("child")
    }
}
struct Root: View {
    var body: some View {
        VStack {
            Text("title")
            Child()
        }
    }
}
