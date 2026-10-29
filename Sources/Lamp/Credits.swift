import Foundation

/// Where a wish came from: `credits.json` at its root. `upstream` is other people's work in it (code, models, pictures,
/// sounds, data), each with where it's from, the commit it was taken at, its license as an SPDX id and its author, which
/// the agent writes when it brings such work in (`Agent.Rules.about`); `remixOf` is the chain of wishes it was made
/// from, oldest first, which only Lamp adds to: a starter's copy starts it (`Starters.copy`), and every share adds the
/// wish being shared (`Sharing.export`), so a remix of a remix still names each wish before it.
///
/// Credit is only ever added to. Lamp keeps what a wish arrived with (`arrived`, in its own folder) and reads it back
/// with whatever the file says now (`load`), so an entry the file lost while the wish was changed is still credited,
/// shared on and shown. `generated` lists the pictures in it that were made with AI (`make_art` adds each it paints),
/// so they're marked as made with AI wherever the wish is shown, shared or published. Lamp reads the file as data and keeps only what passes `checked`, the same for a file the agent
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
        /// Its license as an SPDX id or expression ("MIT", "Apache-2.0", "GPL-3.0-or-later", "MIT OR Apache-2.0"), or
        /// a `LicenseRef-` for terms with no id. None when it came with no license.
        var license: String?
        /// Where its license text is in the wish: "Web/LICENSE-slop-newyork".
        var licenseFile: String?
        /// Its other license and notice files, each kept as it came ("Licenses/owner/name/NOTICE"): they go wherever
        /// `licenseFile` goes, so a project under two licenses, or with a NOTICE beside its license, keeps them all.
        var noticeFiles: [String]? = nil
        /// The project the wish was made from, as against the libraries and assets it uses: the one whose updates the
        /// wish follows (`AppUpdates.route`). At most one source says so.
        var adapted: Bool? = nil

        /// Every file of its terms the wish keeps: its license, then the others.
        var termsFiles: [String] { (licenseFile.map { [$0] } ?? []) + (noticeFiles ?? []) }
    }

    /// A wish this one was made from.
    struct Remix: Codable, Equatable {
        var name: String
        /// The starter's folder, for a wish that came with Lamp.
        var starter: String?
        /// The shared wish's identity (`Sharing.identity`), for one that came in a shared file.
        var wish: String?
        /// Where the wish lives, https only: its repository on GitHub, written as it's put there (`GitHubRepo`) or
        /// opened from there (`RepoImport`), so a remix of a remix links each repository.
        var url: String?
        /// The commit of that repository this wish has: the one it was opened from (`RepoImport`), the last one merged
        /// in (`Upstream`), or the last one Put on GitHub pushed. The base the next update is merged against and the
        /// parent a contribution goes back on top of; shown nowhere.
        var commit: String?
    }

    /// A picture made with AI, by its path in the wish.
    struct Generated: Codable, Equatable {
        var file: String
    }

    var upstream: [Source] = []
    var remixOf: [Remix] = []
    var generated: [Generated] = []

    init(upstream: [Source] = [], remixOf: [Remix] = [], generated: [Generated] = []) {
        self.upstream = upstream
        self.remixOf = remixOf
        self.generated = generated
    }

    /// Written without an empty `generated`, so a wish with no AI pictures has a file the agent reads as before.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Lenient.Keys.self)
        try container.encode(upstream, forKey: .upstream)
        try container.encode(remixOf, forKey: .remixOf)
        if !generated.isEmpty { try container.encode(generated, forKey: .generated) }
    }

    var isEmpty: Bool { upstream.isEmpty && remixOf.isEmpty && generated.isEmpty }

    // MARK: Reading and writing

    /// The wish's credits: what its file says now, with anything it arrived with that the file no longer has.
    static func load(_ project: LampProject) -> Credits {
        let now = read(project.dir.appendingPathComponent(file)) ?? Credits()
        var credits = read(arrivedURL(project)).map { $0.merged(with: now) } ?? now
        // A picture made with AI is marked while it's there; one taken out (or replaced by hand) is nothing to mark.
        credits.generated.removeAll { !FileManager.default.fileExists(atPath: project.dir.appendingPathComponent($0.file).path) }
        return credits
    }

    /// Adds to the wish's credits, in its file and in Lamp's own record, which the file can't take it out of.
    static func add(_ credits: Credits, to project: LampProject) throws {
        let fileURL = project.dir.appendingPathComponent(file)
        let now = (read(fileURL) ?? Credits()).merged(with: credits)
        try now.encoded().write(to: fileURL, options: .atomic)
        let kept = (read(arrivedURL(project)) ?? Credits()).merged(with: credits)
        try FileManager.default.createDirectory(at: arrivedURL(project).deletingLastPathComponent(), withIntermediateDirectories: true)
        try kept.encoded().write(to: arrivedURL(project), options: .atomic)
    }

    static func read(_ url: URL) -> Credits? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decoded(data)
    }

    /// A credits file as Lamp takes it: what passes the checks, nothing else.
    static func decoded(_ data: Data) -> Credits? {
        (try? JSONDecoder().decode(Lenient.self, from: data)).map {
            Credits(upstream: $0.upstream ?? [], remixOf: $0.remixOf ?? [], generated: $0.generated ?? []).checked
        }
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

    static let arrivedPath = ".lamp/credits-arrived.json"
    private static func arrivedURL(_ project: LampProject) -> URL { project.dir.appendingPathComponent(arrivedPath) }

    /// Each list may be missing from a file, and an entry that doesn't decode drops only itself.
    private struct Lenient: Decodable {
        var upstream: [Source]?
        var remixOf: [Remix]?
        var generated: [Generated]?
        enum Keys: String, CodingKey { case upstream, remixOf, generated }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            upstream = try? container.decode([Maybe<Source>].self, forKey: .upstream).compactMap(\.value)
            remixOf = try? container.decode([Maybe<Remix>].self, forKey: .remixOf).compactMap(\.value)
            generated = try? container.decode([Maybe<Generated>].self, forKey: .generated).compactMap(\.value)
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
        // A source both name takes what the newer file says (a later commit, a license filled in), field by field: one it
        // leaves out keeps what was known, so a rewritten entry can't drop an author, an address or a license.
        for (index, source) in result.upstream.enumerated() {
            guard let newer = other.upstream.first(where: { $0.sameWork(as: source) }) else { continue }
            result.upstream[index] = Source(name: newer.name, author: newer.author ?? source.author, url: newer.url ?? source.url,
                                            commit: newer.commit ?? source.commit, license: newer.license ?? source.license,
                                            licenseFile: newer.licenseFile ?? source.licenseFile,
                                            noticeFiles: newer.noticeFiles ?? source.noticeFiles, adapted: newer.adapted ?? source.adapted)
        }
        for remix in other.remixOf where !result.remixOf.contains(where: { $0.sameLink(as: remix) }) { result.remixOf.append(remix) }
        // A link both have keeps the address it has, or takes the one the newer file gives; its commit is the newer
        // file's when that names one (an update merged in moves it on), else what was known.
        for (index, remix) in result.remixOf.enumerated() {
            guard let newer = other.remixOf.first(where: { $0.sameLink(as: remix) }) else { continue }
            if remix.url == nil, let url = newer.url { result.remixOf[index].url = url }
            if let commit = newer.commit { result.remixOf[index].commit = commit }
        }
        for picture in other.generated where !result.generated.contains(picture) { result.generated.append(picture) }
        return result.checked
    }

    /// The chain with one more wish at its end. The same wish shared again (an update, a second share) stays one link,
    /// named as it's called now, and only when it's already the last: a wish that came back after another took it on
    /// is a link of its own. A link that knows where the wish lives keeps that, and its commit, when the share names
    /// no place (a wish opened from its repository and shared on as a file). Put somewhere else (a wish opened from
    /// one repository and put on the person's own), the wish gets a second link, so the chain still names where it
    /// came from: that's what an update is merged from and a contribution goes back to (`origin`).
    func remixed(from remix: Remix) -> Credits {
        var result = self
        if let last = result.remixOf.last, last.sameLink(as: remix) {
            var link = remix
            if link.url == nil { link.url = last.url }
            if link.commit == nil { link.commit = last.commit }
            result.remixOf[result.remixOf.count - 1] = link
        } else {
            result.remixOf.append(remix)
        }
        return result.checked
    }

    /// Where the wish came from, when that's a repository: the last link naming one that isn't the wish's own (where
    /// Put on GitHub put it, `own`). Nil for a wish that came from a starter or a file, or lives only where it was made.
    func origin(own: String?) -> Remix? {
        remixOf.last { link in
            guard let url = link.url else { return false }
            return own.map { Source.plain(url) != Source.plain($0) } ?? true
        }
    }

    // MARK: What a person reads

    /// How AI pictures are marked: "1 picture made with AI", "3 pictures made with AI".
    static func generatedLine(_ count: Int) -> String { count == 1 ? "1 picture made with AI" : "\(count) pictures made with AI" }

    /// "Slop New York by Mr.doob", the standard credit line.
    static func line(for source: Source) -> String {
        source.author.map { "\(source.name) by \($0)" } ?? source.name
    }

    /// The work the wish is built on: the one marked as the project it was made from (`Source.adapted`), else the first
    /// with no mark either way, as credits from before the mark have it. A work marked as only used (`adapted: false`, a
    /// library or an asset) is never what the wish is built on, so a wish that only uses things has no basis.
    var basis: Source? { upstream.first { $0.adapted == true } ?? upstream.first { $0.adapted == nil } }

    /// The works with the one the wish is built on first, as they're shown.
    var basisFirst: [Source] {
        guard let basis, let index = upstream.firstIndex(of: basis) else { return upstream }
        var ordered = upstream
        ordered.remove(at: index)
        return [basis] + ordered
    }

    /// "Based on Slop New York by Mr.doob": the work the wish is built on.
    var basedOn: String? { basis.map { "Based on " + Self.line(for: $0) } }

    /// The page Credits.html in a Mac app's bundle, which the standard About window shows under the app's name: each
    /// work it's based on, linked where it lives, with its license, then the wishes it was remixed from.
    var aboutPage: String? {
        guard !isEmpty else { return nil }
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        var lines: [String] = []
        for (index, source) in basisFirst.enumerated() {
            let name = source.url.map { "<a href=\"\(escaped($0))\">\(escaped(source.name))</a>" } ?? escaped(source.name)
            let by = source.author.map { " by \(escaped($0))" } ?? ""
            let license = source.license.map { " (\(escaped($0)))" } ?? ""
            lines.append((index == 0 ? "Based on " : "Uses ") + name + by + license)
        }
        if !generated.isEmpty { lines.append(Self.generatedLine(generated.count)) }
        if !remixOf.isEmpty {
            lines.append("Remixed from " + remixOf.map { remix in
                (remix.url.map { "<a href=\"\(escaped($0))\">\(escaped(remix.name))</a>" } ?? escaped(remix.name)) + (remix.starter != nil ? " (Lamp)" : "")
            }.joined(separator: ", then "))
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
    static let maxPictures = 500
    static let maxText = 100

    /// Only entries Lamp can show as they are: one plain line for each name, an https address, a commit that's a
    /// commit, a license that's an SPDX id or expression, a path inside the wish. A field that fails is dropped; an
    /// entry with no name is.
    var checked: Credits {
        Credits(upstream: Array(upstream.compactMap(\.checked).prefix(Self.maxEntries)),
                remixOf: Array(remixOf.compactMap(\.checked).prefix(Self.maxEntries)),
                generated: Array(generated.compactMap { Self.validPath($0.file).map(Generated.init) }.prefix(Self.maxPictures)))
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

    /// A license text: LICENSE, LICENCE, COPYING or NOTICE (with anything after it, "LICENSE-slop-newyork"), plain text
    /// or Markdown, inside the wish. Only such a file goes with a share beside the kind's own files, and is put in place on
    /// the way in: never code.
    static func isLicenceFile(_ path: String) -> Bool {
        guard let path = validPath(path) else { return false }
        let name = (path as NSString).lastPathComponent
        let upper = name.uppercased()
        let ext = (name as NSString).pathExtension.lowercased()
        // An extension is a format ("LICENSE.md") or the license's own name ("COPYING.LESSER", "LICENSE.APACHE2"): short,
        // letters and digits, never a kind of file that runs.
        return ["LICENSE", "LICENCE", "COPYING", "NOTICE", "UNLICENSE"].contains(where: upper.hasPrefix)
            && ext.count <= 10 && ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
            && !["sh", "command", "app", "js", "py", "rb", "pl", "swift", "html", "htm"].contains(ext)
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
        let notices = (noticeFiles ?? []).compactMap(Credits.validPath)
        return Credits.Source(name: name, author: Credits.text(author), url: Credits.validURL(url), commit: Credits.validCommit(commit),
                              license: Credits.validLicense(license), licenseFile: Credits.validPath(licenseFile),
                              noticeFiles: notices.isEmpty ? nil : notices, adapted: adapted)
    }

    /// The same work: the same address, or for one with none, the same name.
    func sameWork(as other: Credits.Source) -> Bool {
        if let url, let theirs = other.url { return Self.plain(url) == Self.plain(theirs) }
        return name.lowercased() == other.name.lowercased()
    }

    static func plain(_ url: String) -> String {
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
        return Credits.Remix(name: name, starter: starter, wish: wish, url: Credits.validURL(url), commit: Credits.validCommit(commit))
    }

    func sameWish(as other: Credits.Remix) -> Bool {
        if let wish, let theirs = other.wish { return wish == theirs }
        if let starter, let theirs = other.starter { return starter == theirs }
        return wish == nil && other.wish == nil && starter == nil && other.starter == nil && name == other.name
    }

    /// The same wish at the same place: one link. The same wish at another place is a link of its own (a remix opened
    /// from one repository and put on another), so where it came from stays on the chain.
    func sameLink(as other: Credits.Remix) -> Bool {
        guard sameWish(as: other) else { return false }
        guard let url, let theirs = other.url else { return true }
        return Credits.Source.plain(url) == Credits.Source.plain(theirs)
    }
}
