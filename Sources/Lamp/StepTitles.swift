import Foundation
import LampSidebarKit

/// A line for each fold of a finished turn's steps, saying what it did ("Listed Keychain item names and accounts,
/// without secrets"), in place of "3 steps" or "Worked for…" (`ChatItem.title(of:untitled:)`).
///
/// A stretch of steps is titled as soon as the agent says something after it (`closed(in:turn:)`), while the turn goes
/// on, so the folds have their lines when it ends rather than half a minute later; what's left when the turn ends (the
/// steps after its last message, a fold of one step) is titled then, and never waited on. Each call is one fold's,
/// so a turn that says something between many stretches makes as many small calls. The call goes to the small model
/// on the route that built the turn (`AppAI.fastModel`: Haiku through
/// Claude Code, Luna through Codex; for pi, OpenRouter's default when it builds through OpenRouter, and the model on
/// this Mac it built with when it builds there, never the cloud). It is told the
/// person's request and each fold's steps in the words the chat shows, never what a command printed or a file held,
/// and not what the agent said around a fold, which a model given it turns into claims the steps don't show (a plan
/// it announced becomes something the fold did). A step's words are what the agent set out to do, so the model is told
/// which steps failed or never ran, and that a step's words aren't its result: a fold whose command to share a page
/// failed is not "Shared the page". When there's no such route, the call fails or its answer isn't fit to show, the
/// fold keeps the words it had.
@MainActor
enum StepTitles {
    nonisolated static let maxWords = 12
    nonisolated static let maxChars = 90
    /// The example the prompt gives, which a small model hands back when it can't work a title out.
    nonisolated static let examples = ["Listed Keychain item names and accounts, without secrets"]

    /// What a fold is made of, as the model is told it.
    struct Group: Equatable {
        let id: UUID
        let steps: [String]
    }

    /// Folds whose title is being asked for now, so the call at the turn's end doesn't ask for them again.
    private static var asking: Set<UUID> = []
    /// Folds already asked about while their turn went on, whatever came of it: one whose title failed, or was
    /// turned away, isn't asked again at every later message, each a call paid for. The call at the turn's end is
    /// its one more try.
    private static var attempted: Set<UUID> = []
    /// How a title is asked for: the model, or what a test puts in its place.
    static var asker: (_ request: String?, _ groups: [Group], _ turn: TurnRoute) async -> [UUID: String]? = { request, groups, turn in
        await ask(request: request, groups: groups, turn: turn)
    }

    /// Titles what's left of the run that just ended, out of the turn's way.
    static func start(for project: LampProject, turn: TurnRoute) {
        Task { @MainActor in
            let lines = LogLine.visible(Store.shared.logs[project.id] ?? [], details: false)
            let (request, all, own) = Self.groups(in: lines)
            let groups = all.filter { !asking.contains($0.id) }
            attempted.subtract(groups.map(\.id))
            var titles = own
            if !groups.isEmpty, let made = await asker(request, groups, turn) {
                titles.merge(made) { $1 }
            }
            Store.shared.setFoldTitles(titles, in: project)
        }
    }

    /// Titles the stretches of steps the turn going on has closed by saying something after them, each in a call
    /// of its own as it closes.
    static func closed(in project: LampProject, turn: TurnRoute) {
        askEarly(LogLine.visible(Store.shared.logs[project.id] ?? [], details: false), turn: turn) { titles in
            Store.shared.setFoldTitles(titles, in: project)
        }
    }

    /// Asks once for each closed stretch not asked about yet, handing what comes back to `apply`. The calls it
    /// started, for whoever needs to wait for them.
    @discardableResult
    static func askEarly(_ lines: [LogLine], turn: TurnRoute, apply: @escaping ([UUID: String]) -> Void) -> [Task<Void, Never>] {
        let (request, all) = closed(in: lines)
        return all.filter { !asking.contains($0.id) && !attempted.contains($0.id) }.map { group in
            asking.insert(group.id)
            attempted.insert(group.id)
            return Task { @MainActor in
                let made = await asker(request, [group], turn)
                asking.remove(group.id)
                if let made, !made.isEmpty { apply(made) }
            }
        }
    }

    /// The run going on's stretches of more than one step that something said came after, untitled: those that will
    /// fold. A stretch of one step folds only as the answer's, which isn't known until the run ends. The run starts
    /// at its request, as `ChatItem.live` takes it: the statuses left after the last summary are that turn's end,
    /// titled with the rest of what the run leaves (`start`).
    nonisolated static func closed(in lines: [LogLine]) -> (request: String?, groups: [Group]) {
        let end = lines.lastIndex { $0.kind == .summary }.map { $0 + 1 } ?? lines.startIndex
        let run = lines[(lines[end...].firstIndex { $0.kind == .user } ?? end)...]
        let request = run.first { $0.kind == .user }.map { String($0.text.prefix(600)) }
        var groups: [Group] = []
        var stretch: [LogLine] = []
        for line in run {
            if ChatItem.isStep(line) {
                stretch.append(line)
                continue
            }
            if stretch.count > 1, stretch[0].foldTitle == nil { groups.append(Group(id: stretch[0].id, steps: stretch.map(words))) }
            stretch = []
        }
        return (request, groups)
    }

