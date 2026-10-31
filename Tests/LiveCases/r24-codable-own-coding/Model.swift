import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
func encoded<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return String(decoding: (try? encoder.encode(value)) ?? Data(), as: UTF8.self)
}
struct Item: Codable {
    var name: String
    init(name: String) { self.name = name }
    init(from decoder: Decoder) throws { name = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(name) }
}
struct ContentView: View {
    var body: some View {
        let _ = Log.add("saved \(encoded(Item(name: "Milk")))")
        Text("Items")
    }
}
