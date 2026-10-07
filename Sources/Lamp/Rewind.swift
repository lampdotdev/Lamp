import Foundation

/// Where an engine's conversation is to end after a request was taken back and sent again in other words
/// (`Store.sendAgain`): just before that request, as if the new words had been sent in its place. Lamp never
/// edits a conversation: each engine makes a copy of its own that stops there, and Lamp carries on from the
/// copy, so the original is still whole if the copy can't be made.
///
/// - pi: `fork` in its RPC mode, at the request's own message.
/// - Claude Code: `--resume-session-at` the last message before the request, with `--fork-session`. It has
///   no way to copy a conversation without a turn, so its cut is made by the turn that sends the new words.
/// - Codex: `thread/fork` on its app server, through the last turn before the request. (`codex exec fork`
///   copies a whole conversation and can't stop early.)
///
/// One is kept per engine (`.lamp/cut-<engine>`) from the moment the request is sent again until that engine
/// has answered from the shorter conversation, so a turn that fails first leaves it for the next.
struct Cut: Codable {
    /// When the taken-back request went to the agent. pi's messages and Codex's turns from then on are left out.
    var sent: Date?
    /// The last message Claude Code's conversation had at that moment ("" when it had none yet).
    var claudeEnd: String?
    /// What the taken-back request was told by Lamp along with its words (that the user had gone back to an
    /// earlier version, say). It leaves the conversation with the request, so the new one says it again.
    var carried: String?
    /// What the agent is told when its conversation can't be cut: it still holds the old request.
    var note: String?
    /// Turns Claude Code was asked to make the cut in that failed before it had.
    var tries = 0

    /// Requests from before Lamp noted where they were sent from can't be cut out; they get the note.
    func canCut(_ engine: Engine) -> Bool {
        switch engine {
        case .pi, .codex: sent != nil
        case .claude: claudeEnd != nil && tries < 2
        }
    }

    // MARK: Kept until the engine has had it

    private static func url(_ project: LampProject, _ engine: Engine) -> URL {
        project.dir.appendingPathComponent(".lamp/cut-\(engine.rawValue)")
    }

    static func pending(for project: LampProject, engine: Engine) -> Cut? {
        (try? Data(contentsOf: url(project, engine))).flatMap { try? JSONDecoder().decode(Cut.self, from: $0) }
    }

    /// Keeps a cut for an engine. One it hasn't made yet stays if it's the earlier of the two: the engine
    /// wasn't used since, so its conversation still runs past both.
    static func keep(_ cut: Cut, for project: LampProject, engine: Engine) {
        var cut = cut
        if let waiting = pending(for: project, engine: engine) {
            if let old = waiting.sent, let new = cut.sent, old < new {
                (cut.sent, cut.claudeEnd, cut.carried, cut.tries) = (waiting.sent, waiting.claudeEnd, waiting.carried, waiting.tries)
            }
            cut.note = cut.note ?? waiting.note
        }
        save(cut, for: project, engine: engine)
    }

    static func save(_ cut: Cut, for project: LampProject, engine: Engine) {
        try? JSONEncoder().encode(cut).write(to: url(project, engine), options: .atomic)
    }

    static func forget(for project: LampProject, engine: Engine) {
        try? FileManager.default.removeItem(at: url(project, engine))
    }

    // MARK: pi

    /// Has pi copy its conversation up to the first request sent at or after `sent`. Returns the copy's id,
    /// `session` itself when the conversation already ends before then, or nil when pi couldn't do it.
    static func pi(_ session: String, in project: LampProject, from sent: Date) async -> String? {
        guard let pi = Agent.executable else { return nil }
        var env = Agent.environment(prompt: "", session: session,
                                    sessionDir: project.dir.appendingPathComponent(".lamp/pi-sessions").path)
        env["PI_OFFLINE"] = "1"
        let arguments = ["--mode", "rpc", "--provider", env["LAMP_PROVIDER"] ?? "", "--model", env["LAMP_MODEL"] ?? "",
                         "--no-tools", "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-context-files",
                         "--no-approve", "--session-dir", env["LAMP_SESSION_DIR"] ?? "", "--session-id", session]
        return await Task.detached { () -> String? in
            guard let tool = LineTool(pi.path, arguments, cwd: project.dir, env: env) else { return nil }
            defer { tool.close() }
            func ask(_ command: [String: Any]) -> [String: Any]? {
                let id = UUID().uuidString
                tool.send(command.merging(["id": id]) { $1 })
                guard let reply = tool.reply(where: { $0["id"] as? String == id }),
                      reply["success"] as? Bool == true else { return nil }
                return reply["data"] as? [String: Any] ?? [:]
            }
            // The requests still in the conversation, oldest first, and when each was sent.
            guard let entries = ask(["type": "get_entries"])?["entries"] as? [[String: Any]],
                  let requests = ask(["type": "get_fork_messages"])?["messages"] as? [[String: Any]] else { return nil }
            var times: [String: Date] = [:]
            for entry in entries {
                if let id = entry["id"] as? String, let time = (entry["timestamp"] as? String).flatMap(Self.date) { times[id] = time }
            }
            let ids = requests.compactMap { $0["entryId"] as? String }
            guard ids.allSatisfy({ times[$0] != nil }) else { return nil }
            guard let first = ids.first(where: { times[$0]! >= sent }) else { return session }
            guard let forked = ask(["type": "fork", "entryId": first]), forked["cancelled"] as? Bool != true,
                  let copy = ask(["type": "get_state"])?["sessionId"] as? String, copy != session else { return nil }
            return copy
        }.value
    }

