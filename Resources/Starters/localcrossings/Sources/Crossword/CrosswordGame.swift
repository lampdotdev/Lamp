import Foundation
import Observation

/// Today's crossword as it's being played: the letters in, where the cursor is and which way it's going, what's
/// been checked or revealed, and the solve once every square is right. Letters are saved as they go in, so
/// quitting halfway picks up in the same place until the day's paper changes.
@Observable final class CrosswordGame {
    private struct Progress: Codable {
        var day: Day
        var answers: [String]
        var letters: [Cell: String]
        var revealed: Set<Cell>
        var helped: Bool
        var startedAt: Date?
    }

    private(set) var edition: Edition?
    private(set) var letters: [Cell: Character] = [:]
    /// Squares whose letter Lamp gave away: marked in the corner, and the day isn't perfect.
    private(set) var revealed: Set<Cell> = []
    /// Squares Check found wrong, struck through until they're typed over.
    private(set) var wrong: Set<Cell> = []
    private(set) var helped = false
    private(set) var startedAt: Date?
    private(set) var solve: Solve?
    var selected: Cell?
    var across = true

    private let history: History
    /// Told when the day's puzzle is solved.
    var onSolve: ((Solve) -> Void)?

    init(history: History) {
        self.history = history
    }

    var puzzle: Crossword? { edition?.puzzle }
    var hasStarted: Bool { !letters.isEmpty }
    var isSolved: Bool { solve != nil }

    /// A new edition: today's progress is picked up when it's for this puzzle, else the grid starts empty.
    func open(_ edition: Edition) {
        let answers = edition.puzzle.entries.map(\.answer)
        let same = self.edition.map { $0.day == edition.day && $0.puzzle.entries.map(\.answer) == answers } ?? false
        self.edition = edition
        // The same puzzle with reworded clues: everything in the grid stays.
        guard !same else { return }
        letters = [:]
        revealed = []
        wrong = []
        helped = false
        startedAt = nil
        solve = history.solve(of: .crossword, on: edition.day).flatMap { $0.place == edition.place ? $0 : nil }
        if let kept = LampStore.load(Progress.self, from: "crossword.progress"), kept.day == edition.day,
           kept.answers == answers {
            letters = kept.letters.compactMapValues(\.first)
            revealed = kept.revealed
            helped = kept.helped
            startedAt = kept.startedAt
        }
        if isSolved { letters = edition.puzzle.solution }
        selected = edition.puzzle.entries.first?.start
        across = edition.puzzle.entries.first?.across ?? true
    }

    // MARK: Where the cursor is

    /// The word the cursor is in, going the way it's going when a word goes that way.
    var entry: Crossword.Entry? {
        guard let selected, let puzzle else { return nil }
        let here = puzzle.entries(at: selected)
        return here.first { $0.across == across } ?? here.first
    }

    /// A click on a square: the cursor goes there, and a click where it already is turns it the other way.
    func select(_ cell: Cell) {
        guard let puzzle, puzzle.solution[cell] != nil else { return }
        if selected == cell {
            if puzzle.entries(at: cell).contains(where: { $0.across != across }) { across.toggle() }
        } else {
            selected = cell
            if !puzzle.entries(at: cell).contains(where: { $0.across == across }) { across.toggle() }
        }
    }

    func select(_ entry: Crossword.Entry) {
        across = entry.across
        selected = entry.cells.first { letters[$0] == nil } ?? entry.start
    }

    /// Arrow keys: along the grid to the next square with a letter in it, turning first when the arrow is across
    /// the way the cursor goes.
    func move(rows: Int, cols: Int) {
        guard let puzzle, let selected else { return }
        let wantsAcross = cols != 0
        if wantsAcross != across, puzzle.entries(at: selected).contains(where: { $0.across == wantsAcross }) {
            across = wantsAcross
            return
        }
        var cell = selected
        for _ in 0..<max(puzzle.rows, puzzle.cols) {
            cell = Cell(row: cell.row + rows, col: cell.col + cols)
            if puzzle.solution[cell] != nil {
                self.selected = cell
                if !puzzle.entries(at: cell).contains(where: { $0.across == across }) { across.toggle() }
                return
            }
        }
    }

    /// Tab and Return: to the next word (or the one before), at its first empty square.
    func nextEntry(backward: Bool = false) {
        guard let puzzle, let entry, let index = puzzle.entries.firstIndex(of: entry) else { return }
        let count = puzzle.entries.count
        select(puzzle.entries[(index + (backward ? count - 1 : 1)) % count])
    }

    // MARK: Typing

    func type(_ letter: Character) {
        guard !isSolved, let selected, let entry, letter.isLetter, letter.isASCII else { return }
        if startedAt == nil { startedAt = Date() }
        if !revealed.contains(selected) {
            letters[selected] = Character(letter.uppercased())
            wrong.remove(selected)
        }
        // On to the next square of the word that's still empty, else simply the next one.
        let cells = entry.cells
        if let here = cells.firstIndex(of: selected) {
            let after = cells[(here + 1)...]
            self.selected = after.first { letters[$0] == nil } ?? after.first ?? selected
        }
        finishIfSolved()
        save()
    }

    func deleteBackward() {
        guard !isSolved, let selected, let entry else { return }
        if letters[selected] != nil, !revealed.contains(selected) {
            letters[selected] = nil
            wrong.remove(selected)
        } else if let here = entry.cells.firstIndex(of: selected), here > 0 {
            let back = entry.cells[here - 1]
            self.selected = back
            if !revealed.contains(back) {
                letters[back] = nil
                wrong.remove(back)
            }
        }
        save()
    }

    // MARK: Help

    var canHelp: Bool { !isSolved && selected != nil }

    /// Strikes through every wrong letter in the grid.
    func check() {
        guard let puzzle, canHelp else { return }
        let solution = puzzle.solution
        wrong = Set(letters.filter { solution[$0.key] != $0.value }.map(\.key))
        helped = true
        save()
    }

    func revealSquare() {
        guard let selected else { return }
        reveal([selected])
    }

    func revealWord() {
        guard let entry else { return }
        reveal(entry.cells)
    }

    private func reveal(_ cells: [Cell]) {
        guard let puzzle, canHelp else { return }
        if startedAt == nil { startedAt = Date() }
        for cell in cells where letters[cell] != puzzle.solution[cell] {
            letters[cell] = puzzle.solution[cell]
            revealed.insert(cell)
            wrong.remove(cell)
        }
        helped = true
        finishIfSolved()
        save()
    }

    // MARK: Finishing

    var seconds: Int { startedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0 }

    private func finishIfSolved() {
        guard let edition, !isSolved, letters == edition.puzzle.solution else { return }
        let done = Solve(game: .crossword, day: edition.day, seconds: seconds, helped: helped, place: edition.place,
                         edition: edition.number, isExample: false)
        history.record(done)
        solve = done
        onSolve?(done)
        selected = nil
    }

    private func save() {
        guard let edition else { return }
        let kept = Progress(day: edition.day, answers: edition.puzzle.entries.map(\.answer),
                            letters: letters.mapValues { String($0) }, revealed: revealed, helped: helped, startedAt: startedAt)
        LampStore.save(kept, to: "crossword.progress")
    }
}
