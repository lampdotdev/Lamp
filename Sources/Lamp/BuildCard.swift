import SwiftUI

/// One line of the agent's checklist for a new app (its `plan` tool).
struct PlanPart: Identifiable, Equatable {
    let id: Int
    var title: String
    var done: Bool
    /// The files the agent said it would write for this part. Lamp ticks the part when they're written,
    /// so progress doesn't depend on the agent stopping to report it.
    var files: [String] = []
}

/// What Lamp knows about the turn in progress, for showing the user something better than a spinner.
struct TurnProgress {
    /// The first turn of a new app gets the build card; later turns get one line.
    let newApp: Bool
    let started = Date()
    var finished: Date?
    /// The turn ended without a working app.
    var failed = false
    /// What's happening right now, in the user's words rather than the code's: "Working on the interface",
    /// "Building…". It's the one place a turn in progress says what it's doing.
    var activity = "Getting started"
    /// The file being written or edited right now, if that's what the agent is doing. Never shown: it
    /// tells which part of the plan is being worked on.
    var currentFile: String?
    var plan: [PlanPart] = []
    /// Files written so far, newest last. Never shown: they tick the plan's parts.
    var files: [String] = []
    /// What the agent has worked on so far, as the user was told ("Working on the interface"), newest last.
    /// Shown when the agent gave no plan.
    var steps: [String] = []
    /// The app's window once it has opened: the card's last frame.
    var screenshot: NSImage?

    enum PartState { case open, started, active, done }

    /// Where a part of the plan stands. Parts finish in the order the agent writes their files, which
    /// isn't always the order they're listed in.
    func state(of part: PlanPart) -> PartState {
        let working = finished == nil
        // Being written now, even if that completes it: the tick shows once the agent moves on.
        if working, let currentFile, part.files.contains(currentFile) { return .active }
        if part.done { return .done }
        if part.files.contains(where: files.contains) { return .started }
        // A plan with no files listed: the first part still open is the one in progress.
        if working, plan.allSatisfy(\.files.isEmpty), part.id == plan.first(where: { !$0.done })?.id { return .active }
        return .open
    }

    /// Ticks every part whose files have all been written.
    mutating func tickWrittenParts() {
        let written = Set(files)
        for index in plan.indices where !plan[index].done && !plan[index].files.isEmpty {
            plan[index].done = written.isSuperset(of: plan[index].files)
        }
    }

    /// The agent wrote or edited a file.
    mutating func wrote(_ file: String) {
        if files.last != file {
            files.removeAll { $0 == file }
            files.append(file)
            tickWrittenParts()
        }
        let step = Self.area(of: file)
        if steps.last != step {
            steps.removeAll { $0 == step }
            steps.append(step)
        }
    }

    /// The turn is over. When the app was built and opened, everything planned is done.
    mutating func finish(worked: Bool) {
        finished = Date()
        failed = !worked
        if worked { for index in plan.indices { plan[index].done = true } }
    }

    var stage: String {
        if finished != nil { return failed ? "Not finished" : "Ready" }
        if activity.hasPrefix("Building") || activity.hasPrefix("Fixing a problem") { return "Building" }
        if activity.hasPrefix("Opening") { return "Opening" }
        return plan.isEmpty && files.isEmpty ? "Planning" : "Creating"
    }

    /// What the agent's tool call amounts to for someone who never sees the code: no file names, no tools.
    static func activity(for call: ToolCall) -> String {
        if call.name.hasSuffix("_version") || call.name.hasSuffix("_versions") { return "Looking at earlier versions" }
        switch call.action {
        case .read: return call.argument.hasPrefix("screenshot") ? "Looking at your app" : "Looking things over"
        case .write, .edit: return area(of: call.argument)
        case .delete: return "Tidying up"
        case .run: return "Running a command"
        case .search, .list: return "Looking things over"
        case .web: return "Looking something up"
        case .plan: return "Planning your app"
        case .look: return "Checking how it looks"
        case .use: return "Trying it out"
        case .delegate, .other: return "Working on your app"
        }
    }

