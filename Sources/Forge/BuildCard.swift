import SwiftUI

/// One line of the agent's checklist for a new app (its `plan` tool).
struct PlanPart: Identifiable, Equatable {
    let id: Int
    var title: String
    var done: Bool
}

/// What Forge knows about the turn in progress, for showing the user something better than a spinner.
struct TurnProgress {
    /// The first turn of a new app gets the build card; later turns get one line.
    let newApp: Bool
    let started = Date()
    var finished: Date?
    /// What's happening right now, in plain words: "Writing Scanner.swift", "Building…".
    var activity = "Getting started"
    var plan: [PlanPart] = []
    /// Files written so far, newest last. Shown when the agent gave no plan.
    var files: [String] = []
    /// The app's window once it has opened: the card's last frame.
    var screenshot: NSImage?

    var stage: String {
        if finished != nil { return "Ready" }
        if activity.hasPrefix("Building") || activity.hasPrefix("Fixing a build") { return "Building" }
        if activity.hasPrefix("Opening") { return "Opening" }
        return plan.isEmpty && files.isEmpty ? "Planning" : "Writing code"
    }

    /// The step the agent's tool call amounts to, in the present tense.
    static func activity(for call: ToolCall) -> String {
        let file = call.argument
        if call.name == "look_at_app" { return "Checking the result" }
        switch call.action {
        case .read: return file.hasPrefix("screenshot") ? "Looking at the app" : file.isEmpty ? "Reading the code" : "Reading \(file)"
        case .write: return file.isEmpty ? "Writing a file" : "Writing \(file)"
        case .edit: return file.isEmpty ? "Editing a file" : "Editing \(file)"
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
        let path = partialArguments.firstMatch(of: #/"(?:path|file_path)"\s*:\s*"([^"]+)"/#).map { String($0.1) } ?? ""
        return activity(for: ToolCall("\(tool) \((path as NSString).lastPathComponent)"))
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
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Text(progress.finished == nil ? progress.activity : "\(project.name) is ready").lineLimit(1)
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

    /// The agent's plan with ticks, the files written when there's no plan, or blank bars before either.
    @ViewBuilder
    private var outline: some View {
        if !progress.plan.isEmpty {
            let current = progress.plan.first { !$0.done }?.id
            VStack(alignment: .leading, spacing: 9) {
                ForEach(progress.plan) { part in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: part.done ? "checkmark.circle.fill" : part.id == current ? "circle.dotted" : "circle")
                            .foregroundStyle(part.done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                            .symbolEffect(.pulse, isActive: part.id == current && progress.finished == nil)
                        Text(part.title).foregroundStyle(part.done || part.id == current ? .primary : .secondary)
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
