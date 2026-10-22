import SwiftUI

/// The table: every card drawn at the place `TableLayout` gives it, so a move is just a change to the board and
/// SwiftUI slides each card to its new place. Cards are dragged (with whatever lies on them), double-clicked up
/// to a foundation, and the stock is clicked to draw.
struct TableView: View {
    let game: Game

    @State private var drag: Drag?

    /// The cards being dragged, from where, and how far they've gone.
    private struct Drag {
        var pile: Pile
        var index: Int
        var ids: [Card.ID]
        var origin: CGPoint
        var translation: CGSize = .zero
    }

    private struct Placement: Identifiable {
        let card: Card
        let pile: Pile
        let index: Int
        let point: CGPoint
        let z: Double
        var id: Card.ID { card.id }
    }

    static let moveAnimation = Animation.snappy(duration: 0.22)

    var body: some View {
        GeometryReader { geometry in
            let layout = TableLayout(size: geometry.size)
            ZStack {
                outlines(layout)
                ForEach(placements(layout)) { placement in
                    card(placement, layout: layout)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .coordinateSpace(.named("table"))
        }
    }

    // MARK: Empty places

    @ViewBuilder private func outlines(_ layout: TableLayout) -> some View {
        let board = game.board
        PileOutline(width: layout.cardWidth, symbol: board.waste.isEmpty ? nil : "arrow.counterclockwise")
            .position(layout.spot(of: .stock))
            .onTapGesture { withAnimation(Self.moveAnimation) { game.draw() } }
            .accessibilityElement()
            .accessibilityLabel(board.waste.isEmpty ? "Stock, empty" : "Turn the waste over")
            .accessibilityAddTraits(.isButton)
        PileOutline(width: layout.cardWidth)
            .position(layout.spot(of: .waste))
            .accessibilityHidden(true)
        ForEach(0..<4, id: \.self) { index in
            PileOutline(width: layout.cardWidth, letter: "A")
                .position(layout.spot(of: .foundation(index)))
                .accessibilityLabel("Foundation, empty")
        }
        ForEach(0..<7, id: \.self) { index in
            PileOutline(width: layout.cardWidth, letter: "K")
                .opacity(0.7)
                .position(layout.spot(of: .tableau(index)))
                .accessibilityLabel("Empty column")
        }
    }

    // MARK: Cards

    private func placements(_ layout: TableLayout) -> [Placement] {
        let board = game.board
        var result: [Placement] = []
        func add(_ pile: Pile, layer: Double) {
            for (index, card) in board[pile].enumerated() {
                // Cards a move carried, and cards in hand, are drawn above everything else.
                var z = layer + Double(index)
                if game.lastMoved.contains(card.id) { z += 1000 }
                if drag?.ids.contains(card.id) == true { z += 2000 }
                let point = layout.position(in: pile, at: index, of: board)
                result.append(Placement(card: card, pile: pile, index: index, point: point, z: z))
            }
        }
        add(.stock, layer: 0)
        add(.waste, layer: 100)
        for (i, pile) in Pile.foundations.enumerated() { add(pile, layer: 200 + Double(i) * 20) }
        for (i, pile) in Pile.tableaus.enumerated() { add(pile, layer: 400 + Double(i) * 30) }
        return result
    }

    private func card(_ placement: Placement, layout: TableLayout) -> some View {
        let inHand = drag?.ids.contains(placement.card.id) == true
        return CardView(card: placement.card, width: layout.cardWidth)
            .scaleEffect(inHand ? 1.04 : 1)
            .shadow(color: .black.opacity(inHand ? 0.3 : 0), radius: 8, y: 6)
            .offset(inHand ? drag?.translation ?? .zero : .zero)
            .gesture(dragGesture(for: placement, layout: layout))
            .onTapGesture(count: placement.pile == .stock ? 1 : 2) {
                withAnimation(Self.moveAnimation) {
                    if placement.pile == .stock {
                        game.draw()
                    } else {
                        game.sendToFoundation(placement.card.id)
                    }
                }
            }
            .accessibilityAction(named: placement.pile == .stock ? "Draw" : "Send to Foundation") {
                withAnimation(Self.moveAnimation) {
                    if placement.pile == .stock { game.draw() } else { game.sendToFoundation(placement.card.id) }
                }
            }
            .position(placement.point)
            .zIndex(placement.z)
    }

    // MARK: Dragging

    private func dragGesture(for placement: Placement, layout: TableLayout) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("table"))
            .onChanged { value in
                if drag == nil {
                    guard game.isPlayable, let run = game.board.run(from: placement.pile, at: placement.index) else { return }
                    drag = Drag(pile: placement.pile, index: placement.index, ids: run.map(\.id), origin: placement.point)
                }
                guard drag?.ids.first == placement.card.id else { return }
                drag?.translation = value.translation
            }
            .onEnded { _ in
                guard let drag, drag.ids.first == placement.card.id else { return }
                let target = dropTarget(for: drag, layout: layout)
                withAnimation(Self.moveAnimation) {
                    if let target { game.move(from: drag.pile, at: drag.index, to: target) }
                    self.drag = nil
                }
            }
    }

    /// The pile the dragged cards overlap most among those that would take them; nil sends them back.
    private func dropTarget(for drag: Drag, layout: TableLayout) -> Pile? {
        let board = game.board
        guard let run = board.run(from: drag.pile, at: drag.index) else { return nil }
        let center = CGPoint(x: drag.origin.x + drag.translation.width, y: drag.origin.y + drag.translation.height)
        let held = layout.cardFrame(at: center)
        var best: (pile: Pile, overlap: CGFloat)?
        for pile in Pile.foundations + Pile.tableaus where pile != drag.pile && board.accepts(run, on: pile) {
            let overlap = held.intersection(layout.dropArea(of: pile, on: board))
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.overlap ?? 0) { best = (pile, area) }
        }
        return best?.pile
    }
}
