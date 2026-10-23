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
}
final class Store: ObservableObject {
    @Published var stats: Stats
    init() {
        let saved = #"{"wins":2,"losses":1}"#
        stats = (try? JSONDecoder().decode(Stats.self, from: Data(saved.utf8))) ?? Stats()
    }
    func won() { stats.wins += 1 }
}
struct Game {
    var word: String
    var lives = 6
    static func new() -> Game { Game(word: "ROBOT") }
}
struct ContentView: View {
    @StateObject private var store = Store()
    @State private var game: Game
    init() { _game = State(initialValue: Game.new()) }
    var body: some View {
        let _ = Log.add("wins=\(store.stats.wins) word=\(game.word) lives=\(game.lives)")
        Text("Hangman")
    }
}
