import SwiftUI
import LampSidebarKit

/// A tool call as logged by the engines ("Read App.swift", "Bash: ./build.sh", "Run: ls"), split into
/// what the agent did and what it did it to.
struct ToolCall {
    enum Action { case read, write, edit, delete, run, search, list, web, plan, delegate, look, use, recall, learn, remember, art, offer, kind, connectors, ask, progress, result, wish, other }

    let name: String
    let argument: String
    let action: Action

    init(_ text: String) {
        let parts = text.split(separator: " ", maxSplits: 1)
        var name = parts.first.map(String.init) ?? text
        if name.hasSuffix(":") { name.removeLast() }
        self.name = name
        action = Self.actions[name.lowercased()] ?? .other
        var argument = parts.count > 1 ? String(parts[1]).trimmed : ""
        if action == .run {
            // Commands usually start by changing into the app's folder; that part is noise.
            argument = argument.replacingOccurrences(of: #"^cd\s+("[^"]*"|\S+)\s*&&\s*"#, with: "", options: .regularExpression)
            argument = argument.components(separatedBy: .newlines).first ?? argument
        }
        self.argument = argument
    }

    var isKnown: Bool { action != .other }

    private static let actions: [String: Action] = [
        "read": .read, "write": .write,
        "edit": .edit, "multiedit": .edit, "patch": .edit, "apply_patch": .edit, "notebookedit": .edit,
        "bash": .run, "run": .run, "shell": .run,
        "grep": .search, "glob": .search, "find": .search, "search": .search,
        "delete_file": .delete,
        "ls": .list, "list": .list,
        "webfetch": .web, "web_fetch": .web, "websearch": .web,
        "todowrite": .plan, "plan": .plan, "task": .delegate,
        "look_at_app": .look, "use_app": .use, "read_notes": .recall, "read_skill": .learn, "save_notes": .remember, "make_art": .art, "offer_setup": .offer, "make_app_for": .kind, "connectors": .connectors, "ask": .ask, "progress": .progress, "show_result": .result, "write_wish": .wish,
    ]

    var icon: String {
        switch action {
        case .read: "doc.text"
        case .write: "square.and.pencil"
        case .edit: "pencil"
        case .delete: "trash"
        case .run: "terminal"
        case .search: "magnifyingglass"
        case .list: "folder"
        case .web: "globe"
        case .plan: "checklist"
        case .delegate: "person.2"
        case .look: "eye"
        case .use: "cursorarrow.click.2"
        case .recall: "note.text"
        case .learn: "book"
        case .remember: "square.and.pencil"
        case .art: "paintbrush"
        case .offer: "sparkles"
        case .kind: "laptopcomputer.and.iphone"
        case .connectors: "link"
        case .ask: "questionmark.bubble"
        case .progress: "text.bubble"
        case .result: "checkmark.rectangle.stack"
        case .wish: "sparkles"
        case .other: "wrench.adjustable"
        }
    }

    var verb: String {
        switch action {
        case .read: "Read"
        case .write: "Wrote"
        case .edit: "Edited"
        case .delete: "Deleted"
        case .run: "Ran"
        case .search: "Searched"
        case .list: "Listed"
        case .web: name.lowercased() == "websearch" ? "Searched the web" : "Fetched"
        case .plan: "Updated the plan"
        case .delegate: "Started a subtask"
        case .look: "Looked at the app"
        case .use: "Tried the app"
        case .recall: "Read its notes"
        case .learn: "Read up"
        case .remember: "Updated its notes"
        case .art: "Painted a picture"
        case .offer: "Suggested a setup"
        case .kind: "Changed what it runs on"
        case .connectors: "Looked up a connector"
        case .ask: "Asked you"
        case .progress: "Said how it's going"
        case .result: "Summed it up"
        case .wish: "Wrote your wish"
        case .other: name
        }
    }

    /// "read 3 files", "ran 1 command": one clause of a collapsed group's summary.
    static func clause(_ action: Action, count: Int) -> String {
        func n(_ one: String, _ many: String) -> String { "\(count) \(count == 1 ? one : many)" }
        return switch action {
        case .read: "read \(n("file", "files"))"
        case .write: "wrote \(n("file", "files"))"
        case .edit: "edited \(n("file", "files"))"
        case .delete: "deleted \(n("file", "files"))"
        case .run: "ran \(n("command", "commands"))"
        case .search: "ran \(n("search", "searches"))"
        case .list: "listed \(n("folder", "folders"))"
        case .web: "fetched \(n("page", "pages"))"
        case .plan: "updated the plan"
        case .delegate: "started \(n("subtask", "subtasks"))"
        case .look: "looked at the app" + (count == 1 ? "" : " \(count) times")
        case .use: "tried the app" + (count == 1 ? "" : " \(count) times")
        case .recall: "read its notes"
        case .learn: "read up"
        case .remember: "updated its notes"
        case .art: "painted \(n("picture", "pictures"))"
        case .offer: "suggested a setup"
        case .kind: "changed what it runs on"
        case .connectors: "looked up \(n("connector", "connectors"))"
        case .ask: "asked you"
        case .progress: "said how it's going"
        case .result: "summed it up"
        case .wish: "wrote your wish"
        case .other: n("step", "steps")
        }
    }
}

extension LogLine {
    /// About how many lines of a chat are on screen to begin with, and how many more come in each time
    /// the chat is scrolled up towards the earliest of them. The chat lays out every row it shows, so this
    /// is what bounds the cost of a long one.
    static let recentCount = 60

