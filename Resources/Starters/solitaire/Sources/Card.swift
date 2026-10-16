import SwiftUI

enum Suit: Int, Codable, CaseIterable {
    case spades, hearts, diamonds, clubs

    var isRed: Bool { self == .hearts || self == .diamonds }

    var symbol: String {
        switch self {
        case .spades: "suit.spade.fill"
        case .hearts: "suit.heart.fill"
        case .diamonds: "suit.diamond.fill"
        case .clubs: "suit.club.fill"
        }
    }

    var name: String {
        switch self {
        case .spades: "Spades"
        case .hearts: "Hearts"
        case .diamonds: "Diamonds"
        case .clubs: "Clubs"
        }
    }
}

/// One playing card. Its id stays the same whichever way up it lies, so SwiftUI can follow a card as it moves
/// and flips, and animate it from one pile to the next.
struct Card: Codable, Hashable, Identifiable {
    let suit: Suit
    /// 1 is the ace, 11 to 13 the jack, queen and king.
    let rank: Int
    var faceUp = false

    var id: Int { suit.rawValue * 13 + rank - 1 }
    var isRed: Bool { suit.isRed }
    var isFace: Bool { rank > 10 }

    var rankLabel: String {
        switch rank {
        case 1: "A"
        case 11: "J"
        case 12: "Q"
        case 13: "K"
        default: "\(rank)"
        }
    }

    var spokenName: String {
        let rankName = switch rank {
        case 1: "Ace"
        case 11: "Jack"
        case 12: "Queen"
        case 13: "King"
        default: "\(rank)"
        }
        return "\(rankName) of \(suit.name)"
    }

    static let deck: [Card] = Suit.allCases.flatMap { suit in (1...13).map { Card(suit: suit, rank: $0) } }
}

/// A random number generator that gives the same numbers for the same seed: the sample game is dealt the same
/// way on every Mac, and the felt's texture doesn't shimmer as the window resizes.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        // SplitMix64.
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
