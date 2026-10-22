import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct Stats: Codable {
    var wins: Int = 0
    var losses: Int = 0
    var streak: Int = 0
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wins = try c.decodeIfPresent(Int.self, forKey: .wins) ?? 0
        losses = try c.decodeIfPresent(Int.self, forKey: .losses) ?? 0
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
    }
}
struct ContentView: View {
    var body: some View {
        let _ = Log.add("wins=\((try? JSONDecoder().decode(Stats.self, from: Data(#"{"wins":2}"#.utf8)))?.wins ?? -1)")
        Text("Stats")
    }
}