    /// Where the chat starts showing from: the request that opens a turn, far enough back that at least
    /// `count` lines come before the latest request, or the beginning if there aren't that many. The latest
    /// turn doesn't count towards it, so the start only moves when a request is sent, never while an answer
    /// is being written under what someone is reading.
    static func recentStart(in lines: [LogLine], atLeast count: Int) -> Int {
        guard let latest = lines.lastIndex(where: { $0.kind == .user }) else { return 0 }
        var start = latest
        while start > 0, latest - start < count {
            start = lines[..<start].lastIndex { $0.kind == .user } ?? 0
        }
        return start
    }

    /// How many lines before the latest request a chat starting at `start` is showing.
    static func reach(in lines: [LogLine], from start: Int) -> Int {
        (lines.lastIndex { $0.kind == .user } ?? start) - start
    }

    /// The chat as most people read it: what they asked, what the agent says and what happened to the app. The
    /// agent's steps are left out, which is where the file names and code are; the progress line stands in for
    /// them. What it says between them shows as it's said, so the person follows the work as it goes, and is
    /// gathered with the steps once the turn is over (`ChatItem.items`). Agent Details shows everything.
    static func visible(_ lines: [LogLine], details: Bool) -> [LogLine] {
        // What a card shows isn't said again as a message: decided from the whole chat, since which card a clicked
        // message came from decides it, and left out only at the end, since a clicked answer still ends the
        // request before it for what's chosen below.
        // A request Lamp sent itself to fix a crash isn't the person's to see as theirs: the line before it says
        // what Lamp is doing.
        let hidden = Talk.cardMessages(in: lines).union(lines.filter { $0.byLamp == true }.map(\.id))
        if details { return lines.filter { !hidden.contains($0.id) } }
        // After the agent's questions its card is the answer: whatever it says on the way out ("Waiting for
        // your answers.") would sit under the card saying the same.
        var afterAsk: Set<UUID> = []
        var asked = false
        for line in lines {
            switch line.kind {
            case .agent where asked: afterAsk.insert(line.id)
            case .ask: asked = true
            case .user: asked = false
            default: break
            }
        }
        // A result card saved by an earlier Lamp isn't shown: the agent's last message says what it did. A turn's summary
        // stays, for how long it worked (`ChatItem.items`), and isn't drawn as a line of its own. A tool call is a step
        // in the words the live line said while it ran (`steps(said:)`).
        return said(lines.filter {
            !hidden.contains($0.id)
                && ($0.kind == .agent ? !afterAsk.contains($0.id)
                    : $0.kind == .summary || $0.kind == .tool || !$0.isDetail && $0.kind != .result)
        })
    }

