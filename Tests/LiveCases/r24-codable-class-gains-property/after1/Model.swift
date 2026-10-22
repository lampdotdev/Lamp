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
func decoded<T: Decodable>(_ type: T.Type, _ json: String) -> T? { try? JSONDecoder().decode(T.self, from: Data(json.utf8)) }
final class Basket: Codable { var name = "Weekly"; var count = 0 }
struct ContentView: View {
    var body: some View {
        let _ = Log.add("saved \(encoded(Basket()))")
        Text("Basket")
    }
}
