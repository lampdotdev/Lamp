import Foundation

/// The books on the shelf the first time the app opens, so it shows what it does straight away. They are
/// marked `isExample`, and Clear Examples takes away only these. The ISBNs are real, so their covers load
/// from Open Library; without a connection they get covers drawn in code.
enum Examples {
    static func items(on shelf: Shelf.ID) -> [ShelfItem] {
        let books: [(String, String, Int, String, ItemStatus, Int, Bool, Double, Double)] = [
            // title, author, year, ISBN, status, rating, faces out, width, height
            ("Dune", "Frank Herbert", 1965, "9780441172719", .read, 5, true, 34, 150),
            ("The Hobbit", "J.R.R. Tolkien", 1937, "9780547928227", .read, 5, false, 26, 140),
            ("Pride and Prejudice", "Jane Austen", 1813, "9780141439518", .read, 4, false, 28, 142),
            ("Nineteen Eighty-Four", "George Orwell", 1949, "9780451524935", .read, 4, false, 22, 124),
            ("To Kill a Mockingbird", "Harper Lee", 1960, "9780061120084", .read, 5, false, 24, 132),
            ("The Great Gatsby", "F. Scott Fitzgerald", 1925, "9780743273565", .lent, 4, false, 18, 130),
            ("One Hundred Years of Solitude", "Gabriel García Márquez", 1967, "9780060883287", .reading, 0, false, 30, 154),
            ("Beloved", "Toni Morrison", 1987, "9781400033416", .read, 5, false, 24, 128),
            ("The Left Hand of Darkness", "Ursula K. Le Guin", 1969, "9780441478125", .read, 4, false, 22, 122),
            ("Sapiens", "Yuval Noah Harari", 2011, "9780062316097", .read, 3, true, 36, 146),
            ("The Remains of the Day", "Kazuo Ishiguro", 1989, "9780679731726", .want, 0, false, 20, 126),
            ("Project Hail Mary", "Andy Weir", 2021, "9780593135204", .read, 5, false, 32, 148),
        ]
        let start = Date().addingTimeInterval(-60 * 60 * 24 * 90)
        return books.enumerated().map { index, book in
            let (title, author, year, isbn, status, rating, facesOut, width, height) = book
            var look = SpineLook.random()
            look.width = width
            look.height = height
            return ShelfItem(
                title: title, creator: author, year: year, code: isbn,
                coverURL: BookLookup.coverURL(isbn: isbn),
                notes: notes[title] ?? "", rating: rating, status: status,
                lentTo: status == .lent ? "Sam" : "", shelfID: shelf,
                // Spread over the last three months, so Recently Added has an order to show.
                added: start.addingTimeInterval(Double(index) * 60 * 60 * 24 * 7),
                facesOut: facesOut, look: look, isExample: true)
        }
    }

    private static let notes = [
        "Dune": "Reread every few years. The appendices are worth it.",
        "One Hundred Years of Solitude": "Keep the family tree at the front open while reading.",
        "The Great Gatsby": "Lent after book club. Ask for it back in the spring.",
    ]
}
