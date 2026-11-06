import Darwin
import Foundation

/// Claude Code working on one wish from a terminal, in place of the chat beside the app ("Work in Claude Code"). Lamp
/// launches it itself (`Store.workInClaudeCode`), with the flags, hooks, tools and confinement its own Claude Code runs
/// have (`Agent.outsideClaude`), so every check of Lamp's holds; what differs is who reads the replies (the person, in
/// the terminal) and that nothing goes into the app by itself: the session asks with `apply_change` and ends a request
/// with `finish_request`. While a session holds a wish, Lamp's own agent doesn't start on it: what the person sends in
/// the chat waits, and reaches Claude Code in its tool answers and its next request.
///
/// A request is the span from the person's prompt in the terminal (Claude Code's `UserPromptSubmit` hook) to its
/// `finish_request` (or the `Stop` hook, which calls the same, and does nothing when the request is already over). It
/// holds the wish as a turn does (`Store.Turn`, with this session as its owner rather than a process of Lamp's).
@MainActor final class OutsideSession {
    /// Why a session ended. Ended any way but `finished`, an open request's unapplied edits stay in the folder, unbuilt.
    enum Ending: String {
        /// Claude Code exited (the person quit it or closed the window), or its launcher said so.
        case closed
        /// The person took the wish back in Lamp (Stop in the chat, or Take Back on the desk).
        case takenBack
        /// Lamp is quitting.
        case lampQuit
        /// The launcher never claimed its ticket.
        case neverStarted
    }

    let wish: String
    /// The session's credential: given to the launcher once, for its ticket, and kept by Lamp and the processes the
    /// launcher starts, never written to a file.
    let token = UUID().uuidString + UUID().uuidString
    /// Good once, for the launcher to claim the session within `ticketLife` of its window opening.
    private(set) var ticket: String? = UUID().uuidString + UUID().uuidString
    let opened = Date()
    static let ticketLife: TimeInterval = 120
    /// The launcher's process, as it said when it claimed the session: Claude Code runs under it.
    private(set) var launcher: pid_t?
    private(set) var ending: Ending?
    /// Claude Code's own conversation, as its hooks say: what Lamp's notes and skills briefs were told goes by it.
    var conversation: String?
    /// What the chat is sent while the session lasts (`SidebarState.inClaudeCode`), so it closes: new each time the chat
    /// is opened meanwhile (`Store.chatOpenedInSession`).
    var chatMark = UUID()
    /// One operation at a time, across the wish and its parts.
    let work = OutsideWork()
    /// Messages from the chat handed over in an answer, and when: they count as received once a later call from the
    /// session shows that answer reached it (`Store.outsideCall`).
    var handedAt: Date?

    init(wish: String) { self.wish = wish }

    /// The tools only a session has, besides every engine's (lamp-tools.json, marked `terminal`).
    static let tools = ["apply_change", "finish_request"]
    /// Lamp's tools a session isn't served, and refuses when called anyway: `ask` puts a card in a chat that's closed
    /// while the session has the wish, so the session asks with Claude Code's own AskUserQuestion, in the terminal.
    static let withheld: Set<String> = ["ask"]

    var isLive: Bool { launcher != nil && ending == nil }

    /// The ticket's one use: true and the launcher recorded, the first time, within its life.
    func claim(_ given: String, launcher pid: pid_t, now: Date = Date()) -> Bool {
        guard let ticket, ending == nil, !given.isEmpty, given == ticket, now.timeIntervalSince(opened) < Self.ticketLife, pid > 1 else { return false }
        self.ticket = nil
        launcher = pid
        return true
    }

    /// Ends the session: from here every call is refused, operations still waiting are told so without running, and
    /// the one running goes on to its end, for `work.drained()` to wait for.
    func end(_ why: Ending) {
        guard ending == nil else { return }
        ending = why
        ticket = nil
        work.close()
    }

    /// Whether the launcher still runs. A process that's gone, or that has become a zombie, isn't.
    var launcherAlive: Bool {
        guard let launcher else { return false }
        return Subprocess.alive([launcher])
    }

