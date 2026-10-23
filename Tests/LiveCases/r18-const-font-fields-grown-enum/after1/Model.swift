import SwiftUI
enum Shelf: CaseIterable { case pantry, fridge, freezer }
struct Look {
    var design: Font.Design
    var shelves: [Shelf]
}
enum Theme {
    static let current = Look(design: .rounded, shelves: Shelf.allCases)
    static let plain = Shelf.allCases
}
func show() -> String { "themed=\(Theme.current.shelves.count) plain=\(Theme.plain.count) live=\(Shelf.allCases.count)" }
