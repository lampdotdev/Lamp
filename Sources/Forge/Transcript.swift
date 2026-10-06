import SwiftUI

/// A tool call as logged by the engines ("Read App.swift", "Bash: ./build.sh", "Run: ls"), split into
/// what the agent did and what it did it to.
struct ToolCall {
    enum Action { case read, write, edit, delete, run, search, list, web, plan, delegate, look, use, other }

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
        "look_at_app": .look, "use_app": .use,
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
        case .other: n("step", "steps")
        }
    }
}

extension LogLine {
    /// The chat as most people read it: what they asked, what the agent answered and what happened to the
    /// app. The agent's working is left out, both its steps and what it says between them, which is where
    /// the file names and code are; the progress line stands in for it. Agent Details shows everything.
    static func visible(_ lines: [LogLine], details: Bool, busy: Bool) -> [LogLine] {
        if details { return lines }
        // The last thing the agent says in a run is its answer. A run ends with its summary, so while
        // one is going there's no telling yet whether the latest message is the answer.
        var answers: Set<UUID> = []
        var latest: UUID?
        for line in lines {
            switch line.kind {
            case .agent: latest = line.id
            case .summary, .user:
                if let latest { answers.insert(latest) }
                latest = nil
            default: break
            }
        }
        if !busy, let latest { answers.insert(latest) }
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

    var body: some View {
        let items = ChatItem.items(progressShown ? Self.withoutStepInProgress(lines) : lines)
        let finalAnswers = Self.finalAnswers(in: lines, busy: busy)
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let isLast = index == items.count - 1
            Group {
                switch item {
                case .line(let line): LogRow(line: line, dir: dir, busy: busy, goBack: goBack).equatable()
                case .tools(let lines): ToolGroup(lines: lines, running: isLast && busy && !progressShown).equatable()
                case .statuses(let lines): StatusGroup(lines: lines, running: isLast && busy && !progressShown)
                }
            }
            .padding(.top, ChatItem.gap(after: index > 0 ? items[index - 1] : nil, before: item,
                                        isFinalAnswer: finalAnswers.contains(item.id)))
        }
    }

    /// Without the step at the end that's still going ("Building…"): the progress line is saying it.
    private static func withoutStepInProgress(_ lines: [LogLine]) -> [LogLine] {
        var lines = lines
        while let last = lines.last, last.kind == .status, last.text.hasSuffix("…") { lines.removeLast() }
        return lines
    }

    /// The last agent message of each finished turn: the answer people actually read.
    private static func finalAnswers(in lines: [LogLine], busy: Bool) -> Set<UUID> {
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
    @State private var hovered = false

    static func == (a: LogRow, b: LogRow) -> Bool { a.line == b.line && a.busy == b.busy && a.dir == b.dir }

    var body: some View {
        switch line.kind {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                if let names = line.attachments, !names.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(names, id: \.self) { name in
                            let url = dir.appendingPathComponent(Attachments.folder).appendingPathComponent(name)
                            Button { NSWorkspace.shared.open(url) } label: {
                                if Attachments.isImage(url) {
                                    AttachmentThumbnail(url: url, size: 72)
                                } else {
                                    AttachmentChip(url: url)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(name)
                        }
                    }
                }
                HStack(alignment: .center, spacing: 6) {
                    if line.version != nil, let goBack {
                        Menu {
                            Button("Go Back to After This Change") { goBack(line, false) }
                            Button("Go Back to Before This Change") { goBack(line, true) }
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .foregroundStyle(.secondary)
                        .disabled(busy)
                        .opacity(hovered ? 1 : 0)
                        .help("Go back to how the app was around this request")
                    }
                    // A message that's only attachments shows just them.
                    if !line.text.isEmpty {
                        Text(line.text)
                            .textSelection(.enabled)
                            .lineSpacing(2)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: 480, alignment: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .onHover { hovered = $0 }
        case .agent:
            Text(Self.prose(line.text))
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .status, .tool:
            // Shown through StatusGroup and ToolGroup.
            EmptyView()
        case .summary:
            HStack(spacing: 10) {
                Rectangle().fill(.separator).frame(height: 1)
                Text(line.text).font(.caption).foregroundStyle(.tertiary).fixedSize()
                Rectangle().fill(.separator).frame(height: 1)
            }
        case .error:
            Label {
                Text(line.text).textSelection(.enabled).lineSpacing(2)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        case .detail:
            Text(line.text)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(12)
        }
    }

    /// Parsed once per message: parsing markdown on every redraw adds up while an agent is streaming.
    @MainActor private static var proseCache: [String: AttributedString] = [:]

    /// Inline markdown, with code spans set off by a faint background.
    @MainActor static func prose(_ text: String) -> AttributedString {
        if let cached = proseCache[text] { return cached }
        if proseCache.count > 2000 { proseCache.removeAll() }
        var string = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        let code = string.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }.map(\.range)
        for range in code { string[range].backgroundColor = Color.primary.opacity(0.07) }
        proseCache[text] = string
        return string
    }
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
                if let command = RanCommand.command(in: line) {
                    RanCommand(command: command)
                } else {
                    HStack(spacing: 6) {
                        Group {
                            if running && line.id == lines.last?.id && line.text.hasSuffix("…") {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "checkmark.circle")
                            }
                        }
                        .frame(width: 16)
                        Text(line.text)
                    }
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// A command the agent ran without asking ("Ran: git clone …"). The chat says that it happened; the command
/// itself is a click away, for anyone who wants to see it.
struct RanCommand: View {
    let command: String
    @State private var expanded = false

    static func command(in line: LogLine) -> String? {
        line.kind == .status && line.text.hasPrefix("Ran: ") ? String(line.text.dropFirst(5)) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").frame(width: 16)
                    Text("Ran a command")
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show the command")
            if expanded {
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .padding(.leading, 22)
            }
        }
    }
}
