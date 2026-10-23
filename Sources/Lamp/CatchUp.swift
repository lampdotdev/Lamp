import Foundation

/// What was said in an app's chat that the engine's conversation never saw. Each engine keeps a conversation of its
/// own for an app (`Store.sessionFile`, pi's session), so when the person switches engines in Settings the one they
/// switch to resumes its own older conversation, or starts a new one, and knows nothing of what was asked and said
/// with the other: it would go looking through the code to guess. Engines can't take each other's conversations, so
/// the messages it missed go with the request, in plain words: what the person asked, what the agent said and
/// asked back. Never the steps, commands or tool output: the files those changed are already in the app's folder.
enum CatchUp {
    /// The most of the chat that goes with a request, newest first, and the most of any one message.
    static let budget = 12_000
    static let messageLimit = 2_000

    /// The note for the engine's conversation, given the chat and the turn's requests (`turn`).
    static func note(for project: LampProject, engine: Engine, session: String?, chat: [LogLine], turn requests: [UUID],
                     sendsRequest: Bool) -> String {
        note(missed(in: chat, since: lastRun(of: engine, session: session, in: project),
                    before: cutoff(turn: requests, sendsRequest: sendsRequest)))
    }

    /// Where the missed messages stop: at the turn's request when the run sends it, which then goes as itself. A
    /// repair Lamp asks for later in the turn (a build's errors, a crash) sends only its own words, so an engine
    /// switched to before it is told the whole turn so far, the request and what was said since included; left out
    /// then, they would be behind its conversation's last run by the next turn, and never told.
    static func cutoff(turn requests: [UUID], sendsRequest: Bool) -> UUID? {
        sendsRequest ? requests.first : nil
    }

    /// When the engine's conversation last ran for this app, or nil for one that is only now beginning, which has
    /// seen nothing. Claude Code and Codex name their conversation as each run starts, and Lamp writes the name to
    /// its file then (`Store.runAgent`); pi writes its conversation's file as it goes. `.distantFuture` when it
    /// can't be told, so nothing is sent rather than what the conversation already has.
    static func lastRun(of engine: Engine, session: String?, in project: LampProject) -> Date? {
        guard let session else { return nil }
        let fm = FileManager.default
        let file: URL
        if engine == .pi {
            let folder = project.dir.appendingPathComponent(".lamp/pi-sessions")
            let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            // pi names the file after the time it began and the conversation (`2026-10-19T14-32-58-541Z_<id>.jsonl`);
            // with none, pi has never answered in this conversation.
            guard let name = names.filter({ $0.contains(session) }).max() else { return nil }
            file = folder.appendingPathComponent(name)
        } else {
            file = project.dir.appendingPathComponent(".lamp/session-\(engine.rawValue)")
        }
        return ((try? fm.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date) ?? .distantFuture
    }

    /// The chat's messages from the first request sent after the conversation last ran (`since`; nil for all of
    /// them) up to the turn's own request. A request the agent took while it worked (`midTurn`) belongs to the run
    /// it was handed to, so it doesn't mark where the unseen part begins. Lines from before Lamp noted when it
    /// logged them can't be placed, and count as seen.
    static func missed(in chat: [LogLine], since lastRun: Date?, before request: UUID?) -> [LogLine] {
        let end = request.flatMap { id in chat.firstIndex { $0.id == id } } ?? chat.endIndex
        let start: Int
        if let lastRun {
            guard let first = chat.firstIndex(where: { $0.kind == .user && $0.midTurn != true && ($0.at ?? .distantPast) > lastRun })
            else { return [] }
            start = first
        } else {
            start = chat.startIndex
        }
        guard start < end else { return [] }
        return chat[start..<end].filter { line in
            switch line.kind {
            case .user: line.byLamp != true
            case .agent, .ask: true
            default: false
            }
        }.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The messages as they go at the end of the request, the newest kept when there are more than fit.
    static func note(_ lines: [LogLine]) -> String {
        var kept: [String] = []
        var size = 0
        for line in lines.reversed() {
            var text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count > messageLimit { text = String(text.prefix(messageLimit)) + "…" }
            let who = line.kind == .user ? "The person" : line.kind == .ask ? "The agent asked" : "The agent"
            let entry = "\(who): \(text)"
            guard size + entry.count <= budget else { break }
            kept.append(entry)
            size += entry.count
        }
        guard !kept.isEmpty else { return "" }
        let left = kept.count < lines.count ? "(Older messages are left out.)\n\n" : ""
        return "\n\n---\nEarlier in this chat (from Lamp, not part of the request above): the person went on with it outside "
            + "this conversation, with another of Lamp's agents or in a conversation that has ended, so you haven't seen "
            + "what was said there. Any changes made then are already in the app's files. Oldest first:\n\n"
            + left + kept.reversed().joined(separator: "\n\n")
    }
}
