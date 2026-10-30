import Foundation

/// How big an engine's conversation for an app may grow, and what Lamp does when it grows too big. Each engine sends
/// its whole conversation with every request, pictures included, so one wish worked on for days can grow past what the
/// provider takes in one request (Anthropic's is about 32 MB) long before its context window is full: with a window of a
/// million tokens an engine waits that long to compact, and every picture is sent again each time. So every engine is
/// told to compact at `compactAt` tokens, the older pictures are taken out of what is sent (`keepPicturesFew`), and a
/// conversation that still can't be sent is set aside, never deleted, for a fresh one (`setAside`).
enum Conversation {
    /// Where each engine compacts: well under every model's window, so a long-lived wish stays about 150–250k tokens.
    /// Lamp Dev takes `LAMP_COMPACT_TOKENS` from its environment, to watch a compaction without a day's requests.
    static let compactAt: Int = {
        if Edition.isDev, let tokens = ProcessInfo.processInfo.environment["LAMP_COMPACT_TOKENS"].flatMap(Int.init), tokens > 0 {
            return tokens
        }
        return 200_000
    }()

    /// The pictures kept in what an engine is sent, newest first, and how many there may be before the older ones are
    /// taken out: in a batch, not one at each turn, since each change to the conversation's earlier part costs its
    /// cached copy at the provider. pi's extension does the same with these numbers (`keepsPicturesFew` in lamp-tools.ts).
    static let keepPictures = 6
    static let trimAbove = 12

    /// What a picture taken out of the conversation leaves in its place, for the model.
    static let droppedPicture = "(The picture that came with this reply was taken out of the conversation to make room. "
        + "Look at the app again if you need to see it.)"

    /// The chat's line for a conversation started afresh because the last couldn't be sent.
    static func startedFresh(for name: String) -> String {
        "Started a fresh conversation for \(name): the last one had grown too large to send"
    }

    static let startedAgain = "Started again from the original"

    // MARK: The engine's own record

    /// The file an engine keeps the conversation in: Claude Code's transcript, Codex's rollout, pi's session.
    static func transcript(of engine: Engine, session: String, in project: LampProject) -> URL? {
        let fm = FileManager.default
        switch engine {
        case .pi:
            let folder = project.dir.appendingPathComponent(".lamp/pi-sessions")
            let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            return names.filter { $0.contains(session) && $0.hasSuffix(".jsonl") }.max().map { folder.appendingPathComponent($0) }
        case .claude:
            let projects = EngineInstall.configFolder(.claude).appendingPathComponent("projects")
            let folders = (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
            return folders.lazy.map { $0.appendingPathComponent(session + ".jsonl") }.first { fm.fileExists(atPath: $0.path) }
        case .codex:
            let root = EngineInstall.configFolder(.codex)
            for folder in ["sessions", "archived_sessions"] {
                let base = root.appendingPathComponent(folder)
                guard let walk = fm.enumerator(atPath: base.path) else { continue }
                for case let path as String in walk where path.hasSuffix("-\(session).jsonl") { return base.appendingPathComponent(path) }
            }
            return nil
        }
    }

    /// What a conversation holds, as it would be sent: everything after its last compaction.
    struct Size: Equatable {
        /// The context the last request took, as the engine counted it, or nil when it didn't say.
        var tokens: Int?
        var pictures = 0
        /// The pictures' bytes as sent (base64).
        var pictureBytes = 0
        /// The file itself, which holds what came before the last compaction too.
        var fileBytes = 0
        var compactions = 0

        /// Big enough that a dropped connection is more likely its size than the network.
        var isLarge: Bool { (tokens ?? 0) >= 150_000 || pictureBytes >= 8_000_000 || fileBytes >= 24_000_000 }

        var described: String {
            let mb = { (bytes: Int) in String(format: "%.1f MB", Double(bytes) / 1_000_000) }
            return "tokens=\(tokens.map(String.init) ?? "?") pictures=\(pictures) (\(mb(pictureBytes))) file=\(mb(fileBytes)) compactions=\(compactions)"
        }
    }

    /// One line of the engine's file as Lamp reads it: whether it ends a compaction, the context its request took, and
    /// where its pictures are. The pictures counted are the ones sent (Claude Code's `message`, not the copy beside it).
    private struct Line {
        var compaction = false
        var tokens: Int?
        var pictures = 0
        var pictureBytes = 0
    }

    private static func read(_ object: [String: Any], engine: Engine) -> Line {
        var line = Line()
        switch engine {
        case .claude:
            if object["type"] as? String == "system", object["subtype"] as? String == "compact_boundary" { line.compaction = true }
            let message = object["message"] as? [String: Any]
            if object["type"] as? String == "assistant", let usage = message?["usage"] as? [String: Any] {
                line.tokens = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].reduce(0) { $0 + ((usage[$1] as? Int) ?? 0) }
            }
            if let message { count(message, into: &line) }
        case .codex:
            let payload = object["payload"] as? [String: Any]
            if object["type"] as? String == "compacted" {
                line.compaction = true
                if let payload { count(payload, into: &line) }   // what the compaction kept is what's sent
            }
            if payload?["type"] as? String == "token_count",
               let last = ((payload?["info"] as? [String: Any])?["last_token_usage"] as? [String: Any])?["input_tokens"] as? Int {
                line.tokens = last
            }
            if object["type"] as? String == "response_item", let payload { count(payload, into: &line) }
        case .pi:
            if object["type"] as? String == "compaction" { line.compaction = true }
            let message = object["message"] as? [String: Any]
            if message?["role"] as? String == "assistant", let usage = message?["usage"] as? [String: Any] {
                line.tokens = ["input", "cacheRead", "cacheWrite"].reduce(0) { $0 + ((usage[$1] as? Int) ?? 0) }
            }
            if object["type"] as? String == "message", let message { count(message, into: &line) }
        }
        return line
    }

