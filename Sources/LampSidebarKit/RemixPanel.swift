import SwiftUI

/// What the chat beside an app offers on a Mac that has no Lamp (the app was built from its code on GitHub, or kept
/// after Lamp was removed): the app's name and line, three things someone could ask to change, and a box for their own
/// words. Continue with Lamp takes the request to lamp.dev, where Lamp is downloaded and the wish waits for its first
/// open, or to the wish's own Share Link page when it has one, which also opens Lamp on a Mac that has it. Nothing is
/// sent anywhere else, and nothing is sent at all until the button is pressed.
public struct RemixOffer: Equatable {
    public var name: String
    public var about: String?
    public var suggestions: [RemixIdea]
    /// The wish's Share Link, when the person who made the app shared one: the page that gives this exact wish.
    public var shareLink: URL?
    /// What the app can be copied from, when it's a starter or lives on GitHub: Lamp starts from a copy of that.
    public var origin: RemixLink.Origin?

    public init(name: String, about: String?, suggestions: [RemixIdea], shareLink: URL?, origin: RemixLink.Origin? = nil) {
        self.name = name
        self.about = about
        self.suggestions = suggestions.isEmpty ? Self.fallback : suggestions
        self.shareLink = shareLink
        self.origin = origin
    }

    /// What's offered when Lamp never wrote suggestions for the app: true of any app.
    public static let fallback = [RemixIdea(text: "Change how it looks", symbol: "paintbrush"),
                                  RemixIdea(text: "Add something it doesn't do yet", symbol: "plus.circle"),
                                  RemixIdea(text: "Make it work the way I'd want", symbol: "slider.horizontal.3")]
}

/// One thing to ask for, with the symbol it's drawn with, as the intro's ideas are (`SidebarIdea`).
public struct RemixIdea: Codable, Equatable, Identifiable {
    public var text: String
    public var symbol: String
    public var id: String { text }

    public init(text: String, symbol: String) {
        self.text = text
        self.symbol = symbol
    }

    /// Read back from an app's Info.plist, where each is a dictionary of its two words; one without a symbol gets a spark.
    public static func from(plist: Any?) -> [RemixIdea] {
        ((plist as? [[String: String]]) ?? []).compactMap { entry in
            guard let text = entry["text"], !text.isEmpty else { return nil }
            return RemixIdea(text: text, symbol: entry["symbol"].flatMap { $0.isEmpty ? nil : $0 } ?? "sparkles")
        }
    }

    public var plist: [String: String] { ["text": text, "symbol": symbol] }
}

/// Where Continue with Lamp goes, and what it carries.
public enum RemixLink {
    public static let site = URL(string: "https://lamp.dev/")!
    /// The most a request carries; the site cuts there too (`askFrom` in lib/wish.js).
    public static let askLimit = 1000