    /// Stops what the launcher started (Claude Code and anything it runs) and waits until it's gone, at most `within`
    /// seconds: Claude Code is interrupted first, as Ctrl-C would, so it saves its conversation, then ended outright.
    /// The launcher itself stays, to tell the person in their window that the session is over.
    func stopClaude(within seconds: Double = 8) async {
        guard let launcher else { return }
        let children = Subprocess.tree(under: launcher)
        guard !children.isEmpty else { return }
        for pid in children { kill(pid, SIGINT) }
        let deadline = Date().addingTimeInterval(seconds)
        while Subprocess.alive(children), Date() < deadline { try? await Task.sleep(for: .milliseconds(200)) }
        for pid in children where Subprocess.alive([pid]) { kill(pid, SIGTERM) }
        try? await Task.sleep(for: .milliseconds(500))
        for pid in children where Subprocess.alive([pid]) { kill(pid, SIGKILL) }
    }
}

/// A session's operations (applying a change, finishing a request, a look, a restore, a file the session changes
/// through Lamp) run one at a time, in the order asked, across the wish and all its parts: calls Claude Code sends
/// together otherwise run side by side (`Store.underTurn` lets them). Its own file edits wait too, at Lamp's hook,
/// while one runs (`idle`), so what an apply builds is what the session had written when it began.
@MainActor final class OutsideWork {
    private var busy = false
    private var waiting: [CheckedContinuation<Bool, Never>] = []
    private var idleWaiting: [CheckedContinuation<Void, Never>] = []
    private(set) var closed = false
    /// Each apply's answer, by its operation id and the code it began with (`apply`).
    private var answers: [String: [String: Any]] = [:]

    var isBusy: Bool { busy }
    /// How many operations wait their turn.
    var queued: Int { waiting.count }

    /// Runs `work` once every operation asked before it is done. Nil, without running it, when the session ended first.
    func run<T>(_ work: () async -> T) async -> T? {
        guard await take() else { return nil }
        defer { give() }
        return await work()
    }

    /// An operation the session asked for by its id, for the code as it is when its turn comes (`fingerprint`, every
    /// app of the wish): asked again with the same id while the code is unchanged (a retry after an answer that never
    /// arrived) it gets the first answer, marked `retried`, and nothing runs twice. Code that changed while it ran makes
    /// its answer `stale`: what was built isn't all that's written. A stale answer is kept under the code it began with,
    /// so the same id asked again for the new code runs again.
    func apply(id: String?, fingerprint: () -> String, _ work: () async -> [String: Any]) async -> [String: Any]? {
        await run {
            let before = fingerprint()
            let key = id.flatMap { $0.isEmpty ? nil : $0 + "|" + before }
            if let key, var kept = answers[key] {
                kept["retried"] = true
                return Self.told(kept)
            }
            var answer = await work()
            if fingerprint() != before { answer["stale"] = true }
            // Kept as the work gave it, flags and all, so what's said of them is put in front once, as it's handed out.
            if let key { answers[key] = answer }
            return Self.told(answer)
        }
    }

    /// The answer with what its flags mean put before its text: only the text reaches Claude Code.
    static func told(_ answer: [String: Any]) -> [String: Any] {
        var lines: [String] = []
        if answer["retried"] as? Bool == true {
            lines.append("retried: this is the answer to the first call with this operation_id; nothing ran again.")
        }
        if answer["stale"] as? Bool == true {
            lines.append("stale: files changed while this ran, so it didn't build everything that's written now. Call it again with a new operation_id.")
        }
        guard !lines.isEmpty else { return answer }
        var told = answer
        told["text"] = (lines + [answer["text"] as? String ?? ""]).filter { !$0.isEmpty }.joined(separator: "\n\n")
        return told
    }

    /// Returns once no operation is running (at once when none is). Lamp's hook for the session's own edits and
    /// commands waits here.
    func idle() async {
        while busy { await withCheckedContinuation { idleWaiting.append($0) } }
    }