    /// A picture in any engine's spelling: Anthropic's base64 `image` block, pi's `image` with `data`, OpenAI's
    /// `input_image` with a data URL. Its bytes, or nil for anything else.
    private static func pictureBytes(_ block: [String: Any]) -> Int? {
        switch block["type"] as? String {
        case "image":
            if let data = (block["source"] as? [String: Any])?["data"] as? String { return data.utf8.count }
            if let data = block["data"] as? String { return data.utf8.count }
            return nil
        case "input_image":
            guard let url = block["image_url"] as? String, url.hasPrefix("data:") else { return nil }
            return url.utf8.count
        default: return nil
        }
    }

    private static func count(_ value: Any, into line: inout Line) {
        if let block = value as? [String: Any] {
            if let bytes = pictureBytes(block) {
                line.pictures += 1
                line.pictureBytes += bytes
                return
            }
            for item in block.values { count(item, into: &line) }
        } else if let items = value as? [Any] {
            for item in items { count(item, into: &line) }
        }
    }

    /// The same value with every picture in it put in words, in the spelling its engine reads.
    private static func withoutPictures(_ value: Any, engine: Engine) -> Any {
        if let block = value as? [String: Any] {
            if pictureBytes(block) != nil {
                return ["type": engine == .codex ? "input_text" : "text", "text": droppedPicture]
            }
            return block.mapValues { withoutPictures($0, engine: engine) }
        }
        if let items = value as? [Any] { return items.map { withoutPictures($0, engine: engine) } }
        return value
    }

    private static func lines(of file: URL) -> [Substring]? {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
        return String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
    }

    private static func object(_ text: Substring) -> [String: Any]? {
        guard text.first == "{" else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    /// What the conversation in `file` holds as it would be sent now.
    static func measure(_ file: URL, engine: Engine) -> Size {
        var size = Size()
        size.fileBytes = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int) ?? 0
        // pi keeps a picture its extension took out in the file, with a context edit naming its entry.
        var pictures: [(id: String?, pictures: Int, bytes: Int)] = []
        var edited = Set<String>()
        for text in lines(of: file) ?? [] {
            guard let object = object(text) else { continue }
            let line = read(object, engine: engine)
            if line.compaction {
                size.compactions += 1
                pictures = []
            }
            // A message the engine made up itself (Claude Code's after an error) says it took nothing.
            if let tokens = line.tokens, tokens > 0 { size.tokens = tokens }
            if line.pictures > 0 { pictures.append((object["id"] as? String, line.pictures, line.pictureBytes)) }
            if engine == .pi, object["type"] as? String == "context_edit", let target = object["targetId"] as? String { edited.insert(target) }
        }
        for picture in pictures where !(picture.id.map(edited.contains) ?? false) {
            size.pictures += picture.pictures
            size.pictureBytes += picture.bytes
        }
        return size
    }

