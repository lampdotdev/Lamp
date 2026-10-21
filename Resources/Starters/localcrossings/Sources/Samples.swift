import Foundation

/// A couple of weeks of solved days, written on first launch so the streak and the calendar show what they do
/// before today's puzzle is played, each marked `isExample`; Clear Examples (in the Puzzle menu and the history
/// sheet) removes exactly those. They are written once: a flag in LampStore remembers it, so clearing them
/// never brings them back.
enum Samples {
    /// Days ago, seconds taken, whether anything was checked or revealed. Yesterday back to nine days ago in a
    /// row (the streak), a missed day, then a few more.
    private static let played: [(daysAgo: Int, seconds: Int, helped: Bool)] = [
        (1, 312, false), (2, 455, false), (3, 268, false), (4, 610, true), (5, 397, false),
        (6, 488, false), (7, 251, false), (8, 344, false), (9, 702, true),
        (11, 420, false), (12, 299, false), (13, 515, true), (15, 380, false),
    ]

    static func writeOnce(into store: LampStore.Collection<Solve>) {
        guard LampStore.load(Bool.self, from: "examplesWritten") == nil else { return }
        let today = Day.today
        let solves = played.map {
            Solve(game: .crossword, day: today.adding(days: -$0.daysAgo), seconds: $0.seconds, helped: $0.helped,
                  place: nil, edition: nil, isExample: true)
        }
        store.put(solves)
        LampStore.save(true, to: "examplesWritten")
    }
}
