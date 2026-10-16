import SwiftUI

/// What's saved of the game on the table, so quitting in the middle of one picks it up again.
struct SavedGame: Codable {
    var board: Board
    var seconds: TimeInterval
    /// Whether this game is already in the statistics as one played (it is from its first move).
    var counted: Bool
}

struct Stats: Codable, Equatable {
    var played = 0
    var won = 0
    var bestTime: TimeInterval?
    var fewestMoves: Int?
}

struct Preferences: Codable, Equatable {
    var drawThree = false
}

/// The game being played: the board, Undo, the clock, the statistics and the end of a game (finishing by itself
/// and the win cascade). Views ask it to make moves and draw what it holds; the rules themselves are `Board`'s.
@MainActor @Observable final class Game {
    private(set) var board: Board
    private(set) var stats: Stats
    private(set) var preferences: Preferences
    /// The cards the last move (or Undo) carried, drawn above the rest so they never slide under a pile.
    private(set) var lastMoved: Set<Card.ID> = []
    /// The bouncing cards after a win; when they're done the result shows.
    private(set) var celebrating = false

    private var history: [Board] = []
    private var secondsBefore: TimeInterval
    /// When the clock last started. It stops on a win and while the app is closed: the clock starts again with
    /// the next move after a relaunch.
    private var runningSince: Date?
    private var counted: Bool
    private var finishing: Task<Void, Never>?

    init() {
        if let saved = LampStore.load(SavedGame.self, from: "game") {
            board = saved.board
            secondsBefore = saved.seconds
            counted = saved.counted
        } else {
            // The first time Solitaire opens, a game is already under way (see `Board.sample`), with a minute
            // and a half on the clock. It isn't counted as played until the person makes a move in it.
            board = .sample()
            secondsBefore = 94
            counted = false
        }
        stats = LampStore.load(Stats.self, from: "stats") ?? Stats()
        preferences = LampStore.load(Preferences.self, from: "preferences") ?? Preferences()
        save()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    // MARK: State for the views

    var canUndo: Bool { !history.isEmpty && !board.isWon }
    /// Cards can be moved: not while the game finishes itself, and not once it's won.
    var isPlayable: Bool { finishing == nil && !board.isWon }

    func elapsed(at date: Date) -> TimeInterval {
        secondsBefore + (runningSince.map { date.timeIntervalSince($0) } ?? 0)
    }

    // MARK: Moves

    func draw() {
        guard isPlayable, board.canDraw else { return }
        perform { $0.draw(); return true }
    }

    @discardableResult
    func move(from source: Pile, at index: Int, to target: Pile) -> Bool {
        guard isPlayable else { return false }
        return perform { $0.move(from: source, at: index, to: target) }
    }

    /// A double-click: the card goes up to its foundation when it's on top of its pile and can.
    @discardableResult
    func sendToFoundation(_ id: Card.ID) -> Bool {
        guard let (pile, index) = board.location(of: id), index == board[pile].count - 1 else { return false }
        if case .foundation = pile { return false }
        guard let target = board.foundation(for: board[pile][index]) else { return false }
        return move(from: pile, at: index, to: target)
    }

    func undo() {
        guard canUndo, let previous = history.popLast() else { return }
        finishing?.cancel()
        finishing = nil
        lastMoved = moved(from: board, to: previous)
        board = previous
        save()
    }

    func newGame() {
        finishing?.cancel()
        finishing = nil
        var generator = SystemRandomNumberGenerator()
        let next = Board.deal(drawCount: preferences.drawThree ? 3 : 1, using: &generator)
        lastMoved = Set(next.piles.keys)
        board = next
        history = []
        secondsBefore = 0
        runningSince = nil
        counted = false
        celebrating = false
        save()
    }

    func setDrawThree(_ drawThree: Bool) {
        preferences.drawThree = drawThree
        LampStore.save(preferences, to: "preferences")
    }

    func endCelebration() {
        celebrating = false
    }

    @discardableResult
    private func perform(_ change: (inout Board) -> Bool) -> Bool {
        var next = board
        guard change(&next) else { return false }
        history.append(board)
        if history.count > 500 { history.removeFirst() }
        lastMoved = moved(from: board, to: next)
        board = next
        startClock()
        if board.isWon {
            win()
        } else if board.canFinishByItself && finishing == nil {
            finish()
        }
        save()
        return true
    }

    private func moved(from old: Board, to new: Board) -> Set<Card.ID> {
        let before = old.piles
        return Set(new.piles.filter { before[$0.key] != $0.value }.keys)
    }

    // MARK: The clock, the statistics and winning

    private func startClock() {
        if runningSince == nil { runningSince = .now }
        if !counted {
            counted = true
            stats.played += 1
            LampStore.save(stats, to: "stats")
        }
    }

    /// Sends the cards up one at a time, lowest first, so the end of a game can be watched. Undo or a new game
    /// cancels it.
    private func finish() {
        finishing = Task { [weak self] in
            while let self, let step = self.board.nextFinishingMove() {
                try? await Task.sleep(for: .milliseconds(90))
                if Task.isCancelled { return }
                withAnimation(.snappy(duration: 0.22)) {
                    _ = self.perform { $0.move(from: step.from, at: step.index, to: step.to) }
                }
            }
            self?.finishing = nil
        }
    }

    private func win() {
        secondsBefore = elapsed(at: .now)
        runningSince = nil
        stats.won += 1
        stats.bestTime = min(stats.bestTime ?? .infinity, secondsBefore)
        stats.fewestMoves = min(stats.fewestMoves ?? .max, board.moves)
        LampStore.save(stats, to: "stats")
        celebrating = true
    }

    private func save() {
        LampStore.save(SavedGame(board: board, seconds: elapsed(at: .now), counted: counted), to: "game")
    }
}
