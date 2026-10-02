import SwiftUI

/// One line of the agent's checklist for a new app (its `plan` tool).
struct PlanPart: Identifiable, Equatable {
    let id: Int
    var title: String
    var done: Bool
    /// The files the agent said it would write for this part. Forge ticks the part when they're written,
    /// so progress doesn't depend on the agent stopping to report it.
    var files: [String] = []
}

/// What Forge knows about the turn in progress, for showing the user something better than a spinner.
struct TurnProgress {
    /// The first turn of a new app gets the build card; later turns get one line.
    let newApp: Bool
    let started = Date()
    var finished: Date?
    /// The turn ended without a working app.
    var failed = false
    /// What's happening right now, in plain words: "Writing Scanner.swift", "Building…".
    var activity = "Getting started"
    /// What the model has started on but not finished ("Writing GameView.swift", "Thinking"), shown at the
    /// end of the chat. nil once the step is logged.
    var upcoming: String?
    /// The file being written or edited right now, if that's what the agent is doing.
    var currentFile: String?
    var plan: [PlanPart] = []
    /// Files written so far, newest last. Shown when the agent gave no plan.
    var files: [String] = []
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

    /// The turn is over. When the app was built and opened, everything planned is done.
    mutating func finish(worked: Bool) {
        finished = Date()
        failed = !worked
        if worked { for index in plan.indices { plan[index].done = true } }
    }

    var stage: String {
        if finished != nil { return failed ? "Not finished" : "Ready" }
        if activity.hasPrefix("Building") || activity.hasPrefix("Fixing a build") { return "Building" }
        if activity.hasPrefix("Opening") { return "Opening" }
        return plan.isEmpty && files.isEmpty ? "Planning" : "Writing code"
    }

    /// The step the agent's tool call amounts to, in the present tense.
    static func activity(for call: ToolCall) -> String {
        let file = call.argument
        if call.name == "look_at_app" { return "Checking the result" }
        if call.name == "use_app" { return "Trying the app" }
        switch call.action {
        case .read: return file.hasPrefix("screenshot") ? "Looking at the app" : file.isEmpty ? "Reading the code" : "Reading \(file)"
        case .write: return file.isEmpty ? "Writing a file" : "Writing \(file)"
        case .edit: return file.isEmpty ? "Editing a file" : "Editing \(file)"
        case .delete: return file.isEmpty ? "Deleting a file" : "Deleting \(file)"
        case .run: return "Running a command"
        case .search: return "Searching the code"
        case .list: return "Looking through the files"
        case .web: return "Looking something up"
        case .plan: return "Planning"
        case .delegate: return "Working on a subtask"
        case .other: return "Working"
        }
    }

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
    let project: ForgeProject
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
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
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

    /// The agent's plan with ticks, the files written when there's no plan, or blank bars before either.
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
        } else if !progress.files.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(progress.files.suffix(5), id: \.self) { file in
                    Label(file, systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
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
            ProgressView().controlSize(.mini).frame(width: 16)
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