    /// Tool calls as the steps a person reads: what the live line said while each ran ("Looking things over",
    /// "Working on the interface", `TurnProgress.activity`), never the call itself with its files. Calls in a row
    /// that said the same are one step, and a call that says nothing of its own (a progress line) is no step. A
    /// command is no step here either: its own row ("Ran: …", by the name the agent gave it) already is, and commands
    /// under one name are gathered there; the file work after it is named after it too (`Store`, the agent's latest
    /// words), so it's part of that row, not the same words again under it. Without this a turn that only read and
    /// edited files had nothing under its open line.
    private static func said(_ lines: [LogLine]) -> [LogLine] {
        var out: [LogLine] = []
        for line in lines {
            guard line.kind == .tool else {
                // A command's row is logged once it's allowed or has run, which can be after file work Lamp already
                // named after it (Claude Code's calls in one message, the command still running): that file work is
                // part of the command's row too, not the same words once more above it.
                if line.kind == .status, let said = line.said, ChatLook.ranCommand(in: line.text) != nil,
                   let last = out.last, last.kind == .status, last.said == nil, last.text == said {
                    out.removeLast()
                }
                out.append(line)
                continue
            }
            let call = ToolCall(line.text)
            guard call.action != .run else { continue }
            // The agent's own words for the step when it gave some, else what the live line said.
            let words = line.said ?? TurnProgress.activity(for: call)
            guard !words.isEmpty else { continue }
            if let last = out.last, last.kind == .status, (last.said ?? last.text) == words { continue }
            out.append(LogLine(id: line.id, kind: .status, text: words, at: line.at, foldTitle: line.foldTitle))
        }
        return out
    }
}

/// What the transcript shows: chat lines, with runs of tool calls and of status updates gathered up, and a finished
/// turn's steps folded into one line saying how long it worked.
enum ChatItem: Identifiable {
    case line(LogLine)
    case tools([LogLine])
    case statuses([LogLine])
    /// A finished turn's steps, under one line: "Worked for 2 min 3 s", opened to see them. `id` is the turn's summary.
    case work(id: UUID, title: String, steps: [LogLine])

    var id: UUID {
        switch self {
        case .line(let line): line.id
        case .tools(let lines), .statuses(let lines): lines[0].id
        case .work(let id, _, _): id
        }
    }

    var kind: LogLine.Kind {
        switch self {
        case .line(let line): line.kind
        case .tools: .tool
        case .statuses, .work: .status
        }
    }

    /// With `gather` (the chat without Agent Details), each finished run's steps (what the agent ran, the app built
    /// and opened) fold where they came (`folded`), the ones before its answer into one line above it, as ChatGPT and
    /// Codex show the work behind an answer: the answer is what's read, and the steps are a click away. Every finished run ends with its summary, so a run is what
    /// comes after the one before it up to its own: requests don't mark them, since a clicked answer to a card is left
    /// out of the chat and Lamp starts runs of its own (a build to fix). What comes after the last summary is a run
    /// still going, whose steps show as they come. Lamp's note that it reopened the app stays out, since it explains
    /// the window going away, and so does its note that it's fixing a crash nobody asked about. A summary times its
    /// run and is otherwise left out; with Agent Details it's a line of its own and nothing is gathered. A run that
    /// ended on a question still waiting for its answer isn't gathered until it's answered: the card is clickable
    /// before the run's summary arrives, and nothing above it may change height while it waits.
    static func items(_ lines: [LogLine], gather: Bool) -> [ChatItem] {
        guard gather else { return items(lines) }
        let waiting = Talk.open(in: lines)?.id
        var result: [ChatItem] = []
        var run: [LogLine] = []
        for line in lines {
            guard line.kind == .summary else { run.append(line); continue }
            result += run.contains { $0.id == waiting } ? items(run) : folded(run, summary: line)
            run = []
        }
        return result + items(run)
    }

    /// What a turn did, as against what it said: the lines that go into its one line ("Worked for…", and while it
    /// goes on the live line) rather than being shown in the chat.
    static func isStep(_ line: LogLine) -> Bool {
        (line.kind == .status && line.text != ChatLook.fixingCrash) || line.kind == .tool
    }

    /// While a turn goes on, the steps since the last thing it said aren't rows of their own: they're inside the one
    /// line at the bottom that says what it's doing (`ActivityRow`, the sidebar's `workingSteps`), which opens to show
    /// them. Steps that came before something it said (a message, a progress line, Reload) stay rows where they came,
    /// so the chat reads in the order things happened, newest at the bottom. `shown` is the chat without the live
    /// line's steps, `steps` what that line opens to. The turn still going is what comes after the last summary, from
    /// its request on: a status left after the summary before it ("Hot Shelf is ready") belongs to that turn's end.
    /// `doing` is what the line says the turn is doing now (`TurnProgress.activity`), and `looking` whether Lamp is
    /// looking at the app for the agent (`TurnProgress.looking`). The step the line is about is still going and isn't
    /// one of the steps done yet: it joins them once the agent moves on.
    static func live(_ lines: [LogLine], doing: String? = nil, looking: Bool = false) -> (shown: [LogLine], steps: [LogLine]) {
        let end = lines.lastIndex { $0.kind == .summary }.map { $0 + 1 } ?? lines.startIndex
        let start = lines[end...].firstIndex { $0.kind == .user } ?? end
        let latest = lines[start...].lastIndex { !isStep($0) }.map { $0 + 1 } ?? start
        var steps = Transcript.withoutStepInProgress(lines[latest...].filter(isStep))
        if let last = steps.last, isGoing(last, in: lines[latest...], doing: doing, looking: looking) { steps.removeLast() }
        return (Array(lines[..<latest]), steps)
    }

