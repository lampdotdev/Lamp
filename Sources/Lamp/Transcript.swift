import SwiftUI
import LampSidebarKit

/// A tool call as logged by the engines ("Read App.swift", "Bash: ./build.sh", "Run: ls"), split into
/// what the agent did and what it did it to.
struct ToolCall {
    enum Action { case read, write, edit, delete, run, search, list, web, plan, delegate, look, use, recall, learn, remember, art, assets, offer, kind, remove, rename, connectors, network, ask, progress, result, wish, other }

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
        "look_at_app": .look, "use_app": .use, "read_notes": .recall, "read_skill": .learn, "save_notes": .remember, "make_art": .art, "assets": .assets, "offer_setup": .offer, "make_app_for": .kind, "remove_app": .remove, "rename_app": .rename, "connectors": .connectors, "lampify": .kind, "network_devices": .network, "device_permission": .ask, "ask": .ask, "progress": .progress, "show_result": .result, "write_wish": .wish,
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
        case .assets: "shippingbox"
        case .offer: "sparkles"
        case .kind: "laptopcomputer.and.iphone"
        case .remove: "minus.circle"
        case .rename: "character.cursor.ibeam"
        case .connectors: "link"
        case .network: "wifi"
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
        case .assets: "Looked through free models and art"
        case .offer: "Suggested a setup"
        case .kind: "Changed what it runs on"
        case .remove: "Took an app away"
        case .rename: "Renamed it"
        case .connectors: "Looked up a connector"
        case .network: "Looked around your network"
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
        case .assets: "looked through free models and art"
        case .offer: "suggested a setup"
        case .kind: "changed what it runs on"
        case .remove: "took an app away"
        case .rename: "renamed it"
        case .connectors: "looked up \(n("connector", "connectors"))"
        case .network: "looked around your network"
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
        if details { return lines.filter { !hidden.contains($0.id) }.map(\.withOutcome) }
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
        let retrying = refusedAskRetries(in: lines)
        // A result card saved by an earlier Lamp isn't shown: the agent's last message says what it did. A turn's summary
        // stays, for how long it worked (`ChatItem.items`), and isn't drawn as a line of its own. A tool call is a step
        // in the words the live line said while it ran (`steps(said:)`).
        return said(lines.map(\.withOutcome).filter {
            !hidden.contains($0.id) && !retrying.contains($0.id)
                && ($0.kind == .agent ? !afterAsk.contains($0.id)
                    : $0.kind == .summary || $0.kind == .tool || !$0.isDetail && $0.kind != .result)
        })
    }

    /// What the agent says to itself between questions Lamp turned back (`Talk.ask(from:)`: too many words, too few
    /// options) and the card it asks with instead. The person never saw the questions turned back, so a remark
    /// about fixing them ("Counting “Yes,” too, shortening.") would be about nothing on screen. Hidden from the
    /// refusal on, so it never shows for a moment while the card is on its way, through any number of tries; only
    /// once a card lands. When something else comes first (other work, the person, the end of the turn) the agent
    /// gave up on asking, and what it said meanwhile is its answer: it shows. Agent Details and the saved chat keep it.
    static func refusedAskRetries(in lines: [LogLine]) -> Set<UUID> {
        var retries: Set<UUID> = []
        var held: [UUID]? = nil   // the agent's lines since the first refusal, while it's still trying to ask
        for line in lines {
            switch line.kind {
            case .tool where ToolCall(line.text).name == "ask":
                if line.failed == true, held == nil { held = [] }
            case .agent:
                held?.append(line.id)
            case .ask:
                if let held { retries.formUnion(held) }
                held = nil
            case .user, .summary, .status, .progress, .error, .tool:
                held = nil
            default: break
            }
        }
        // Still trying when the chat ends: the turn is going, and its card may be next.
        if let held { retries.formUnion(held) }
        return retries
    }

    /// A refused `ask` or `progress` call is no step: the person never saw the questions or the line it was
    /// turned back for, and what it was retried as is on screen.
    private static func refusedTalk(_ line: LogLine, _ call: ToolCall) -> Bool {
        line.failed == true && (call.name == "ask" || call.action == .progress)
    }

    /// The line as the chat shows it: a command that failed says so after the name the agent gave it, so its row
    /// never reads as done. Its own row keeps its name for when it ran fine, and two commands of one name, one failed
    /// and one not, are two rows (`ChatItem.items`).
    var withOutcome: LogLine {
        guard failed == true, kind == .status, ChatLook.ranCommand(in: text) != nil else { return self }
        var line = self
        line.said = (said ?? ChatLook.unnamedStep) + ChatLook.failedMark
        return line
    }

    /// Tool calls as the steps a person reads: what the live line said while each ran ("Looking things over",
    /// "Working on the interface", `TurnProgress.activity`), never the call itself with its files, and that it failed
    /// when it did. Calls in a row that said the same are one step, and a call that says nothing of its own (a progress
    /// line) is no step. A command is no step here either: its own row ("Ran: …", by the name the agent gave it)
    /// already is, and commands under one name are gathered there. For Codex the file work after a command is named
    /// after it too (`Store`, the heading of its reasoning), so it's part of that row, not the same words again under
    /// it. Without this a turn that only read and edited files had nothing under its open line.
    private static func said(_ lines: [LogLine]) -> [LogLine] {
        var out: [LogLine] = []
        for line in lines {
            guard line.kind == .tool else {
                // A command's row is logged once it's allowed or has run, which can be after file work Lamp already
                // named after it (Claude Code's calls in one message, the command still running): that file work is
                // part of the command's row too, not the same words once more above it.
                if line.kind == .status, let said = line.said, ChatLook.ranCommand(in: line.text) != nil,
                   let last = out.last, last.kind == .status, last.said == nil, last.text == said, last.part == line.part {
                    out.removeLast()
                }
                out.append(line)
                continue
            }
            let call = ToolCall(line.text)
            guard call.action != .run, !refusedTalk(line, call) else { continue }
            // The agent's own words for the step when it gave some, else what the live line said.
            let said = line.said ?? TurnProgress.activity(for: call)
            guard !said.isEmpty else { continue }
            let words = line.failed == true ? said + ChatLook.failedMark : said
            // The same words twice are one step, but within one part of a first build: the later part's step is the
            // only sign in the chat that the build moved on.
            if let last = out.last, last.kind == .status, (last.said ?? last.text) == words, last.part == line.part { continue }
            out.append(LogLine(id: line.id, kind: .status, text: words, at: line.at, foldTitle: line.foldTitle, failed: line.failed, part: line.part))
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
        return result + (run.contains { $0.id == waiting } ? items(run) : closing(run))
    }

    /// The run going on: each stretch of more than one step that something said came after folds to its one line,
    /// as it will when the turn ends, so the chat keeps only what's going on now open. The line reads how many steps
    /// it was until its title comes, which is asked for as the stretch closes (`StepTitles.closed(in:turn:)`). The
    /// stretch still going, and a step on its own, stay rows.
    /// `next` is what follows the run, when something does, which closes its last stretch too.
    private static func closing(_ run: [LogLine], closedBy next: LogLine? = nil) -> [ChatItem] {
        var result: [ChatItem] = []
        var stretch: [LogLine] = []
        func close(at next: LogLine) {
            if stretch.count > 1 {
                result.append(fold(stretch, ended: next.at))
            } else {
                result += items(stretch)
            }
            stretch = []
        }
        for line in run {
            if isStep(line) {
                // A step of another part of a first build closes the stretch of the part before it.
                if let last = stretch.last, last.part != line.part { close(at: line) }
                stretch.append(line)
                continue
            }
            close(at: line)
            result += items([line])
        }
        if let next { close(at: next) }
        return result + items(stretch)
    }

    /// A closed stretch of steps as its one line: its title and how long it took once that's come (`StepTitles`),
    /// how many steps it was until then.
    private static func fold(_ stretch: [LogLine], ended: Date?) -> ChatItem {
        let seconds = stretch[0].at.flatMap { start in ended.map { max(0, $0.timeIntervalSince(start)) } }
        let fold = Fold(steps: stretch, first: stretch[0], isAnswers: false, seconds: seconds)
        return .work(id: stretch[0].id, title: title(of: fold, untitled: "\(stretch.count) steps"), steps: stretch)
    }

    /// A part of a new app's first build that the build has moved on from, or one of a build that's over (`Chapters`):
    /// as in the run going on, each stretch of its steps folds to its title, or how many steps it was until that
    /// comes, and so does its last one, which nothing more in the part will follow: it was titled as the build moved
    /// on to the next part (`StepTitles.closed(in:)`), and `ended` is when that was, for how long it took. While a question in it waits for its answer nothing is folded, as in a run
    /// (`items(_:gather:)`): nothing above the card may change height. `waiting` is the card still waiting in the
    /// whole chat, which a part alone can't tell, its answer being in a later one.
    static func chapter(_ lines: [LogLine], waiting: UUID?, ended: Date? = nil) -> [ChatItem] {
        if lines.contains(where: { $0.id == waiting }) { return items(lines) }
        // Only the steps of the part's own: those from before the plan, which go under its first part, are a stretch of
        // their own, titled as one (`StepTitles.closed(in:)`).
        let trailing = lines.reversed().prefix { isStep($0) && $0.part == lines.last?.part }.count
        guard trailing > 1 else { return closing(lines) }
        let stretch = Array(lines.suffix(trailing))
        return closing(Array(lines.dropLast(trailing)), closedBy: stretch[0]) + [fold(stretch, ended: ended)]
    }

    /// What a turn did, as against what it said: the lines that go into its one line ("Worked for…", and while it
    /// goes on the live line) rather than being shown in the chat.
    static func isStep(_ line: LogLine) -> Bool {
        (line.kind == .status && line.text != ChatLook.fixingCrash) || line.kind == .tool
    }

    /// While a turn goes on, the steps since the last thing it said aren't rows of their own: they're inside the one
    /// line at the bottom that says what it's doing (`ActivityRow`, the sidebar's `workingSteps`), which opens to show
    /// them. Steps that came before something it said (a message, a progress line, Reload) stay where they came, folded
    /// when there's more than one (`closing`), so the chat reads in the order things happened, newest at the bottom. `shown` is the chat without the live
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

    /// The stretches of a finished run's steps, and the run's other lines between them; the stretches in folds[i]
    /// come before others[i]. Steps between two things said are one stretch, or one for each part of a new app's
    /// first build they're in (`Chapters`), so no fold spans two parts and each part's are titled on their own. The
    /// answer's stretch is the last one with steps up to the run's last message.
    static func folds(_ run: [LogLine], summary: LogLine) -> (folds: [[Fold]], others: [LogLine]) {
        var slots: [[[LogLine]]] = [[]]
        var others: [LogLine] = []
        for line in run {
            if isStep(line) {
                if let stretch = slots[slots.count - 1].last, stretch.last?.part == line.part {
                    slots[slots.count - 1][slots[slots.count - 1].count - 1].append(line)
                } else {
                    slots[slots.count - 1].append([line])
                }
            } else {
                others.append(line)
                slots.append([])
            }
        }
        let answer = others.lastIndex { $0.kind == .agent } ?? others.count
        let last = slots[...min(answer, slots.count - 1)].lastIndex { !$0.isEmpty } ?? slots.lastIndex { !$0.isEmpty }
        let folds = slots.enumerated().map { index, stretches -> [Fold] in
            let after = index < others.count ? others[index] : summary
            return stretches.enumerated().map { place, stretch in
                let steps = items(stretch).flatMap { item -> [LogLine] in
                    switch item {
                    case .statuses(let lines), .tools(let lines): lines
                    case .line(let line): [line]
                    case .work(_, _, let steps): steps
                    }
                }
                let ended = place + 1 < stretches.count ? stretches[place + 1][0].at : after.at
                let seconds = stretch[0].at.flatMap { start in ended.map { max(0, $0.timeIntervalSince(start)) } }
                return Fold(steps: steps, first: stretch[0], isAnswers: index == last && place == stretches.count - 1, seconds: seconds)
            }
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
        for (index, slot) in folds.enumerated() {
            for fold in slot {
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
                   last.text == line.text, last.part == line.part {
                    items[items.count - 1] = .statuses(kept)
                    continue
                }
                // Commands the agent gave one name to are one step: the name once, their commands under it.
                // Each command keeps its own "(not run)", whichever came first, and the step whether none of them ran.
                if let said = line.said, let last = kept.last, last.said == said, last.part == line.part,
                   let command = ChatLook.ranCommand(in: line.text), let before = ChatLook.ranCommand(in: last.text) {
                    kept[kept.count - 1].text = "Ran: " + before + "\n" + command
                    kept[kept.count - 1].notRun = last.wasNotRun && line.wasNotRun
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

/// What both chats draw of a stretch of the chat, worked out from its lines (`SidebarServer.lines`).
enum Transcript {

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
            // The offer to set up iPhone apps, while the app is still only a Mac app; for one of a wish's other apps,
            // while the wish still waits for it.
            case .iphoneSetup: IPhoneSetupLine.shows(line.text, for: project)
            // Reload, while the change it's for still waits: the last such line only, under the latest change.
            // A wish's line is for its other parts' changes too.
            case .reload: project.map { Runtime.waitsForReload($0) || Store.shared.parts(of: $0).contains(where: Runtime.waitsForReload)
                || Store.shared.awaitsReloadElsewhere($0) } ?? false
                && line.id == lines.last(where: { $0.kind == .reload })?.id
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

/// Consecutive tool calls, summed up in one line with Agent Details on.
enum ToolGroup {

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

/// The line under a change that waits for the app to be reopened (`Store.awaitReload`): its button does what the
/// one in the app's title bar does.
enum ReloadLine {
    static func text(_ name: String) -> String { "Reload \(name) to see this change." }
    /// Reload reaches the wish's other places too (`Store.reloadEverywhere`): where it opens the app again (where it's
    /// open) and where it only puts the new version, for next time, so nobody using a TV or a phone is surprised.
    static func text(_ name: String, reopens: [String], updates: [String]) -> String {
        guard reopens.count + updates.count > 1 || !updates.isEmpty else { return text(name) }
        let open = reopens.isEmpty ? "" : "Reload opens \(name) again on \(listed(reopens))"
        let next = updates.isEmpty ? "" : (open.isEmpty ? "Reload puts this change on " : ", and puts it on ") + listed(updates) + " for next time"
        return open + next + "."
    }
    static func listed(_ names: [String]) -> String {
        names.count < 2 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
    /// Reload was pressed while the agent was at work on the app: it goes in as soon as the agent is between steps.
    static func queued(_ name: String) -> String { "\(name) reloads in a moment." }
}
