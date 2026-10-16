import SwiftUI

extension Color {
    /// Cards are printed on white whatever the Mac's appearance, as real cards are.
    static let cardPaper = Color(red: 0.995, green: 0.99, blue: 0.975)
    static let cardRed = Color(red: 0.80, green: 0.11, blue: 0.16)
    static let cardBlack = Color(red: 0.09, green: 0.09, blue: 0.11)
    /// The warm panel behind a jack, queen or king.
    static let courtGold = Color(red: 0.99, green: 0.93, blue: 0.78)
}

/// One card, either way up, at a given width (its height is 1.4 times that).
struct CardView: View {
    let card: Card
    let width: CGFloat

    var body: some View {
        Group {
            if card.faceUp { CardFace(card: card, width: width) } else { CardBack(width: width) }
        }
        .frame(width: width, height: width * 1.4)
        .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
        .accessibilityElement()
        .accessibilityLabel(card.faceUp ? card.spokenName : "Face-down card")
    }
}

/// The face of a card, drawn entirely in code: the rank and suit in two corners, and in the middle the pips of a
/// number card, one large suit for an ace, or a framed letter for a jack, queen or king.
struct CardFace: View {
    let card: Card
    let width: CGFloat

    private var height: CGFloat { width * 1.4 }
    private var ink: Color { card.isRed ? .cardRed : .cardBlack }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                .fill(Color.cardPaper)
            RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                .strokeBorder(.black.opacity(0.18), lineWidth: 0.5)
            middle
            CornerIndex(card: card, width: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, width * 0.04)
                .padding(.top, width * 0.04)
            CornerIndex(card: card, width: width)
                .rotationEffect(.degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, width * 0.04)
                .padding(.bottom, width * 0.04)
        }
        .foregroundStyle(ink)
        .frame(width: width, height: height)
    }

    @ViewBuilder private var middle: some View {
        if card.rank == 1 {
            Image(systemName: card.suit.symbol)
                .font(.system(size: width * 0.42))
        } else if card.isFace {
            faceCenter
        } else {
            pips
        }
    }

    private var faceCenter: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.04, style: .continuous)
                .fill(Color.courtGold)
            RoundedRectangle(cornerRadius: width * 0.04, style: .continuous)
                .strokeBorder(ink.opacity(0.55), lineWidth: max(0.75, width * 0.012))
            VStack(spacing: -width * 0.02) {
                Text(card.rankLabel)
                    .font(.system(size: width * 0.44, weight: .bold, design: .serif))
                Image(systemName: card.suit.symbol)
                    .font(.system(size: width * 0.2))
            }
        }
        .frame(width: width * 0.56, height: height * 0.66)
    }

    /// The pips of a 2 to 10, placed as on printed cards; those in the lower half are upside down.
    private var pips: some View {
        let area = CGSize(width: width * 0.38, height: height * 0.62)
        return ZStack {
            ForEach(Array(Self.pipLayout(for: card.rank).enumerated()), id: \.offset) { _, spot in
                Image(systemName: card.suit.symbol)
                    .font(.system(size: width * 0.15))
                    .rotationEffect(.degrees(spot.y > 0.5 ? 180 : 0))
                    .position(x: spot.x * area.width, y: spot.y * area.height)
            }
        }
        .frame(width: area.width, height: area.height)
    }

    /// Pip places as fractions of the middle area: columns at 0, ½ and 1, rows from 0 (top) to 1 (bottom).
    static func pipLayout(for rank: Int) -> [CGPoint] {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)]
        let sides = [CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)]
        let thirds = [CGPoint(x: 0, y: 1.0 / 3), CGPoint(x: 1, y: 1.0 / 3), CGPoint(x: 0, y: 2.0 / 3), CGPoint(x: 1, y: 2.0 / 3)]
        func middle(_ y: Double) -> CGPoint { CGPoint(x: 0.5, y: y) }
        switch rank {
        case 2: return [middle(0), middle(1)]
        case 3: return [middle(0), middle(0.5), middle(1)]
        case 4: return corners
        case 5: return corners + [middle(0.5)]
        case 6: return corners + sides
        case 7: return corners + sides + [middle(0.25)]
        case 8: return corners + sides + [middle(0.25), middle(0.75)]
        case 9: return corners + thirds + [middle(0.5)]
        case 10: return corners + thirds + [middle(1.0 / 6), middle(5.0 / 6)]
        default: return []
        }
    }
}

/// The rank above a small suit, in a card's corner.
private struct CornerIndex: View {
    let card: Card
    let width: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Text(card.rankLabel)
                .font(.system(size: width * 0.17, weight: .semibold, design: .rounded))
                .tracking(card.rank == 10 ? -width * 0.02 : 0)
            Image(systemName: card.suit.symbol)
                .font(.system(size: width * 0.11))
        }
        .frame(width: width * 0.17)
    }
}