    /// The same split of the chat as it's shown: without the lines that aren't (a spent Reload, an offer with nothing
    /// left to offer). Every place that draws a turn going on takes both halves from here: the transcript its `shown`,
    /// the live line its `steps`. Split over different lines, a line one half drops and the other keeps would divide
    /// the turn in two places, and the steps between them would be in neither.
    @MainActor static func live(_ lines: [LogLine], dir: URL, doing: String? = nil, looking: Bool = false) -> (shown: [LogLine], steps: [LogLine]) {
        live(Transcript.withoutSpentOffers(lines, dir: dir), doing: doing, looking: looking)
    }

    /// Whether `step` is the one the turn is still on: nothing came after it but Lamp's own stages of it, and the line
    /// says its words, or Lamp is still looking at the app for the agent (the line then says the look's stages:
    /// "Building…", "Opening…", and the last step is the look, in whatever words it was given). Any other words are
    /// the next thing already, which the engines report before it's logged (a call being written, a command's name
    /// from Codex's reasoning), so the step before it is done.
    private static func isGoing(_ step: LogLine, in lines: ArraySlice<LogLine>, doing: String?, looking: Bool) -> Bool {
        guard let doing, doing != Activity.thinking, let index = lines.lastIndex(where: { $0.id == step.id }),
              lines[(index + 1)...].allSatisfy({ $0.kind == .status && $0.text.hasSuffix("…") }) else { return false }
        return doing == (step.said ?? step.text) || looking
    }

    /// A stretch of a finished run's steps, between the things said around it: what folds into one line.
    struct Fold {
        /// The steps as the fold opens to them.
        let steps: [LogLine]
        /// The stretch's first line, which carries its title (`LogLine.foldTitle`) and names it.
        let first: LogLine
        /// The stretch just before the answer, whose fold is the run's "Worked for…".
        let isAnswers: Bool
        /// How long its steps took: from the first being logged to what came after it. Nil in a chat from before
        /// lines were timed.
        let seconds: TimeInterval?
        /// Shown as a fold, not as its one step.
        var folds: Bool { isAnswers || steps.count > 1 }
    }

    /// The stretches of a finished run's steps, and the run's other lines between them; stretch i
    /// comes before others[i]. The answer's stretch is the last one with steps up to the run's last message.
    static func folds(_ run: [LogLine], summary: LogLine) -> (folds: [Fold?], others: [LogLine]) {
        var stretches: [[LogLine]] = [[]]
        var others: [LogLine] = []
        for line in run {
            if isStep(line) {
                stretches[stretches.count - 1].append(line)
            } else {
                others.append(line)
                stretches.append([])
            }
        }
        let answer = others.lastIndex { $0.kind == .agent } ?? others.count
        let last = stretches[...min(answer, stretches.count - 1)].lastIndex { !$0.isEmpty } ?? stretches.lastIndex { !$0.isEmpty }
        let folds = stretches.enumerated().map { index, stretch -> Fold? in
            guard let first = stretch.first else { return nil }
            let steps = items(stretch).flatMap { item -> [LogLine] in
                switch item {
                case .statuses(let lines), .tools(let lines): lines
                case .line(let line): [line]
                case .work(_, _, let steps): steps
                }
            }
            let after = index < others.count ? others[index] : nil
            let ended = (after ?? summary).at
            let seconds = first.at.flatMap { start in ended.map { max(0, $0.timeIntervalSince(start)) } }
            return Fold(steps: steps, first: first, isAnswers: index == last, seconds: seconds)
        }
        return (folds, others)
    }

    /// A finished run's lines, each stretch of its steps folded where it came, between the things the agent said and
    /// Lamp's lines (Reload), so the chat reads in the order things happened. The stretch just before the answer (the
    /// run's last message) is its "Worked for…", above the answer, as ChatGPT and Codex show the work behind one; any
    /// other stretch folds to how many steps it was, or is its one step, as Lamp's note after the answer that the app
    /// is ready is. A run with no answer has its last stretch for "Worked for…". Once the turn is over each fold is
    /// given a line saying what it did (`StepTitles`), shown with how long it took in place of those words. What the
    /// agent said on the way (its progress lines and messages) stays where it was, a message like any other: what the
    /// person has read doesn't change form or go when the turn ends, and only what was done goes into the folds.
    private static func folded(_ run: [LogLine], summary: LogLine) -> [ChatItem] {
        let (folds, others) = folds(run, summary: summary)
        var result: [ChatItem] = []
        for (index, fold) in folds.enumerated() {
            if let fold {
                if fold.isAnswers {
                    result.append(.work(id: summary.id, title: title(of: fold, untitled: workedFor(summary.text)), steps: fold.steps))
                } else if !fold.folds {
                    result += items(fold.steps)
                } else {
                    result.append(.work(id: fold.first.id, title: title(of: fold, untitled: "\(fold.steps.count) steps"), steps: fold.steps))
                }
            }
            if index < others.count { result += items([others[index]]) }
        }
        return result
    }