    /// Takes the older pictures out of Claude Code's or Codex's conversation before it's resumed, so only the newest
    /// `keepPictures` are sent again; neither engine drops them itself (pi's extension does, with pi's context edits). Only
    /// once more than `trimAbove` are there, so the conversation's cached beginning changes seldom. The rest of the file is
    /// left as it was, line for line. The number of pictures taken out.
    @discardableResult
    static func keepPicturesFew(in file: URL, engine: Engine, keep: Int = keepPictures, above: Int = trimAbove) -> Int {
        guard engine != .pi, var lines = lines(of: file) else { return 0 }
        var found: [(index: Int, pictures: Int)] = []
        for (index, text) in lines.enumerated() where text.contains("base64") {
            guard let object = object(text) else { continue }
            let pictures = read(object, engine: engine).pictures
            if pictures > 0 { found.append((index, pictures)) }
        }
        let total = found.reduce(0) { $0 + $1.pictures }
        guard total > above else { return 0 }
        // Newest first: lines are kept whole until the newest `keep` pictures are in.
        var kept = 0
        var dropped = 0
        for entry in found.reversed() {
            if kept < keep {
                kept += entry.pictures
                continue
            }
            guard let object = object(lines[entry.index]),
                  let data = try? JSONSerialization.data(withJSONObject: withoutPictures(object, engine: engine), options: [.withoutEscapingSlashes])
            else { continue }
            lines[entry.index] = Substring(String(decoding: data, as: UTF8.self))
            dropped += entry.pictures
        }
        guard dropped > 0 else { return 0 }
        // Beside it and moved over it, so a run that reads it never finds half a file.
        let text = lines.joined(separator: "\n")
        return (try? Data(text.utf8).write(to: file, options: .atomic)) != nil ? dropped : 0
    }

    // MARK: When a request can't be sent

    /// Whether a failed request is one a fresh conversation would get through: the provider refused it for its size,
    /// the context overflowed though the engine should have compacted, or the connection was cut (or the provider
    /// failed) while sending a conversation large enough that its size is the likely reason.
    static func isTooBigToSend(_ failure: String, size: Size?) -> Bool {
        let lower = failure.lowercased()
        if Agent.isRequestTooLarge(failure) || lower.contains("prompt is too long") { return true }
        let cut = ["eproto", "econnreset", "epipe", "socket hang up", "unable to connect", "connection error",
                   "connection reset", "server_error", "internal server error", "stream disconnected"]
        return cut.contains(where: lower.contains) && size?.isLarge == true
    }

    // MARK: Setting a conversation aside

    /// What one engine's conversation is kept by: Claude Code and Codex by the id Lamp keeps for them, pi by its own.
    static func pointer(of engine: Engine, in project: LampProject) -> URL {
        project.dir.appendingPathComponent(engine == .pi ? ".lamp/pi-session" : ".lamp/session-\(engine.rawValue)")
    }

    static func folder(in project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/set-aside") }

    /// A record of conversations set aside together: the engines' ids for them, and the chat when it was cleared too.
    struct Record: Codable {
        var reason: String
        var at: Date
        /// The version a Start Again from the Original made, which Undo of it brings this back for.
        var version: String?
        var chat: [LogLine]?
    }

    /// Moves the engines' conversations out of the way, so the next request starts a fresh one; the conversations
    /// themselves stay where each engine keeps them, and their ids under `.lamp/set-aside`, so they can be brought
    /// back (`bringBack`). The agent can write in `.lamp`, so these are read as `AppFile` reads and written through
    /// `AppFolder`, never through a link it left. Nil when nothing could be kept.
    @discardableResult
    static func setAside(_ engines: [Engine], of project: LampProject, reason: String, chat: [LogLine]? = nil) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let record = folder(in: project).appendingPathComponent("\(stamp)-\(reason)-\(UUID().uuidString.prefix(4))")
        guard save(Record(reason: reason, at: Date(), chat: chat), in: record, of: project) else { return nil }
        for engine in engines {
            let file = pointer(of: engine, in: project)
            guard let id = AppFile.read(file, in: project) else { continue }
            guard (try? AppFolder.write(id, to: record.appendingPathComponent(file.lastPathComponent), in: project.dir)) != nil else { continue }
            AppFolder.remove(file, in: project.dir)
            // Its next request carries the wish's notes, as its first did (`freshNote`).
            try? AppFolder.write(Data(), to: freshMark(of: engine, in: project), in: project.dir)
        }
        return record
    }

