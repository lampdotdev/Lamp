import Foundation

/// A word that could go in the grid, with a clue made only from what the map said about it.
struct Candidate: Codable, Hashable {
    var answer: String
    /// The lengths of its words, shown after the clue: "5", or "3,4" for NEW YORK.
    var lengths: String
    var clue: String
    /// How likely someone living here is to get it: 0 they know it (their town, the main streets, the big park),
    /// 1 they can work it out from the clue, 2 only a regular would know.
    var tier: Int
    /// What the clue was made from, for the AI to reword and for `Polish` to check its words against.
    var facts: String
}

/// Turns a neighborhood into candidate answers. Every clue here is true, since it says nothing the map didn't:
/// a street is "___ Street", a place named in more than one word has its most distinctive word taken out
/// ("Late ___ Cafe"), a one-word name is clued by what it is and where.
enum Answers {
    static func candidates(for place: Neighborhood) -> [Candidate] {
        var found: [String: Candidate] = [:]
        func add(_ answer: String, lengths: String? = nil, _ clue: String, tier: Int) {
            guard (3...12).contains(answer.count), !stock.contains(answer) else { return }
            if let have = found[answer], have.tier <= tier { return }
            found[answer] = Candidate(answer: answer, lengths: lengths ?? "\(answer.count)", clue: clue, tier: tier, facts: clue)
        }

        // The town and the part of it.
        if let area = place.area, let answer = letters(area) {
            add(answer, lengths: lengths(of: area), area == place.town ? "Your town" : "The part of town you're in", tier: 0)
        }
        if let town = place.town, town != place.area, let answer = letters(town) {
            add(answer, lengths: lengths(of: town), "Your town", tier: 0)
        }

        // Streets: the one most places are on is the main drag.
        let main = place.streets.max { $0.value < $1.value }?.key
        for (street, count) in place.streets {
            var words = street.split(separator: " ").map(String.init)
            guard words.count >= 2, let last = words.last, let kind = streetKinds[last] else { continue }
            words.removeLast()
            let stem = words.joined(separator: " ")
            guard let answer = ordinals[stem] ?? letters(stem) else { continue }
            // A place on it tells one "___ Street" from another, and is true: the map put it there.
            let landmark = place.spots.filter { $0.street == street }.map(\.name).min { ($0.count, $0) < ($1.count, $1) }
            let clue = street == main ? "___ \(kind), the main drag around here"
                : landmark.map { "___ \(kind), home of \($0)" } ?? "___ \(kind)"
            add(answer, lengths: ordinals[stem] == nil ? lengths(of: stem) : nil, clue, tier: street == main || count > 2 ? 0 : 1)
        }

        // Places.
        for spot in place.spots {
            let words = spot.name.split(separator: " ").map(String.init)
            let outdoors = ["Park", "Beach", "Zoo", "Marina"].contains(spot.kind)
            let where_ = spot.street.map { "on \($0)" } ?? "nearby"
            if words.count == 1, let answer = letters(spot.name), !generic.contains(answer) {
                add(answer, "\(spot.kind) \(where_)", tier: outdoors ? 1 : 2)
            } else if (2...5).contains(words.count) {
                let options = words.enumerated()
                    .compactMap { index, word in letters(word).map { (index, $0) } }
                    .filter { (3...12).contains($0.1.count) && !stock.contains($0.1) && !generic.contains($0.1) }
                guard let (index, answer) = options.max(by: { $0.1.count < $1.1.count }) else { continue }
                var shown = words
                shown[index] = "___"
                let name = shown.joined(separator: " ")
                if outdoors {
                    add(answer, name, tier: 0)
                } else {
                    add(answer, "\(name), \(spot.kind.lowercased()) \(where_)", tier: 1)
                }
            }
        }
        return found.values.sorted { ($0.tier, $0.answer) < ($1.tier, $1.answer) }
    }

    /// The AI's choices for a place, when it has made them, as candidates: its first dozen are the ones a local
    /// would know. Lengths come from the map's candidates, which every curated answer is one of.
    static func curated(_ place: Neighborhood, from candidates: [Candidate]) -> [Candidate] {
        let byAnswer = Dictionary(candidates.map { ($0.answer, $0) }, uniquingKeysWith: { a, _ in a })
        return place.curated.enumerated().compactMap { index, pick in
            guard var candidate = byAnswer[pick.answer] else { return nil }
            candidate.clue = pick.clue
            candidate.tier = index < 12 ? 0 : 1
            return candidate
        }
    }

