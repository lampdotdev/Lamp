import SwiftUI
final class Card {
    private var shape: some Shape = Circle()
    var name = "card"
    func describe() -> String { "\(type(of: shape)) name=\(name)" }
}
