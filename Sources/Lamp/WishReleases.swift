import Foundation

/// What's new in each version of a wish its maker released with its link (Release Update on the Share Link card,
/// `WishLinkCards.share`): a few plain lines for the people who use it ("You can jump out of helicopters now"), written by
/// Lamp's helper model from the versions saved since the last release and changed on the card before they go, so the
/// maker never writes release notes. Kept with the wish in its own folder, newest first, with the version each release
/// was made at, which is where the next one's changes start. The link's page shows them under What's new
/// (site/lib/shared-wishes.js), and the app shows them in What's New… in its menu (`LampWhatsNew`), asked of Lamp
/// (`/app/releases`) or else read from the copy in its bundle (`bundleFile`).
enum WishReleases {
    static let file = ".lamp/releases.json"
    /// Beside Credits.html in an installed app, for when Lamp doesn't answer.
    static let bundleFile = "Releases.json"

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

    /// The releases that say something, as the link and the app show them: newest first, at most `WishLink.Limit.releases`.
    static func shown(_ releases: [Release]) -> [[String: Any]] {
        releases.filter { !$0.lines.isEmpty }.prefix(WishLink.Limit.releases)
            .map { ["date": ISO8601DateFormatter().string(from: $0.date), "lines": $0.lines] }
    }

    /// The card's lines as they go: one a line, tidied, none empty, at most `releaseLines` of at most `releaseLine`.
    static func lines(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { String($0).split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "•-*· ")) }
            .filter { !$0.isEmpty }.prefix(WishLink.Limit.releaseLines).map { WishLink.clip($0, WishLink.Limit.releaseLine) }
    }

    /// What changed since the last release, oldest first, as the versions saved since say it: their titles, or the
    /// requests that made them. Lamp's own versions (an Undo, a support update) aren't changes the maker made. A wish
    /// shared before releases were kept starts from its last few versions.
    static func changes(in project: LampProject) async -> [String] {
        let versions = await Versions.list(project)
        let since = load(project).first?.version
        var changes: [String] = []
        for version in versions {
            if version.id == since { break }
            if since == nil, changes.count >= 8 { break }
            guard !version.isLampNote, version.title != "Lamp update" else { continue }
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
