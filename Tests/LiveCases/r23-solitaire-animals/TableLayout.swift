import CoreGraphics

/// Where everything goes on a table of a given size, laid out as Windows Solitaire had it: the stock and waste
/// top left, the four foundations top right, the seven columns below. Cards grow and shrink with the window.
struct TableLayout {
    static let margin: CGFloat = 20
    /// How far a card in a column sits below the one under it, as a share of a card's height.
    static let faceDownStep: CGFloat = 0.1
    static let faceUpStep: CGFloat = 0.27

    let size: CGSize
    let cardWidth: CGFloat
    let gap: CGFloat
    var cardHeight: CGFloat { cardWidth * 1.4 }
    var cardSize: CGSize { CGSize(width: cardWidth, height: cardHeight) }

    init(size: CGSize) {
        self.size = size
        gap = max(8, size.width * 0.014)
        let byWidth = (size.width - 2 * Self.margin - 6 * gap) / 7
        // Leave room under the top row for a column of a dozen cards before the column has to squeeze.
        let byHeight = (size.height - 2 * Self.margin) / 1.4 / 3.2
        cardWidth = max(36, min(byWidth, byHeight, 130))
    }

    private var left: CGFloat { (size.width - (7 * cardWidth + 6 * gap)) / 2 }
    private var tableauTop: CGFloat { Self.margin + cardHeight + max(gap * 1.5, 16) }

    private func columnX(_ column: Int) -> CGFloat {
        left + cardWidth / 2 + CGFloat(column) * (cardWidth + gap)
    }

    /// The middle of the first card of a pile, or of its empty place.
    func spot(of pile: Pile) -> CGPoint {
        let top = Self.margin + cardHeight / 2
        switch pile {
        case .stock: return CGPoint(x: columnX(0), y: top)
        case .waste: return CGPoint(x: columnX(1), y: top)
        case .foundation(let i): return CGPoint(x: columnX(3 + i), y: top)
        case .tableau(let i): return CGPoint(x: columnX(i), y: tableauTop + cardHeight / 2)
        }
    }

    /// The middle of the card at `index` in `pile`.
    func position(in pile: Pile, at index: Int, of board: Board) -> CGPoint {
        var point = spot(of: pile)
        switch pile {
        case .stock:
            // A hint of thickness: the stack rises a little every eight cards.
            point.x -= CGFloat(index / 8)
            point.y -= CGFloat(index / 8)
        case .waste:
            // Drawing three shows the last three turned over, fanned to the right.
            let shown = board.drawCount == 3 ? 3 : 1
            let firstShown = max(0, board.waste.count - shown)
            point.x += CGFloat(max(0, index - firstShown)) * cardWidth * 0.24
        case .foundation:
            break
        case .tableau:
            let cards = board[pile]
            let steps = steps(for: cards)
            for card in cards.prefix(index) { point.y += card.faceUp ? steps.up : steps.down }
        }
        return point
    }

    /// The fan of a column, squeezed when a long one would run off the bottom of the window.
    private func steps(for cards: [Card]) -> (down: CGFloat, up: CGFloat) {
        let down = cardHeight * Self.faceDownStep, up = cardHeight * Self.faceUpStep
        let needed = cards.dropLast().reduce(0) { $0 + ($1.faceUp ? up : down) }
        let room = size.height - Self.margin - tableauTop - cardHeight
        guard needed > room, needed > 0 else { return (down, up) }
        let squeeze = max(room, 0) / needed
        return (down * squeeze, up * squeeze)
    }

    func cardFrame(at center: CGPoint) -> CGRect {
        CGRect(x: center.x - cardWidth / 2, y: center.y - cardHeight / 2, width: cardWidth, height: cardHeight)
    }

    /// Where a dragged card may be let go to land on a pile: the foundation's card, or the whole length of a
    /// column, a little wider than its cards so a near miss still counts.
    func dropArea(of pile: Pile, on board: Board) -> CGRect {
        let first = cardFrame(at: spot(of: pile))
        guard case .tableau = pile else { return first }
        let last = cardFrame(at: position(in: pile, at: max(0, board[pile].count - 1), of: board))
        return first.union(last).insetBy(dx: -gap / 2, dy: -gap / 2)
    }
}