    private static func date(_ text: String) -> Date? {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = format.date(from: text) { return date }
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: text)
    }

    // MARK: Codex

    enum CodexCut { case unchanged, copy(String), empty }

    /// Has Codex copy a conversation through its last turn before `sent`. `.unchanged` when the conversation
    /// already ends before then, `.empty` when nothing of it is from before, nil when Codex couldn't do it.
    static func codex(_ thread: String, in project: LampProject, from sent: Date) async -> CodexCut? {
        guard let codex = ToolLocator.path(for: .codex) else { return nil }
        return await Task.detached { () -> CodexCut? in
            guard let tool = LineTool(codex, ["app-server"], cwd: project.dir, env: ["PATH": ToolLocator.userPath]) else { return nil }
            defer { tool.close() }
            var count = 0
            func ask(_ method: String, _ params: [String: Any]) -> [String: Any]? {
                count += 1
                let id = count
                tool.send(["id": id, "method": method, "params": params])
                return tool.reply(where: { $0["id"] as? Int == id })?["result"] as? [String: Any]
            }
            guard ask("initialize", ["clientInfo": ["name": "lamp", "title": "Lamp", "version": "1"]]) != nil else { return nil }
            tool.send(["method": "initialized"])
            // Newest first, a page at a time, until a turn from before the request turns up.
            var cursor: String?
            var newest = true
            repeat {
                var params: [String: Any] = ["threadId": thread, "sortDirection": "desc", "limit": 50]
                if let cursor { params["cursor"] = cursor }
                guard let page = ask("thread/turns/list", params), let turns = page["data"] as? [[String: Any]] else { return nil }
                for turn in turns {
                    guard let id = turn["id"] as? String, let before = Self.codexTurn(turn, isBefore: sent) else { return nil }
                    if before {
                        if newest { return .unchanged }
                        guard let copy = (ask("thread/fork", ["threadId": thread, "lastTurnId": id, "excludeTurns": true])?["thread"]
                                          as? [String: Any])?["id"] as? String, copy != thread else { return nil }
                        // Unlike the conversations Lamp starts, a copy made here shows in Codex's own list
                        // of recent ones, so it says whose it is.
                        _ = ask("thread/name/set", ["threadId": copy, "name": "Lamp: \(project.name)"])
                        return .copy(copy)
                    }
                    newest = false
                }
                cursor = (page["nextCursor"] as? String)?.nilIfEmpty
            } while cursor != nil
            return .empty
        }.value
    }

    /// Whether a Codex turn started before `sent`. Its id is a UUIDv7, which begins with the millisecond it
    /// was made; `startedAt` is only to the second, so a turn counts as earlier when it's a full second
    /// earlier (one that came before the request ran to its end before it, which takes longer than that).
    static func codexTurn(_ turn: [String: Any], isBefore sent: Date) -> Bool? {
        let hex = (turn["id"] as? String ?? "").replacingOccurrences(of: "-", with: "")
        if hex.count == 32, hex.dropFirst(12).first == "7", let milliseconds = UInt64(hex.prefix(12), radix: 16) {
            return Double(milliseconds) / 1000 < sent.timeIntervalSince1970
        }
        guard let started = turn["startedAt"] as? Double ?? (turn["startedAt"] as? Int).map(Double.init) else { return nil }
        return started + 1 <= sent.timeIntervalSince1970
    }
}

/// A tool that takes requests on its input and answers each with a line of JSON on its output: pi's RPC
/// mode, Codex's app server. Used off the main thread; `reply` waits.
final class LineTool: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let lock = NSLock()
    private var buffer = Data()

    init?(_ tool: String, _ arguments: [String], cwd: URL, env: [String: String]) {
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { self?.lock.withLock { self?.buffer.append(chunk) } }
        }
        do { try process.run() } catch { return nil }
    }

    func send(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    /// The next line that is a JSON object matching `wanted`; other lines (notices, events) are passed over.
    /// Nil when it doesn't come in time or the tool has gone.
    func reply(where wanted: ([String: Any]) -> Bool, timeout: TimeInterval = 30) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            while let line = nextLine() {
                if let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], wanted(object) { return object }
            }
            guard process.isRunning, Date() < deadline else { return nil }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    private func nextLine() -> Data? {
        lock.withLock {
            guard let end = buffer.firstIndex(of: 0x0A) else { return nil }
            let line = buffer[buffer.startIndex..<end]
            buffer.removeSubrange(buffer.startIndex...end)
            return Data(line)
        }
    }

    func close() {
        try? input.fileHandleForWriting.close()
        Subprocess.terminateTree(process)
    }
}
