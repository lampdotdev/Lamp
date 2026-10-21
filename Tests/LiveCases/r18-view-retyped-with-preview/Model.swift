import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct RailText: View {
    var label: String
    var heat: Int?
    var body: some View {
        let _ = Log.add(reading)
        Text(reading)
    }
    var reading: String { "\(label) heat=\(heat.map(String.init) ?? "none")" }
}
struct Shelf: View { var body: some View { RailText(label: "IPA", heat: 3) } }
#Preview {
    RailText(label: "Preview", heat: 1)
}