    /// The last finished run's folds that need a title: those of more than one step, to ask the model about, and
    /// the answer's fold of one step, whose title is that step's own words.
    nonisolated static func groups(in lines: [LogLine]) -> (request: String?, groups: [Group], own: [UUID: String]) {
        guard let end = lines.lastIndex(where: { $0.kind == .summary }) else { return (nil, [], [:]) }
        let start = lines[..<end].lastIndex { $0.kind == .summary }.map { $0 + 1 } ?? lines.startIndex
        let run = Array(lines[start..<end])
        let request = run.first { $0.kind == .user }.map { String($0.text.prefix(600)) }
        var groups: [Group] = []
        var own: [UUID: String] = [:]
        for fold in ChatItem.folds(run, summary: lines[end]).folds.compactMap({ $0 }) where fold.folds && fold.first.foldTitle == nil {
            let steps = fold.steps.map(words)
            if steps.count == 1 {
                own[fold.first.id] = steps[0]
            } else {
                groups.append(Group(id: fold.first.id, steps: steps))
            }
        }
        return (request, groups, own)
    }

    /// A step as the chat names it: the agent's words for a command, never the command itself, with whether it failed
    /// (`LogLine.withOutcome`) or was stopped before it ran, which the chat says only once the step is opened. Commands of
    /// one name are one step (`ChatItem.items`): it wasn't run when none of them ran, and some of it wasn't when one of
    /// them was stopped, its mark kept in the step's commands.
    nonisolated static func words(_ step: LogLine) -> String {
        guard let commands = ChatLook.ranCommand(in: step.text) else { return step.said ?? step.text }
        let said = step.said ?? ChatLook.unnamedStep
        if step.wasNotRun { return said + " (not run)" }
        return commands.contains(ChatLook.notRunMark) ? said + " (some not run)" : said
    }

    nonisolated static let system = """
    You write the one-line titles of folded groups of steps in a chat, where an assistant changes an app for \
    someone. A title sums up one group's steps, in the past tense, in at most 8 plain words, like "\(examples[0])".

    Each step is what the assistant set out to do, in its words, not what came of it. A step marked (failed) was \
    tried and didn't work; one marked (not run) was stopped before it ran. Say what was done, never that its aim \
    was reached: from "Share the page over the network" write "Ran the page's network share", not "Shared the \
    page". When a group's main steps failed or didn't run, the title says so ("Tried to start the server, but it \
    failed"), unless a later step did the same thing without failing.

    Make the title from the steps alone. Add no result, reason or success the steps don't state. No file, type or \
    framework names, no quotes, no emoji.

    Respond with JSON: {"titles": {"<group number>": "<title>", ...}}, one title for every group.
    """

    nonisolated static func prompt(request: String?, groups: [Group]) -> String {
        var text = request.map { "The person asked: \($0)\n\n" } ?? ""
        for (index, group) in groups.enumerated() {
            text += "Group \(index + 1)\n"
            text += "Steps:\n" + group.steps.map { "- \($0.prefix(200))" }.joined(separator: "\n") + "\n"
            text += "\n"
        }
        return text
    }

    /// The model's titles, by fold, keeping only those fit to show.
    nonisolated static func read(_ reply: String, groups: [Group]) -> [UUID: String] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any],
              let titles = object["titles"] as? [String: Any] else { return [:] }
        var out: [UUID: String] = [:]
        for (index, group) in groups.enumerated() {
            if let raw = titles[String(index + 1)] as? String, let title = normalize(raw) { out[group.id] = title }
        }
        return out
    }

    /// One line, without wrapping quotes or a closing full stop; nothing too long, no file or path, and not the
    /// prompt's own example.
    nonisolated static func normalize(_ raw: String) -> String? {
        var text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
        if text.hasSuffix(".") && !text.hasSuffix("..") { text.removeLast() }
        guard !text.isEmpty, text.split(separator: " ").count <= maxWords, text.count <= maxChars,
              !text.contains("/"), text.firstMatch(of: #/\w\.[A-Za-z]{1,6}\b/#) == nil,
              !AppAI.parrots(text, examples: examples) else { return nil }
        return text
    }

    /// What built a turn, taken as it starts: the engine and, for pi, whether through OpenRouter or a model on this
    /// Mac, and which.
    enum TurnRoute: Equatable {
        case engine(Engine)
        case openRouter
        case local(model: String)

        @MainActor static var current: TurnRoute {
            switch Builder.engine {
            case .pi: Builder.piProvider == Builder.localProvider ? .local(model: Builder.piModel) : .openRouter
            case let engine: .engine(engine)
            }
        }
    }

    /// The route the titles go along: the one that built the turn, with its small model where it has one. A turn
    /// built on this Mac is titled on this Mac, by the model that built it, or not at all: a key saved for
    /// OpenRouter is no leave to send what stayed on the Mac to the cloud.
    nonisolated static func route(for turn: TurnRoute, among routes: [AppAI.TextRoute]) -> (route: AppAI.TextRoute, model: String?)? {
        let found = routes.first { route in
            guard route.available else { return false }
            switch (turn, route.kind) {
            case (.engine(let engine), .engine(let other, _)): return engine == other
            case (.openRouter, .openRouter(let model)): return model == AppAI.defaultOpenRouterModel
            case (.local(let model), .localModel(_, let other)): return model == other
            default: return false
            }
        }
        return found.map { ($0, AppAI.fastModel(for: $0)) }
    }

    /// One call for all the groups, on the route that built the turn.
    private static func ask(request: String?, groups: [Group], turn: TurnRoute) async -> [UUID: String]? {
        guard let (route, model) = route(for: turn, among: AppAI.allTextRoutes) else { return nil }
        let prompt = prompt(request: request, groups: groups)
        guard let (reply, _) = try? await AppAI.complete(prompt: prompt, images: [], system: system, json: true,
                                                         engineModel: model, via: route) else { return nil }
        return read(reply, groups: groups)
    }
}
