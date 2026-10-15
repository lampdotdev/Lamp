import SwiftUI
import LampSidebarKit

/// A tool call as logged by the engines ("Read App.swift", "Bash: ./build.sh", "Run: ls"), split into
/// what the agent did and what it did it to.
struct ToolCall {
    enum Action { case read, write, edit, delete, run, search, list, web, plan, delegate, look, use, recall, remember, art, offer, kind, ask, result, wish, other }

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
        "look_at_app": .look, "use_app": .use, "read_notes": .recall, "save_notes": .remember, "make_art": .art, "offer_setup": .offer, "make_app_for": .kind, "ask": .ask, "show_result": .result, "write_wish": .wish,
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
        case .remember: "square.and.pencil"
        case .art: "paintbrush"
        case .offer: "sparkles"
        case .kind: "laptopcomputer.and.iphone"
        case .ask: "questionmark.bubble"
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
        case .remember: "Updated its notes"
        case .art: "Painted a picture"
        case .offer: "Suggested a setup"
        case .kind: "Changed what it runs on"
        case .ask: "Asked you"
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
        case .remember: "updated its notes"
        case .art: "painted \(n("picture", "pictures"))"
        case .offer: "suggested a setup"
        case .kind: "changed what it runs on"
        case .ask: "asked you"
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

    /// The chat as most people read it: what they asked, what the agent answered and what happened to the
    /// app. The agent's working is left out, both its steps and what it says between them, which is where
    /// the file names and code are; the progress line stands in for it. Agent Details shows everything.
    static func visible(_ lines: [LogLine], details: Bool) -> [LogLine] {
        if details { return lines }
        // The last thing the agent says in a run is its answer. A run ends with its summary; while one is
        // going, the latest message shows as it's written (it says what the agent is about to do, or is
        // the answer arriving) and gives way to the next.
        var answers: Set<UUID> = []
        var latest: UUID?
        // After the agent's questions its card is the answer: whatever it says on the way out ("Waiting for
        // your answers.") would sit under the card saying the same.
        var asked = false
        // A request that ends on its result card is answered by the card: it takes the place of the reply,
        // which would say the same above it.
        var thisRequest: [UUID] = []
        for line in lines {
            switch line.kind {
            case .agent: latest = asked ? nil : line.id
            case .ask:
                asked = true
                latest = nil
            case .result:
                answers.subtract(thisRequest)
                latest = nil
            case .summary, .user:
                if let latest {
                    answers.insert(latest)
                    thisRequest.append(latest)
                }
                latest = nil
                if line.kind == .user {
                    asked = false
                    thisRequest = []
                }
            default: break
            }
        }
        if let latest { answers.insert(latest) }
        return lines.filter { $0.kind == .agent ? answers.contains($0.id) : !$0.isDetail }
    }
}

/// What the transcript shows: chat lines, with runs of tool calls and of status updates gathered up.
enum ChatItem: Identifiable {
    case line(LogLine)
    case tools([LogLine])
    case statuses([LogLine])

    var id: UUID {
        switch self {
        case .line(let line): line.id
        case .tools(let lines), .statuses(let lines): lines[0].id
        }
    }

    var kind: LogLine.Kind {
        switch self {
        case .line(let line): line.kind
        case .tools: .tool
        case .statuses: .status
        }
    }

    static func items(_ lines: [LogLine]) -> [ChatItem] {
        var items: [ChatItem] = []
        for line in lines {
            switch (line.kind, items.last) {
            case (.tool, .tools(let run)?): items[items.count - 1] = .tools(run + [line])
            case (.tool, _): items.append(.tools([line]))
            case (.status, .statuses(let run)?):
                // A progress step ("Building…") is superseded by whatever status follows it.
                let kept = run.filter { !$0.text.hasSuffix("…") }
                items[items.count - 1] = .statuses(kept + [line])
            case (.status, _): items.append(.statuses([line]))
            default: items.append(.line(line))
            }
        }
        return items
    }

    /// Space above an item: tight within a run of work, roomy between turns.
    static func gap(after previous: ChatItem?, before item: ChatItem, isFinalAnswer: Bool) -> CGFloat {
        guard let previous else { return 0 }
        switch (previous.kind, item.kind) {
        case (_, .user): return 32
        case (.user, _): return 16
        case (_, .summary): return 14
        case (.tool, .detail), (.detail, .detail): return 4
        case (_, .agent): return isFinalAnswer ? 20 : (previous.kind == .agent ? 10 : 14)
        case (_, .tool): return 10
        default: return 12
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

    var body: some View {
        let _ = iconChoice
        let lines = Self.withoutSpentOffers(lines, dir: dir)
        let finalAnswers = Self.finalAnswers(in: lines, busy: busy)
        let latestRequest = lines.last { $0.kind == .user }?.id
        let openAsk = Talk.open(in: lines)?.id
        let currentResult = Talk.current(in: lines)?.id
        // Answers clicked on a card are shown by the card, folded where it was: not again as a message.
        let shown = lines.filter { $0.fromCard != true }
        let items = ChatItem.items(progressShown ? Self.withoutStepInProgress(shown) : shown)
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let isLast = index == items.count - 1
            let gap = ChatItem.gap(after: index > 0 ? items[index - 1] : nil, before: item,
                                   isFinalAnswer: finalAnswers.contains(item.id))
            Group {
                switch item {
                // The agent's cards depend on what came after them, so they're outside the row that's
                // redrawn only when its own line changes.
                case .line(let line) where line.kind == .ask: AskCard(line: line, dir: dir, isOpen: line.id == openAsk)
                case .line(let line) where line.kind == .result: ResultCard(line: line, dir: dir, isCurrent: line.id == currentResult && !busy)
                case .line(let line): LogRow(line: line, dir: dir, busy: busy, goBack: goBack, sendAgain: sendAgain,
                                             retryPhone: retryPhone, isLatestRequest: line.id == latestRequest).equatable()
                case .tools(let lines): ToolGroup(lines: lines, running: isLast && busy && !progressShown).equatable()
                case .statuses(let lines): StatusGroup(lines: lines, running: isLast && busy && !progressShown)
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
        guard lines.contains(where: { $0.kind == .drawIcon || $0.kind == .widget || $0.kind == .iphoneSetup }) else { return lines }
        let project = Store.shared.projects.first { $0.dir == dir }
        return lines.filter { line in
            switch line.kind {
            case .drawIcon: project.map { Icons.awaitsDrawing(line.text, in: $0, byHand: AppAI.iconsByHand) } ?? false
            // The widget's card, likewise, while there's a widget to add.
            case .widget: project.map { WidgetCard.isShown(for: $0) } ?? false
            // The offer to set up iPhone apps, while the app is still only a Mac app.
            case .iphoneSetup: project?.platform == .mac
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
                ForEach(urls, id: \.self) { url in
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
            ToolRow(call: calls[0], help: lines[0].text, running: running)
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
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded {
                    ForEach(Array(zip(calls, lines)), id: \.1.id) { call, line in
                        ToolRow(call: call, help: line.text, running: running && line.id == lines.last?.id)
                    }
                    .padding(.leading, 10)
                }
            }
        }
    }

    /// "Read 4 files, wrote 7 files and ran 1 command"
    private static func summary(_ calls: [ToolCall]) -> String {
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
    private static func icon(_ calls: [ToolCall]) -> String {
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
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .font(.callout)
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
                    ChatLook.RanCommand(command)
                } else {
                    ChatLook.StatusLine(line.text, running: running && line.id == lines.last?.id && line.text.hasSuffix("…"))
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

