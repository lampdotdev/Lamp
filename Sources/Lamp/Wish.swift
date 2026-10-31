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

    /// A wish link's query, read as a browser's form would write it too: a page that builds the link with
    /// `URLSearchParams` writes a space as "+", which `URLComponents` would keep (a "+" typed is "%2B" either way).
    static func items(of url: URL) -> [URLQueryItem] {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
        return parts.queryItems ?? []
    }

    /// The wish a link carries, when it is one of this Lamp's wish links.
    static func from(link url: URL, scheme: String = Edition.urlScheme) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "wish" else { return nil }
        return tidy(items(of: url).first { $0.name == "text" }?.value)
    }

    /// The exact wish a link brings with a request (`lamp://wish?file=https://…&text=…`, from a shared wish's page
    /// when a request came with it from an app's remix panel): the shared file's address, which Lamp fetches and
    /// reviews as it would a file opened by hand, and the request for the wish's box. The address must be https.
    struct Exact: Equatable {
        let file: URL
        let text: String?
    }

    static func exact(from url: URL, scheme: String = Edition.urlScheme) -> Exact? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "wish",
              case let items = items(of: url),
              let file = items.first(where: { $0.name == "file" })?.value.flatMap(URL.init(string:)),
              file.scheme?.lowercased() == "https", file.host?.isEmpty == false else { return nil }
        return Exact(file: file, text: tidy(items.first { $0.name == "text" }?.value))
    }

    /// A remix a link brings (`lamp://wish?starter=newyork&text=…`, or `?repo=https://github.com/…&commit=…&text=…`,
    /// from Lamp's site when a published page's Remix panel or an app's names what it's a copy of): what to start
    /// from, and the request for its chat's box. Lamp puts a fresh copy of that on the desk (a starter it ships, or the
    /// repository through Open from GitHub's own fetch and review) and opens it with the request waiting there.
    /// Everything in it is untrusted: a starter only by a folder's plain name, which must be one this Lamp ships; a
    /// repository only as an https github.com address with no path past its name, and a commit only as its full 40 hex digits.
    struct Remix: Equatable, Codable {
        enum From: Equatable, Codable {
            case starter(String)
            case repository(url: String, commit: String?)
        }
        let from: From
        let text: String?

        /// The repository to fetch, at its commit when one was named.
        var source: RepoImport.Source? {
            guard case .repository(let url, let commit) = from, var source = RepoImport.source(from: url) else { return nil }
            source.ref = commit
            return source
        }
    }

    /// Whether a link is one of this Lamp's wish links naming what to start from, valid or not: one that names it
    /// badly is refused, never taken for a plain wish.
    static func isRemix(_ url: URL, scheme: String = Edition.urlScheme) -> Bool {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "wish" else { return false }
        return items(of: url).contains { $0.name == "starter" || $0.name == "repo" }
    }

    static func remix(from url: URL, scheme: String = Edition.urlScheme) -> Remix? {
        guard isRemix(url, scheme: scheme) else { return nil }
        let items = items(of: url)
        let value = { (name: String) in items.first { $0.name == name }?.value }
        return remix(starter: value("starter"), repo: value("repo"), commit: value("commit"), text: value("text"))
    }

    /// A remix from its parts, each checked: exactly one of a starter or a repository.
    static func remix(starter: String?, repo: String?, commit: String?, text: String?) -> Remix? {
        switch (starter, repo) {
        case (let id?, nil):
            guard commit == nil, isStarterName(id) else { return nil }
            return Remix(from: .starter(id), text: tidy(text))
        case (nil, let address?):
            // The repository's own address and nothing else: https, github.com, owner and name.
            guard address.lowercased().hasPrefix("https://github.com/"), let source = RepoImport.source(from: address),
                  source.ref == nil else { return nil }
            if let commit, !isCommit(commit) { return nil }
            return Remix(from: .repository(url: source.url, commit: commit?.lowercased()), text: tidy(text))
        default:
            return nil
        }
    }

    /// A starter's folder name as Lamp ships them ("newyork", "homehq"): lowercase letters, digits and hyphens.
    static func isStarterName(_ text: String) -> Bool {
        (1...40).contains(text.count) && text.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") } && !text.hasPrefix("-")
    }

    /// A commit in full, 40 hex digits: a shallow fetch takes only a full one, never an abbreviation.
    static func isCommit(_ text: String) -> Bool {
        text.count == 40 && text.allSatisfy(\.isHexDigit)
    }

    /// What was copied, only when it carries Lamp's mark.
    static func marked(html: String?, plain: String?) -> String? {
        guard let html, html.contains(mark) else { return nil }
        return tidy(plain)
    }

    /// A remix copied with Lamp's mark: the site puts what to start from in the mark's own value, as a link's query
    /// would (`data-lamp-wish="starter=newyork"`, or `repo=…&commit=…`; `wishHTML` in lib/wish.js), since the mark is
    /// what browsers are known to keep. Nil when the copy names none, or names it badly; the words are the request.
    static func markedRemix(html: String?, plain: String?) -> Remix? {
        guard let html, let found = html.range(of: #"\#(mark)="([^"]*)""#, options: .regularExpression) else { return nil }
        let value = html[found].dropFirst(mark.count + 2).dropLast()
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
        let items = URL(string: "lamp://wish?" + value).map(items(of:)) ?? []
        let named = { (name: String) in items.first { $0.name == name }?.value }
        guard named("starter") != nil || named("repo") != nil else { return nil }
        return remix(starter: named("starter"), repo: named("repo"), commit: named("commit"), text: plain)
    }

    enum Look: Equatable {
        case wish(String)
        /// A remix copied by the site's Download: a copy of a starter or a repository, with the request.
        case remix(Remix)
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
        let html = pasteboard.string(forType: .html), plain = pasteboard.string(forType: .string)
        if let remix = markedRemix(html: html, plain: plain) { return .remix(remix) }
        return marked(html: html, plain: plain).map(Look.wish) ?? .nothing
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