    /// A fold's line: what it did and how long that took ("Listed the shelf's entries · 12 s"), or, until that's
    /// known or when it couldn't be made, `untitled`. A fold from before lines were timed shows no time.
    static func title(of fold: Fold, untitled: String) -> String {
        guard let title = fold.first.foldTitle else { return untitled }
        return fold.seconds.map { "\(title) · \(duration($0))" } ?? title
    }

    /// "12 s", "3 min", "1 min 5 s".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(1, Int(seconds.rounded()))
        let minutes = total / 60, rest = total % 60
        switch (minutes, rest) {
        case (0, _): return "\(rest) s"
        case (_, 0): return "\(minutes) min"
        default: return "\(minutes) min \(rest) s"
        }
    }

    /// "Worked for 2 min 3 s", from a turn's summary ("Worked for 2m 3s · $0.12").
    static func workedFor(_ summary: String) -> String {
        guard let match = summary.firstMatch(of: #/Worked for (?:(\d+)m )?(\d+)s/#) else { return "Worked" }
        let minutes = match.1.flatMap { Int($0) } ?? 0, seconds = Int(match.2) ?? 0
        switch (minutes, seconds) {
        case (0, _): return "Worked for \(seconds) s"
        case (_, 0): return "Worked for \(minutes) min"
        default: return "Worked for \(minutes) min \(seconds) s"
        }
    }

    static func items(_ lines: [LogLine]) -> [ChatItem] {
        var items: [ChatItem] = []
        for line in lines {
            switch (line.kind, items.last) {
            case (.tool, .tools(let run)?): items[items.count - 1] = .tools(run + [line])
            case (.tool, _): items.append(.tools([line]))
            case (.status, .statuses(let run)?):
                // A progress step ("Building…") is superseded by whatever status follows it, and a step that says what
                // the one before it said (two looks with a build between them) is that step again.
                var kept = run.filter { !$0.text.hasSuffix("…") }
                if line.said == nil, ChatLook.ranCommand(in: line.text) == nil, let last = kept.last, last.said == nil,
                   last.text == line.text {
                    items[items.count - 1] = .statuses(kept)
                    continue
                }
                // Commands the agent gave one name to are one step: the name once, their commands under it.
                // Each command keeps its own "(not run)", whichever came first.
                if let said = line.said, let last = kept.last, last.said == said,
                   let command = ChatLook.ranCommand(in: line.text), let before = ChatLook.ranCommand(in: last.text) {
                    kept[kept.count - 1].text = "Ran: " + before + "\n" + command
                    items[items.count - 1] = .statuses(kept)
                } else {
                    items[items.count - 1] = .statuses(kept + [line])
                }
            case (.status, _): items.append(.statuses([line]))
            default: items.append(.line(line))
            }
        }
        return items
    }

    /// Space above an item: bubbles from one side close together, as Messages keeps them, the steps tucked
    /// under them, and more room between turns.
    static func gap(after previous: ChatItem?, before item: ChatItem, isFinalAnswer: Bool) -> CGFloat {
        guard let previous else { return 0 }
        // A progress line is spaced as the agent's message it looks like.
        func spaced(_ kind: LogLine.Kind) -> LogLine.Kind { kind == .progress ? .agent : kind }
        switch (spaced(previous.kind), spaced(item.kind)) {
        case (.summary, .user): return 16
        case (_, .user): return 24
        case (.user, _): return 12
        case (_, .summary): return 16
        case (.tool, .detail), (.detail, .detail): return 4
        case (.agent, .agent): return 4
        case (_, .agent): return isFinalAnswer ? 12 : 8
        case (.agent, .tool), (.agent, .status): return 6
        case (_, .tool): return 6
        default: return 10
        }
    }
}

struct Transcript: View {
    let lines: [LogLine]
    let dir: URL
    let busy: Bool
    /// The turn's progress line or build card is on screen. It's the one spinner, and the one place that
    /// says what's happening now, so nothing here repeats it.
    var progressShown = false
    /// Goes back to the version a request made, or (true) to the one before it.
    var goBack: ((LogLine, Bool) -> Void)?
    /// Takes a request back into the message box, to change it and send it again. Nil while the app is being
    /// worked on: that has to finish first.
    var sendAgain: ((LogLine) -> Void)?
    var retryPhone: ((String) -> Void)?
    /// The request just sent from the chat, which it holds at the top while the answer comes in below.
    var pinned: UUID?
    /// Read so the chat follows the choice of what draws icons: it decides whether a "Draw Icon…" line shows.
    @AppStorage("iconModel") private var iconChoice = ""
    /// With Agent Details on every step is its own line; without, a finished turn's steps are gathered up.
    @AppStorage("showDetails") private var details = false

