import AppKit

/// A wish written on lamp.dev and handed to Lamp, so nobody has to copy and paste it. Two ways in:
/// a link (`lamp://wish?text=…`), for a Mac that already has Lamp, and the clipboard, for one that is
/// about to: the site's Download button copies the wish with a mark only Lamp looks for, and Lamp takes it
/// on its first open. Either way the wish only fills a box: any page can open a link or copy something, so
/// nothing is sent or built until the person says so.
enum Wish {
    /// The site puts this attribute on the wish in the clipboard's web form (`site/lib/wish.js`). The plain
    /// text beside it is just the wish, so pasted anywhere else nothing shows.
    static let mark = "data-lamp-wish"
    /// Longer than anything the site writes; whatever arrives is cut here.
    static let limit = 4000
    /// Lamp looks at the clipboard by itself once, the first time the welcome is shown.
    static let lookedKey = "wishClipboardLooked"

    /// The words as they go in a box: trimmed, without control characters, never longer than `limit`.
    static func tidy(_ text: String?) -> String? {
        guard let text else { return nil }
        let kept = text.unicodeScalars.filter { $0 == "\n" || !CharacterSet.controlCharacters.contains($0) }
        let wish = String(String(String.UnicodeScalarView(kept)).trimmed.prefix(limit)).trimmed
        return wish.isEmpty ? nil : wish
    }

    /// The wish a link carries, when it is one of this Lamp's wish links.
    static func from(link url: URL, scheme: String = Edition.urlScheme) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "wish" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        return tidy(items?.first { $0.name == "text" }?.value)
    }

    /// What was copied, only when it carries Lamp's mark.
    static func marked(html: String?, plain: String?) -> String? {
        guard let html, html.contains(mark) else { return nil }
        return tidy(plain)
    }

    enum Look: Equatable {
        case wish(String)
        /// A browser's copy is waiting, but reading it would make macOS ask the person first.
        case wouldAsk
        case nothing
    }

    /// Looks for a wish without ever making macOS ask about the clipboard: what kinds of thing are on it can be
    /// seen without reading them, and macOS says beforehand whether a read would ask.
    @MainActor static func look(at pasteboard: NSPasteboard = .general) -> Look {
        guard let types = pasteboard.types, types.contains(.html), types.contains(.string) else { return .nothing }
        if #available(macOS 15.4, *) {
            switch pasteboard.accessBehavior {
            case .alwaysAllow: break
            case .alwaysDeny: return .nothing
            default: return fromBrowser(types) ? .wouldAsk : .nothing
            }
        }
        return marked(html: pasteboard.string(forType: .html), plain: pasteboard.string(forType: .string)).map(Look.wish) ?? .nothing
    }

    /// Whether to offer a Paste button: only where macOS stands between Lamp and a browser's copy. Reads nothing.
    @MainActor static func offersPaste(from pasteboard: NSPasteboard = .general) -> Bool {
        guard #available(macOS 15.4, *), let types = pasteboard.types, types.contains(.string), fromBrowser(types) else { return false }
        return pasteboard.accessBehavior != .alwaysAllow && pasteboard.accessBehavior != .alwaysDeny
    }

    /// Browsers leave a type of their own beside what they copy; other apps' rich text doesn't have one.
    static func fromBrowser(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains { type in ["webkit", "chromium", "mozilla"].contains { type.rawValue.lowercased().contains($0) } }
    }

    /// The clipboard's text, read because the person pressed Paste.
    @MainActor static func pasted(from pasteboard: NSPasteboard = .general) -> String? {
        tidy(pasteboard.string(forType: .string))
    }

    /// A wish being written into a box a word at a time. Only what the box shows: the box's own text is the
    /// whole wish from the first moment, so whatever reads it meanwhile (Send, Continue, a save) has all of it,
    /// and nothing the person adds to the box (a file, their own words, an idea, dictation) is written over.
    struct Arrival: Equatable {
        let wish: String
        private(set) var shown = ""

        init(_ wish: String) { self.wish = wish }

        /// What the box shows over what it holds. The moment it holds anything but the untouched wish, that
        /// is what shows: the writing never covers a choice the person made.
        func text(over held: String) -> String { held == wish ? shown : held }

        mutating func advance(to step: String) { shown = step }
    }

    /// How much of the wish shows at each moment while it is written into a box a word at a time, as the site
    /// writes its own lines: each step is the text up to the end of one more word, the last one all of it.
    static func steps(_ wish: String) -> [String] {
        var steps: [String] = []
        var inWord = false
        for index in wish.indices {
            let space = wish[index].isWhitespace
            if inWord && space { steps.append(String(wish[..<index])) }
            inWord = !space
        }
        return steps + [wish]
    }

    /// The pause between words: the site's pace, quicker for a long wish so it never takes more than a moment.
    static func pace(words: Int) -> Duration {
        .milliseconds(max(8, min(45, 1600 / max(words, 1))))
    }
}
