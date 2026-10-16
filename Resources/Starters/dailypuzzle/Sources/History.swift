import Foundation
import Observation

/// Every puzzle solved, saved in LampStore, and what follows from them: the streak and the calendar.
@Observable final class History {
    private let store = LampStore.collection("solves", of: Solve.self)
    private(set) var solves: [Solve] = []

    init() {
        Samples.writeOnce(into: store)
        solves = store.all()
    }

    func record(_ solve: Solve) {
        store.put(solve)
        solves.removeAll { $0.id == solve.id }
        solves.append(solve)
    }

    func solve(of game: Game, on day: Day) -> Solve? {
        solves.first { $0.game == game && $0.day == day }
    }

    /// The best solve on a day, for the calendar: a perfect one if there is one.
    func best(on day: Day) -> Solve? {
        solves.filter { $0.day == day }.max { !$0.isPerfect && $1.isPerfect }
    }

    private var solvedDays: Set<Day> { Set(solves.map(\.day)) }

    /// Days in a row with a solve, ending today, or yesterday while today's puzzle is still open, so the streak
    /// doesn't read zero every morning before the first word.
    var streak: Int {
        let days = solvedDays
        var day = days.contains(.today) ? Day.today : Day.today.adding(days: -1)
        var count = 0
        while days.contains(day) {
            count += 1
            day = day.adding(days: -1)
        }
        return count
    }

    var longestStreak: Int {
        var longest = 0
        var run = 0
        var previous: Day?
        for day in solvedDays.sorted() {
            run = (previous.map { $0.adding(days: 1) == day } ?? false) ? run + 1 : 1
            longest = max(longest, run)
            previous = day
        }
        return longest
    }

    var perfectCount: Int { solves.filter(\.isPerfect).count }

    var hasExamples: Bool { solves.contains(where: \.isExample) }

    func clearExamples() {
        for solve in solves where solve.isExample { store.delete(solve.id) }
        solves.removeAll(where: \.isExample)
    }
}