    var body: some View {
        let _ = iconChoice
        let lines = Self.withoutSpentOffers(lines, dir: dir)
        let finalAnswers = Self.finalAnswers(in: lines, busy: busy)
        let latestRequest = lines.last { $0.kind == .user }?.id
        let openAsk = Talk.open(in: lines)?.id
        // Answers clicked on a card are shown by the card, folded where it was: not again as a message.
        let shown = lines
        // While the turn goes on, its steps since it last said something are in the one line that says what it's doing.
        let items = ChatItem.items(progressShown ? (details ? Self.withoutStepInProgress(shown) : ChatItem.live(shown, dir: dir).shown) : shown,
                                   gather: !details)
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let isLast = index == items.count - 1
            let gap = ChatItem.gap(after: index > 0 ? items[index - 1] : nil, before: item,
                                   isFinalAnswer: finalAnswers.contains(item.id))
            Group {
                switch item {
                // The agent's cards depend on what came after them, so they're outside the row that's
                // redrawn only when its own line changes.
                case .line(let line) where line.kind == .ask: AskCard(line: line, dir: dir, isOpen: line.id == openAsk)
                case .line(let line): LogRow(line: line, dir: dir, busy: busy, goBack: goBack, sendAgain: sendAgain,
                                             retryPhone: retryPhone, isLatestRequest: line.id == latestRequest).equatable()
                case .tools(let lines): ToolGroup(lines: lines, running: isLast && busy && !progressShown).equatable()
                case .statuses(let lines): StatusGroup(lines: lines, running: isLast && busy && !progressShown)
                case .work(_, let title, let steps):
                    ChatLook.Worked(title) { StepList(steps: steps) }
                }
            }
            .padding(.top, gap)
            // The gap goes off the top of the chat with whatever is above it.
            .layoutValue(key: ChatStack.Pinned.self, value: item.id == pinned ? gap : nil)
        }
    }

    /// Without the offers to draw an icon that have nothing left to offer: the icon was drawn or designed
    /// again, or icons are no longer drawn by hand. A line that stayed would say what's no longer so.
    @MainActor static func withoutSpentOffers(_ lines: [LogLine], dir: URL) -> [LogLine] {
        guard lines.contains(where: { $0.kind == .drawIcon || $0.kind == .widget || $0.kind == .iphoneSetup || $0.kind == .reload }) else { return lines }
        let project = Store.shared.projects.first { $0.dir == dir }
        return lines.filter { line in
            switch line.kind {
            case .drawIcon: project.map { Icons.awaitsDrawing(line.text, in: $0, byHand: AppAI.iconsByHand) } ?? false
            // The widget's card, likewise, while there's a widget to add.
            case .widget: project.map { WidgetCard.isShown(for: $0) } ?? false
            // The offer to set up iPhone apps, while the app is still only a Mac app.
            case .iphoneSetup: project?.platform == .mac
            // Reload, while the change it's for still waits: the last such line only, under the latest change.
            case .reload: project.map(Runtime.waitsForReload) ?? false && line.id == lines.last(where: { $0.kind == .reload })?.id
            default: true
            }
        }
    }

    /// Without the step at the end that's still going ("Building…"): the progress line is saying it.
    static func withoutStepInProgress(_ lines: [LogLine]) -> [LogLine] {
        var lines = lines
        while let last = lines.last, last.kind == .status, last.text.hasSuffix("…") { lines.removeLast() }
        return lines
    }

    /// The last agent message of each finished turn: the answer people actually read.
    static func finalAnswers(in lines: [LogLine], busy: Bool) -> Set<UUID> {
        var answers: Set<UUID> = []
        var lastAgent: LogLine?
        for line in lines {
            if line.kind == .user {
                if let lastAgent { answers.insert(lastAgent.id) }
                lastAgent = nil
            } else if line.kind == .agent {
                lastAgent = line
            }
        }
        if !busy, let lastAgent { answers.insert(lastAgent.id) }
        return answers
    }
}

