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
    /// The first turn of a new app is drawn as its plan's chapters (`Chapters`); later turns get one line.
    let newApp: Bool
    /// Set only by the gallery, to show a turn that has been going a while.
    var started = Date()
    var finished: Date?
    /// The turn ended without a working app.
    var failed = false
    /// The agent has asked its questions: nothing is built until they're answered. Set as they arrive, so
    /// a new app's chapters stop showing the parts sketched before them at once.
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
    /// The part of the plan the build has reached: the chapter each line it logs goes under (`chapter(for:)`).
    /// It never goes back, so a line goes under an earlier part only by being logged while that part was the one.
    var reached = 0
    /// The agent's run is over: what's logged from here (Lamp's own build and opening, a run to fix it) is no part's.
    var chaptersClosed = false

    /// Until the model first answers, only a new app is getting started: a follow-up in a chat that's been
    /// going a while is being thought about.
    init(newApp: Bool) {
        self.newApp = newApp
        activity = newApp ? "Waking the genie" : Activity.thinking
    }

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

    /// Which part of the plan a line being logged goes under, going only by what Lamp is sure of: the agent's plan
    /// (its parts, the files it listed for each, which it says are done) and the files it writes. Writing a file
    /// listed for a later part, and for none before it, moves the build on to that part; the agent saying something
    /// (a message, a progress line, a question, a new plan) once the part it's on is done moves it to the next one,
    /// since it begins each pass by saying so. Anything else (a read, a command, a look at the app, Lamp's "Building…") stays with the
    /// part the build is on: the agent checks and fixes a part after writing it, and which part a read or a command
    /// is for can't be told. Nil when there is no plan yet, or the run is over.
    mutating func chapter(for line: LogLine) -> Int? {
        guard newApp, !chaptersClosed, !plan.isEmpty else { return nil }
        var part = min(reached, plan.count - 1)
        let call = line.kind == .tool ? ToolCall(line.text) : nil
        // Codex reports one change to several files ("Edit A.swift, B.swift").
        if let call, let changed = Self.file(changedBy: call) {
            let files = Set(changed.components(separatedBy: ", ").map { ($0 as NSString).lastPathComponent })
            if !plan[...part].contains(where: { !files.isDisjoint(with: $0.files) }),
               let later = plan.indices.first(where: { $0 > part && !files.isDisjoint(with: plan[$0].files) }) {
                part = later
            }
        } else if plan[part].done, [.agent, .progress, .ask].contains(line.kind) || call?.action == .plan {
            // The next part in order, even one that looks done already: a listed file is kept by its name alone, so a
            // later part's Phone/index.html is ticked by the first part's index.html.
            part = min(part + 1, plan.count - 1)
        }
        reached = part
        return part
    }

    /// Whether the run's summary keeps the plan, which makes its lines chapters for good. A run that ended on a question
    /// asked before there was any plan built nothing, and chapters drawn round that card would move it under the pointer.
    /// One asked once the plan had come is in a part already, drawn under its heading, so the plan stays or the headings
    /// above the card would go.
    static func savesPlan(asked: Bool, in lines: [LogLine]) -> Bool {
        !asked || lines.last { $0.kind == .ask }?.part != nil
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
