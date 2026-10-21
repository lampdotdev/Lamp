import Foundation

/// A square of the grid, by row and column from the top left.
struct Cell: Hashable, Codable {
    var row: Int
    var col: Int
}

/// A day's puzzle: its words where they cross, numbered as a newspaper numbers them. The grid is freeform:
/// words cross where they share a letter and the squares between them are empty, which lets any set of names
/// make a puzzle, however long they are.
struct Crossword: Codable, Equatable {
    struct Entry: Codable, Hashable, Identifiable {
        var number: Int
        var across: Bool
        var start: Cell
        var answer: String
        var lengths: String
        var clue: String
        var facts: String

        var id: String { "\(number)\(across ? "A" : "D")" }
        var cells: [Cell] {
            (0..<answer.count).map { across ? Cell(row: start.row, col: start.col + $0) : Cell(row: start.row + $0, col: start.col) }
        }
        var label: String { "\(number) \(across ? "Across" : "Down")" }
    }

    var entries: [Entry]
    var rows: Int
    var cols: Int

    /// The right letter for every square that has one.
    var solution: [Cell: Character] {
        var all: [Cell: Character] = [:]
        for entry in entries { for (cell, letter) in zip(entry.cells, entry.answer) { all[cell] = letter } }
        return all
    }

    /// The number printed in a square's corner, where a word starts.
    var numbers: [Cell: Int] { Dictionary(entries.map { ($0.start, $0.number) }, uniquingKeysWith: { a, _ in a }) }

    func entries(at cell: Cell) -> [Entry] { entries.filter { $0.cells.contains(cell) } }
}

/// Lays out a crossword from candidates: the longest goes in first, then each of the others where it crosses
/// the most letters while keeping the grid square and small. It's tried a couple of hundred ways and the
/// fullest, best-knit grid is kept, which takes a tenth of a second. The same seed gives the same puzzle, so a
/// day's puzzle is the same however often it's made.
enum Layout {
    static let maxSide = 13
    static let wordsWanted = 12

    static func make(from candidates: [Candidate], seed: UInt64) -> Crossword? {
        var random = SeededRandom(seed: seed)
        let known = candidates.filter { $0.tier == 0 }
        let gettable = candidates.filter { $0.tier == 1 }
        let hard = candidates.filter { $0.tier == 2 }
        var best: Grid?
        for _ in 0..<200 {
            // A fair mix: what anyone living here knows, most of what can be worked out, a couple of hard ones.
            var pool = known.shuffled(using: &random) + Array(gettable.shuffled(using: &random).prefix(16))
                + Array(hard.shuffled(using: &random).prefix(2))
            guard let longest = pool.max(by: { $0.answer.count < $1.answer.count }) else { return nil }
            pool.removeAll { $0.answer == longest.answer }
            let grid = build([longest] + pool.shuffled(using: &random))
            if best == nil || grid.score > best!.score { best = grid }
        }
        guard let best, best.placed.count >= 5 else { return nil }
        return best.crossword
    }

    private static func build(_ pool: [Candidate]) -> Grid {
        var grid = Grid()
        var rest = pool
        grid.put(rest.removeFirst(), at: Cell(row: 0, col: 0), across: true, sharing: 0)
        var moved = true
        while moved && grid.placed.count < wordsWanted {
            moved = false
            for (index, candidate) in rest.enumerated() {
                guard let spot = grid.bestSpot(for: candidate) else { continue }
                grid.put(candidate, at: spot.start, across: spot.across, sharing: spot.shared)
                rest.remove(at: index)
                moved = true
                break
            }
        }
        return grid
    }

    private struct Grid {
        var letters: [Cell: Character] = [:]
        /// Every square a word runs through, with its direction: two words never run the same way through one.
        var runs: Set<String> = []
        var placed: [(candidate: Candidate, start: Cell, across: Bool)] = []
        var crossings = 0

        var bounds: (top: Int, bottom: Int, left: Int, right: Int) {
            let rows = letters.keys.map(\.row), cols = letters.keys.map(\.col)
            return (rows.min() ?? 0, rows.max() ?? 0, cols.min() ?? 0, cols.max() ?? 0)
        }

