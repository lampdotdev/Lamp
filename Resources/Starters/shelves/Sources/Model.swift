import SwiftUI

/// One thing on a shelf. The fields are general on purpose (a creator rather than an author, a code rather
/// than an ISBN), so the same model holds records, games or figurines when the app is changed to keep those.
/// New properties should be optional, so items saved before them still load.
struct ShelfItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var creator: String
    var year: Int?
    /// The barcode number it was found by (an ISBN for a book), when it has one.
    var code: String?
    var coverURL: URL?
    var notes = ""
    /// 0 is not rated, otherwise 1 to 5 stars.
    var rating = 0
    var tags: [String] = []
    var status: ItemStatus = .read
    var lentTo = ""
    var shelfID: UUID
    var added = Date()
    /// Stood with its cover to the room instead of its spine.
    var facesOut = false
    var look: SpineLook
    /// Written as an example on first launch; Clear Examples removes only these.
    var isExample = false
}

enum ItemStatus: String, Codable, CaseIterable, Identifiable {
    case want, reading, read, lent
    var id: String { rawValue }
    var label: String { ItemKind.label(for: self) }
}

/// How an item stands on the shelf: its colour and its size in points. Picked at random when it's added, so
/// a shelf looks lived in, and recoloured once from its cover when that arrives.
struct SpineLook: Codable, Hashable {
    var hue: Double
    var saturation: Double
    var brightness: Double
    var width: Double
    var height: Double
    var fromCover = false

    var color: Color { Color(hue: hue, saturation: saturation, brightness: brightness) }
    /// Words on the spine are dark on a light colour (a yellow, a cream) and light on everything else.
    var ink: Color {
        let rgb = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        let lightness = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return lightness > 0.6 ? .black.opacity(0.78) : .white.opacity(0.92)
    }

    static let tallest = 156.0

    /// A plausible look for a new item; thicker when it has more pages.
    static func random(pages: Int? = nil) -> SpineLook {
        let colours: [(Double, Double, Double)] = [
            (0.02, 0.62, 0.62), (0.08, 0.55, 0.78), (0.12, 0.35, 0.88), (0.33, 0.35, 0.45),
            (0.55, 0.45, 0.50), (0.60, 0.55, 0.38), (0.75, 0.30, 0.40), (0.95, 0.45, 0.55),
            (0.10, 0.10, 0.92), (0.58, 0.10, 0.25),
        ]
        let (h, s, b) = colours.randomElement()!
        let width = pages.map { min(44, max(16, 12 + Double($0) / 22)) } ?? Double.random(in: 20...36)
        return SpineLook(hue: h, saturation: s, brightness: b, width: width.rounded(),
                         height: Double.random(in: 118...tallest).rounded())
    }

    /// The same look in the colour of the cover, kept readable on a shelf.
    func tinted(from cover: NSColor) -> SpineLook {
        guard let rgb = cover.usingColorSpace(.deviceRGB) else { return self }
        var copy = self
        copy.hue = rgb.hueComponent
        copy.saturation = min(0.8, rgb.saturationComponent * 1.1)
        copy.brightness = min(0.88, max(0.22, rgb.brightnessComponent))
        copy.fromCover = true
        return copy
    }
}

struct Shelf: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var order: Int
}

/// What a lookup found, before it's put on a shelf.
struct ItemDetails: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var creator: String
    var year: Int?
    var code: String?
    var coverURL: URL?
    var pages: Int?
}

enum ShelfOrder: String, CaseIterable, Identifiable {
    case creator, colour, recent
    var id: String { rawValue }

    var label: String {
        switch self {
        case .creator: "By \(ItemKind.creator)"
        case .colour: "By Colour"
        case .recent: "Recently Added"
        }
    }

    func sorted(_ items: [ShelfItem]) -> [ShelfItem] {
        switch self {
        case .creator:
            // By surname, the way a bookshop shelves them.
            return items.sorted { a, b in
                let byName = a.creator.surname.localizedCaseInsensitiveCompare(b.creator.surname)
                if byName != .orderedSame { return byName == .orderedAscending }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        case .colour:
            // Greys and near-blacks at the end, the rest round the colour wheel.
            return items.sorted { a, b in
                let ga = a.look.saturation < 0.15, gb = b.look.saturation < 0.15
                if ga != gb { return gb }
                return ga ? a.look.brightness > b.look.brightness : a.look.hue < b.look.hue
            }
        case .recent:
            return items.sorted { $0.added > $1.added }
        }
    }
}

private extension String {
    var surname: String { split(separator: " ").last.map(String.init) ?? self }
}