/// Equatable so a row is only redrawn when its own line changes, not on every update during a turn.
struct LogRow: View, Equatable {
    let line: LogLine
    let dir: URL
    var busy = false
    var goBack: ((LogLine, Bool) -> Void)?
    var sendAgain: ((LogLine) -> Void)?
    var retryPhone: ((String) -> Void)?
    /// The latest request shows its Send Again button all the time, so there's one to find; earlier ones
    /// show it when pointed at.
    var isLatestRequest = false
    @State private var expandedDetail = false
    @State private var shownDetailHeight: CGFloat = 0
    @State private var fullDetailHeight: CGFloat = 0

    static func == (a: LogRow, b: LogRow) -> Bool {
        a.line == b.line && a.busy == b.busy && a.dir == b.dir
            && (a.retryPhone == nil) == (b.retryPhone == nil) && a.isLatestRequest == b.isLatestRequest && (a.sendAgain == nil) == (b.sendAgain == nil)
    }

    var body: some View {
        switch line.kind {
        case .user:
            let urls = (line.attachments ?? []).map { dir.appendingPathComponent(Attachments.folder).appendingPathComponent($0) }
            ChatLook.UserRow(text: line.text, busy: busy, goBack: line.version != nil ? goBack.map { goBack in { goBack(line, $0) } } : nil,
                             sendAgain: line.canSendAgain ? sendAgain.map { sendAgain in { sendAgain(line) } } : nil,
                             isLatest: isLatestRequest) {
                // What was pointed at keeps its pill, and its picture isn't shown a second time beside it.
                if let pointed = line.pointed, let url = urls.first(where: { $0.lastPathComponent == pointed.picture }) {
                    AttachmentPreview(url: url, siblings: urls) {
                        ChatLook.PointedPill(title: pointed.title, detail: pointed.detail)
                    }
                }
                ForEach(urls.filter { $0.lastPathComponent != line.pointed?.picture }, id: \.self) { url in
                    if Attachments.isImage(url) {
                        AttachmentPreview(url: url, siblings: urls) { AttachmentThumbnail(url: url, size: 72) }
                    } else {
                        AttachmentChip(url: url, siblings: urls)
                    }
                }
            }
        case .agent:
            // While a turn is going this may be a message still being written, a little longer every time.
            ChatLook.AgentText(line.text, keep: !busy)
        case .status, .tool:
            // Shown through StatusGroup and ToolGroup.
            EmptyView()
        case .progress:
            // A message like any other, while the turn goes on and once it's over.
            ChatLook.AgentText(line.text)
        case .summary:
            ChatLook.SummaryLine(line.text)
        case .error:
            ChatLook.ErrorNote(line.text) {
                if let udid = line.retryPhone, let retryPhone {
                    Button("Retry") { retryPhone(udid) }
                        .disabled(busy)
                }
            }
        case .detail:
            VStack(alignment: .leading, spacing: 6) {
                Text(line.text)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(expandedDetail ? nil : 12)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownDetailHeight = $0 }
                    // The same text with no limit, unseen, says how tall it would be in full: the button to
                    // show the rest appears only when there is a rest.
                    .background {
                        Text(line.text)
                            .font(.caption.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                            .hidden()
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullDetailHeight = $0 }
                    }
                if expandedDetail || fullDetailHeight > shownDetailHeight + 1 {
                    Button(expandedDetail ? "Show Less" : "Show Full Output") { expandedDetail.toggle() }
                        .buttonStyle(.link)
                        .pointingHand()
                        .font(.caption)
                }
            }
        case .needsKey, .offer:
            if let offer = line.setupOffer { SetupCard(offer: offer, reason: line.text, dir: dir) }
        case .noted:
            NoteCard(line: line, dir: dir)
        case .drawIcon:
            if let project = Store.shared.projects.first(where: { $0.dir == dir }) { DrawIconLine(project: project) }
        case .widget:
            WidgetCardView(dir: dir)
        case .reload:
            if let project = Store.shared.projects.first(where: { $0.dir == dir }) {
                ReloadLine.Row(project: project)
            }
        case .iphoneSetup:
            if let project = Store.shared.projects.first(where: { $0.dir == dir }) {
                IPhoneSetupLine(project: project, wanted: Platform(rawValue: line.text) ?? .iphone)
            }
        case .ask, .result:
            // Drawn by Transcript, which knows whether they're still waiting.
            EmptyView()
        }
    }

    @MainActor static func prose(_ text: String, keep: Bool = true) -> AttributedString { ChatLook.prose(text, keep: keep) }
}

