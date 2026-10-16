import Foundation

/// The daily puzzles the app offers. Today there is one; a second is a case here, its own folder beside
/// WordLadder/ (rules, a model, a view), and a line in `PuzzleBoard`. Solves, the streak and the calendar work
/// for every game without change: a day counts toward the streak when any of its puzzles was solved.
enum Game: String, Codable, CaseIterable, Identifiable {
    case wordLadder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wordLadder: "Word Ladder"
        }
    }

    var symbol: String {
        switch self {
        case .wordLadder: "stairs"
        }
    }

    /// One line on how to play, shown under the puzzle until the first word is in.
    var rules: String {
        switch self {
        case .wordLadder: "Change one letter at a time. Every step must be a real word."
        }
    }
}

/// A puzzle someone finished: what it took them, kept for the streak and the calendar.
struct Solve: Codable, Identifiable, Hashable {
    let game: Game
    let day: Day
    let steps: Int
    let par: Int
    let seconds: Int
    let usedHint: Bool
    /// Written by `Samples` on first launch so the streak has something to show; Clear Examples removes these only.
    let isExample: Bool

    var id: String { "\(game.rawValue) \(day.key)" }

    /// At par without a hint: the best way to finish.
    var isPerfect: Bool { steps <= par && !usedHint }

    static func time(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return String(format: "%d:%02d", minutes, seconds % 60)
    }
}
