import SwiftUI
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ line: String) { if !lines.contains(line) { lines.append(line) } }
    static func take() -> String { defer { lines = [] }; return lines.sorted().joined(separator: ", ") }
}
struct ShowApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
struct Stats: Codable, Equatable {
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
final class Store: ObservableObject {
    @Published var stats: Stats
    init() {
        let saved = #"{"wins":2,"losses":1}"#
        stats = (try? JSONDecoder().decode(Stats.self, from: Data(saved.utf8))) ?? Stats()
    }
    func won() { stats.wins += 1; stats.streak += 1 }
}
struct Game {
    var word: String
    var lives = 6
    static func new(lives: Int = 6) -> Game { var game = Game(word: "ROBOT"); game.lives = lives; return game }
}
struct ContentView: View {
    @StateObject private var store = Store()
    @State private var game: Game
    init() { _game = State(initialValue: Game.new()) }
    var body: some View {
        let _ = Log.add("wins=\(store.stats.wins) streak=\(store.stats.streak) word=\(game.word) lives=\(game.lives)")
        let _ = Log.add("saved \({ let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return String(decoding: (try? e.encode(store.stats)) ?? Data(), as: UTF8.self) }())")
        Text("Hangman")
    }
}
