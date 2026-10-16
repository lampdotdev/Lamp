import Foundation

/// A note Lamp adds at the end of a request instead of to the system prompt, which Claude Code and Codex keep
/// from a conversation's start. It's told once per conversation and again only when it changes, or when the
/// engine may have lost it (it compacted the conversation; Codex doesn't say when it does, so its
/// conversations are told again every so many requests). What each engine's conversation last knew is kept
/// in a file in the app's `.lamp` folder, so most requests carry nothing.
@MainActor final class RequestNote {
    enum Telling: Equatable {
        /// The conversation knows the note as it is.
        case nothing
        /// A new conversation, or one that may have lost it: tell it whole.
        case fresh
        /// The conversation knows an older note.
        case changed
    }

    private let file: String
    private var pending: [String: Shown] = [:]

    /// `file` is relative to the app's folder, e.g. ".lamp/ai-shown.json".
    init(file: String) { self.file = file }

    /// What to tell the engine's conversation, given the note as it is now. Remembered as told only once the
    /// agent answers (`delivered`).
    func telling(_ line: String, for project: LampProject, engine: Engine, session: String?) -> Telling {
        let known = session.flatMap { session in
            shown(in: project)[engine.rawValue].flatMap { $0.session == session || $0.session.isEmpty ? $0 : nil }
        }
        let stale = engine == .codex && (known?.requests ?? 0) >= 8
        let fresh = known == nil || known?.forgot == true || stale
        pending[project.id] = Shown(engine: engine.rawValue, session: session ?? "", line: line,
                                    requests: fresh ? 1 : (known?.requests ?? 0) + 1)
        if fresh { return .fresh }
        return known?.line == line ? .nothing : .changed
    }

    /// The note the engine's conversation last received, if it has one.
    func lastTold(for project: LampProject, engine: Engine, session: String?) -> String? {
        session.flatMap { session in
            shown(in: project)[engine.rawValue].flatMap { $0.session == session || $0.session.isEmpty ? $0.line : nil }
        }
    }

    /// The agent answered, so the request and the note in it arrived.
    func delivered(to project: LampProject, session: String? = nil) {
        guard var run = pending[project.id] else { return }
        if let session { run.session = session; pending[project.id] = run }
        var all = shown(in: project)
        all[run.engine] = run
        try? JSONEncoder().encode(all).write(to: url(project), options: .atomic)
    }

    /// The engine summed up its conversation: the note may be gone from it, so the next request says it again.
    func compacted(_ project: LampProject) { pending[project.id]?.forgot = true }

    private struct Shown: Codable {
        var engine: String
        var session: String
        var line: String
        var requests: Int
        var forgot: Bool?
    }

    private func url(_ project: LampProject) -> URL { project.dir.appendingPathComponent(file) }

    private func shown(in project: LampProject) -> [String: Shown] {
        (try? Data(contentsOf: url(project))).flatMap { try? JSONDecoder().decode([String: Shown].self, from: $0) } ?? [:]
    }
}
