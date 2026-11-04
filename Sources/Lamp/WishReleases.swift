import Foundation

/// What's new in each version of a wish its maker released with its link (Release Update on the Share Link card,
/// `WishLinkCards.share`): a few plain lines for the people who use it ("You can jump out of helicopters now"), written by
/// Lamp's helper model from the versions saved since the last release and changed on the card before they go, so the
/// maker never writes release notes. Kept with the wish in its own folder, newest first, with the version each release
/// was made at, which is where the next one's changes start. The link's page shows them under What's new
/// (site/lib/shared-wishes.js), and the app shows them in What's New… in its menu (`LampWhatsNew`), asked of Lamp
/// (`/app/releases`) or else read from the copy in its bundle (`bundleFile`). A copy made from the shared file keeps the
/// history it arrived with apart from its own (`receivedFile`), so its app shows what's new in the original too, while its
/// own releases start from its own versions.
enum WishReleases {
    static let file = ".lamp/releases.json"
    /// What's new in the copy this wish came from, as its shared file carried it (`fileEntry` at the file's root).
    static let receivedFile = ".lamp/releases-received.json"
    static let fileEntry = "releases.json"
    /// Beside Credits.html in an installed app, for when Lamp doesn't answer.
    static let bundleFile = "Releases.json"

    /// A release as it's shown and carried: when, and its lines; never the version it was made at, which is this Mac's.
    struct Entry: Codable, Equatable {
        var date: Date
        var lines: [String]
    }

    struct Release: Codable, Equatable {
        /// The version (commit) the release was made at.
        var version: String
        var date: Date
        /// Empty for a release that said nothing (the first share, or one whose lines were all taken off the card): it's
        /// still where the next one's changes start.
        var lines: [String]
    }

    /// Newest first.
    static func load(_ project: LampProject) -> [Release] {
        guard let data = try? Data(contentsOf: project.dir.appendingPathComponent(file)) else { return [] }
        return ((try? decoder.decode([Release].self, from: data)) ?? []).sorted { $0.date > $1.date }
    }

