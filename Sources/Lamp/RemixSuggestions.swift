import AppKit
import CryptoKit
import Foundation
import LampSidebarKit

/// Three things someone could ask Lamp to change in a wish, each a request in a few words ("Add a weekly view"),
/// written by Lamp's helper model once a change has landed and kept in the wish's own folder. They're for where there's
/// no Lamp to think of any: the chat beside an app on a Mac without Lamp (`RemixPanel`, which the sidebar extension
/// reads from its Info.plist, written as the app is installed) and a published page's remix panel. They go stale with
/// the wish's name, line or APP.md, and are written again after the next change; until Lamp has written any, the
/// panel offers three that are true of every app (`RemixOffer.fallback`).
enum RemixSuggestions {
    static let file = ".lamp/suggestions.json"
    static let count = 3
    static let maxLength = 60

    struct Kept: Codable {
        var ideas: [RemixIdea]
        /// What they were written from, so a change to the wish's words makes them stale.
        var stamp: String
    }

    /// The suggestions kept for the wish, when they're of the wish as it is now.
    static func load(_ project: LampProject) -> [RemixIdea]? {
        guard let data = try? Data(contentsOf: project.dir.appendingPathComponent(file)),
              let kept = try? JSONDecoder().decode(Kept.self, from: data), kept.stamp == stamp(project),
              let ideas = valid(kept.ideas) else { return nil }
        return ideas
    }

    /// Writes suggestions when the kept ones are missing or stale. Quiet when the helper can't answer: the panel has
    /// its own.
    static func refresh(_ project: LampProject) async {
        guard load(project) == nil, let ideas = await make(for: project) else { return }
        let kept = Kept(ideas: ideas, stamp: stamp(project))
        guard let data = try? JSONEncoder().encode(kept) else { return }
        try? data.write(to: project.dir.appendingPathComponent(file), options: .atomic)
    }

    static func stamp(_ project: LampProject) -> String {
        let words = [project.name, AppDescription.description(of: project) ?? "", appMd(project)].joined(separator: "\n")
        return SHA256.hash(data: Data(words.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func appMd(_ project: LampProject) -> String {
        String(((try? String(contentsOf: project.dir.appendingPathComponent("APP.md"), encoding: .utf8)) ?? "").prefix(2000))
    }

    static let examples = ["Add a weekly view", "Let me star the ones I love", "Make it remember the last search"]

    private static func make(for project: LampProject) async -> [RemixIdea]? {
        let about = AppDescription.description(of: project)
        let prompt = """
        Write three things the person who made this app might ask for next: each a request in their own words, at most \
        eight words, about this app in particular, no two alike, no greetings, and nothing the app already does, each \
        with the name of an SF Symbol that fits it ("calendar", "star", "bell.badge").
        Reply as JSON: {"suggestions": [{"text": "…", "symbol": "…"}, {"text": "…", "symbol": "…"}, {"text": "…", "symbol": "…"}]}
        The form of the words, never to be reused: \(examples.map { "\"\($0)\"" }.joined(separator: ", "))

        The app: \(project.name)
        What it is: \(about ?? "(no line yet)")
        Its description:
        \(appMd(project))
        """
        guard let (text, _) = try? await AppAI.complete(prompt: prompt, images: [], system: "", json: true, model: await AppAI.helperModel()) else { return nil }
        return lines(from: text)
    }

    /// The model's reply as suggestions, or nil when it isn't three usable lines.
    static func lines(from text: String) -> [RemixIdea]? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let raw = object["suggestions"] as? [[String: Any]] else { return nil }
        return valid(raw.map { RemixIdea(text: $0["text"] as? String ?? "", symbol: $0["symbol"] as? String ?? "") })
    }

    /// Three ideas, each a few words that aren't the prompt's own examples, with a symbol macOS has (else a spark).
    static func valid(_ raw: [RemixIdea]) -> [RemixIdea]? {
        var seen: Set<String> = []
        let ideas: [RemixIdea] = raw.compactMap { idea in
            let text = idea.text.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’."))
            guard !text.isEmpty, text.count <= maxLength, !AppAI.parrots(text, examples: examples), seen.insert(text.lowercased()).inserted else { return nil }
            let symbol = idea.symbol.trimmingCharacters(in: .whitespaces)
            return RemixIdea(text: text, symbol: !symbol.isEmpty && NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : "sparkles")
        }
        guard ideas.count >= count else { return nil }
        return Array(ideas.prefix(count))
    }
}