/// Consecutive tool calls. A single call shows as is; several collapse into one summary line.
struct ToolGroup: View, Equatable {
    let lines: [LogLine]
    let running: Bool
    @State private var expanded = false

    static func == (a: ToolGroup, b: ToolGroup) -> Bool { a.running == b.running && a.lines == b.lines }

    var body: some View {
        let calls = lines.map { ToolCall($0.text) }
        if calls.count == 1 {
            ToolRow(call: calls[0], help: lines[0].text, running: running).padding(.leading, ChatLook.stepIndent)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Group {
                            if running { ProgressView().controlSize(.mini) } else { Image(systemName: Self.icon(calls)) }
                        }
                        .frame(width: 16)
                        Text(Self.summary(calls))
                        if running && !expanded, let last = calls.last, !last.argument.isEmpty {
                            Text(last.argument)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .font(ChatLook.stepFont)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                if expanded {
                    ForEach(Array(zip(calls, lines)), id: \.1.id) { call, line in
                        ToolRow(call: call, help: line.text, running: running && line.id == lines.last?.id)
                    }
                    .padding(.leading, 10)
                }
            }
            .padding(.leading, ChatLook.stepIndent)
        }
    }

    /// "Read 4 files, wrote 7 files and ran 1 command"
    static func summary(_ calls: [ToolCall]) -> String {
        var order: [ToolCall.Action] = []
        var counts: [ToolCall.Action: Int] = [:]
        for call in calls {
            if counts[call.action] == nil { order.append(call.action) }
            counts[call.action, default: 0] += 1
        }
        let clauses = order.map { ToolCall.clause($0, count: counts[$0]!) }
        let text = clauses.count > 1
            ? clauses.dropLast().joined(separator: ", ") + " and " + clauses.last!
            : clauses[0]
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The most frequent action's icon.
    static func icon(_ calls: [ToolCall]) -> String {
        let groups = Dictionary(grouping: calls, by: \.action)
        return groups.max { $0.value.count < $1.value.count }?.value.first?.icon ?? "wrench.adjustable"
    }
}

struct ToolRow: View {
    let call: ToolCall
    let help: String
    let running: Bool

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if running { ProgressView().controlSize(.mini) } else { Image(systemName: call.icon) }
            }
            .frame(width: 16)
            .foregroundStyle(.secondary)
            Text(call.verb).foregroundStyle(.secondary)
            if !call.argument.isEmpty {
                Text(call.argument)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .font(ChatLook.stepFont)
        .help(help)
    }
}

/// Consecutive status updates, in one compact block. The latest shows a spinner while it's in progress.
struct StatusGroup: View {
    let lines: [LogLine]
    let running: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines) { line in
                if line.kind == .status, let command = ChatLook.ranCommand(in: line.text) {
                    ChatLook.RanCommand(command, said: line.said)
                } else {
                    ChatLook.StatusLine(line.text, running: running && line.id == lines.last?.id && line.text.hasSuffix("…"))
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}


/// The line under a change that waits for the app to be reopened (`Store.awaitReload`): its button does what the
/// one in the app's title bar does.
enum ReloadLine {
    static func text(_ name: String) -> String { "Reload \(name) to see this change." }
    /// Reload was pressed while the agent was at work on the app: it goes in as soon as the agent is between steps.
    static func queued(_ name: String) -> String { "\(name) reloads in a moment." }

    /// Its own view, watching Lamp: the row it's in is drawn again only when its line changes, and a Reload waiting
    /// for the request changes no line.
    struct Row: View {
        let project: LampProject
        @ObservedObject private var store = Store.shared

        var body: some View {
            let queued = store.reloadWhenFree.contains(project.id)
            ChatLook.ActionLine(symbol: "arrow.clockwise", text: queued ? ReloadLine.queued(project.name) : ReloadLine.text(project.name),
                                button: "Reload", disabled: queued, prominent: true) {
                store.reloadWaiting(project.id)
            }
        }
    }
}

/// A turn's steps as its one line opens to them: "Worked for…" once it's over, and the live line while it goes on.
struct StepList: View {
    let steps: [LogLine]

    var body: some View {
        ForEach(ChatItem.items(steps)) { step in
            switch step {
            case .tools(let lines): ToolGroup(lines: lines, running: false).equatable()
            case .statuses(let lines): StatusGroup(lines: lines, running: false)
            default: EmptyView()
            }
        }
    }
}
