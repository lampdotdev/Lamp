import Foundation
import Observation

/// Today's Word Ladder as it's being played: the words entered so far, what's being typed, a hint, and the
/// solve once the end word is reached. What has been entered is saved as it happens, so quitting halfway picks
/// up in the same place, until the day changes and a new puzzle starts.
@Observable final class LadderGame {
    /// What's kept between launches for the day's puzzle.
    private struct Progress: Codable {
        var day: Day
        var steps: [String]
        var usedHint: Bool
        var startedAt: Date?
    }

    /// The next letter to change, shown in the row being typed.
    struct Hint: Equatable {
        let position: Int
        let letter: Character
    }

    private(set) var day: Day
    private(set) var puzzle: LadderPuzzle
    /// The words entered after the start word, the last of them the end word once it's solved.
    private(set) var steps: [String] = []
    private(set) var typed = ""
    private(set) var usedHint = false
    private(set) var hint: Hint?
    /// Why the last word was turned away, shown quietly under the ladder until the next key.
    private(set) var problem: String?
    /// Goes up by one each time a word is turned away; the typing row shakes when it changes.
    private(set) var shakes = 0
    private(set) var startedAt: Date?
    private(set) var solve: Solve?

    private let history: History

    init(history: History) {
        self.history = history
        day = .today
        puzzle = WordLadder.puzzle(for: .today)
        load()
    }

    /// The word the next step changes.
    var current: String { steps.last ?? puzzle.start }
    var isSolved: Bool { solve != nil }

    // MARK: Playing

    func type(_ letter: Character) {
        guard !isSolved, typed.count < WordLadder.length, letter.isLetter, letter.isASCII else { return }
        typed.append(Character(letter.lowercased()))
        problem = nil
        startClock()
    }

    func deleteBackward() {
        guard !typed.isEmpty else { return }
        typed.removeLast()
        problem = nil
    }

    func submit() {
        guard !isSolved else { return }
        if let reason = reasonToRefuse(typed) {
            problem = reason
            shakes += 1
            return
        }
        steps.append(typed)
        typed = ""
        hint = nil
        if current == puzzle.end { finish() }
        save()
    }

    /// Takes back the last word entered, for a ladder that went somewhere it can't get back from.
    func undoStep() {
        guard canUndoStep else { return }
        steps.removeLast()
        typed = ""
        hint = nil
        problem = nil
        save()
    }

    var canUndoStep: Bool { !isSolved && !steps.isEmpty }

    /// Shows which letter to change next and to what, along a shortest way from where the ladder is now. Using
    /// one means today's solve can't be perfect.
    func showHint() {
        guard canHint,
              let path = WordLadder.shortestPath(from: current, to: puzzle.end), path.count > 1,
              let position = WordLadder.differences(current, path[1]).first else { return }
        hint = Hint(position: position, letter: Array(path[1])[position])
        usedHint = true
        startClock()
        typed = ""
        problem = nil
        save()
    }

    var canHint: Bool { !isSolved && hint == nil }

    /// The time on the done card runs from the first letter typed (or hint asked for), not from opening the app.
    private func startClock() {
        guard startedAt == nil else { return }
        startedAt = Date()
        save()
    }

    private func reasonToRefuse(_ word: String) -> String? {
        if word.count < WordLadder.length { return "Words here have four letters." }
        if !WordLadder.isWord(word) { return "“\(word.uppercased())” isn't in the word list." }
        let changed = WordLadder.differences(current, word).count
        if changed == 0 { return "That's the word you're on. Change one letter." }
        if changed > 1 { return "Change just one letter at a time." }
        if word == puzzle.start || steps.contains(word) { return "You've been on “\(word.uppercased())” already." }
        return nil
    }

    private func finish() {
        let seconds = max(1, Int(Date().timeIntervalSince(startedAt ?? Date())))
        let solve = Solve(game: .wordLadder, day: day, steps: steps.count, par: puzzle.par,
                          seconds: seconds, usedHint: usedHint, isExample: false)
        history.record(solve)
        self.solve = solve
    }

    // MARK: Days

    /// Moves to the new day's puzzle when the date has changed since this one began (the app was left open
    /// overnight, or the Mac woke up the next morning).
    func refreshDay() {
        guard day != .today else { return }
        day = .today
        puzzle = WordLadder.puzzle(for: day)
        steps = []
        typed = ""
        usedHint = false
        hint = nil
        problem = nil
        startedAt = nil
        solve = nil
        load()
    }

    private func load() {
        solve = history.solve(of: .wordLadder, on: day)
        guard let saved = LampStore.load(Progress.self, from: "ladder.progress"), saved.day == day else { return }
        steps = saved.steps
        usedHint = saved.usedHint
        startedAt = saved.startedAt
    }

    private func save() {
        LampStore.save(Progress(day: day, steps: steps, usedHint: usedHint, startedAt: startedAt), to: "ladder.progress")
    }
}
