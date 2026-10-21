import SwiftUI
final class Card {
    private var shape: some Shape = RoundedRectangle(cornerRadius: 8)
    var name = "card"
    func describe() -> String { "\(type(of: shape)) corner=\((shape as? RoundedRectangle)?.cornerSize == CGSize(width: 8, height: 8) ? "8x8" : "not what was made") name=\(name)" }
}
