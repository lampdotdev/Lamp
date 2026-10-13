import CryptoKit
import SwiftUI

/// What Lamp remembers between requests: two short sets of notes it keeps itself, so they outlast any one
/// engine's conversation and are the same whichever engine is building.
///
/// - About the person (their taste and habits): one file in Lamp's support folder, shared by every app.
/// - About an app (decisions made, things the person turned down): `.lamp/notes.md` in the app's folder. Not
///   APP.md, which travels with a shared copy of the app; these stay on this Mac.
///
/// The notes cost the person tokens only when they're used. Each set has a one-line summary; the agent is
/// told just that (`brief`), once per conversation and again when the notes change, and opens the notes
/// with `read_notes` when it judges a request touches them. It rewrites them with `save_notes`. The person
/// reads and changes them in Settings → Memory.
enum Memory {
    /// Whose notes: the person's, or one app's.
    enum Place: Hashable {
        case you
        case app(LampProject)

        var file: URL {
            switch self {
            case .you: Edition.supportFolder.appendingPathComponent("about-you.md")
            case .app(let project): project.dir.appendingPathComponent(".lamp/notes.md")
            }
        }

        /// How the agent names it, in its tools and in what it's told.
        var name: String { self == .you ? "you" : "app" }
        var words: String { self == .you ? "about the person" : "about this app" }
    }

    struct Notes: Equatable {
        /// A line saying what the notes cover: all the agent sees of them until it opens them.
        var summary = ""
        var text = ""

        var isEmpty: Bool { text.isEmpty }
    }

    struct Failure: Error {
        let status: Int
        let message: String
    }

    /// Each set of notes holds this many characters: a few dozen lines, cheap to open.
    static let limit = 2000
    /// The summary is what rides along with requests, so it stays a line.
    static let summaryLimit = 120

    /// On unless the person has switched it off in Settings → Memory. Off, the
    /// agent hears nothing of the notes and has no tools for them, so nothing is noted and they cost nothing;
    /// what was noted while it was on stays, for when it's switched back on.
    /// The key keeps the name it had while this was an experiment, off by default, so a choice made then
    /// still stands: only someone who never chose gets the new default.
    static let switchKey = "experimentMemory"
    static let onByDefault = true
    static var isOn: Bool { isOn(in: .standard) }
    static func isOn(in defaults: UserDefaults) -> Bool { defaults.object(forKey: switchKey) as? Bool ?? onByDefault }
    static let tools: Set<String> = ["read_notes", "save_notes"]

    /// Posted after notes are saved or cleared, so an open Settings window shows what the agent just noted.
    static let changed = Notification.Name("LampMemoryChanged")

    // MARK: Files

    /// The file is the summary on a first line of its own (`summary: …`), then the notes.
    static func read(_ place: Place) -> Notes {
        guard let content = try? String(contentsOf: place.file, encoding: .utf8) else { return Notes() }
        var lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var notes = Notes()
        if let first = lines.first, first.hasPrefix("summary: ") {
            notes.summary = String(first.dropFirst(9)).trimmed
            lines.removeFirst()
        }
        notes.text = String(lines.joined(separator: "\n").trimmed.prefix(limit))
        if notes.summary.isEmpty { notes.summary = summary(from: notes.text) }
        return notes
    }

