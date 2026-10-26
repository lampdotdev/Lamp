import Foundation

/// Where a wish came from: `credits.json` at its root. `upstream` is other people's work in it (code, models, pictures,
/// sounds, data), each with where it's from, the commit it was taken at, its licence as an SPDX id and its author, which
/// the agent writes when it brings such work in (`Agent.Rules.about`); `remixOf` is the chain of wishes it was made
/// from, oldest first, which only Lamp adds to: a starter's copy starts it (`Starters.copy`), and every share adds the
/// wish being shared (`Sharing.export`), so a remix of a remix still names each wish before it.
///
/// Credit is only ever added to. Lamp keeps what a wish arrived with (`arrived`, in its own folder) and reads it back
/// with whatever the file says now (`load`), so an entry the file lost while the wish was changed is still credited,
/// shared on and shown. Lamp reads the file as data and keeps only what passes `checked`, the same for a file the agent
/// wrote and one a shared file brought.
struct Credits: Codable, Equatable {
    static let file = "credits.json"

    /// Someone else's work in the wish.
    struct Source: Codable, Equatable {
        /// What it's called where it came from: "Slop New York".
        var name: String
        /// Who made it, as they sign their work: "Mr.doob".
        var author: String?
        /// Where it lives, https only: "https://github.com/mrdoob/slop-newyork".
        var url: String?
        /// The commit it was taken at, for code from a repository.
        var commit: String?
        /// Its licence as an SPDX id or expression ("MIT", "Apache-2.0", "GPL-3.0-or-later", "MIT OR Apache-2.0"), or
        /// a `LicenseRef-` for terms with no id. None when it came with no licence.
        var license: String?
        /// Where its licence text is in the wish: "Web/LICENSE-slop-newyork".
        var licenseFile: String?
    }

    /// A wish this one was made from.
    struct Remix: Codable, Equatable {
        var name: String
        /// The starter's folder, for a wish that came with Lamp.
        var starter: String?
        /// The shared wish's identity (`Sharing.identity`), for one that came in a shared file.
        var wish: String?
    }

    var upstream: [Source] = []
    var remixOf: [Remix] = []

    var isEmpty: Bool { upstream.isEmpty && remixOf.isEmpty }

    // MARK: Reading and writing

    /// The wish's credits: what its file says now, with anything it arrived with that the file no longer has.
    static func load(_ project: LampProject) -> Credits {
        let now = read(project.dir.appendingPathComponent(file)) ?? Credits()
        guard let arrived = read(arrivedURL(project)) else { return now }
        return arrived.merged(with: now)
    }

