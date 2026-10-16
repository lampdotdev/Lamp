import Foundation

/// Finds books by ISBN or title in Open Library, which is free and needs no key. This is the one file that
/// knows the shelves hold books: to keep something else (records, games), replace it with a lookup that
/// returns `ItemDetails` for that kind, and change the words in ItemKind.swift.
enum BookLookup {
    private static let base = URL(string: "https://openlibrary.org")!

    /// Accepts ISBN-13 and ISBN-10 as typed or scanned (with dashes or spaces) and gives back the ISBN-13,
    /// or nil when it isn't one. A barcode that isn't a book's (978 or 979) is nil too.
    static func normalize(_ text: String) -> String? {
        let raw = text.uppercased().filter { $0.isNumber || $0 == "X" }
        if raw.count == 13, raw.hasPrefix("978") || raw.hasPrefix("979"), raw.allSatisfy(\.isNumber),
           checkDigit13(raw.prefix(12)) == raw.last {
            return raw
        }
        if raw.count == 10, raw.dropLast().allSatisfy(\.isNumber) {
            let digits = raw.prefix(9).compactMap(\.wholeNumberValue)
            let sum = digits.enumerated().reduce(0) { $0 + $1.element * (10 - $1.offset) }
            let check = (11 - sum % 11) % 11
            guard raw.last == (check == 10 ? "X" : Character(String(check))) else { return nil }
            let body = "978" + raw.prefix(9)
            return body + String(checkDigit13(Substring(body)))
        }
        return nil
    }

    private static func checkDigit13(_ twelve: Substring) -> Character {
        let sum = twelve.compactMap(\.wholeNumberValue).enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 1 : 3) }
        return Character(String((10 - sum % 10) % 10))
    }

    static func coverURL(isbn: String) -> URL? {
        // default=false makes a missing cover a 404 rather than a blank picture.
        URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-M.jpg?default=false")
    }

    /// The book with this ISBN, or nil when Open Library doesn't know it.
    static func find(isbn: String) async throws -> ItemDetails? {
        var found = try await search(["isbn": isbn], limit: 1).first
        found?.code = isbn
        if found != nil, found?.coverURL == nil { found?.coverURL = coverURL(isbn: isbn) }
        return found
    }

    /// Books matching a title, an author or both.
    static func search(_ text: String) async throws -> [ItemDetails] {
        try await search(["q": text], limit: 12)
    }

    private static func search(_ terms: [String: String], limit: Int) async throws -> [ItemDetails] {
        var url = URLComponents(url: base.appendingPathComponent("search.json"), resolvingAgainstBaseURL: false)!
        url.queryItems = terms.map { URLQueryItem(name: $0.key, value: $0.value) } + [
            URLQueryItem(name: "fields", value: "title,author_name,first_publish_year,cover_i,number_of_pages_median"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        var request = URLRequest(url: url.url!, timeoutInterval: 15)
        // Open Library asks apps to say who they are.
        request.setValue("Shelves (a Mac app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(SearchResults.self, from: data).docs.map { doc in
            ItemDetails(title: doc.title, creator: doc.author_name?.first ?? "",
                        year: doc.first_publish_year,
                        coverURL: doc.cover_i.flatMap { URL(string: "https://covers.openlibrary.org/b/id/\($0)-M.jpg?default=false") },
                        pages: doc.number_of_pages_median)
        }
    }

    private struct SearchResults: Decodable {
        struct Doc: Decodable {
            let title: String
            let author_name: [String]?
            let first_publish_year: Int?
            let cover_i: Int?
            let number_of_pages_median: Int?
        }
        let docs: [Doc]
    }
}
