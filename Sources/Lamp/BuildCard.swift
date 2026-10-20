import SwiftUI
import LampSidebarKit

/// One line of the agent's checklist for a new app (its `plan` tool).
struct PlanPart: Identifiable, Equatable {
    let id: Int
    var title: String
    var done: Bool
    /// The files the agent said it would write for this part. Lamp ticks the part when they're written,
    /// so progress doesn't depend on the agent stopping to report it.
    var files: [String] = []

    /// The parts in a `plan` call's arguments, whichever engine made it.
    static func parts(from arguments: [String: Any]) -> [PlanPart] {
        (arguments["parts"] as? [[String: Any]] ?? []).enumerated().compactMap { index, part in
            (part["title"] as? String).map {
                PlanPart(id: index, title: $0, done: part["done"] as? Bool ?? false,
                         files: (part["files"] as? [String] ?? []).map { ($0 as NSString).lastPathComponent })
            }
        }
    }
}

/// What Lamp knows about the turn in progress, for showing the user something better than a spinner.
struct TurnProgress {
    /// The first turn of a new app gets the build card; later turns get one line.
    let newApp: Bool
    /// Set only by the gallery, to show a turn that has been going a while.
    var started = Date()
    var finished: Date?
    /// The turn ended without a working app.
    var failed = false
    /// The agent has asked its questions: nothing is built until they're answered. Set as they arrive, so
    /// the card is already at its short size under them.
    var asking = false
    /// The app was built, but couldn't be put in place or opened: the turn made its change, and there is
    /// nothing for the person to use yet.
    var unopened = false
    /// What's happening right now, in the user's words rather than the code's: "Working on the interface",
    /// "Building…". It's the one place a turn in progress says what it's doing; how it reads as the wait goes on
    /// is `Activity.words`.
    var activity: String {
        // Lamp is building what the agent wrote: every part it has worked on is as done as this pass makes it,
        // even with a listed file left unwritten, so none sits unticked above Lamp's own last row, and it stays
        // ticked when the agent goes on.
        didSet {
            if activity != oldValue { activitySince = Date() }
            guard finishing else { return }
            for index in plan.indices where plan[index].files.contains(where: files.contains) { plan[index].done = true }
        }
    }
    /// When the activity last changed, which is what a long think or a long build is counted from.
    var activitySince = Date()
    /// What the status line under the wish's name on the desk says: the activity in Lamp's own words only. A command the agent named,
    /// or a step that only a coder would follow, reads there as plain work on the app (`Store.note`).
    var deskActivity: String
    var deskSince = Date()
    /// What the desk says for `activity`: Lamp's own words as they are, and a command (named by the agent or not)
    /// as plain work on the app, since a tile is no place for what only a coder would follow.
    static func deskWords(_ activity: String, named: Bool) -> String {
        if activity.hasPrefix("Waiting for your OK") { return "Waiting for your OK" }
        return named || activity.localizedCaseInsensitiveContains("command") ? "Working on your app" : activity
    }
    /// Lamp is looking at the app for the agent, so the activity is the look's stage and the look is the step going on.
    var looking = false
    /// The file being written or edited right now, if that's what the agent is doing. Never shown: it
    /// tells which part of the plan is being worked on.
    var currentFile: String?
    var plan: [PlanPart] = []
    /// Files written so far, newest last. Never shown: they tick the plan's parts.
    var files: [String] = []
    /// What the agent has worked on so far, as the user was told ("Working on the interface"), newest last.
    /// Shown when the agent gave no plan.
    var steps: [String] = []
    /// Lamp is naming the app from the request right now.
    var naming = false
    /// Lamp's own guess at the app's parts, made with its name: shown, unticked, while the agent thinks
    /// (which can take minutes) and replaced by the agent's plan when it gives one.
    var sketch: [String] = []

    /// Until the model first answers, only a new app is getting started: a follow-up in a chat that's been
    /// going a while is being thought about.
    init(newApp: Bool) {
        self.newApp = newApp
        activity = newApp ? "Waking the genie" : Activity.thinking
        deskActivity = activity
    }

    /// A part's mark on the build card. A part being worked on gets a spinner instead.
    static let symbols: [PartState: String] = [
        .open: "circle", .started: "circle.dotted", .done: "checkmark.circle.fill",
    ]

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