    /// The words as they go: trimmed, without control characters, cut at the limit. Empty for nothing to say.
    public static func tidy(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { $0 == "\n" || !CharacterSet.controlCharacters.contains($0) }
        return String(String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines).prefix(askLimit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What a remix starts from: a starter Lamp ships (by its folder, "newyork"), or a repository on GitHub at a commit.
    /// Lamp's site takes these beside `ask` (`remixFrom` in lib/wish.js) and hands them to Lamp (`Wish.Remix`), which
    /// puts a copy of that on the desk with the request in its chat's box.
    public enum Origin: Equatable {
        case starter(String)
        case repository(url: String, commit: String?)

        /// The site's parameters for it, beside `ask`.
        public var queryItems: [URLQueryItem] {
            switch self {
            case .starter(let id): [URLQueryItem(name: "starter", value: id)]
            case .repository(let url, let commit): [URLQueryItem(name: "repo", value: url)] + (commit.map { [URLQueryItem(name: "commit", value: $0)] } ?? [])
            }
        }

        /// A repository as Lamp wrote it into an app's chat (`Sidebar.install`), checked as the site and Lamp check a link's:
        /// an https github.com address of an owner and a name, and a commit of hex. Nil for anything else.
        public static func repository(_ url: String?, commit: String?) -> Origin? {
            guard let url, let rest = url.hasPrefix("https://github.com/") ? url.dropFirst("https://github.com/".count) : nil else { return nil }
            let parts = rest.split(separator: "/", omittingEmptySubsequences: false)
            let plain = { (part: Substring) in !part.isEmpty && !part.hasPrefix("-") && !part.hasPrefix(".")
                && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) } }
            guard parts.count == 2, plain(parts[0]), plain(parts[1]) else { return nil }
            let commit = commit.flatMap { $0.isEmpty ? nil : $0 }
            if let commit, !((7...40).contains(commit.count) && commit.allSatisfy(\.isHexDigit)) { return nil }
            return .repository(url: url, commit: commit)
        }

        /// The same as JSON, for a page's own script (`Publish.withCreditBar`).
        public var json: [String: String] {
            Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in item.value.map { (item.name, $0) } })
        }
    }

    /// The page for the request. With an origin, Lamp's site with it and the request as it is, since Lamp starts from a
    /// copy of that; else the wish's Share Link with the request as `ask`, which the page adds to the wish's words; else
    /// Lamp's site with a request that names the app, since without either Lamp makes its own version.
    public static func url(for offer: RemixOffer, ask: String) -> URL? {
        let words = tidy(ask)
        guard !words.isEmpty else { return nil }
        let base = offer.origin == nil ? offer.shareLink ?? site : site
        guard var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let request = offer.origin == nil && offer.shareLink == nil ? tidy(self.request(for: offer, ask: words)) : words
        let mine: Set = ["ask", "starter", "repo", "commit"]
        parts.queryItems = (parts.queryItems ?? []).filter { !mine.contains($0.name) } + (offer.origin?.queryItems ?? [])
            + [URLQueryItem(name: "ask", value: request)]
        return parts.url
    }

    /// What pressing Continue with Lamp means, in one line under it: the only thing the person has to accept.
    public static func note(for offer: RemixOffer) -> String {
        if offer.origin != nil {
            return "Opens lamp.dev with your request. Lamp is a free Mac app; it opens a copy of \(offer.name.isEmpty ? "it" : offer.name) with your request ready to send."
        }
        if offer.shareLink != nil {
            return "Opens this wish's page with your request. Lamp is a free Mac app; it opens on this exact wish and changes it as you ask."
        }
        return "Opens lamp.dev with your request. Lamp is a free Mac app; it makes its own version of \(offer.name.isEmpty ? "it" : offer.name) and changes it as you ask."
    }

    /// A wish for an app like this one, then the change: what Lamp's welcome gets when there's no link to the exact wish.
    public static func request(for offer: RemixOffer, ask: String) -> String {
        var text = "Make an app like \(offer.name)"
        if let about = offer.about, !about.isEmpty { text += ": \(about)" }
        if let last = text.last, !".!?".contains(last) { text += "." }
        return text + "\n\nThen: \(ask)"
    }
}

/// The panel itself. Drawn from plain values, so the chat beside an app and the gallery show the same thing.
public struct RemixPanel: View {
    let offer: RemixOffer
    let go: (String) -> Void
    @State private var text = ""
    @State private var hovered: String?

    public init(offer: RemixOffer, go: @escaping (String) -> Void) {
        self.offer = offer
        self.go = go
    }

    private var ready: Bool { !RemixLink.tidy(text).isEmpty }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Make \(offer.name) yours").font(.title3.bold())
                Text("Say what you'd change. Lamp makes the change and keeps your data.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Drawn as the intro's ideas are: a quiet outline, the icon lit on hover.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(offer.suggestions.enumerated()), id: \.element.id) { index, idea in
                    Button {
                        text = idea.text
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            IdeaIcon(symbol: idea.symbol, hue: Double(index) * 0.27 + 0.08, size: 22, lit: hovered == idea.id)
                            Text(idea.text).font(.subheadline).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(hovered == idea.id ? 0.2 : 0.1), lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 ? idea.id : (hovered == idea.id ? nil : hovered) }
                }
            }
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 72)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            HStack {
                Spacer(minLength: 0)
                Button("Continue with Lamp") { go(text) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready)
            }
            .cardButtons()
            // What pressing it means, in one line: the only thing the person has to accept.
            Text(RemixLink.note(for: offer))
                .font(.footnote).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