    @discardableResult
    static func save(_ record: Record, in folder: URL, of project: LampProject) -> Bool {
        guard let data = try? JSONEncoder().encode(record) else { return false }
        return (try? AppFolder.write(data, to: folder.appendingPathComponent("record.json"), in: project.dir)) != nil
    }

    static func record(in folder: URL, of project: LampProject) -> Record? {
        AppFile.read(folder.appendingPathComponent("record.json"), in: project).flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
    }

    /// The conversations a Start Again from the Original set aside when it made `version`.
    static func startedAgain(at version: String, in project: LampProject) -> URL? {
        let folders = (try? FileManager.default.contentsOfDirectory(at: folder(in: project), includingPropertiesForKeys: nil)) ?? []
        return folders.sorted { $0.lastPathComponent > $1.lastPathComponent }.first { record(in: $0, of: project)?.version == version }
    }

    /// Puts conversations set aside back as each engine's current one, setting aside whatever took their place. The chat
    /// they were set aside with, if any.
    static func bringBack(_ record: URL, in project: LampProject) -> [LogLine]? {
        let saved = self.record(in: record, of: project)
        setAside(Engine.allCases, of: project, reason: "undone")
        for engine in Engine.allCases {
            let file = pointer(of: engine, in: project)
            AppFolder.remove(freshMark(of: engine, in: project), in: project.dir)
            guard let id = AppFile.read(record.appendingPathComponent(file.lastPathComponent), in: project) else { continue }
            try? AppFolder.write(id, to: file, in: project.dir)
        }
        return saved?.chat
    }

    // MARK: What a fresh conversation is told

    private static func freshMark(of engine: Engine, in project: LampProject) -> URL {
        project.dir.appendingPathComponent(".lamp/fresh-\(engine.rawValue)")
    }

    /// Said with the first request of a conversation that took the place of one set aside: what the wish is, from its
    /// APP.md, since the conversation that knew has gone. What was said in the chat goes with it too (`CatchUp`).
    static func freshNote(for engine: Engine, in project: LampProject) -> String {
        guard FileManager.default.fileExists(atPath: freshMark(of: engine, in: project).path) else { return "" }
        let notes = AppFile.text(project.dir.appendingPathComponent("APP.md"), in: project)?.trimmed ?? ""
        let limit = 8_000
        let shown = notes.count > limit ? String(notes.prefix(limit)) + "…" : notes
        return "\n\n---\nThis is a fresh conversation about this app (from Lamp, not part of the request above): the earlier one "
            + "was set aside, so you remember nothing of it. Everything made then is in the app's files."
            + (shown.isEmpty ? "" : " Its APP.md, as it is now:\n\n" + shown)
    }

    /// The fresh conversation has had its note.
    static func told(_ engine: Engine, in project: LampProject) {
        AppFolder.remove(freshMark(of: engine, in: project), in: project.dir)
    }

    // MARK: Lamp's log

    /// One line per turn in Lamp's own log (`conversations.log` in its logs folder), so a conversation growing toward
    /// what a request can carry is seen before it fails.
    static func note(_ project: LampProject, engine: Engine, _ words: String) {
        let fm = FileManager.default
        let file = Edition.logsFolder.appendingPathComponent("conversations.log")
        try? fm.createDirectory(at: Edition.logsFolder, withIntermediateDirectories: true)
        // The newest half kept once it grows past a megabyte.
        if let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size > 1_000_000,
           let data = try? Data(contentsOf: file) {
            try? data.suffix(size / 2).write(to: file, options: .atomic)
        }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(project.dir.lastPathComponent) \(engine.rawValue) \(words)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: file)
        }
    }
}
