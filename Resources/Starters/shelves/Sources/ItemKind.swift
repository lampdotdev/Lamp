import Foundation

/// Every word that says what kind of thing is on the shelves. To keep records, games or figurines instead of
/// books, change these and the lookup (BookLookup.swift); the shelves, the model and the views don't name books.
enum ItemKind {
    static let singular = "Book"
    static let plural = "Books"
    /// Who made it: an author for a book, an artist for a record, a studio for a game.
    static let creator = "Author"
    /// The number on its barcode.
    static let code = "ISBN"
    /// The shelf a new collection starts with, and the one offered for things to get later.
    static let firstShelf = "Books"
    static let wishShelf = "Want to Read"
    static let symbol = "book.closed"

    /// How a finished item's status reads ("Read" for a book, "Played" for a game).
    static func label(for status: ItemStatus) -> String {
        switch status {
        case .want: "Want to Read"
        case .reading: "Reading"
        case .read: "Read"
        case .lent: "Lent Out"
        }
    }
}
