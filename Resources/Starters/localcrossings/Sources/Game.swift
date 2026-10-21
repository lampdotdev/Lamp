import Foundation

/// The daily puzzles the app offers. Today there is one; a second is a case here, its own folder beside
/// Crossword/ (a model and a view), and a line in `PuzzleBoard`. Solves, the streak and the calendar work for
/// every game without change: a day counts toward the streak when any of its puzzles was solved.
enum Game: String, Codable, CaseIterable, Identifiable {
    case crossword

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crossword: "Crossword"
        }
    }

    var symbol: String {
        switch self {
        case .crossword: "square.grid.3x3.square"
        }
    }
}

/// A puzzle someone finished: what it took, kept for the streak and the calendar.
struct Solve: Codable, Identifiable, Hashable {
    let game: Game
    let day: Day
    let seconds: Int
    /// Checked or revealed anything along the way.
    let helped: Bool
    /// The place the paper was made for: "Park Slope".
    let place: String?
    /// The edition's number.
    let edition: Int?
    /// Written by `Samples` on first launch so the streak has something to show; Clear Examples removes these only.
    let isExample: Bool

    var id: String { "\(game.rawValue) \(day.key)" }

    /// Solved without checking or revealing anything.
    var isPerfect: Bool { !helped }

    static func time(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return String(format: "%d:%02d", minutes, seconds % 60)
    }
}
