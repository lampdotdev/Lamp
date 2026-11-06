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
    /// One operation at a time, across the wish and its parts.
    let work = OutsideWork()
    /// Messages from the chat handed over in an answer, and when: they count as received once a later call from the
    /// session shows that answer reached it (`Store.outsideCall`).
    var handedAt: Date?

    init(wish: String) { self.wish = wish }

    /// The tools only a session has, besides every engine's (lamp-tools.json, marked `terminal`).
    static let tools = ["apply_change", "finish_request", "wait_for_answer"]

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
                return kept
            }
            var answer = await work()
            if fingerprint() != before { answer["stale"] = true }
            if let key { answers[key] = answer }
            return answer
        }
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