    // MARK: Words

    /// Only the letters of a name, in capitals, when every one of them is A to Z once its accents are off:
    /// "Graça" is GRACA, "Kala Bagai" is KALABAGAI, a name in another script is nothing.
    static func letters(_ name: String) -> String? {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en")).uppercased()
        let kept = folded.filter { $0.isLetter }
        let expected = folded.filter { !" '’-.&".contains($0) }
        guard !kept.isEmpty, kept.allSatisfy(\.isASCII), kept.count == expected.count else { return nil }
        return kept
    }

    private static func lengths(of name: String) -> String {
        name.split(whereSeparator: { $0 == " " || $0 == "-" }).compactMap { letters(String($0))?.count }.map(String.init).joined(separator: ",")
    }

    private static let streetKinds: [String: String] = [
        "St": "Street", "Street": "Street", "Ave": "Avenue", "Av": "Avenue", "Avenue": "Avenue", "Pl": "Place",
        "Place": "Place", "Rd": "Road", "Road": "Road", "Blvd": "Boulevard", "Boulevard": "Boulevard", "Dr": "Drive",
        "Drive": "Drive", "Ln": "Lane", "Lane": "Lane", "Ct": "Court", "Court": "Court", "Ter": "Terrace",
        "Terrace": "Terrace", "Pkwy": "Parkway", "Parkway": "Parkway", "Sq": "Square", "Square": "Square", "Way": "Way",
    ]

    private static let ordinals: [String: String] = [
        "1st": "FIRST", "2nd": "SECOND", "3rd": "THIRD", "4th": "FOURTH", "5th": "FIFTH", "6th": "SIXTH", "7th": "SEVENTH",
        "8th": "EIGHTH", "9th": "NINTH", "10th": "TENTH", "First": "FIRST", "Second": "SECOND", "Third": "THIRD",
        "Fourth": "FOURTH", "Fifth": "FIFTH", "Sixth": "SIXTH", "Seventh": "SEVENTH", "Eighth": "EIGHTH", "Ninth": "NINTH",
    ]

    /// Words that are never an answer: they say what a place is rather than which one it is.
    private static let stock: Set<String> = [
        "THE", "AND", "CAFE", "CAFFE", "RESTAURANT", "BAR", "GRILL", "KITCHEN", "COFFEE", "PIZZA", "PIZZERIA", "SHOP",
        "HOUSE", "PARK", "BISTRO", "DINER", "DELI", "INC", "LLC", "NYC", "BAKERY", "TAVERN", "PUB", "EATERY", "FOOD",
        "FOODS", "BRASSERIE", "TAQUERIA", "SUSHI", "RAMEN", "MARKET", "CLUB", "LOUNGE", "WINE", "BEER", "TEA", "ICE",
        "CREAM", "BAGELS", "BAGEL", "EXPRESS", "STATION",
    ]

    /// Words that are never the one taken out of a name: what's left would give nothing away.
    private static let generic: Set<String> = [
        "DEPARTMENT", "STREET", "CITY", "MUSEUM", "MUSEU", "MUSEE", "COLLEGE", "SOCIETY", "CENTER", "CENTRE", "LIBRARY",
        "BIBLIOTECA", "CENTRAL", "HISTORY", "SCHOOL", "UNIVERSITY", "BUILDING", "HALL", "ART", "ARTS", "INSTITUTE",
        "NATIONAL", "PUBLIC", "MEMORIAL", "GALLERY", "THEATRE", "THEATER", "CINEMA", "DANCE", "STUDIO", "STUDIOS",
        "PROGRAM", "PROGRAMS", "CLINIC", "COMMUNITY", "BRANCH", "NORTH", "SOUTH", "EAST", "WEST", "NEW", "OLD", "LITTLE",
        "GRAND", "ROYAL", "CASA", "RUA", "LARGO", "PRACA", "IGREJA", "DOS", "DAS", "ESCOLA", "JARDIM", "PARQUE", "VIEW",
        "GARDEN", "GARDENS", "PLAYGROUND", "FIELD", "FIELDS", "DRINKING", "WATER", "FOUNTAIN", "TRUST", "ZONA",
    ]
}
