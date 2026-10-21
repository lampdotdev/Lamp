import Foundation
import LampSidebarKit

/// A line for each fold of a finished turn's steps, saying what it did ("Listed Keychain item names and accounts,
/// without secrets"), in place of "3 steps" or "Worked for…" (`ChatItem.title(of:untitled:)`).
///
/// Made once the turn is over, in one call for all its folds, and never waited on: the agent has finished, the
/// chat is already as it will be, and each fold takes its line when the answer comes. While the turn goes on its
/// steps are open rows anyway, so a line made earlier would show no sooner, and one call per turn costs less than one
/// per fold. The call goes to the small model on the route that built the turn (`AppAI.fastModel`: Haiku through
/// Claude Code, Luna through Codex; for pi, OpenRouter's default with the key pi builds through). It is told the
/// person's request and each fold's steps in the words the chat shows, never what a command printed or a file held,
/// and not what the agent said around a fold, which a model given it turns into claims the steps don't show (a plan
/// it announced becomes something the fold did). When there's no such route, the call fails or its answer isn't fit
/// to show, the fold keeps the words it had.
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

    /// Titles the folds of the run that just ended, out of the turn's way.
    static func start(for project: LampProject, engine: Engine) {
        Task { @MainActor in
            let lines = LogLine.visible(Store.shared.logs[project.id] ?? [], details: false)
            let (request, groups, own) = Self.groups(in: lines)
            var titles = own
            if !groups.isEmpty, let made = await ask(request: request, groups: groups, engine: engine) {
                titles.merge(made) { $1 }
            }
            Store.shared.setFoldTitles(titles, in: project)
        }
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

    /// A step as the chat names it: the agent's words for a command, never the command itself.
    nonisolated static func words(_ step: LogLine) -> String {
        if let said = step.said { return said }
        return ChatLook.ranCommand(in: step.text) == nil ? step.text : ChatLook.unnamedStep
    }

    nonisolated static let system = """
    You write the one-line titles of folded groups of steps in a chat, where an assistant changes an app for \
    someone. A title sums up one group's steps, in the past tense, in at most 8 plain words, like "\(examples[0])".

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

    /// One call for all the groups, on the route that built the turn.
    private static func ask(request: String?, groups: [Group], engine: Engine) async -> [UUID: String]? {
        let prompt = prompt(request: request, groups: groups)
        let reply: String
        do {
            switch engine {
            case .claude, .codex:
                guard let route = AppAI.allTextRoutes.first(where: {
                    if case .engine(engine, _) = $0.kind { return $0.available }
                    return false
                }) else { return nil }
                reply = try await AppAI.complete(prompt: prompt, images: [], system: system, json: true,
                                                 engineModel: AppAI.fastModel(for: route), via: route).0
            case .pi:
                guard Provider.hasKey else { return nil }
                reply = try await AppAI.complete(prompt: prompt, images: [], system: system, json: true,
                                                 model: AppAI.defaultOpenRouterModel).0
            }
        } catch {
            return nil
        }
        return read(reply, groups: groups)
    }
}
