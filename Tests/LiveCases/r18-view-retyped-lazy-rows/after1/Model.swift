import SwiftUI
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
struct Root: View {
    var body: some View {
        VStack {
            List {
                ForEach(0..<3, id: \.self) { n in Meter(label: "list \(n)", level: Double(n)) }
            }
            .frame(height: 150)
            ScrollView {
                LazyVStack {
                    ForEach(0..<3, id: \.self) { n in Meter(label: "lazy \(n)", level: Double(n)) }
                }
            }
            .frame(height: 150)
        }
    }
}