        var score: Int {
            let known = placed.filter { $0.candidate.tier == 0 }.count
            return placed.count * 10 + crossings * 4 + min(known, 4) * 12
        }

        /// How many letters a word would share at a spot, or nil when it can't go there: off the end of a word,
        /// beside another word without crossing it, or over a letter that differs.
        func sharing(_ word: [Character], at start: Cell, across: Bool) -> Int? {
            let (dr, dc) = across ? (0, 1) : (1, 0)
            if letters[Cell(row: start.row - dr, col: start.col - dc)] != nil { return nil }
            if letters[Cell(row: start.row + dr * word.count, col: start.col + dc * word.count)] != nil { return nil }
            var shared = 0
            for (index, letter) in word.enumerated() {
                let cell = Cell(row: start.row + dr * index, col: start.col + dc * index)
                if let have = letters[cell] {
                    guard have == letter, !runs.contains("\(cell.row),\(cell.col),\(across)") else { return nil }
                    shared += 1
                } else if letters[Cell(row: cell.row + dc, col: cell.col + dr)] != nil
                            || letters[Cell(row: cell.row - dc, col: cell.col - dr)] != nil {
                    return nil
                }
            }
            return shared == word.count ? nil : shared
        }

        func bestSpot(for candidate: Candidate) -> (start: Cell, across: Bool, shared: Int)? {
            let word = Array(candidate.answer)
            var best: (score: Int, start: Cell, across: Bool, shared: Int)?
            // In order, since a dictionary's order changes from launch to launch and the seed must decide.
            for cell in letters.keys.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) }) {
                let have = letters[cell]!
                for (index, letter) in word.enumerated() where letter == have {
                    for across in [true, false] {
                        let start = across ? Cell(row: cell.row, col: cell.col - index) : Cell(row: cell.row - index, col: cell.col)
                        guard let shared = sharing(word, at: start, across: across), shared > 0 else { continue }
                        var trial = self
                        trial.put(candidate, at: start, across: across, sharing: shared)
                        let b = trial.bounds
                        let height = b.bottom - b.top + 1, width = b.right - b.left + 1
                        guard height <= Layout.maxSide, width <= Layout.maxSide else { continue }
                        let score = shared * 20 - (height + width) - abs(height - width) * 2
                        if best == nil || score > best!.score { best = (score, start, across, shared) }
                    }
                }
            }
            return best.map { ($0.start, $0.across, $0.shared) }
        }

        mutating func put(_ candidate: Candidate, at start: Cell, across: Bool, sharing shared: Int) {
            for (index, letter) in candidate.answer.enumerated() {
                let cell = across ? Cell(row: start.row, col: start.col + index) : Cell(row: start.row + index, col: start.col)
                letters[cell] = letter
                runs.insert("\(cell.row),\(cell.col),\(across)")
            }
            placed.append((candidate, start, across))
            crossings += shared
        }

        /// Moved to start at the top left and numbered left to right, top to bottom.
        var crossword: Crossword {
            let b = bounds
            let shifted = placed.map { (candidate: $0.candidate, start: Cell(row: $0.start.row - b.top, col: $0.start.col - b.left), across: $0.across) }
            let starts = Set(shifted.map(\.start)).sorted { ($0.row, $0.col) < ($1.row, $1.col) }
            let numbers = Dictionary(uniqueKeysWithValues: starts.enumerated().map { ($1, $0 + 1) })
            let entries = shifted.map {
                Crossword.Entry(number: numbers[$0.start]!, across: $0.across, start: $0.start, answer: $0.candidate.answer,
                                lengths: $0.candidate.lengths, clue: $0.candidate.clue, facts: $0.candidate.facts)
            }
            .sorted { ($0.number, $0.across ? 0 : 1) < ($1.number, $1.across ? 0 : 1) }
            return Crossword(entries: entries, rows: b.bottom - b.top + 1, cols: b.right - b.left + 1)
        }
    }
}

/// A random number generator that gives the same numbers for the same seed (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