    static func read(_ url: URL) -> Credits? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decoded(data)
    }

    /// A credits file as Lamp takes it: what passes the checks, nothing else.
    static func decoded(_ data: Data) -> Credits? {
        (try? JSONDecoder().decode(Lenient.self, from: data)).map { Credits(upstream: $0.upstream ?? [], remixOf: $0.remixOf ?? []).checked }
    }

    /// Gives the wish these credits, in its file and as what it arrived with: a starter's copy, a shared file opened.
    /// None takes both away, for a wish updated from a file that carries none.
    static func arrive(_ credits: Credits?, in project: LampProject) throws {
        let fm = FileManager.default
        guard let credits, !credits.isEmpty else {
            try? fm.removeItem(at: project.dir.appendingPathComponent(file))
            try? fm.removeItem(at: arrivedURL(project))
            return
        }
        try credits.encoded().write(to: project.dir.appendingPathComponent(file), options: .atomic)
        try fm.createDirectory(at: arrivedURL(project).deletingLastPathComponent(), withIntermediateDirectories: true)
        try credits.encoded().write(to: arrivedURL(project), options: .atomic)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    private static func arrivedURL(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/credits-arrived.json") }

    /// Each list may be missing from a file, and an entry that doesn't decode drops only itself.
    private struct Lenient: Decodable {
        var upstream: [Source]?
        var remixOf: [Remix]?
        enum Keys: String, CodingKey { case upstream, remixOf }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            upstream = try? container.decode([Maybe<Source>].self, forKey: .upstream).compactMap(\.value)
            remixOf = try? container.decode([Maybe<Remix>].self, forKey: .remixOf).compactMap(\.value)
        }
    }

    private struct Maybe<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    // MARK: Adding to the chain

    /// These credits with `other`'s added: everything in either, each entry once, in the order first seen.
    func merged(with other: Credits) -> Credits {
        var result = self
        for source in other.upstream where !result.upstream.contains(where: { $0.sameWork(as: source) }) { result.upstream.append(source) }
        // A source both name is taken as the newer file says it (a later commit, a licence filled in).
        for (index, source) in result.upstream.enumerated() {
            if let newer = other.upstream.first(where: { $0.sameWork(as: source) }) { result.upstream[index] = newer }
        }
        for remix in other.remixOf where !result.remixOf.contains(where: { $0.sameWish(as: remix) }) { result.remixOf.append(remix) }
        return result.checked
    }

    /// The chain with one more wish at its end. The same wish shared again (an update, a second share) stays one link,
    /// named as it's called now, and only when it's already the last: a wish that came back after another took it on
    /// is a link of its own.
    func remixed(from remix: Remix) -> Credits {
        var result = self
        if let last = result.remixOf.last, last.sameWish(as: remix) {
            result.remixOf[result.remixOf.count - 1] = remix
        } else {
            result.remixOf.append(remix)
        }
        return result.checked
    }

    // MARK: What a person reads

    /// "Slop New York by Mr.doob", the standard credit line.
    static func line(for source: Source) -> String {
        source.author.map { "\(source.name) by \($0)" } ?? source.name
    }

    /// "Based on Slop New York by Mr.doob": the work the wish is built on, which is the first one recorded.
    var basedOn: String? { upstream.first.map { "Based on " + Self.line(for: $0) } }

    /// The page Credits.html in a Mac app's bundle, which the standard About window shows under the app's name: each
    /// work it's based on, linked where it lives, with its licence, then the wishes it was remixed from.
    var aboutPage: String? {
        guard !isEmpty else { return nil }
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        var lines: [String] = []
        for (index, source) in upstream.enumerated() {
            let name = source.url.map { "<a href=\"\(escaped($0))\">\(escaped(source.name))</a>" } ?? escaped(source.name)
            let by = source.author.map { " by \(escaped($0))" } ?? ""
            let license = source.license.map { " (\(escaped($0)))" } ?? ""
            lines.append((index == 0 ? "Based on " : "Uses ") + name + by + license)
        }
        if !remixOf.isEmpty {
            lines.append("Remixed from " + remixOf.map { escaped($0.name) + ($0.starter != nil ? " (Lamp)" : "") }.joined(separator: ", then "))
        }
        return """
            <!doctype html><html><head><meta charset="utf-8"><style>
            body { font: 11px -apple-system, sans-serif; text-align: center; color: #777; }
            @media (prefers-color-scheme: dark) { body { color: #aaa; } a { color: #6af; } }
            p { margin: 0 0 4px; }
            </style></head><body>
            \(lines.map { "<p>\($0)</p>" }.joined(separator: "\n"))
            </body></html>
            """
    }

    // MARK: Checks

    static let maxEntries = 32
    static let maxText = 100

    /// Only entries Lamp can show as they are: one plain line for each name, an https address, a commit that's a
    /// commit, a licence that's an SPDX id or expression, a path inside the wish. A field that fails is dropped; an
    /// entry with no name is.
    var checked: Credits {
        Credits(upstream: Array(upstream.compactMap(\.checked).prefix(Self.maxEntries)),
                remixOf: Array(remixOf.compactMap(\.checked).prefix(Self.maxEntries)))
    }

    fileprivate static func text(_ value: String?) -> String? {
        guard let line = value.flatMap(AppDescription.valid), line.count <= maxText else { return nil }
        return line
    }

    static func validURL(_ value: String?) -> String? {
        guard let value = text(value), let url = URL(string: value), url.scheme == "https", let host = url.host, host.contains(".") else { return nil }
        return value
    }

    static func validCommit(_ value: String?) -> String? {
        guard let value = value?.trimmed.lowercased(), (7...64).contains(value.count), value.allSatisfy(\.isHexDigit) else { return nil }
        return value
    }

    /// An SPDX license id, `LicenseRef-…`, or an expression of them with AND, OR, WITH and brackets.
    static func validLicense(_ value: String?) -> String? {
        guard let value = text(value) else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-+:() ")
        return value.allSatisfy(allowed.contains) && value.contains(where: \.isLetter) ? value : nil
    }

    static func validPath(_ value: String?) -> String? {
        guard let value = text(value), !value.hasPrefix("/"), !value.hasPrefix("~"),
              !value.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        return value
    }
}

extension Credits.Source {
    var checked: Credits.Source? {
        guard let name = Credits.text(name) else { return nil }
        return Credits.Source(name: name, author: Credits.text(author), url: Credits.validURL(url), commit: Credits.validCommit(commit),
                              license: Credits.validLicense(license), licenseFile: Credits.validPath(licenseFile))
    }

    /// The same work: the same address, or for one with none, the same name.
    func sameWork(as other: Credits.Source) -> Bool {
        if let url, let theirs = other.url { return Self.plain(url) == Self.plain(theirs) }
        return name.lowercased() == other.name.lowercased()
    }

    private static func plain(_ url: String) -> String {
        var url = url.lowercased()
        while url.hasSuffix("/") { url.removeLast() }
        if url.hasSuffix(".git") { url.removeLast(4) }
        return url
    }
}

extension Credits.Remix {
    var checked: Credits.Remix? {
        guard let name = Credits.text(name) else { return nil }
        let starter = starter.flatMap(Credits.text).flatMap { $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } ? $0 : nil }
        let wish = wish.flatMap { UUID(uuidString: $0.trimmed)?.uuidString }
        return Credits.Remix(name: name, starter: starter, wish: wish)
    }

    func sameWish(as other: Credits.Remix) -> Bool {
        if let wish, let theirs = other.wish { return wish == theirs }
        if let starter, let theirs = other.starter { return starter == theirs }
        return wish == nil && other.wish == nil && starter == nil && other.starter == nil && name == other.name
    }
}
