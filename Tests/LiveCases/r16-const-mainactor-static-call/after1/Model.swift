import SwiftUI
// A constant of a main-actor type made by a static helper of the type.
@MainActor enum Board {
    static let columnCount = makeCount()
    static func makeCount() -> Int { 4 }
}
@MainActor func show() -> String { "columns=\(Board.columnCount)" }