    static func record(_ release: Release, in project: LampProject) {
        let all = [release] + load(project)
        guard let data = try? encoder.encode(Array(all.prefix(200))) else { return }
        try? FileManager.default.createDirectory(at: project.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try? data.write(to: project.dir.appendingPathComponent(file), options: .atomic)
    }

    /// The releases that say something, as the link shows them: newest first, at most `WishLink.Limit.releases`.
    static func shown(_ releases: [Release]) -> [[String: Any]] {
        shown(releases.map { Entry(date: $0.date, lines: $0.lines) })
    }

    static func shown(_ entries: [Entry]) -> [[String: Any]] {
        entries.filter { !$0.lines.isEmpty }.prefix(WishLink.Limit.releases)
            .map { ["date": ISO8601DateFormatter().string(from: $0.date), "lines": $0.lines] }
    }

    /// What the app shows under What's New… and its shared file carries: the wish's own releases and those it arrived
    /// with, newest first.
    /// `releasing` is a release on its way out with this file, not kept yet (`WishLinkCards.share`).
    static func forApp(_ project: LampProject, releasing: Entry? = nil) -> [Entry] {
        let own = ([releasing].compactMap { $0 } + load(project).map { Entry(date: $0.date, lines: $0.lines) }).filter { !$0.lines.isEmpty }
        var seen: Set<String> = []
        return (own + received(project)).sorted { $0.date > $1.date }
            .filter { seen.insert("\($0.date.timeIntervalSince1970) \($0.lines)").inserted }
            .prefix(WishLink.Limit.releases).map { $0 }
    }

    static func received(_ project: LampProject) -> [Entry] {
        read(project.dir.appendingPathComponent(receivedFile)) ?? []
    }

    /// The history a shared file carried, checked as the site checks it: nil when the file has none (one from a Lamp
    /// from before), so an update from it leaves what arrived earlier.
    static func read(_ url: URL) -> [Entry]? {
        guard let data = try? Data(contentsOf: url), let list = try? decoder.decode([Entry].self, from: data) else { return nil }
        return list.prefix(WishLink.Limit.releases).compactMap { entry in
            let lines = lines(from: entry.lines.joined(separator: "\n"))
            return lines.isEmpty || entry.date > Date().addingTimeInterval(86_400) ? nil : Entry(date: entry.date, lines: lines)
        }
    }

    /// Keeps the history a shared file brought, in place of what an earlier one brought.
    static func arrive(_ entries: [Entry]?, in project: LampProject) {
        guard let entries, let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: project.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try? data.write(to: project.dir.appendingPathComponent(receivedFile), options: .atomic)
    }

    /// Into a shared file being made: what the app shows, for the copies made from it.
    static func carry(_ project: LampProject, releasing: Entry? = nil, into folder: URL) throws {
        let entries = forApp(project, releasing: releasing)
        guard !entries.isEmpty else { return }
        try encoder.encode(entries).write(to: folder.appendingPathComponent(fileEntry))
    }

    /// The card's lines as they go: one a line, tidied, none empty, at most `releaseLines` of at most `releaseLine`.
    static func lines(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { String($0).split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "•-*· ")) }
            .filter { !$0.isEmpty }.prefix(WishLink.Limit.releaseLines).map { WishLink.clip($0, WishLink.Limit.releaseLine) }
    }

    /// What changed since the last release, oldest first, as the versions saved since say it: their titles, or the
    /// requests that made them. Lamp's own versions (an Undo, a support update) aren't changes the maker made, and nor is
    /// a version an Undo took back. Going back to an earlier version takes back everything between, and it doesn't say
    /// how far, so only what came after it counts. A wish shared before releases were kept starts from its last few versions.
    static func changes(in project: LampProject) async -> [String] {
        let versions = await Versions.list(project)
        let since = load(project).first?.version
        var changes: [String] = []
        var undone: Set<String> = []
        for version in versions {
            if version.id == since { break }
            if since == nil, changes.count >= 8 { break }
            // Newest first, so an Undo is met before the version it took back.
            if let undid = version.undid { undone.formUnion(undid.split(separator: ",").map { String($0).trimmed }) }
            if version.message.hasPrefix("Restored to “") { break }
            guard !version.isLampNote, version.title != "Lamp update", !undone.contains(where: { !$0.isEmpty && version.id.hasPrefix($0) }) else { continue }
            changes.append(String((version.name ?? version.title ?? version.message).prefix(300)))
        }
        return changes.reversed()
    }

    static let examples = ["You can jump out of helicopters now", "Every landmark has its own model now", "Potholes come from the city's data"]

    /// The lines Lamp offers for a release, written from what changed since the last one: empty when nothing did, or
    /// when the helper can't answer (the maker can still write their own on the card).
    static func write(for project: LampProject) async -> [String] {
        let changes = await changes(in: project)
        guard !changes.isEmpty else { return [] }
        let prompt = """
        Write what's new in this version of an app called \(project.name), for the people who use it, from the changes \
        its maker asked for since the version they last released. One to five lines, fewer when fewer things changed: \
        each a short sentence in plain words about something a person using it will notice, said as it is now, in the \
        form of \(examples.map { "\"\($0)\"" }.joined(separator: ", ")) (never these lines themselves). Leave out what \
        nobody using it would notice, and never mention files, code, AI or Lamp.
        Reply as JSON: {"lines": ["…"]}

        The changes, oldest first:
        \(changes.map { "- \($0)" }.joined(separator: "\n"))
        """
        guard let (text, _) = try? await AppAI.complete(prompt: prompt, images: [], system: "", json: true, model: await AppAI.helperModel()),
              let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let raw = object["lines"] as? [String] else { return [] }
        // Without a full stop, as the page and the menu list them.
        return lines(from: raw.filter { !AppAI.parrots($0, examples: examples) }
            .map { $0.hasSuffix(".") && !$0.hasSuffix("..") ? String($0.dropLast()) : $0 }.joined(separator: "\n"))
    }

    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