    /// Saves notes and returns them as saved; notes with no text remove the file.
    @discardableResult
    static func save(_ notes: Notes, in place: Place) throws -> Notes {
        var notes = notes
        notes.text = notes.text.replacingOccurrences(of: "\r\n", with: "\n").trimmed
        notes.summary = notes.summary.components(separatedBy: .newlines).joined(separator: " ").trimmed
        guard notes.text.count <= limit else {
            throw Failure(status: 400, message: "That's \(notes.text.count) characters, and these notes hold \(limit). Merge lines or drop the least useful, then send them again.")
        }
        guard notes.summary.count <= summaryLimit else {
            throw Failure(status: 400, message: "The summary is \(notes.summary.count) characters; keep it to \(summaryLimit).")
        }
        if notes.text.isEmpty { notes.summary = "" } else if notes.summary.isEmpty { notes.summary = summary(from: notes.text) }
        let fm = FileManager.default
        do {
            if notes.text.isEmpty {
                if fm.fileExists(atPath: place.file.path) { try fm.removeItem(at: place.file) }
            } else {
                try fm.createDirectory(at: place.file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("summary: \(notes.summary)\n\n\(notes.text)\n".utf8).write(to: place.file, options: .atomic)
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: place.file.path)
            }
        } catch {
            throw Failure(status: 500, message: "The notes couldn't be saved: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: changed, object: nil)
        return notes
    }

    /// Notes written without a summary (by hand, in the file) are summed up by their first line.
    private static func summary(from text: String) -> String {
        let line = text.components(separatedBy: "\n").first?.trimmed ?? ""
        return line.count <= summaryLimit ? line : String(line.prefix(summaryLimit - 1)) + "…"
    }

    // MARK: What the agent is told

    /// What a conversation knows of one set of notes: its summary, and a mark that changes with the text.
    private static func mark(_ notes: Notes) -> String {
        notes.isEmpty ? "" : notes.summary + "\n" + SHA256.hash(data: Data(notes.text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func pointer(_ place: Place, _ notes: Notes) -> String {
        "- \(place.words): \(notes.isEmpty ? "nothing yet" : notes.summary)"
    }

    /// What goes at the end of a request to the agent: a line on what each set of notes covers, never the
    /// notes. It rides with the request, not the system prompt: Claude Code and Codex keep the system prompt a
    /// conversation began with when it's resumed, so anything that changed since would never arrive. A
    /// conversation is told once; after that a request carries nothing, unless notes were changed by someone
    /// other than the agent it goes to (another engine, another app, the person), and then only their line.
    static func brief(for project: LampProject, engine: Engine, session: String?) -> String {
        // The conversation being resumed, if Lamp has a record of what it was told. One recorded before its
        // engine named it ("") is the one being resumed now.
        let known = session.flatMap { session in
            shown(to: engine, in: project).flatMap { $0.session == session || $0.session.isEmpty ? $0 : nil }
        }
        guard isOn else {
            // Switched off, the agent has no rule and no tools for the notes. A conversation that was told of
            // them, though, still holds what it read, and Claude Code and Codex still hold the rule to follow
            // it: it is told once that they no longer apply.
            var told = known
            if told?.off == true { told = nil } else { told?.off = true }
            lock.lock()
            pending[project.id] = told
            lock.unlock()
            return told == nil ? "" : "\n\n---\nLamp's notes (not part of the request above): the person has switched them off. "
                + "Leave aside what you were told or read of them from here on, and don't try to read or save them."
        }
        let places: [Place] = [.you, .app(project)]
        let now = places.map(read)
        let marks = Dictionary(uniqueKeysWithValues: zip(places, now).map { ($0.name, mark($1)) })
        // Codex doesn't say when it compacts a conversation, as pi and Claude Code do (`compacted`), so one of
        // its conversations is told again every so many requests, in case the lines have gone from it.
        let stale = engine == .codex && (known?.requests ?? 0) >= codexRefresh
        // Told afresh: a conversation Lamp has no record of telling, one whose engine has summed up its history
        // since, and one that was last told the notes were off.
        let fresh = known == nil || known?.forgot == true || known?.off == true || stale
        lock.lock()
        pending[project.id] = Shown(engine: engine.rawValue, session: session ?? "", marks: marks,
                                    requests: fresh ? 1 : (known?.requests ?? 0) + 1)
        // A conversation that is only now beginning has read nothing, whatever an earlier one that never got
        // as far as a name of its own did. Nor can one that may have lost its history vouch for what it read.
        if session == nil {
            seen = seen.filter { !$0.key.hasPrefix("\(project.id)/\(engine.rawValue)//") }
        } else if stale {
            unsee("\(project.id)/\(engine.rawValue)/\(session ?? "")/")
        }
        lock.unlock()
        guard !fresh, let shown = known else {
            return "\n\n---\nLamp's notes (not part of the request above; `read_notes` opens them when the request touches what they cover):\n"
                + zip(places, now).map { pointer($0, $1) }.joined(separator: "\n")
        }
        let news = zip(places, now).filter { shown.marks[$0.0.name] != marks[$0.0.name] }
        guard !news.isEmpty else { return "" }
        return "\n\n---\nLamp's notes have changed since you last saw them (not part of the request above; `read_notes` opens them):\n"
            // Cleared notes may still be in the conversation from an earlier read: say they no longer hold.
            + news.map { $1.isEmpty ? "- \($0.words): cleared by the person; what you read of them no longer holds" : pointer($0, $1) }
                .joined(separator: "\n")
    }

    /// The engine has compacted the conversation it is running for this app: what it was told about the
    /// notes, and what it read of them, may not have survived. The next request tells it again, and a save
    /// needs a fresh read.
    static func compacted(_ project: LampProject) {
        lock.lock()
        if let run = pending[project.id] {
            pending[project.id]?.forgot = true
            unsee("\(project.id)/\(run.engine)/\(run.session)/")
        }
        lock.unlock()
    }

    /// The notes as one engine's conversation about an app last knew them, kept in `.lamp/notes-shown.json`.
    private struct Shown: Codable {
        var engine: String
        var session: String
        var marks: [String: String]
        /// The engine compacted the conversation after it was told.
        var forgot: Bool?
        /// The conversation's last word on the notes was that they are switched off.
        var off: Bool?
        /// Requests since the conversation was last told what the notes cover.
        var requests: Int?
    }

    /// How many requests a Codex conversation goes before it is told again.
    private static let codexRefresh = 8

    private static let lock = NSLock()
    /// What `brief` told each app's running agent, until its request is known to have arrived.
    nonisolated(unsafe) private static var pending: [String: Shown] = [:]

    private static func shownFile(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/notes-shown.json") }

    private static func allShown(in project: LampProject) -> [String: Shown] {
        (try? Data(contentsOf: shownFile(project))).flatMap { try? JSONDecoder().decode([String: Shown].self, from: $0) } ?? [:]
    }

    private static func shown(to engine: Engine, in project: LampProject) -> Shown? { allShown(in: project)[engine.rawValue] }

    /// The agent has answered, so the request, and the lines in it, reached the conversation. `session` is
    /// the id the engine gave a conversation that began with this request.
    static func delivered(to project: LampProject, session: String? = nil) {
        lock.lock()
        if let session, let run = pending[project.id], run.session != session {
            // What the conversation read before its engine named it is still what it has read.
            let unnamed = "\(project.id)/\(run.engine)/\(run.session)/"
            for (key, notes) in seen where key.hasPrefix(unnamed) {
                seen["\(project.id)/\(run.engine)/\(session)/" + key.dropFirst(unnamed.count)] = notes
                seen[key] = nil
            }
            for key in reread where key.hasPrefix(unnamed) {
                reread.insert("\(project.id)/\(run.engine)/\(session)/" + key.dropFirst(unnamed.count))
                reread.remove(key)
            }
            pending[project.id]?.session = session
        }
        let shown = pending[project.id]
        lock.unlock()
        guard let shown else { return }
        var all = allShown(in: project)
        all[shown.engine] = shown
        try? JSONEncoder().encode(all).write(to: shownFile(project), options: .atomic)
    }

    // MARK: The agent's tools

    /// The notes as each conversation last read or wrote them: what tells `save_notes` that it would be
    /// writing over something the agent hasn't seen. Kept per conversation, not per app: what pi read or
    /// wrote says nothing about what a Claude Code conversation on the same app has in front of it.
    nonisolated(unsafe) private static var seen: [String: Notes] = [:]

    /// Conversations' sets of notes that have to be read before they can be saved, whatever is there now:
    /// the conversation read them once and may have lost that. Without this, notes the person cleared in the
    /// meantime would look like notes that were never there, which a conversation may save without reading.
    nonisolated(unsafe) private static var reread: Set<String> = []

    /// Call with `lock` held. Drops what a conversation (a key prefix) has read, and has it read again before saving.
    private static func unsee(_ conversation: String) {
        seen = seen.filter { !$0.key.hasPrefix(conversation) }
        for place in ["you", "app"] { reread.insert(conversation + place) }
    }

    /// Call with `lock` held. The conversation is the one `brief` last started a request for.
    private static func seenKey(_ place: Place, _ project: LampProject) -> String {
        let run = pending[project.id]
        return "\(project.id)/\(run?.engine ?? "")/\(run?.session ?? "")/\(place.name)"
    }

    private static func see(_ notes: Notes, _ place: Place, _ project: LampProject, saved: Bool = false) {
        lock.lock()
        seen[seenKey(place, project)] = notes
        reread.remove(seenKey(place, project))
        // The agent's own change isn't news to its conversation next time.
        if saved, pending[project.id] != nil { pending[project.id]?.marks[place.name] = mark(notes) }
        lock.unlock()
    }

    private static func place(_ arguments: [String: Any], _ project: LampProject) -> Place? {
        switch (arguments["about"] as? String ?? "").lowercased() {
        case "you": .you
        case "app": .app(project)
        default: nil
        }
    }

    /// `read_notes` and `save_notes`, for pi's endpoint and the MCP tools alike.
    static func call(_ tool: String, _ arguments: [String: Any], for project: LampProject) -> (Int, [String: Any]) {
        guard isOn else { return (403, ["error": "The person has turned Lamp's notes off."]) }
        do {
            switch tool {
            case "read_notes":
                // Both sets unless one is asked for: they're short, and a second call costs more than the other set.
                let places = place(arguments, project).map { [$0] } ?? [.you, .app(project)]
                return (200, ["text": places.map { place in
                    let notes = read(place)
                    see(notes, place, project)
                    return "\(place.words.prefix(1).uppercased() + place.words.dropFirst()):\n\(notes.isEmpty ? "(nothing yet)" : notes.text)"
                }.joined(separator: "\n\n")])
            case "save_notes":
                guard let place = place(arguments, project) else {
                    throw Failure(status: 400, message: "Say what the notes are about: \"you\" (the person, in every app) or \"app\" (this app).")
                }
                guard let text = arguments["notes"] as? String else { throw Failure(status: 400, message: "The notes are needed, in full.") }
                let current = read(place)
                lock.lock()
                let seen = seen[seenKey(place, project)]
                let mustRead = reread.contains(seenKey(place, project))
                lock.unlock()
                // A save replaces the notes whole. Written without them as they now stand in view, it would undo
                // whatever the agent hasn't seen (a request to another app, another engine, the person's edit in
                // Settings), so it gets the notes to work from instead. That holds for notes the person has
                // cleared since: saving the old ones with a line added would bring back what they removed. Only
                // a first save, of notes that were never there to read, needs no reading.
                if seen != current, mustRead || !(seen == nil && current.isEmpty) {
                    see(current, place, project)
                    throw Failure(status: 409, message: current.isEmpty ? """
                        These notes have been cleared since you last read them: the person removed what was there. Don't \
                        put it back. If what you learned in this request should still be kept, call save_notes \
                        again with only that.
                        """ : """
                        \(seen == nil ? "You haven't read these notes yet" : "These notes have changed since you read them"). They read:

                        \(current.text)

                        Work your change into that and call save_notes again.
                        """)
                }
                // The summary is all the person sees in the list and all the agent is told: a word or two ("look")
                // says nothing to either, so the agent is asked for a line.
                let summary = (arguments["summary"] as? String ?? "").trimmed
                // Words as the system counts them for the text's language: Japanese and Chinese have no spaces.
                var words = 0
                summary.enumerateSubstrings(in: summary.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
                if !text.trimmed.isEmpty, words < 4 {
                    throw Failure(status: 400, message: """
                        The summary stands in for the notes, for the person and for you: write one plain line on what \
                        they cover, like “How my apps should look and sound, and how I write dates”, and save again.
                        """)
                }
                let saved = try save(Notes(summary: summary, text: text), in: place)
                see(saved, place, project, saved: true)
                return (200, ["text": "Saved."])
            default:
                return (404, ["error": "Unknown tool \(tool)."])
            }
        } catch let failure as Failure {
            return (failure.status, ["error": failure.message])
        } catch {
            return (500, ["error": error.localizedDescription])
        }
    }
}

/// Settings → Memory: whether Lamp keeps notes, and under that the notes it holds, about the person and about
/// each app, to open, change and clear. Only notes that hold something are listed: a row for everything Lamp
/// could have notes on was a column of "Nothing yet" for anyone with a few apps.
struct MemorySettings: View {
    @EnvironmentObject private var store: Store
    @AppStorage(Memory.switchKey) private var memory = Memory.onByDefault
    @State private var revision = 0   // bumps when notes change, so the list re-reads them
    @State private var editing: Row?

    /// One set of notes in the list. The app's id, not the app, so a row for an app that has since gone
    /// (deleted, or renamed before its first request) opens nothing and can't be saved anywhere else.
    struct Row: Identifiable, Hashable {
        let id: String   // "" for the person, otherwise an app's id
        let title: String
    }

    /// What the pane shows under the checkbox: the notes that hold something, and what could still be given some.
    struct Listing: Equatable {
        struct Saved: Identifiable, Equatable {
            let row: Row
            let summary: String
            var id: String { row.id }
        }

        var saved: [Saved] = []
        /// What Add Notes offers, so the person can still start a set Lamp hasn't.
        var empty: [Row] = []

        /// How Add Notes is shown: a menu is for choosing among several, so one place left is a button
        /// that says where the notes go.
        enum Adding: Equatable {
            case nothing
            case one(Row)
            case several([Row])
        }

        var adding: Adding {
            switch empty.count {
            case 0: .nothing
            case 1: .one(empty[0])
            default: .several(empty)
            }
        }
    }

    /// Every set of notes there could be, the person's first, split by whether it holds anything. Nil while
    /// Lamp isn't keeping notes: off, nothing reads them, so the pane doesn't either. Each set is read once.
    /// An app that has no name yet is offered nothing to note.
    static func listing(on: Bool, apps: [LampProject], read: (Row) -> Memory.Notes) -> Listing? {
        guard on else { return nil }
        var listing = Listing()
        for row in [Row(id: "", title: "About you")] + apps.map({ Row(id: $0.id, title: "About \($0.name)") }) {
            let notes = read(row)
            if !notes.isEmpty {
                listing.saved.append(.init(row: row, summary: notes.summary))
            } else if !apps.contains(where: { $0.id == row.id && $0.untitled }) {
                listing.empty.append(row)
            }
        }
        return listing
    }

    /// The button's words when one set of notes is left to start.
    static func addLabel(_ row: Row) -> String {
        row.id.isEmpty ? "Add Notes About You…" : "Add Notes \(row.title)…"
    }

    private func place(_ row: Row) -> Memory.Place? {
        row.id.isEmpty ? .you : store.projects.first { $0.id == row.id }.map(Memory.Place.app)
    }

    private func notes(_ row: Row) -> Memory.Notes { place(row).map(Memory.read) ?? Memory.Notes() }

    var body: some View {
        let _ = revision
        Form {
            Section {
                SettingsCheckboxes {
                    Toggle("Remember how I like things", isOn: $memory)
                }
            }
            // The notes depend on the checkbox: off, nothing reads them, so they aren't read or listed.
            if let listing = Self.listing(on: memory, apps: store.projects, read: notes) {
                Section {
                    if listing.saved.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nothing yet")
                            Text("Lamp takes notes as you build: how you like things, and what you decided for each app.")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(.secondary)
                    }
                    ForEach(listing.saved) { saved in
                        Button { editing = saved.row } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(saved.row.title)
                                    Text(saved.summary)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("What Lamp remembers")
                } footer: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(listing.saved.isEmpty ? "Notes stay on this Mac." : "Notes stay on this Mac. Click one to read, change or clear it.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Group {
                            switch listing.adding {
                            case .nothing: EmptyView()
                            case .one(let row): Button(Self.addLabel(row)) { editing = row }
                            case .several(let rows):
                                Menu("Add Notes") {
                                    ForEach(rows) { row in Button(row.title) { editing = row } }
                                }
                            }
                        }
                        .controlSize(.small)
                        .fixedSize()
                    }
                }
            }
        }
        .settingsPane()
        .onReceive(NotificationCenter.default.publisher(for: Memory.changed).receive(on: RunLoop.main)) { _ in revision += 1 }
        .sheet(item: $editing) { row in
            NotesSheet(title: row.title, notes: notes(row)) { changed, opened in
                guard let place = place(row) else { return .failed("This app isn't in Lamp any more.") }
                // The sheet holds its own copy. If Lamp has rewritten the notes while it was open, saving the
                // copy would undo that, so the person is told and chooses.
                let current = Memory.read(place)
                guard current == opened else { return .changed(current) }
                do {
                    try Memory.save(changed, in: place)
                    return .saved
                } catch {
                    return .failed((error as? Memory.Failure)?.message ?? error.localizedDescription)
                }
            }
        }
    }
}

/// One set of notes, to read and change. `save` is given the notes to keep and the notes as the sheet
/// last knew them on disk.
private struct NotesSheet: View {
    enum Outcome {
        case saved
        case failed(String)
        /// Lamp changed the notes while the sheet was open: nothing was saved, and these are the ones on disk.
        case changed(Memory.Notes)
    }

    let title: String
    @State var notes: Memory.Notes
    /// The notes on disk when the sheet opened, or when the person was last told they had changed.
    @State private var opened: Memory.Notes
    let save: (Memory.Notes, Memory.Notes) -> Outcome
    @Environment(\.dismiss) private var dismiss
    @State private var problem: String?
    @State private var clearing = false
    private let had: Bool

    init(title: String, notes: Memory.Notes, save: @escaping (Memory.Notes, Memory.Notes) -> Outcome) {
        self.title = title
        _notes = State(initialValue: notes)
        _opened = State(initialValue: notes)
        self.save = save
        had = !notes.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            // Its own scrolling, whatever the form behind the sheet has switched off: notes can be longer than the box.
            TextEditor(text: $notes.text)
                .font(.body)
                .scrollDisabled(false)
                .frame(height: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .accessibilityLabel("Notes")
            TextField("In short", text: $notes.summary, prompt: Text("What these notes cover, in a line: “How my apps should look”"))
                .textFieldStyle(.roundedBorder)
            Text(problem ?? "The AI is always told the short line, and opens the notes when a request needs them. \(notes.text.count.formatted()) of \(Memory.limit.formatted()) characters.")
                .font(.caption).foregroundStyle(problem == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if had { Button("Clear…", role: .destructive) { clearing = true } }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { finish(notes) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(notes.text.count > Memory.limit)
            }
        }
        .padding(20)
        .frame(width: 480)
        .confirmationDialog("Clear what Lamp remembers here?", isPresented: $clearing) {
            Button("Clear", role: .destructive) { finish(Memory.Notes()) }
        } message: {
            Text("Lamp starts these notes again from nothing. This can't be undone.")
        }
    }

    private func finish(_ notes: Memory.Notes) {
        switch save(notes, opened) {
        case .saved: dismiss()
        case .failed(let message): problem = message
        case .changed(let current):
            // What's typed here stays. Having been told, the person's next Save or Clear is their answer.
            opened = current
            problem = current.isEmpty
                ? "These notes were cleared while this was open. Save again to keep what's here, or Cancel to leave them cleared."
                : "Lamp changed these notes while this was open. Save or Clear again to go ahead anyway, or Cancel to keep Lamp's."
        }
    }
}