    /// No more operations: those waiting are told so (their `run` gives nil), the one running finishes.
    func close() {
        closed = true
        let left = waiting
        waiting = []
        for waiter in left { waiter.resume(returning: false) }
    }

    /// Returns once the operation running when the session ended is done.
    func drained() async { await idle() }

    private func take() async -> Bool {
        guard !closed else { return false }
        if !busy {
            busy = true
            return true
        }
        return await withCheckedContinuation { waiting.append($0) }
    }

    private func give() {
        if !closed, !waiting.isEmpty {
            // Handed straight to the next one: `busy` stays, so nothing slips in between.
            waiting.removeFirst().resume(returning: true)
            return
        }
        busy = false
        let idle = idleWaiting
        idleWaiting = []
        for waiter in idle { waiter.resume() }
    }
}

/// One request of a session, from the prompt to Claude Code stopping: what its checkpoints (`finish_request`) have left,
/// for the next checkpoint and for the request's end.
struct OutsideRequest {
    /// How often Claude Code stopping is turned back to fix what's broken, per request, before the request ends anyway.
    static let stopBlocks = 2
    /// The version this request saved, while Lamp knows it to be the request's own.
    private(set) var savedCommit: String?
    /// The code at the last checkpoint that left nothing broken.
    private(set) var lastGood: String?
    /// The last checkpoint left the code not building, or the app crashing on launch.
    private(set) var failing = false
    private(set) var blocks = 0

    /// Whether a checkpoint amends the request's version: only one this request made, and only while it's still the
    /// latest (a restore or another commit since makes the next one a version of its own).
    func amends(head: String?) -> Bool { savedCommit != nil && head == savedCommit }

    mutating func saved(_ commit: String) { savedCommit = commit }

    mutating func checkpointed(at code: String, failed: Bool) {
        failing = failed
        if !failed { lastGood = code }
    }

    /// Whether Claude Code stopping checks the code again: it changed since the last checkpoint that went through, or that
    /// checkpoint's failure isn't known to be fixed.
    func checksAtStop(code: String) -> Bool { failing || lastGood != code }

    /// Claude Code is stopping with something broken: true to turn it back, while the request has blocks left. Counted
    /// apart from checkpoints, so a request can't be held open by checkpoints alone.
    mutating func turnsBack(failed: Bool) -> Bool {
        guard failed, blocks < Self.stopBlocks else { return false }
        blocks += 1
        return true
    }
}

extension OutsideSession {
    /// The file Terminal opens for a session: it deletes itself, then runs Lamp's launcher with the ticket in its
    /// environment, never its arguments, which Terminal shows in the window's title. The ticket is in the file for the
    /// seconds until it opens; the token it's exchanged for never is.
    static func commandFile(launcher: String, base: String, ticket: String) -> String {
        """
        #!/bin/zsh
        rm -f -- "$0"
        LAMP_TICKET=\(shellQuoted(ticket)) exec /bin/zsh \(shellQuoted(launcher)) \(shellQuoted(base))

        """
    }

    /// The exports the launcher evaluates when it claims its session, then the command it runs.
    static func setupScript(env: [String: String], folder: String, command: String) -> String {
        var lines = env.keys.sorted().map { "export \($0)=\(shellQuoted(env[$0]!))" }
        lines.append("cd \(shellQuoted(folder)) || exit 1")
        lines.append("export LAMP_RUN=\(shellQuoted(command))")
        return lines.joined(separator: "\n") + "\n"
    }

    /// A word for zsh, in single quotes.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension Subprocess {
    /// Every process under `pid`, nearest first, not `pid` itself.
    static func tree(under pid: pid_t) -> [pid_t] {
        var found: [pid_t] = []
        var level = [pid]
        while !level.isEmpty {
            level = level.flatMap { parent -> [pid_t] in
                var children = [pid_t](repeating: 0, count: 256)
                let bytes = Int32(children.count * MemoryLayout<pid_t>.size)
                let count = Int(proc_listchildpids(parent, &children, bytes))
                return count > 0 ? Array(children.prefix(count)) : []
            }
            found += level
        }
        return found
    }
}
