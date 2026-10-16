import Foundation

/// A couple of weeks of solved days, written on first launch so the streak and the calendar show what they do
/// before today's puzzle is played. Each is the real puzzle of its day, marked `isExample`; Clear Examples
/// (in the Puzzle menu and the history sheet) removes exactly those. They are written once: a flag in LampStore
/// remembers it, so clearing them never brings them back.
enum Samples {
    /// Days ago, extra steps over par, seconds taken, whether a hint was used. Yesterday back to nine days ago
    /// in a row (the streak), a missed day, then a few more.
    private static let played: [(daysAgo: Int, overPar: Int, seconds: Int, hint: Bool)] = [
        (1, 0, 74, false), (2, 1, 131, false), (3, 0, 58, false), (4, 2, 204, true), (5, 0, 97, false),
        (6, 1, 143, false), (7, 0, 66, false), (8, 0, 89, false), (9, 3, 262, true),
        (11, 1, 118, false), (12, 0, 71, false), (13, 2, 175, false), (15, 0, 102, false),
    ]

    static func writeOnce(into store: LampStore.Collection<Solve>) {
        guard LampStore.load(Bool.self, from: "examplesWritten") == nil else { return }
        let today = Day.today
        let solves = played.map { sample -> Solve in
            let day = today.adding(days: -sample.daysAgo)
            let puzzle = WordLadder.puzzle(for: day)
            return Solve(game: .wordLadder, day: day, steps: puzzle.par + sample.overPar, par: puzzle.par,
                         seconds: sample.seconds, usedHint: sample.hint, isExample: true)
        }
        store.put(solves)
        LampStore.save(true, to: "examplesWritten")
    }
}