    /// Ticks every part whose files have all been written, and every part the agent has started and then left
    /// for a later one's files: the agent writes the parts in the list's order, and a file it listed often goes
    /// into another one instead, which would leave its part unticked under ticked ones, as if skipped.
    mutating func tickWrittenParts() {
        let written = Set(files)
        let latest = files.last.flatMap { file in plan.firstIndex { $0.files.contains(file) } } ?? -1
        for index in plan.indices where !plan[index].done && !plan[index].files.isEmpty {
            let started = plan[index].files.contains(where: written.contains)
            plan[index].done = written.isSuperset(of: plan[index].files) || (started && latest > index)
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

    /// The turn is over with nothing built yet: the agent asked first.
    mutating func wait() {
        finished = Date()
        asking = true
    }

    /// How a finished turn ended, for the line under the app's name.
    enum Ending { case ready, didNotFinish, didNotOpen }

    var ending: Ending? {
        guard finished != nil else { return nil }
        return failed ? .didNotFinish : unopened ? .didNotOpen : .ready
    }

    /// The turn is over. When the app was built and opened, everything planned is done.
    mutating func finish(worked: Bool, opened: Bool = true) {
        asking = false   // it asked and then built anyway
        finished = Date()
        failed = !worked
        unopened = !opened
        if worked { for index in plan.indices { plan[index].done = true } }
    }

    /// The app is being built and opened: past what the agent's plan or steps describe.
    var finishing: Bool {
        finished == nil && ["Building", "Fixing a problem", "Installing", "Opening"].contains { activity.hasPrefix($0) }
    }

    /// The checklist gets a last row of Lamp's own once there's nothing left on it to work on.
    var showsFinishing: Bool {
        guard finished == nil else { return false }
        if !plan.isEmpty { return finishing || plan.allSatisfy(\.done) }
        return !steps.isEmpty && finishing
    }

    /// What the agent's tool call amounts to for someone who never sees the code: no file names, no tools. Empty
    /// for a call that leaves what's being done as it was.
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
        case .recall: return "Checking its notes"
        case .learn: return "Reading up"
        case .remember: return "Taking notes for next time"
        case .art: return "Painting a picture"
        case .offer: return "Suggesting a better setup"
        case .kind: return "Making it for other devices"
        case .connectors: return "Looking up a connector"
        case .ask: return "Asking you"
        // What it's doing goes on being what it was: the line it wrote says the rest.
        case .progress: return ""
        case .result: return "Wrapping up"
        case .wish: return "Writing your wish"
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
        ("Making your app look nice", ["theme", "style", "color", "color", "font", "appearance", "design",
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
/// its icon, the agent's plan and what it's doing now (`BuildCardView`).
struct BuildCard: View {
    @EnvironmentObject private var store: Store
    let project: LampProject
    let progress: TurnProgress

    var body: some View {
        BuildCardView(title: project.title, name: project.untitled ? nil : project.name,
                      iconReady: store.icons[project.id] != nil, progress: progress) {
            AppIcon(project: project, size: 44)
        }
    }
}

/// The build card drawn from plain values: by Lamp's window and its gallery. Once the turn is over it folds to its
/// first line, the app's name and how it ended. It used to end on a big picture of the app's window, which said
/// again what the app beside it and the agent's message under it say, and left people unsure what the block was for.
struct BuildCardView<Icon: View>: View {
    let title: String
    /// The app's name once Lamp has given it one.
    let name: String?
    let iconReady: Bool
    let progress: TurnProgress
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                icon()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    status.font(.body).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(14)
            // Nothing is being built while the agent waits for an answer, and nothing more once it's over:
            // the card is just the app.
            if !progress.asking && progress.finished == nil {
                Divider()
                outline.transition(.opacity).padding(14)
            }
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .animation(.easeInOut(duration: 0.35), value: progress.plan)
        .animation(.easeInOut(duration: 0.35), value: progress.sketch)
        .animation(.easeInOut(duration: 0.35), value: progress.naming)
        .animation(.easeInOut(duration: 0.35), value: progress.showsFinishing)
        .animation(.easeInOut(duration: 0.35), value: iconReady)
        .animation(.easeInOut(duration: 0.35), value: progress.finished != nil)
    }

    /// What's happening right now, under the app's name; once it's over, how it ended.
    @ViewBuilder
    private var status: some View {
        if progress.asking {
            Text("A quick question first")
        } else if progress.finished == nil {
            ChatLook.ActivityText(progress.activity, since: progress.activitySince)
        } else {
            switch progress.ending {
            case .didNotFinish:
                Label("Didn't finish. See the messages below.", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            case .didNotOpen:
                Label("Built, but it didn't open. See the messages below.", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            default:
                Label { Text("Ready") } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
    }

    /// The agent's plan with ticks, what it has worked on when there's no plan, or what Lamp is doing before either.
    @ViewBuilder
    private var outline: some View {
        if !progress.plan.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(progress.plan) { part in
                    let state = progress.state(of: part)
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Mark(symbol: TurnProgress.symbols[state])
                            .foregroundStyle(state == .done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                        Text(part.title).foregroundStyle(state == .open ? .secondary : .primary)
                    }
                }
                if progress.showsFinishing { finishingRow }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !progress.steps.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(progress.steps.suffix(5), id: \.self) { step in
                    let current = progress.finished == nil && step == progress.activity
                    Label { Text(step) } icon: { Mark(symbol: current ? nil : "checkmark.circle.fill") }
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                }
                if progress.showsFinishing { finishingRow }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            gettingStarted
        }
    }

    /// Before the agent has a plan, which can take minutes: what Lamp itself has done (all of it real, none
    /// of it timed), then its sketch of the app or blank bars that show it's still going.
    private var gettingStarted: some View {
        let working = progress.finished == nil
        return VStack(alignment: .leading, spacing: 7) {
            if progress.naming {
                Self.step("Naming your app", done: false, working: working)
            } else {
                if let name { Self.step("Called it \(name)", done: true, working: working) }
                Self.step(iconReady ? "Designed an icon" : "Designing an icon", done: iconReady, working: working)
                Self.step("Working out the details", done: false, working: working)
            }
            Group {
                if progress.sketch.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach([240, 180, 210] as [CGFloat], id: \.self) { width in
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: width, height: 10)
                        }
                    }
                    .shimmering(working)
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(progress.sketch, id: \.self) { part in
                            Label(part, systemImage: "circle.dashed")
                        }
                    }
                    .foregroundStyle(.tertiary)
                    .shimmering(working)
                }
            }
            .padding(.leading, 24)
            .padding(.top, 2)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Lamp's own last row: the build and the first opening, which no plan lists. The header says which.
    private var finishingRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Mark(symbol: nil).foregroundStyle(.secondary)
            Text("Building and opening it")
        }
        .transition(.opacity)
    }

    private static func step(_ title: String, done: Bool, working: Bool) -> some View {
        Label { Text(title) } icon: { Mark(symbol: done ? "checkmark.circle.fill" : working ? nil : "circle.dotted") }
            .foregroundStyle(.secondary)
            .transition(.opacity)
    }
}

/// A checklist row's mark: a symbol, or a spinner (nil) for what's being worked on right now.
private struct Mark: View {
    let symbol: String?

    var body: some View {
        if let symbol {
            Image(systemName: symbol)
        } else {
            // Sized and aligned like a symbol, so the row doesn't move when its spinner becomes a tick.
            Image(systemName: "circle").hidden()
                .overlay { ProgressView().controlSize(.small).scaleEffect(0.75) }
        }
    }
}

/// A slow light passing over something that's still on its way, so a wait doesn't look like a freeze.
private struct Shimmer: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content
                .overlay {
                    GeometryReader { geometry in
                        let band = geometry.size.width * 0.5
                        LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: -band + phase * (geometry.size.width + band))
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
                .onAppear {
                    phase = 0
                    withAnimation(.linear(duration: 1.8).delay(0.4).repeatForever(autoreverses: false)) { phase = 1 }
                }
        } else {
            content
        }
    }
}

private extension View {
    func shimmering(_ active: Bool) -> some View { modifier(Shimmer(active: active)) }
}

/// A later turn's progress: one line saying what the agent is doing and for how long, which opens to the turn's steps
/// so far (they aren't rows of their own while it goes on, `ChatItem.live`).
struct ActivityRow: View {
    let progress: TurnProgress
    /// The chat's lines, for the steps the line opens to.
    var lines: [LogLine] = []
    @AppStorage("showDetails") private var details = false

    var body: some View {
        let steps = details ? [] : ChatItem.live(lines, doing: progress.activity, looking: progress.looking).steps
        ChatLook.ActivityLine(progress.activity, started: progress.started, since: progress.activitySince,
                              hasSteps: !steps.isEmpty) { StepList(steps: steps) }
    }
}
