import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
private typealias UInt64 = String
struct RailText: View {
    var label: String
    fileprivate var heat: UInt64? = "hot"
    var body: some View {
        let _ = Log.add(reading)
        Text(reading)
    }
    var reading: String { "\(label) heat=\(heat ?? "none")" }
}
struct Shelf: View { var body: some View { RailText(label: "IPA") } }
@MainActor func extra() -> String { "" }