    /// The part of the app a file belongs to, going by the words in its name: "DealRowView.swift" is the
    /// interface, "Theme.swift" is how it looks. A guess, which is all a progress line needs.
    static func area(of file: String) -> String {
        let name = (file as NSString).deletingPathExtension
        if file.lowercased() == "app.md" { return "Taking notes for next time" }
        if file.lowercased() == "icon.json" { return "Designing the icon" }
        if name.hasSuffix("App") { return "Putting the pieces together" }
        let words = Set(name
            .replacingOccurrences(of: #"(?<=[a-z0-9])(?=[A-Z])|[^A-Za-z0-9]+"#, with: " ", options: .regularExpression)
            .lowercased().split(separator: " ")
            .map { $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : String($0) })
        return areas.first { !words.isDisjoint(with: $0.words) }?.activity ?? "Working on your app"
    }

    /// In order: "SettingsView" is the settings, not just any part of the interface.
    private static let areas: [(activity: String, words: Set<String>)] = [
        ("Making your app look nice", ["theme", "style", "color", "colour", "font", "appearance", "design",
                                       "animation", "effect", "background", "gradient"]),
        ("Working on the settings", ["setting", "preference"]),
        ("Working on the interface", ["view", "screen", "window", "sidebar", "toolbar", "row", "cell", "panel",
                                      "sheet", "menu", "button", "card", "form", "picker", "chart", "list",
                                      "detail", "editor", "popover", "command"]),
        ("Setting up what your app remembers", ["model", "store", "storage", "data", "database", "state",
                                                "persistence", "record", "library", "history"]),
        ("Working behind the scenes", ["service", "client", "api", "network", "fetcher", "sync",
                                       "manager", "engine", "controller", "provider", "parser",
                                       "importer", "exporter", "watcher", "monitor", "scanner",
                                       "calculator", "logic", "helper", "util", "extension"]),
    ]

    /// The same, from a tool call that is still streaming in: its name and the arguments so far.
    static func activity(tool: String, partialArguments: String) -> String {
        guard !tool.isEmpty else { return "Thinking" }
        return activity(for: call(tool: tool, partialArguments: partialArguments))
    }

    /// The call so far, as the engines log it: "write Scanner.swift".
    static func call(tool: String, partialArguments: String) -> ToolCall {
        let path = partialArguments.firstMatch(of: #/"(?:path|file_path)"\s*:\s*"([^"]+)"/#).map { String($0.1) } ?? ""
        return ToolCall("\(tool) \((path as NSString).lastPathComponent)")
    }

    /// The file a call writes or edits, if it does.
    static func file(changedBy call: ToolCall) -> String? {
        (call.action == .write || call.action == .edit) && !call.argument.isEmpty ? call.argument : nil
    }
}

/// Shown while a new app's first version is built: an outline of the app that fills in with its name,
/// its icon, the agent's plan and what it's doing now, and ends on a picture of the real window.
struct BuildCard: View {
    let project: LampProject
    let progress: TurnProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AppIcon(project: project, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.untitled ? "New app" : project.name).font(.headline)
                    Text(progress.stage).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            Divider()
            Group {
                if let screenshot = progress.screenshot {
                    Image(nsImage: screenshot).resizable().interpolation(.high).scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .transition(.opacity)
                } else {
                    outline.transition(.opacity)
                }
            }
            .padding(14)
            Divider()
            HStack(spacing: 8) {
                if progress.finished == nil {
                    Spinner(side: 11).frame(width: 14, height: 14)
                } else if progress.failed {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Text(progress.finished == nil ? progress.activity
                     : progress.failed ? "This didn't finish. See the messages above." : "\(project.name) is ready")
                    .lineLimit(1)
                Spacer()
                Elapsed(from: progress.started, to: progress.finished)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .animation(.easeInOut(duration: 0.35), value: progress.plan)
        .animation(.easeInOut(duration: 0.5), value: progress.screenshot != nil)
    }

    private static let symbols: [TurnProgress.PartState: String] = [
        .open: "circle", .started: "circle.lefthalf.filled", .active: "circle.dotted", .done: "checkmark.circle.fill",
    ]

    /// The agent's plan with ticks, what it has worked on when there's no plan, or blank bars before either.
    @ViewBuilder
    private var outline: some View {
        if !progress.plan.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(progress.plan) { part in
                    let state = progress.state(of: part)
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: Self.symbols[state] ?? "circle")
                            .foregroundStyle(state == .done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                            .symbolEffect(.pulse, isActive: state == .active)
                        Text(part.title).foregroundStyle(state == .open ? .secondary : .primary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !progress.steps.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(progress.steps.suffix(5), id: \.self) { step in
                    // The step it's on right now is still open; the footer says so.
                    let current = progress.finished == nil && step == progress.activity
                    Label(step, systemImage: current ? "circle.dotted" : "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, isActive: current)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach([280, 210, 245, 160] as [CGFloat], id: \.self) { width in
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: width, height: 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A later turn's progress: one line saying what the agent is doing and for how long.
struct ActivityRow: View {
    let progress: TurnProgress

    var body: some View {
        HStack(spacing: 6) {
            Spinner(.mini).frame(width: 16)
            Text(progress.activity).lineLimit(1)
            Text("·")
            Elapsed(from: progress.started, to: nil)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// A running clock, "0:42", that stops at `end`.
private struct Elapsed: View {
    let start: Date
    let end: Date?

    init(from start: Date, to end: Date?) {
        self.start = start
        self.end = end
    }

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let seconds = max(0, Int((end ?? context.date).timeIntervalSince(start)))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60)).monospacedDigit()
        }
    }
}
