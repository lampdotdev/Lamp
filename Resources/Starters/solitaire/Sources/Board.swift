import Foundation

/// Where a card can lie on the table.
enum Pile: Hashable, Codable {
    case stock, waste, foundation(Int), tableau(Int)

    static let foundations = (0..<4).map(Pile.foundation)
    static let tableaus = (0..<7).map(Pile.tableau)
}

/// The rules of Klondike, and nothing else: a value that knows where every card is and which moves are legal.
/// The game (`Game`) keeps one, with the history for Undo, the clock and the statistics around it.
struct Board: Codable, Equatable {
    /// The last card of each array is the one on top.
    var stock: [Card] = []
    var waste: [Card] = []
    var foundations: [[Card]] = Array(repeating: [], count: 4)
    var tableau: [[Card]] = Array(repeating: [], count: 7)
    /// One or three cards turned over from the stock at a time, fixed when the game is dealt.
    var drawCount = 1
    var moves = 0

    subscript(pile: Pile) -> [Card] {
        get {
            switch pile {
            case .stock: stock
            case .waste: waste
            case .foundation(let i): foundations[i]
            case .tableau(let i): tableau[i]
            }
        }
        set {
            switch pile {
            case .stock: stock = newValue
            case .waste: waste = newValue
            case .foundation(let i): foundations[i] = newValue
            case .tableau(let i): tableau[i] = newValue
            }
        }
    }

    // MARK: Dealing

    /// Seven columns of one to seven cards, the last of each face up, and the rest in the stock.
    static func deal<R: RandomNumberGenerator>(drawCount: Int, using generator: inout R) -> Board {
        var deck = Card.deck.shuffled(using: &generator)
        var board = Board(drawCount: drawCount)
        for column in 0..<7 {
            for row in 0...column {
                var card = deck.removeLast()
                card.faceUp = row == column
                board.tableau[column].append(card)
            }
        }
        board.stock = deck
        return board
    }

    // MARK: Rules

    /// The cards picked up by grabbing the card at `index`, or nil when it can't be moved: a face-up run from the
    /// tableau, or only the top card of the waste or a foundation.
    func run(from pile: Pile, at index: Int) -> [Card]? {
        let cards = self[pile]
        guard cards.indices.contains(index), cards[index].faceUp else { return nil }
        switch pile {
        case .stock:
            return nil
        case .waste, .foundation:
            return index == cards.count - 1 ? [cards[index]] : nil
        case .tableau:
            let run = Array(cards[index...])
            let ordered = zip(run, run.dropFirst()).allSatisfy { upper, lower in
                lower.faceUp && lower.isRed != upper.isRed && lower.rank == upper.rank - 1
            }
            return ordered ? run : nil
        }
    }

    /// Foundations build up by suit from the ace; the tableau builds down in alternating colors, and only a king
    /// (with whatever lies on it) goes to an empty column.
    func accepts(_ run: [Card], on pile: Pile) -> Bool {
        guard let first = run.first else { return false }
        let top = self[pile].last
        switch pile {
        case .stock, .waste:
            return false
        case .foundation:
            guard run.count == 1 else { return false }
            guard let top else { return first.rank == 1 }
            return top.suit == first.suit && first.rank == top.rank + 1
        case .tableau:
            guard let top else { return first.rank == 13 }
            return top.faceUp && top.isRed != first.isRed && first.rank == top.rank - 1
        }
    }

    /// Moves the run starting at `index` and turns over the card it uncovers in the tableau.
    @discardableResult
    mutating func move(from source: Pile, at index: Int, to target: Pile) -> Bool {
        guard source != target, let run = run(from: source, at: index), accepts(run, on: target) else { return false }
        self[source].removeLast(run.count)
        self[target].append(contentsOf: run)
        if case .tableau = source, let last = self[source].indices.last, !self[source][last].faceUp {
            self[source][last].faceUp = true
        }
        moves += 1
        return true
    }

    var canDraw: Bool { !stock.isEmpty || !waste.isEmpty }

    /// Turns over the next one or three cards; with the stock empty, turns the waste back into the stock.
    mutating func draw() {
        guard canDraw else { return }
        if stock.isEmpty {
            stock = waste.reversed().map { card in
                var card = card
                card.faceUp = false
                return card
            }
            waste = []
        } else {
            for _ in 0..<min(drawCount, stock.count) {
                var card = stock.removeLast()
                card.faceUp = true
                waste.append(card)
            }
        }
        moves += 1
    }

    /// The foundation this card can go up to now, if any.
    func foundation(for card: Card) -> Pile? {
        Pile.foundations.first { accepts([card], on: $0) }
    }

    func location(of id: Card.ID) -> (pile: Pile, index: Int)? {
        for pile in [.stock, .waste] + Pile.foundations + Pile.tableaus {
            if let index = self[pile].firstIndex(where: { $0.id == id }) { return (pile, index) }
        }
        return nil
    }

    /// Which pile each card is in, to tell which cards a move carried.
    var piles: [Card.ID: Pile] {
        var result: [Card.ID: Pile] = [:]
        for pile in [.stock, .waste] + Pile.foundations + Pile.tableaus {
            for card in self[pile] { result[card.id] = pile }
        }
        return result
    }

    var isWon: Bool { foundations.allSatisfy { $0.count == 13 } }

    /// Nothing is hidden and nothing is left to draw, so the game can only be won: Solitaire finishes it.
    var canFinishByItself: Bool {
        !isWon && stock.isEmpty && waste.isEmpty && tableau.allSatisfy { $0.allSatisfy(\.faceUp) }
    }

    /// The lowest card that can go up to a foundation now.
    func nextFinishingMove() -> (from: Pile, index: Int, to: Pile)? {
        var best: (from: Pile, index: Int, to: Pile)?
        var bestRank = Int.max
        for pile in [.waste] + Pile.tableaus {
            guard let card = self[pile].last, card.faceUp, card.rank < bestRank,
                  let target = foundation(for: card) else { continue }
            best = (pile, self[pile].count - 1, target)
            bestRank = card.rank
        }
        return best
    }

    // MARK: The sample game

    /// The game on the table the first time Solitaire opens: always the same deal, a few moves in, so it looks
    /// like a game someone has started rather than a fresh deal.
    static func sample() -> Board {
        var generator = SeededGenerator(seed: 1990)
        var board = deal(drawCount: 1, using: &generator)
        var played = 0
        for _ in 0..<40 where played < 8 {
            if board.makeUsefulMove() { played += 1 } else { board.draw() }
        }
        return board
    }

    /// A sensible move, as a person would play it: a card up to a foundation, a run that uncovers a hidden
    /// card, or the waste's card onto the tableau.
    private mutating func makeUsefulMove() -> Bool {
        for pile in [.waste] + Pile.tableaus {
            if let card = self[pile].last, card.faceUp, let target = foundation(for: card) {
                return move(from: pile, at: self[pile].count - 1, to: target)
            }
        }
        for source in Pile.tableaus {
            guard let start = self[source].firstIndex(where: \.faceUp), start > 0 else { continue }
            for target in Pile.tableaus {
                if move(from: source, at: start, to: target) { return true }
            }
        }
        if !waste.isEmpty {
            for target in Pile.tableaus {
                if move(from: .waste, at: waste.count - 1, to: target) { return true }
            }
        }
        return false
    }
}
