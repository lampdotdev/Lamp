import Foundation
// As agents write a category: String raw values, for saving and showing.
enum Shelf: String, CaseIterable { case pantry, fridge, freezer }
enum Rank: Int, CaseIterable { case low, high, top }
struct Look { var shelf: Shelf; var size: Double }
enum Catalog {
    static let shelves = Shelf.allCases
    static let ranks = Rank.allCases
    static let start: Shelf = .fridge
    static let look = Look(shelf: .pantry, size: 12)
}
// A list the app keeps and may change, made once from the enum: a new case has to reopen the app.
enum Pantry { static var open = Shelf.allCases }
func show() -> String {
    "open=\(Pantry.open.count) shelves=\(Catalog.shelves.count) live=\(Shelf.allCases.count) ranks=\(Catalog.ranks.count) start=\(Catalog.start.rawValue) size=\(Catalog.look.size)"
}
