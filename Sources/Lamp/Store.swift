import SwiftUI
import CryptoKit
import AppKit

/// What an app is for: a Mac app that installs beside the user's others, or an iPhone app that runs in the
/// iOS Simulator on this Mac (putting one on a real iPhone needs Apple's developer program; not yet).
enum Platform: String, Codable {
    case mac, iphone   // "iphone" is the iOS kind: iPhone and iPad apps alike (see DeviceFamily)
}

/// Which simulator an iOS app opens on. The app itself is built for both.
enum DeviceFamily: String, Codable {
    case iphone, ipad
    var name: String { self == .ipad ? "iPad" : "iPhone" }
}

struct LampProject: Identifiable, Hashable {
    let id: String      // folder name; also used in lamp:// links
    let name: String    // display name
    let exe: String     // Swift target / executable name
    let dir: URL
    /// Made with New App and not named yet. The first message names it.
    var untitled = false
    var platform: Platform = .mac
    var family: DeviceFamily = .iphone
    /// The person's own iPhone or iPad that Play puts the app on (Devices), instead of the simulator.
    var device: String?

    var bundleID: String { Edition.appBundlePrefix + id }
    /// On a phone the app is registered with Apple under the person's team, so the id carries the team:
    /// another team may have registered the plain one for the same app name.
    func deviceBundleID(team: String) -> String { bundleID + "." + team.lowercased() }
    var builtURL: URL { dir.appendingPathComponent("build/\(exe).app") }
    /// Every successful build is copied here so it shows up in Spotlight and Launchpad.
    var installedURL: URL { Store.installDir.appendingPathComponent("\(name).app") }
}

struct ProjectMeta: Codable {
    var name: String
    var exe: String
    var untitled: Bool?
    var platform: Platform?   // nil in apps made before iPhone apps existed: a Mac app
    var family: DeviceFamily?  // iOS apps: which simulator they open on; nil means iPhone
    var device: String?        // iOS apps: the person's own phone (its udid) that Play puts the app on, if any
}

struct AppUsage: Codable {
    var calls = 0       // AI calls made by the app itself
    var cost = 0.0
    // Optional so usage.json files from before these were tracked still decode.
    var agentRuns: Int?
    var agentCost: Double?

    var totalCost: Double { cost + (agentCost ?? 0) }
}

struct LogLine: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case user, agent, status, error, detail, tool, summary, needsKey }
    var id = UUID()
    let kind: Kind
    var text: String
    var attachments: [String]? = nil   // names in the app's Attachments/ folder
    var version: String? = nil         // for a request: the version it made
    var before: String? = nil          // for a request: the version the app was at when it was sent
    var replaced: String? = nil        // for a request sent again in other words: the request it took the place of
    var tookBack: [String]? = nil      // …and every request that left the chat for it, oldest first

    /// Lamp knows where the app was before this request, so it can be changed and sent again from there.
    /// Not so for some requests from before that was noted.
    var canSendAgain: Bool { kind == .user && (before != nil || version != nil) }

    /// Hidden unless Agent Details is on.
    var isDetail: Bool { kind == .detail || kind == .tool || kind == .summary }

    /// "Worked for 4m 21s · $0.48"
    static func workSummary(seconds: Double, cost: Double) -> String {
        let total = Int(seconds.rounded())
        let time = total < 60 ? "\(total)s" : "\(total / 60)m \(total % 60)s"
        return String(format: "Worked for %@ · $%.2f", time, cost)
    }

    /// Older chats logged tool calls and run summaries as plain details, and named the engine in summaries.
    var upgraded: LogLine {
        guard kind == .detail || kind == .summary else { return self }
        if let match = text.firstMatch(of: #/^\S.* (?:done|error) · (\d+)s · \$([\d.]+)$/#),
           let seconds = Double(match.1), let cost = Double(match.2) {
            return LogLine(id: id, kind: .summary, text: Self.workSummary(seconds: seconds, cost: cost))
        }
        guard kind == .detail else { return self }
        if ToolCall(text).isKnown { return LogLine(id: id, kind: .tool, text: text) }
        return self
    }
}

/// A message typed while the app was busy. It waits in the chat until the current work finishes.
struct QueuedMessage: Identifiable {
    let id = UUID()
    let text: String
    var attachments: [URL] = []
    /// Files already in the app's Attachments folder: those of a request that's sent again.
    var kept: [String] = []
    /// The request this one takes the place of, when it's one sent again in other words.
    var replaces: String? = nil
    /// Every request that left the chat when this one was sent, oldest first.
    var tookBack: [String] = []
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var projects: [LampProject] = []
    @Published var selection: String? {
        didSet {
            markRead()
            if let oldValue, oldValue != selection { discardIfUnused(oldValue) }
        }
    }
    /// Apps whose chat finished a turn while you were looking elsewhere.
    @Published var unread: Set<String> = [] {
        didSet {
            Notifier.shared.setBadge(unread.count)
            for id in oldValue.subtracting(unread) { Notifier.shared.clear(id) }
        }
    }
    @Published var logs: [String: [LogLine]] = [:]
    @Published var busy: Set<String> = []
    @Published var queued: [String: [QueuedMessage]] = [:]
    /// The turn in progress for each app. A new app's first turn stays here after it finishes, so its
    /// build card can show the result until the next message.
    @Published var progress: [String: TurnProgress] = [:]
    /// Apps that are open right now, however they were started, so Lamp can offer to quit them.
    @Published var openApps: Set<String> = []
    /// Which Lamp built each installed app (see BuildStamp). Missing for apps that aren't built yet.
    @Published var stamps: [String: BuildStamp] = [:]
    @Published var chatFocusRequest = 0
    @Published var setup = SetupCheck()
    /// The welcome finished this run. Normally the saved setting says so too, but `-onboarded NO` on the
    /// command line (for checking the welcome) keeps that setting from changing until Lamp quits.
    @Published var welcomeFinished = false
    @Published var usage: [String: AppUsage] = [:]
    @Published var icons: [String: NSImage] = [:]
    @Published var pendingImport: PendingImport?

    /// A shell command an agent wants to run, or a file outside the app's folder it wants, waiting for the user
    /// (see ApprovalCard).
    struct PendingApproval: Identifiable {
        let id = UUID()
        let command: String
        /// A file request sets its own title; a command keeps this one.
        static let commandTitle = "Can the agent do this?"
        var title = commandTitle
        let answer: CheckedContinuation<Bool, Never>
        var explanation: CommandExplanation?
    }

    /// What a command does and how risky it is, in plain words for people who don't read shell commands.
    struct CommandExplanation {
        let summary: String
        let risk: String     // "low", "medium" or "high"
        let why: String
    }
    @Published var approvals: [String: PendingApproval] = [:]   // project id → the command waiting
    private var approving: Set<String> = []                       // project ids between the queue check and the card
    private var lastReloadForToken = Date.distantPast
    private var computerUseRefused: Set<String> = []   // apps told once this launch that using other apps is off
    /// The app whose Rename… alert is showing.
    @Published var renaming: LampProject?
    /// The app whose Delete confirmation is showing.
    @Published var deleting: LampProject?
    /// The version whose Name… alert is showing.
    @Published var naming: VersionNaming?
    /// Bumped when a version is named, so open version lists reload.
    @Published var versionsRevision = 0
    /// One span of Lamp owning an app: a chat turn, a rebuild, an undo, an icon redesign. Everything that
    /// belongs to that span lives here and goes with it, so Stop, Delete and quit have one thing to cancel,
    /// and nothing has to be kept in step across a dozen dictionaries. `busy` is the set of apps that have
    /// one, for the interface.
    @MainActor final class Turn {
        var agent: Process?                 // the engine, while it runs
        var build: Process?                 // the app's build.sh, while it runs
        var stopped = false                 // the user pressed Stop (or deleted the app, or quit Lamp)
        var allowAll = false                // "Allow all for this turn"
        var approving = false               // between the queue check and the approval card
        var look = Look()                   // what the agent's look_at_app has done
        var pendingName: String?            // a name the agent gave the version this request makes
        var request: String?                // the user's words, for the command classifiers
        var writing: (line: UUID, unshown: String)?   // the message the agent is writing right now
        var showingWritten = false
        /// The agent's token for this turn (Store.agentTokens): the only way to its routes.
        let agentToken = UUID().uuidString + UUID().uuidString

        var isWorking: Bool { agent != nil || build != nil }

        /// Stops what's running. Returns the processes signalled, for a caller that waits for them (quit).
        @discardableResult func cancel() -> [pid_t] {
            stopped = true
            allowAll = false
            var pids: [pid_t] = []
            if let agent { pids += Subprocess.terminateTree(agent) }
            if let build { pids += Subprocess.terminateTree(build) }
            return pids
        }
    }
    private var turns: [String: Turn] = [:]

    /// Takes the app for a span of work. Nil when something else has it.
    private func begin(_ project: LampProject) -> Turn? {
        guard turns[project.id] == nil else { return nil }
        let turn = Turn()
        turns[project.id] = turn
        agentTokens[turn.agentToken] = project.id
        busy.insert(project.id)
        return turn
    }

    /// Gives the app back, without starting anything queued (see `finish`).
    private func release(_ project: LampProject) {
        if let turn = turns.removeValue(forKey: project.id) { agentTokens[turn.agentToken] = nil }
        busy.remove(project.id)
    }

    /// Whether any app has an agent or a build going, for the question asked before quitting.
    var isWorking: Bool { turns.values.contains(where: \.isWorking) }

    /// Stops every agent and build, as when Lamp quits: otherwise they'd carry on without it. Returns the
    /// processes signalled, so quitting can wait until they're gone.
    func stopAll() -> [pid_t] {
        var pids: [pid_t] = []
        for project in projects {
            guard let turn = turns[project.id], turn.isWorking else { continue }
            endApprovals(for: project)
            pids += turn.cancel()
        }
        return pids + Subprocess.stopping
    }

    /// Whether the app still exists: a turn can outlive Delete by a moment, and mustn't write to the Trash.
    private func exists(_ project: LampProject) -> Bool { projects.contains { $0.id == project.id } }
    /// Apps whose versions are getting titles, so only one run at a time asks the model.
    private var titling: Set<String> = []

    /// What the agent's `look_at_app` tool has done during the current turn.
    struct Look {
        var inProgress = false
        /// The app was built and opened by the last look, and this is how that launch went.
        var installed = false
        var crash: String?
    }
    private var artInProgress: Set<String> = []
    private var pendingIconArt: Set<String> = []     // artwork finished during a turn, to apply after it
    private var artApplied: [String: IconSpec] = [:] // the spec whose artwork the rendered icon includes
    private var iconDesigns: [String: Task<Void, Never>] = [:]   // icons designed from the first message
    private var tokens: [String: String] = [:]   // app token → project id, for the app's own routes (/ai…)
    /// The agent's token for the turn in progress → project id. Minted per turn and gone with it, so the agent's
    /// routes (/agent/…, /mcp) can't be reached with the app's token, which the app itself holds, nor after the
    /// turn ends. A leaked app token then buys AI calls as that app, and nothing more.
    private var agentTokens: [String: String] = [:]
    private var gateway: Gateway?

    nonisolated static let installDir = Edition.appsFolder

    let root = Edition.supportFolder.appendingPathComponent("Apps")

    private init() {
        Migration.fromForge()
        Agent.syncKeyFile()   // keys an earlier Lamp left in pi's auth file come out of it
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
        restoreWaiting()
        for project in projects { discardIfUnused(project.id) }
        Onboarding.settle(hasApps: !projects.isEmpty)
        selection = projects.first?.id
        startGateway()
        watchOpenApps()
        refreshDevices()
        if !Provider.models.contains(where: { $0.id == UserDefaults.standard.string(forKey: "model") }) {
            UserDefaults.standard.set(Provider.model, forKey: "model")   // from the Claude Code era ("sonnet")
        }
        // Finding Claude Code / Codex means asking the login shell for PATH, then running each copy found with
        // --version to pick the newest; done off the main thread now, so the first turn doesn't wait for it.
        Task.detached(priority: .utility) {
            _ = ToolLocator.userPath
            for engine in Engine.allCases { _ = ToolLocator.path(for: engine) }
        }
        Task {
            LocalModels.shared.refresh()
            await LocalModels.shared.detectExternal()
            await recheckSetup()
        }
    }

    private var pollingSetup = false

    /// Re-checks setup. On a fresh Mac this opens Apple's installer straight away, then keeps
    /// checking in the background so setup finishes by itself once the tools are installed.
    func recheckSetup() async {
        let wasReady = setup.checked && setup.ready
        setup = await SetupCheck.run(keeping: setup)
        // During the welcome, Apple's installer waits for the step that explains it.
        if !setup.hasBuildTools && !setup.installRequested && Onboarding.isDone { requestBuildTools() }
        if !setup.hasBuildTools { pollSetup() }
        if setup.ready && !wasReady { await becameReady() }
    }

    func requestBuildTools() {
        SetupCheck.installBuildTools()
        setup.installRequested = true
        pollSetup()
    }

    /// Requests sent before setup finished (the welcome's first app) start now.
    private func becameReady() async {
        for project in projects where !(queued[project.id] ?? []).isEmpty { startQueued(project) }
        saveWaiting()
        await backfillIcons()
    }

    private func pollSetup() {
        guard !pollingSetup else { return }
        pollingSetup = true
        Task {
            defer { pollingSetup = false }
            while !setup.hasBuildTools {
                try? await Task.sleep(for: .seconds(5))
                setup = await SetupCheck.run(keeping: setup)
            }
            if setup.ready { await becameReady() }
        }
    }

    var selected: LampProject? { projects.first { $0.id == selection } }

    /// Clears the "ready" dot for the app on screen. Also called when Lamp comes back to the front.
    func markRead() {
        if let selection, NSApp?.isActive ?? true { unread.remove(selection) }
    }

    /// Lamp is in front with this app's chat on screen.
    func isWatching(_ id: String?) -> Bool {
        id != nil && selection == id && NSApp.isActive
    }

    func reload() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        projects = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(".lamp/meta.json")),
                  let meta = try? JSONDecoder().decode(ProjectMeta.self, from: data) else { return nil }
            return LampProject(id: dir.lastPathComponent, name: meta.name, exe: meta.exe, dir: dir,
                                untitled: meta.untitled ?? false, platform: meta.platform ?? .mac, family: meta.family ?? .iphone,
                                device: meta.device)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        for project in projects {
            tokens[Template.token(for: project)] = project.id
            if icons[project.id] == nil, let image = NSImage(contentsOf: Icons.previewURL(project)) {
                icons[project.id] = image
            }
        }
        for project in projects { stamps[project.id] = BuildStamp.read(project.installedURL) }
        for project in projects where logs[project.id] == nil {
            let lamp = project.dir.appendingPathComponent(".lamp")
            if let data = try? Data(contentsOf: lamp.appendingPathComponent("chat.json")),
               let saved = try? JSONDecoder().decode([LogLine].self, from: data) {
                logs[project.id] = saved.map(\.upgraded)
            }
            if let data = try? Data(contentsOf: lamp.appendingPathComponent("usage.json")),
               let saved = try? JSONDecoder().decode(AppUsage.self, from: data) {
                usage[project.id] = saved
            }
        }
    }

    func log(_ project: LampProject, _ kind: LogLine.Kind, _ text: String, attachments: [String]? = nil) {
        logs[project.id, default: []].append(LogLine(kind: kind, text: text, attachments: attachments))
        if kind == .status, text.hasSuffix("…") { note(text, for: project) }   // "Building…"
        saveChat(project)
    }

    private func saveChat(_ project: LampProject) {
        guard exists(project) else { return }
        if let data = try? JSONEncoder().encode(logs[project.id]) {
            try? data.write(to: project.dir.appendingPathComponent(".lamp/chat.json"))
        }
    }

    /// The message each app's agent is writing right now: its chat line, and text that has arrived but isn't
    /// in the chat yet.

    /// Adds a piece of the message the agent is writing, so it shows in the chat as it arrives. Pieces come
    /// twenty a second, and after a tool call the first few seconds' worth arrive all at once, so they go into
    /// the chat a few times a second rather than one by one: redrawing the chat for every piece keeps the
    /// main thread busy for seconds, and nothing shows until it has caught up. The message isn't saved
    /// until it's whole, since saving rewrites the chat's file.
    private func write(_ piece: String, for project: LampProject) {
        guard let turn = turns[project.id] else { return }
        guard turn.writing != nil else {
            guard !piece.trimmed.isEmpty else { return }
            let line = LogLine(kind: .agent, text: String(piece.drop(while: \.isWhitespace)))
            logs[project.id, default: []].append(line)
            turn.writing = (line.id, "")
            note("Replying", for: project)
            return
        }
        turn.writing?.unshown += piece
        guard !turn.showingWritten else { return }
        turn.showingWritten = true
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            turn.showingWritten = false
            showWritten(for: project)
        }
    }

    /// Puts what has arrived of the message being written into its chat line.
    private func showWritten(for project: LampProject) {
        guard let turn = turns[project.id], let (line, unshown) = turn.writing, !unshown.isEmpty,
              let index = logs[project.id]?.lastIndex(where: { $0.id == line }) else { return }
        logs[project.id]?[index].text += unshown
        turn.writing?.unshown = ""
    }

    /// Updates what the app's turn is doing right now, for the build card and the activity line.
    /// `file` is the file being written or edited, when that's the step.
    private func note(_ activity: String, file: String? = nil, for project: LampProject) {
        guard let current = progress[project.id], current.activity != activity || current.currentFile != file else { return }
        progress[project.id]?.activity = activity
        progress[project.id]?.currentFile = file
    }

    /// The installed app was built by an older Lamp and hasn't been rebuilt since.

    // MARK: - Drafts

    /// What's typed but not sent in an app's chat.
    struct Draft {
        var text = ""
        var attachments: [URL] = []
        /// The request in the chat this takes the place of when it's sent (see `sendAgain`).
        var replacing: UUID?
        /// What was in the message box before that request was taken back into it, put back if it isn't
        /// sent again after all.
        var setAsideText = ""
        var setAsideAttachments: [URL] = []
    }

    private var drafts: [String: Draft] = [:]

    /// Each app keeps its own draft, so it's still there after switching apps. The text also survives a
    /// restart (.lamp/draft.txt), and so do the request it replaces and the text that was set aside for it;
    /// attached files are only remembered while Lamp runs, so after a restart a replaced request has the
    /// files it was sent with.
    func draft(for project: LampProject) -> Draft {
        if let draft = drafts[project.id] { return draft }
        let lamp = project.dir.appendingPathComponent(".lamp")
        let text = try? String(contentsOf: lamp.appendingPathComponent("draft.txt"), encoding: .utf8)
        let id = (try? String(contentsOf: lamp.appendingPathComponent("draft-replaces"), encoding: .utf8)).flatMap(UUID.init)
        guard let line = (logs[project.id] ?? []).first(where: { $0.id == id && $0.canSendAgain }) else {
            return Draft(text: text ?? "")
        }
        let setAside = try? String(contentsOf: lamp.appendingPathComponent("draft-set-aside.txt"), encoding: .utf8)
        return Draft(text: text ?? "", attachments: Attachments.urls(line.attachments ?? [], in: project), replacing: line.id,
                     setAsideText: setAside ?? "")
    }

    func saveDraft(_ draft: Draft, for project: LampProject) {
        drafts[project.id] = draft
        // Written to disk a moment after typing stops, not on every keystroke.
        draftWrites[project.id]?.cancel()
        draftWrites[project.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.writeDraft(for: project)
        }
    }

    /// Writes every draft that's waiting for its pause, for when Lamp quits.
    func flushDrafts() {
        for project in projects where draftWrites[project.id] != nil {
            draftWrites[project.id]?.cancel()
            writeDraft(for: project)
        }
    }

    private var draftWrites: [String: Task<Void, Never>] = [:]

    private func writeDraft(for project: LampProject) {
        draftWrites[project.id] = nil
        guard exists(project), let draft = drafts[project.id] else { return }
        let file = project.dir.appendingPathComponent(".lamp/draft.txt")
        if draft.text.isEmpty {
            try? FileManager.default.removeItem(at: file)
        } else {
            try? draft.text.write(to: file, atomically: true, encoding: .utf8)
        }
        let replaces = project.dir.appendingPathComponent(".lamp/draft-replaces")
        if let id = draft.replacing {
            try? id.uuidString.write(to: replaces, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: replaces)
        }
        let setAside = project.dir.appendingPathComponent(".lamp/draft-set-aside.txt")
        if draft.replacing != nil, !draft.setAsideText.isEmpty {
            try? draft.setAsideText.write(to: setAside, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: setAside)
        }
    }

    func handle(url: URL) {
        if url.isFileURL && url.pathExtension == "lampapp" {
            importApp(from: url)
            return
        }
        guard url.scheme == Edition.urlScheme,
              let slug = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "app" })?.value else { return }
        showChat(slug)
    }

    /// Brings Lamp to the front on an app's chat, ready to type.
    func showChat(_ id: String) {
        reload()
        selection = id
        chatFocusRequest += 1
        NSApp.activate()
    }

    // MARK: - Actions

    /// New App: an untitled app, straight into its chat. Its first message names it and designs its icon.
    func create(platform: Platform = .mac, family preferred: DeviceFamily = .iphone) {
        guard platform == .mac || Experiments.iosApps else { return }   // Settings → Building → Experimental
        var family = preferred
        if platform == .iphone {
            // The app is for both devices: it opens on the preferred one, or on whichever this Mac can show.
            if Simulator.problem(family) != nil, Simulator.problem(family == .iphone ? .ipad : .iphone) == nil {
                family = family == .iphone ? .ipad : .iphone
            }
            if let problem = Simulator.problem(family) {
                let alert = NSAlert()
                alert.messageText = "Lamp can't build iPhone & iPad apps on this Mac yet"
                alert.informativeText = problem
                alert.runModal()
                return
            }
        }
        let project: LampProject
        do {
            project = try Template.scaffold(name: uniqueName("Untitled"), untitled: true, platform: platform, family: family, in: root)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        reload()
        selection = project.id
        chatFocusRequest += 1
        Task { await initRepo(project, message: "Scaffold") }
    }

    private func initRepo(_ project: LampProject, message: String) async {
        _ = await Shell.run("git init -q && git add -A && \(Self.commit) -qm \"$LAMP_MESSAGE\"", cwd: project.dir,
                            env: ["LAMP_MESSAGE": message]) { _ in }
    }

    /// Which simulator an iPhone & iPad app opens in. Takes effect at its next open; the app is quit first
    /// so the other device gets a fresh launch.
    /// Which of the person's own phones Play puts the app on, or nil for the simulator. The agent keeps
    /// looking at the simulator either way, since the phone's screen can't be photographed from here.
    func setDevice(_ project: LampProject, _ udid: String?) {
        guard project.platform == .iphone, project.device != udid, begin(project) != nil else { return }
        var changed = project
        changed.device = udid
        try? JSONEncoder().encode(ProjectMeta(name: changed.name, exe: changed.exe, untitled: changed.untitled ? true : nil,
                                              platform: changed.platform, family: changed.family, device: udid))
            .write(to: changed.dir.appendingPathComponent(".lamp/meta.json"))
        if let index = projects.firstIndex(where: { $0.id == project.id }) { projects[index] = changed }
        let name = devices.first(where: { $0.udid == udid })?.name
        log(changed, .status, name.map { "\(changed.name) will open on \($0) from now on. Press Play to put it there." }
                               ?? "\(changed.name) will open on the \(changed.family.name) simulator from now on.")
        finish(changed)
    }

    /// Back to a simulator from a phone, as one change: the family is set on the project as it is after
    /// the phone is forgotten, not on the copy the menu held.
    func setSimulator(_ project: LampProject, _ family: DeviceFamily) {
        setDevice(project, nil)
        if let current = projects.first(where: { $0.id == project.id }) { setFamily(current, family) }
    }

    /// The person's paired iPhones and iPads, for Try On. Looked up when the list is wanted (opening the
    /// menu) and at startup; a phone that's gone stays chosen, and Play says so.
    @Published var devices: [Devices.Device] = []

    /// What Try On shows beside Play: the simulator's kind, or the chosen phone's name.
    func tryOnName(_ project: LampProject) -> String {
        guard Experiments.devices, let udid = project.device else { return project.family.name }
        return devices.first(where: { $0.udid == udid })?.name ?? "Your phone"
    }

    /// Pairs a plugged-in phone that hasn't trusted this Mac yet, then lists again. Told in the app's chat,
    /// where the person is looking, as the Try On menu is the app's.
    func pairDevice(_ device: Devices.Device, for project: LampProject) {
        guard !pairing.contains(device.udid) else { return }
        pairing.insert(device.udid)
        log(project, .status, "Look at \(device.name): tap Trust when it asks, and enter its passcode.")
        Task {
            defer { pairing.remove(device.udid) }
            // The chat may have moved meanwhile: a first message renames a new app under a new id.
            @MainActor func tell(_ kind: LogLine.Kind, _ text: String) { if let now = current(project) { log(now, kind, text) } }
            do {
                try await Devices.pair(device.udid)
                devices = await Devices.list()
                guard let paired = devices.first(where: { $0.udid == device.udid }), paired.paired else {
                    // Paired, as far as devicectl said, but not in the list now: unplugged, or the listing
                    // failed. Not a word about Developer Mode until the phone is seen again.
                    tell(.status, "\(device.name) said yes, but it isn't in the list now. Plug it in, unlock it and choose Look for Devices Again under Try On.")
                    return
                }
                if paired.developerMode {
                    tell(.status, "\(device.name) is paired with this Mac. Choose it under Try On and press Play.")
                } else {
                    tell(.status, "\(device.name) is paired with this Mac. Now turn on Developer Mode on it (Settings → Privacy & Security → Developer Mode; the phone restarts), then choose it under Try On.")
                }
            } catch {
                tell(.error, error.localizedDescription)
                devices = await Devices.list()
            }
        }
    }

    /// Phones being paired right now, so the menu doesn't offer it twice.
    @Published var pairing: Set<String> = []

    func refreshDevices() {
        guard Experiments.devices else { if !devices.isEmpty { devices = [] }; return }
        Task {
            let found = await Devices.list()
            if found != devices { devices = found }
        }
    }

    func setFamily(_ project: LampProject, _ family: DeviceFamily) {
        guard project.platform == .iphone, project.family != family, begin(project) != nil else { return }
        var changed = project
        changed.family = family
        try? JSONEncoder().encode(ProjectMeta(name: changed.name, exe: changed.exe, untitled: changed.untitled ? true : nil,
                                              platform: changed.platform, family: family, device: changed.device))
            .write(to: changed.dir.appendingPathComponent(".lamp/meta.json"))
        // In the list straight away, so nothing that starts meanwhile sees the old choice; the app itself is
        // quit so its next open is a fresh launch on the other device.
        if let index = projects.firstIndex(where: { $0.id == project.id }) { projects[index] = changed }
        Task {
            await quit(changed)
            log(changed, .status, "\(changed.name) will open on the \(family.name) simulator from now on.")
            finish(changed)
        }
    }

    /// An untitled app you left without ever using is deleted, so trying New App leaves nothing behind.
    private func discardIfUnused(_ id: String) {
        guard let project = projects.first(where: { $0.id == id }), project.untitled,
              (logs[id] ?? []).isEmpty, queued[id] == nil, !busy.contains(id),
              !FileManager.default.fileExists(atPath: project.builtURL.path) else { return }
        try? FileManager.default.removeItem(at: project.dir)
        projects.removeAll { $0.id == id }
    }

    /// Nothing has happened in the app but its scaffold, so it can still change its folder and executable name.
    private func isPristine(_ project: LampProject) async -> Bool {
        var output: [String] = []
        let status = await Shell.run("test $(git rev-list --count HEAD) -eq 1 && git status --porcelain -- . ':!\(Attachments.folder)'",
                                     cwd: project.dir) { output.append($0) }
        return status == 0 && output.allSatisfy { $0.trimmed.isEmpty }
    }

    /// Renames an app. Before any work happens it is scaffolded afresh under the new name, so its folder,
    /// executable and bundle ID match. After that only the display name changes: the bundle ID stays,
    /// so the app keeps its settings and data. Returns the app as it is now.
    func rename(_ project: LampProject, to name: String) async {
        guard begin(project) != nil else { return }
        finish(await performRename(project, to: name))
    }

    /// Renames while the app is marked busy, so nothing else starts on it meanwhile.
    private func performRename(_ project: LampProject, to rawName: String) async -> LampProject {
        let name = rawName.trimmed.filter { !"\"\\<>&/:".contains($0) }
        guard !name.isEmpty, name != project.name || project.untitled,
              let current = projects.first(where: { $0.id == project.id }) else { return project }
        let unique = uniqueName(name, ignoring: current.id)
        if await isPristine(current) {
            return await rescaffold(current, as: unique)
        }

        let fm = FileManager.default
        let renamed = LampProject(id: current.id, name: unique, exe: current.exe, dir: current.dir, platform: current.platform,
                                  family: current.family, device: current.device)
        try? JSONEncoder().encode(ProjectMeta(name: unique, exe: current.exe, platform: current.platform, family: current.family, device: current.device))
            .write(to: current.dir.appendingPathComponent(".lamp/meta.json"))
        if fm.fileExists(atPath: current.installedURL.path) {
            try? fm.moveItem(at: current.installedURL, to: renamed.installedURL)
            _ = await Shell.run(Self.lsregister + " -f \"$LAMP_APP\"", cwd: current.dir,
                                env: ["LAMP_APP": renamed.installedURL.path]) { _ in }
        }
        // The old name in window titles and APP.md. Anything subtler is left for the agent.
        let sources = current.dir.appendingPathComponent("Sources")
        let files = (fm.enumerator(at: sources, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "LampSupport.swift" }
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let updated = text.replacingOccurrences(of: "\"\(current.name)\"", with: "\"\(unique)\"")
            if updated != text { try? updated.write(to: file, atomically: true, encoding: .utf8) }
        }
        let appMd = current.dir.appendingPathComponent("APP.md")
        if let text = try? String(contentsOf: appMd, encoding: .utf8), text.hasPrefix("# \(current.name)\n") {
            try? ("# \(unique)\n" + text.dropFirst(current.name.count + 3)).write(to: appMd, atomically: true, encoding: .utf8)
        }
        _ = await Shell.run("git add -A && \(Self.commit) -qm \"$LAMP_MESSAGE\"", cwd: current.dir,
                            env: ["LAMP_MESSAGE": "Rename to \(unique)"]) { _ in }
        reload()
        log(renamed, .status, "Renamed to \(unique)")
        return renamed
    }

    /// Replaces an untouched app with a fresh scaffold under its new name, carrying over its chat and queue.
    private func rescaffold(_ old: LampProject, as name: String) async -> LampProject {
        let fm = FileManager.default
        let project: LampProject
        do {
            project = try Template.scaffold(name: name, platform: old.platform, family: old.family, in: root)
        } catch {
            NSAlert(error: error).runModal()
            return old
        }
        for path in [".lamp/chat.json", ".lamp/usage.json", Attachments.folder] {
            let from = old.dir.appendingPathComponent(path)
            if fm.fileExists(atPath: from.path) {
                try? fm.copyItem(at: from, to: project.dir.appendingPathComponent(path))
            }
        }
        await initRepo(project, message: "Scaffold")
        await quit(old)
        try? fm.removeItem(at: old.installedURL)
        try? fm.removeItem(at: old.dir)

        if let device = old.device {   // the phone chosen before the first message stays chosen
            try? JSONEncoder().encode(ProjectMeta(name: project.name, exe: project.exe, platform: project.platform,
                                                  family: project.family, device: device))
                .write(to: project.dir.appendingPathComponent(".lamp/meta.json"))
        }
        // Rewritten so every entry points straight at the latest id: a slug that comes free and is used
        // again (A → B → A) would otherwise close a loop. Nothing points at the new id afterwards.
        for (from, to) in moved where to == old.id { moved[from] = project.id }
        moved = moved.filter { $0.key != project.id }
        moved[old.id] = project.id
        logs[project.id] = logs.removeValue(forKey: old.id)
        usage[project.id] = usage.removeValue(forKey: old.id)
        queued[project.id] = queued.removeValue(forKey: old.id)
        if let turn = turns.removeValue(forKey: old.id) {   // the rename itself is a turn: it moves with the app
            turns[project.id] = turn
            agentTokens[turn.agentToken] = project.id
            busy.remove(old.id)
            busy.insert(project.id)
        }
        if unread.remove(old.id) != nil { unread.insert(project.id) }
        tokens = tokens.filter { $0.value != old.id }
        reload()
        if selection == old.id { selection = project.id }
        return project
    }

    /// Where an app's chat went when its first message rescaffolded it under a new id, so something started
    /// on the old app (pairing a phone, say) can still speak in the right chat.
    private var moved: [String: String] = [:]

    /// The app as it is now, following any rescaffold since `project` was taken (one step: `moved` always
    /// points straight at the latest id).
    private func current(_ project: LampProject) -> LampProject? {
        projects.first { $0.id == moved[project.id] ?? project.id }
    }

    /// Display names must be unique: each app installs as "<name>.app" in the apps folder (Edition.appsFolder).
    private func uniqueName(_ name: String, ignoring id: String? = nil) -> String {
        let taken = Set(projects.filter { $0.id != id }.map { $0.name.lowercased() })
        let base = name.trimmed
        var candidate = base
        var n = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(base) \(n)"
            n += 1
        }
        return candidate
    }

    // MARK: - Sharing

    func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.lampApp]
        panel.message = "Choose a Lamp app someone shared with you"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importApp(from: url)
    }

    /// Puts the app's .lampapp file on the clipboard, ready to paste into Slack, Messages, Mail or Finder.
    /// Sharing is for Mac apps: an iPhone app's file would be opened as a Mac app by another Lamp.
    func canShare(_ project: LampProject) -> Bool { project.platform == .mac }

    func copyAppFile(_ project: LampProject) {
        guard canShare(project) else { return }
        do {
            let exported = try Sharing.export(project)
            let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Forge/Shared", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(exported.lastPathComponent)
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: exported, to: file)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([file as NSURL])
            log(project, .status, "Copied \(file.lastPathComponent). Paste it into Slack, Messages, Mail or a Finder window.")
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func chooseExport(_ project: LampProject) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.lampApp]
        panel.nameFieldStringValue = "\(project.name).lampapp"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let file = try Sharing.export(project)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: file, to: destination)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    struct PendingImport: Identifiable {
        let id = UUID()
        let package: Sharing.Package
        var review: ImportReview?
    }

    /// Opens a shared `.lampapp`: unpacks it, then shows a review (fixed checklist + AI check) before building.
    func importApp(from file: URL) {
        NSApp.activate()
        guard setup.ready else {
            let alert = NSAlert()
            alert.messageText = "Finish setting up Lamp first"
            alert.informativeText = "Then open the shared app again."
            alert.runModal()
            return
        }
        // The newest request wins: a file opened while an earlier one is still unpacking, or a Cancel
        // meanwhile, makes the earlier result unwanted when it arrives.
        let request = UUID()
        importRequest = request
        if let previous = pendingImport { try? FileManager.default.removeItem(at: previous.package.folder) }
        pendingImport = nil
        Task {
            // Unpacking is a process and some file reads: off the main actor, so Lamp stays responsive.
            let package: Sharing.Package
            do {
                package = try await Task.detached { try Sharing.open(file) }.value
            } catch {
                if importRequest == request { NSAlert(error: error).runModal() }
                return
            }
            guard importRequest == request else { try? FileManager.default.removeItem(at: package.folder); return }
            let pending = PendingImport(package: package)
            pendingImport = pending
            let review = await Sharing.review(package)
            if pendingImport?.id == pending.id { pendingImport?.review = review }
        }
    }

    private var importRequest: UUID?

    func cancelImport() {
        importRequest = nil
        if let pending = pendingImport { try? FileManager.default.removeItem(at: pending.package.folder) }
        pendingImport = nil
    }

    func confirmImport() {
        guard let pending = pendingImport else { return }
        importRequest = nil
        pendingImport = nil
        finishImport(pending.package)
    }

    private func finishImport(_ package: Sharing.Package) {
        defer { try? FileManager.default.removeItem(at: package.folder) }
        let fm = FileManager.default
        let project: LampProject
        do {
            project = try Template.scaffold(name: uniqueName(package.name), in: root)
            // Swap the scaffold's code for the shared code; keep Lamp's own LampSupport.swift.
            let sources = project.dir.appendingPathComponent("Sources")
            for item in try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            where item.lastPathComponent != "LampSupport.swift" {
                try fm.removeItem(at: item)
            }
            let sharedSources = package.folder.appendingPathComponent("Sources").standardizedFileURL.path + "/"
            for file in package.sources where file.lastPathComponent != "LampSupport.swift" {
                let relative = file.standardizedFileURL.path.replacingOccurrences(of: sharedSources, with: "")
                guard !relative.contains("..") else { continue }
                let target = sources.appendingPathComponent(relative)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: file, to: target)
            }
            if !package.attachments.isEmpty {
                let folder = project.dir.appendingPathComponent(Attachments.folder)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                for file in package.attachments {
                    try fm.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
                }
            }
            let appMd = package.folder.appendingPathComponent("APP.md")
            if fm.fileExists(atPath: appMd.path) {
                try? fm.removeItem(at: project.dir.appendingPathComponent("APP.md"))
                try fm.copyItem(at: appMd, to: project.dir.appendingPathComponent("APP.md"))
            }
            if let data = try? Data(contentsOf: package.folder.appendingPathComponent("icon.json")),
               let spec = try? JSONDecoder().decode(IconSpec.self, from: data) {
                Icons.save(spec, for: project)
                // Files from older Lamp versions carry full-square artwork; only cut-out objects fit the new icons.
                if let art = try? Data(contentsOf: package.folder.appendingPathComponent("icon-art.png")),
                   Icons.isCutOut(art) {
                    let url = Icons.artURL(project, spec: spec)
                    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? art.write(to: url)
                }
            }
        } catch {
            NSAlert(error: error).runModal()
            return
        }

        reload()
        selection = project.id
        log(project, .status, "Imported from a shared file. Building it now…")
        Task {
            _ = await Shell.run("git init -q && git add -A && \(Self.commit) -qm 'Imported from a shared file'",
                                cwd: project.dir) { _ in }
            await run(project)
        }
    }

    /// Sends a message, or queues it while the app is busy. Everything queued goes out together
    /// as the next turn, so several quick follow-ups cost one agent run and one rebuild.
    func send(_ prompt: String, attachments: [URL] = [], to project: LampProject) {
        // Waiting for setup can outlast this run, and the files may be temporary (a pasted screenshot):
        // keep copies, so the request still has them after a relaunch.
        let files = setup.ready ? attachments : keepForLater(attachments)
        queued[project.id, default: []].append(QueuedMessage(text: prompt, attachments: files))
        startQueued(project)
        saveWaiting()
    }

    /// Requests waiting for setup (the welcome's first app, while Apple's tools install), kept on disk so
    /// quitting meanwhile doesn't lose them: they come back on the next launch and start once setup is done.
    private static let waitingKey = "waitingRequests"

    /// Where waiting requests' files are kept until their build starts.
    private var waitingFiles: URL { root.deletingLastPathComponent().appendingPathComponent("Waiting") }

    /// Each file gets a folder of its own, so two with the same name (two "Dropped image.png") both keep a copy.
    private func keepForLater(_ files: [URL]) -> [URL] {
        files.map { file in
            let folder = waitingFiles.appendingPathComponent(UUID().uuidString)
            let copy = folder.appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return (try? FileManager.default.copyItem(at: file, to: copy)) != nil ? copy : file
        }
    }

    private func saveWaiting() {
        let waiting = setup.ready ? [:] : queued.filter { !$0.value.isEmpty }.mapValues { messages in
            messages.map { ["text": $0.text, "attachments": $0.attachments.map(\.path)] as [String: Any] }
        }
        if waiting.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.waitingKey)
        } else {
            UserDefaults.standard.set(waiting, forKey: Self.waitingKey)
        }
    }

    /// Brings back requests that were waiting for setup when Lamp last quit. Kept files no waiting request
    /// needs any more (its build has started, or it was taken back) are cleared out.
    private func restoreWaiting() {
        var kept = Set<String>()
        if let waiting = UserDefaults.standard.dictionary(forKey: Self.waitingKey) as? [String: [[String: Any]]] {
            for (id, messages) in waiting where projects.contains(where: { $0.id == id }) {
                queued[id] = messages.map { message in
                    let files = (message["attachments"] as? [String] ?? []).filter { FileManager.default.fileExists(atPath: $0) }
                    kept.formUnion(files.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path })
                    return QueuedMessage(text: message["text"] as? String ?? "", attachments: files.map(URL.init(fileURLWithPath:)))
                }
            }
        }
        let folders = (try? FileManager.default.contentsOfDirectory(at: waitingFiles, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where !kept.contains(folder.path) { try? FileManager.default.removeItem(at: folder) }
    }

    /// The version label for a request without words: what was sent.
    static func label(attachments names: [String]) -> String {
        "Sent \(names.count == 1 ? names[0] : "\(names.count) files")"
    }

    static func label(for line: LogLine) -> String {
        line.text.isEmpty ? label(attachments: line.attachments ?? []) : line.text
    }

    /// The first message bootstraps the app: it names an untitled app, then designs the icon
    /// while the agent builds the first version. Returns the app as it is now.
    private func bootstrap(_ project: LampProject, brief: String) async -> LampProject {
        var project = project
        if project.untitled, let name = await AppName.suggest(for: brief) {
            project = await performRename(project, to: name)
        }
        if Icons.load(project) == nil {
            let designing = project
            iconDesigns[project.id] = Task {
                let spec = await Icons.design(for: designing, brief: brief)
                if Icons.load(designing) == nil {
                    Icons.save(spec, for: designing)
                    await renderIcon(designing, spec: spec)
                    // The artwork takes a minute or two; the build takes longer. Started now, it's usually
                    // there by the time the app first opens, instead of swapping in afterwards.
                    upgradeIconArt(designing)
                }
                iconDesigns[designing.id] = nil
            }
        }
        return project
    }

    func unqueue(_ message: QueuedMessage, from project: LampProject) {
        queued[project.id]?.removeAll { $0.id == message.id }
        saveWaiting()
    }

    private func startQueued(_ project: LampProject) {
        guard setup.ready, let messages = queued[project.id], !messages.isEmpty,
              begin(project) != nil else { return }
        queued[project.id] = nil
        let first = !(logs[project.id] ?? []).contains { $0.kind == .user }
        // Still a new app until a request has made its first version: after the agent only asked questions,
        // the answers start the build and get the build card. An imported app has already been built.
        let newApp = Template.isScaffold(project) && !hasVersions(project)
        progress[project.id] = TurnProgress(newApp: newApp)
        Task {
            var project = project
            let saved = post(messages, to: project)
            let asked = (logs[project.id] ?? []).filter { $0.kind == .user }.suffix(messages.count).map(\.id)
            if first {
                let untitled = project
                let words = messages.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
                let brief = words.isEmpty
                    ? "An app made from the attached file\(saved.count == 1 ? "" : "s"): \(saved.joined(separator: ", "))"
                    : words
                project = await bootstrap(project, brief: brief)
                if project.id != untitled.id { progress[project.id] = progress.removeValue(forKey: untitled.id) }
            }
            // Where the app is as the turn starts, so the request can be changed and sent again from here.
            if let head = await Versions.head(project) { mark(asked, sentFrom: head, in: project) }
            var worked = false
            var result = TurnResult(end: .failed, watched: true)
            defer {
                // A new app's card stays, showing the result; a later turn's activity line goes away. So does a
                // new app's card when the agent only asked questions: nothing was built, and the answers bring it back.
                if newApp && result.end != .replied {
                    progress[project.id]?.finish(worked: worked)
                } else {
                    progress[project.id] = nil
                }
                if selection != project.id || !NSApp.isActive { unread.insert(project.id) }
                // Messages queued meanwhile start the next turn straight away; tell the user once it's all done.
                if !result.watched, (queued[project.id] ?? []).isEmpty { notify(project, after: result.end) }
                finish(project)
            }
            result = await turn(messages, attachments: saved, asked: asked, on: project)
            worked = result.end != .failed
            if newApp && result.end == .changed { await showResult(of: project) }
        }
    }

    /// Puts the app's real window on its build card, once it has opened and saved a picture of itself.
    private func showResult(of project: LampProject) async {
        guard let started = progress[project.id]?.started,
              NSRunningApplication.runningApplications(withBundleIdentifier: project.bundleID).first != nil,
              let picture = await Runtime.screenshots(of: project, since: started, waiting: 4).first,
              let image = NSImage(contentsOf: picture) else { return }
        progress[project.id]?.screenshot = image
    }

    /// Posts a notification for a turn that ended while the user was looking elsewhere.
    /// Nothing for a turn the user stopped: it ends without an error.
    private func notify(_ project: LampProject, after end: TurnEnd) {
        let turnLines = (logs[project.id] ?? []).reversed().prefix { $0.kind != .user }
        // An error wins: even a turn that otherwise worked (say, the app couldn't be installed) needs the user.
        if let error = turnLines.first(where: { $0.kind == .error }) {
            Notifier.shared.post(for: project, subtitle: "Needs your attention", body: error.text)
            return
        }
        let reply = turnLines.first { $0.kind == .agent }.map { Self.plain($0.text) }
        switch end {
        case .changed:
            Notifier.shared.post(for: project, subtitle: "Your change is ready", body: reply ?? "It's built and open.")
        case .replied:
            Notifier.shared.post(for: project, subtitle: "Replied", body: reply ?? "")
        case .failed:
            break
        }
    }

    /// An agent reply without its Markdown, short enough for a notification.
    private static func plain(_ markdown: String) -> String {
        let text = markdown
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: #"(?m)^#+\s*"#, with: "", options: .regularExpression)
            .split(whereSeparator: \.isNewline).joined(separator: " ")
        return text.count > 240 ? String(text.prefix(239)) + "…" : text
    }

    /// Marks the app idle again, then starts anything queued while it was busy.
    private func finish(_ project: LampProject) {
        endApprovals(for: project)   // a card nobody can answer any more, from a request that raced the agent's end
        // Artwork that arrived during the turn, for an icon that was installed without it: applied now, still
        // owning the app, so nothing else builds or installs meanwhile. With more work queued, the next
        // install picks the artwork up itself.
        if pendingIconArt.contains(project.id), (queued[project.id] ?? []).isEmpty,
           let spec = Icons.load(project), artApplied[project.id] != spec {
            pendingIconArt.remove(project.id)
            Task {
                await applyIconArt(project, spec: spec)
                release(project)
                startQueued(project)
            }
            return
        }
        release(project)
        startQueued(project)
    }

    /// Renders the icon with its artwork and installs it, when there's a built app to install it into;
    /// otherwise the artwork waits in the cache for the first successful build.
    private func applyIconArt(_ project: LampProject, spec: IconSpec) async {
        await renderIcon(project, spec: spec)
        let executable = project.builtURL.appendingPathComponent("Contents/MacOS/\(project.exe)")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return }
        try? await deploy(project)
        log(project, .status, "New icon artwork is in. It shows in the Dock after the app restarts.")
    }

    /// Puts the messages in the chat and their files in Attachments/. Returns the saved file names.
    private func post(_ messages: [QueuedMessage], to project: LampProject) -> [String] {
        var saved: [String] = []
        for message in messages {
            let names = message.kept + Attachments.save(message.attachments, to: project)
            log(project, .user, message.text, attachments: names.isEmpty ? nil : names)
            if message.replaces != nil || !message.tookBack.isEmpty, let last = logs[project.id]?.indices.last {
                logs[project.id]?[last].replaced = message.replaces
                logs[project.id]?[last].tookBack = message.tookBack.isEmpty ? nil : message.tookBack
                saveChat(project)
            }
            saved += names
        }
        return saved
    }

    /// How a turn ended: the app changed, the agent only replied, or there's no working app
    /// (the agent couldn't run or was stopped, or the app won't build or open).
    enum TurnEnd { case changed, replied, failed }

    struct TurnResult {
        var end: TurnEnd
        /// The user had this app's chat on screen, so there's nothing to notify about.
        var watched: Bool
    }

    /// One turn of the loop: agent edits → build (agent fixes failures) → commit → relaunch.
    /// `asked` are the chat lines of the requests, which are linked to the version the turn makes.
    private func turn(_ messages: [QueuedMessage], attachments saved: [String], asked: [UUID],
                      on project: LampProject) async -> TurnResult {
        var prompt = messages.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
        // Attachments with no words: usually a screenshot or mockup meaning "like this", or a file to use.
        if prompt.isEmpty {
            prompt = """
            The user sent only the attached file\(saved.count == 1 ? "" : "s"), with no message. Work out what \
            they most likely want from it: a screenshot or mockup usually means "make the app look or work like \
            this" (or, if it shows this app, "fix what's wrong here"); a document or data file usually means \
            "use this in the app". If it's clear, do it. If it could mean several different things, ask one \
            short question instead of guessing.
            """
        }

        let files = Attachments.inline(saved, in: project).map { "\(Attachments.folder)/\($0)" }
        // After a request is sent again the build on disk is still of the code that was just taken back, so
        // its picture and its crashes say nothing about the files the agent has now.
        let sentAgain = messages.contains { $0.replaces != nil || !$0.tookBack.isEmpty }
        let notes = Attachments.note(for: saved) + Versions.note(for: project)
            + (sentAgain ? "" : Runtime.crashNote(for: project) + Runtime.screenshotNote(for: project))
        turns[project.id]?.request = prompt
        let ran = await runAgent(prompt + notes, files: files, on: project)
        // The note about going back is the agent's only word of it, so it's kept until the agent has had it:
        // a turn that failed before reaching the agent leaves it for the next one.
        if let last = asked.last, Self.reachedAgent(last, in: logs[project.id] ?? []) { Versions.forgetNote(for: project) }
        guard ran else {
            return TurnResult(end: .failed, watched: isWatching(project.id))
        }
        // A new app the agent didn't touch: it only replied (say, with questions about a vague request).
        // There's nothing worth building or opening yet; the answers start the first build.
        if !hasVersions(project), await !agentChangedFiles(project) {
            return TurnResult(end: .replied, watched: isWatching(project.id))
        }
        // Only build when something changed: not after a question, and not again when the agent's last
        // look already built and opened exactly this code.
        try? Template.writeSupport(for: project)
        let changed = Runtime.sourcesChanged(project)
        if changed {
            guard await buildFixingErrors(project) else { return TurnResult(end: .failed, watched: isWatching(project.id)) }
        }
        // Opening the app brings it in front of Lamp, so whether the user was watching is decided first.
        let watched = isWatching(project.id)
        // Nothing is committed when the agent changed no files.
        let label = messages.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n").nilIfEmpty
            ?? Self.label(attachments: saved)
        var committed = await Shell.run("git add -A && \(Self.commit) -qm \"$LAMP_PROMPT\"", cwd: project.dir,
                                        env: ["LAMP_PROMPT": label]) { _ in } == 0
        let edited = changed || committed
        var crash: String?
        if changed {
            crash = await install(project)
        } else if let look = turns[project.id]?.look, look.installed {
            crash = look.crash
            if crash == nil {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: project.bundleID).first {
                    // The look opened it behind the user's windows. Now it's theirs: it shows itself, as when it's
                    // opened again. An app that lives in the menu bar opens its panel (see LampWindows).
                    DistributedNotificationCenter.default().postNotificationName(
                        Notification.Name(Edition.notificationPrefix + "showWindow"), object: project.bundleID, userInfo: nil, deliverImmediately: true)
                    app.activate()
                    log(project, .status, "\(project.name) is ready")
                } else {
                    crash = await install(project)
                }
            }
        }
        // Like build errors, a crash on launch goes back to the agent. The fix joins this turn's commit,
        // so Undo still reverts the whole change.
        for _ in 0..<2 where crash != nil {
            log(project, .status, "Fixing the crash…")
            guard await runAgent("The app builds, but it quit right after launching. Find the cause and fix it.\n\n\(crash!)",
                                 on: project),
                  await buildFixingErrors(project) else { return TurnResult(end: .failed, watched: watched) }
            let commit = committed ? "-q --amend --no-edit" : "-qm 'Fix a crash on launch'"
            if await Shell.run("git add -A && \(Self.commit) \(commit)", cwd: project.dir) { _ in } == 0 { committed = true }
            crash = await install(project)
        }
        if crash != nil {
            log(project, .error, ErrorMessages.quitsAfterLaunch(project.name))
        }
        // After the crash fixes, which amend the commit, so the name and the links stay on the version that's kept.
        if committed || turns[project.id]?.pendingName != nil, let head = await Versions.head(project) {
            if let name = turns[project.id]?.pendingName {
                turns[project.id]?.pendingName = nil
                await Versions.name(project, head, name)
            }
            if committed {
                link(asked, to: head, in: project)
                if crash == nil { keepPicture(of: project, version: head) }
                titleVersions(project, limit: 1)
            }
            versionsRevision += 1
        }
        return TurnResult(end: crash != nil ? .failed : edited ? .changed : .replied, watched: watched)
    }

    /// Whether any request has made a version of this app yet (its messages are linked to the versions they made).
    private func hasVersions(_ project: LampProject) -> Bool {
        (logs[project.id] ?? []).contains { $0.kind == .user && $0.version != nil }
    }

    /// Whether the agent changed any of the app's files this turn. Lamp's own writes don't count: it
    /// regenerates LampSupport.swift, designs the icon (icon.json) while the agent works, and saves the
    /// request's attachments before the agent starts.
    private func agentChangedFiles(_ project: LampProject) async -> Bool {
        var output = ""
        let ignored = "':!Sources/LampSupport.swift' ':!icon.json' ':!\(Attachments.folder)'"
        _ = await Shell.run("git status --porcelain -- . \(ignored)", cwd: project.dir) {
            output += $0
        }
        return !output.trimmed.isEmpty
    }

    /// Builds the app, sending compiler errors back to the agent up to three times. False when it still doesn't build.
    private func buildFixingErrors(_ project: LampProject) async -> Bool {
        var errors = await build(project)
        for _ in 0..<3 where errors != nil {
            // A build the user stopped (or whose app they deleted) isn't a problem for the agent to fix.
            guard turns[project.id]?.stopped != true, exists(project) else { return false }
            log(project, .status, "Fixing a problem…")
            guard await runAgent("The app failed to build. Fix these compiler errors:\n\n\(errors!)",
                                 on: project) else { return false }
            errors = await build(project)
        }
        guard turns[project.id]?.stopped != true, exists(project) else { return false }
        if errors != nil {
            log(project, .error, ErrorMessages.buildFailed)
        }
        return errors == nil
    }

    /// Returns false when the agent couldn't run at all (bad key, no credit, …), after telling the user why.
    private func runAgent(_ prompt: String, files: [String] = [], on project: LampProject) async -> Bool {
        try? Template.writeSupport(for: project)
        if let problem = Builder.problem() {
            log(project, .error, "\(problem) Open Lamp → Settings (⌘,) to fix it.")
            return false
        }
        let engine = Builder.engine
        if engine == .pi && Builder.piProvider == Builder.localProvider {
            do {
                try await LocalModels.shared.ensureServer(for: Builder.piModel)
            } catch {
                log(project, .error, error.localizedDescription)
                return false
            }
        }
        let started = Date()
        var cost = 0.0
        var failure: String?
        // Guard against runaway agents (small local models can loop): stop after the same step 6 times
        // in a row, or 150 tool calls in one turn.
        var lastTool = ""
        var repeats = 0
        var toolCalls = 0
        // The tool call the model is writing at the moment, for the activity shown to the user.
        var streamingTool = ""
        var streamingArguments = ""
        guard let turn = turns[project.id] else { return false }   // only inside a turn (startQueued)
        turn.stopped = false
        let sessionFile = Self.sessionFile(for: project, engine: engine)
        let run = Agent.run(prompt: prompt, files: files, project: project,
                            session: engine == .pi ? Self.piSession(for: project) : Self.savedSession(sessionFile),
                            token: turn.agentToken)
        let status = await Shell.run(run.command, cwd: project.dir, env: run.env,
                                     started: { turn.agent = $0 }) { [weak self] line in
            guard let self else { return }
            for event in Agent.parseLine(line) {
                switch event {
                case .textPiece(let piece):
                    write(piece, for: project)
                case .text(let text):
                    // The whole message. It takes the place of what was shown of it while it was written.
                    let written = turn.writing?.line
                    turn.writing = nil
                    if let line = written, let index = logs[project.id]?.lastIndex(where: { $0.id == line }) {
                        logs[project.id]?[index].text = text
                        saveChat(project)
                    } else {
                        log(project, .agent, text)
                    }
                case .step(let tool):
                    streamingTool = tool
                    streamingArguments = ""
                    note(TurnProgress.activity(tool: tool, partialArguments: ""), for: project)
                case .stepArgs(let piece):
                    // The file name is among the first arguments; the rest is the file itself.
                    guard streamingArguments.count < 600 else { break }
                    streamingArguments += piece
                    let call = TurnProgress.call(tool: streamingTool, partialArguments: streamingArguments)
                    note(TurnProgress.activity(for: call), file: TurnProgress.file(changedBy: call), for: project)
                case .plan(let parts):
                    progress[project.id]?.plan = parts
                    progress[project.id]?.tickWrittenParts()
                case .tool(let text, let fullCall):
                    log(project, .tool, text)
                    let call = ToolCall(text)
                    note(TurnProgress.activity(for: call), file: TurnProgress.file(changedBy: call), for: project)
                    if let file = TurnProgress.file(changedBy: call) { progress[project.id]?.wrote(file) }
                    toolCalls += 1
                    // Compared in full: six different searches of one file all read "grep cache.json".
                    repeats = fullCall == lastTool ? repeats + 1 : 1
                    lastTool = fullCall
                    if repeats >= 6 || toolCalls > 150, failure == nil {
                        failure = repeats >= 6
                            ? "The model got stuck repeating the same step, so Lamp stopped it."
                            : "The model made over 150 changes in one go, so Lamp stopped it."
                        if let process = turn.agent { Subprocess.terminateTree(process) }
                    }
                case .cost(let amount): cost += amount
                case .failed(let text): failure = text
                case .raw(let text): log(project, .detail, text)
                case .session(let id): if engine != .pi { try? id.write(to: sessionFile, atomically: true, encoding: .utf8) }
                }
            }
        }
        turn.agent = nil
        endApprovals(for: project)
        // A message cut short (the run was stopped, or failed) keeps what was written of it.
        showWritten(for: project)
        turn.writing = nil
        log(project, .summary, LogLine.workSummary(seconds: Date().timeIntervalSince(started), cost: cost))
        recordAgent(project, cost: cost)
        if turn.stopped {
            turn.stopped = false
            log(project, .status, "Stopped. Any changes made so far are kept; press Undo to discard them.")
            return false
        }
        if let failure, failure.hasPrefix("The model ") {
            log(project, .error, failure + " Try again, or pick a stronger model in Settings.")
            return false
        }
        if status != 0 && failure == nil { failure = "\(engine.title) exited with status \(status)" }
        guard let failure else { return true }
        log(project, .detail, failure)
        // Claude Code's auto permission mode isn't offered on every account or model: fall back to asking
        // before every command, remember that, and run the turn again.
        let lower = failure.lowercased()
        if engine == .claude, CommandApproval.current.isAutomatic, !CommandApproval.claudeAutoUnavailable,
           lower.contains("auto"), lower.contains("mode") || lower.contains("permission") {
            CommandApproval.claudeAutoUnavailable = true
            log(project, .status, "Claude Code's auto mode isn't available, so Lamp will ask before every command.")
            return await runAgent(prompt, files: files, on: project)
        }
        log(project, .error, Provider.friendlyError(failure))
        return false
    }

    /// One pi conversation per app, so the agent remembers earlier requests, including ones that were undone.
    private static func piSession(for project: LampProject) -> String {
        let url = project.dir.appendingPathComponent(".lamp/pi-session")
        if let id = (try? String(contentsOf: url, encoding: .utf8))?.trimmed, !id.isEmpty { return id }
        let id = "lamp-" + UUID().uuidString.lowercased()
        try? id.write(to: url, atomically: true, encoding: .utf8)
        return id
    }

    /// External engines report their own conversation ids; Lamp keeps one per engine per app.
    private static func sessionFile(for project: LampProject, engine: Engine) -> URL {
        project.dir.appendingPathComponent(".lamp/session-\(engine.rawValue)")
    }

    private static func savedSession(_ url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8))?.trimmed.nilIfEmpty
    }

    /// Deletes an app: quits it, stops its agent, and moves its source and built app to the Trash.
    func delete(_ project: LampProject) async {
        stop(project)
        iconDesigns.removeValue(forKey: project.id)?.cancel()
        await quit(project)
        let fm = FileManager.default
        if fm.fileExists(atPath: project.installedURL.path) {
            try? fm.trashItem(at: project.installedURL, resultingItemURL: nil)
        }
        do {
            try fm.trashItem(at: project.dir, resultingItemURL: nil)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        let index = projects.firstIndex { $0.id == project.id }
        projects.removeAll { $0.id == project.id }
        logs[project.id] = nil
        usage[project.id] = nil
        queued[project.id] = nil
        icons[project.id] = nil
        release(project)
        unread.remove(project.id)
        tokens = tokens.filter { $0.value != project.id }
        if selection == project.id {
            selection = index.flatMap { projects.indices.contains($0) ? projects[$0] : projects.last }?.id
        }
    }

    // MARK: - Approvals

    /// The latest request per app, so the decision model can judge commands against what the user asked for.

    /// Applies Settings → Building → "Ask before running commands" to one command.
    private func approveCommand(_ command: String, for project: LampProject, escalated: Bool, shell: Bool = true) async -> Bool {
        switch CommandApproval.current {
        case .never:
            log(project, .status, "Ran: \(command)")
            return true
        case .risky where !escalated, .unusual where !escalated:
            if await commandLooksSafe(command, for: project) {
                log(project, .status, "Ran: \(command)")
                return true
            }
            return await requestApproval(for: project, command: command, shell: shell)
        default:
            return await requestApproval(for: project, command: command, shell: shell)
        }
    }

    /// For agents without their own classifier (pi): obviously risky commands always go to the user; the rest
    /// are judged by the decision model against the user's request. No decision model available → ask.
    private func commandLooksSafe(_ command: String, for project: LampProject) async -> Bool {
        // What's outside the app's folder goes to the AI model once read, so that's the user's call and not a
        // model's: a command that names such a place is never routine, however the decision model would score it.
        if Privacy.reachesOutside(command, project: project) { return false }
        let state: [String: Any] = [
            "command": command,
            "user_request": turns[project.id]?.request ?? "",
            "working_folder": "The app's own project folder: \(project.dir.path)",
        ]
        // A command that reads is held to the privacy setting the file tools follow: what's outside the app's
        // folder goes to the AI model once read, so it's the user's call, however harmless the command looks.
        let asks = Privacy.asksOutsideFolder
        let question: [String: Any] = [
            "type": "noul",
            "instructions": "Is it safe to run `command` without asking the user first, given `user_request`?",
            "criteria": [
                "true": "Routine and low-risk for building this app: listing, reading or searching files"
                    + (asks ? " inside the working folder, in system or developer folders (/usr, /System, /Library/Developer, Xcode, Homebrew) or in temporary folders" : "")
                    + "; git status, log, diff, or cloning a repository the user mentioned; creating, editing, converting or deleting files inside the working folder (what the agent's own file tools do anyway, and every change is kept in the app's history); fetching a public web page; running the app's own build or tests.",
                "false": "Could cause harm or surprise: "
                    + (asks ? "reading, listing, searching or copying anything else outside the working folder (the user's home folder, documents, keys, settings, other apps' data), even when the user asked for it; " : "")
                    + "reading sign-ins, keys, passwords, tokens or browser data wherever they are, even when the user asked for it; "
                    + "deleting or overwriting files outside the working folder, needing administrator rights, changing system settings, installing software system-wide, running downloaded scripts, sending files or data somewhere, pushing to a remote, or doing something the user didn't ask for.",
            ],
        ]
        guard let (answers, cost) = try? await AppAI.decide(state: state, questions: ["safe": question]),
              let probability = (answers["safe"] as? [String: Any])?["noul"] as? Double else { return false }
        _ = cost
        return probability >= 0.85
    }

    /// Applies Settings → Building → Privacy to one of the agent's file tools, about to touch `path`: pi's own
    /// tools ask through its extension, Codex's come from Lamp's MCP endpoint. The reason is for the agent.
    private func fileAccess(tool: String, path: String, for project: LampProject) async -> (allowed: Bool, reason: String?) {
        switch Privacy.verdict(tool: tool, path: path, project: project) {
        case .allow: return (true, nil)
        case .deny(let reason): return (false, reason)
        case .ask:
            let card = Privacy.explanation(tool: tool, path: path, project: project)
            let allowed = await requestApproval(for: project, command: card.command,
                                                title: "The agent wants a file outside this app's folder",
                                                explanation: card.explanation)
            return (allowed, allowed ? "Approved in Lamp."
                : "The user didn't allow that. It's outside the app's folder; work with what's inside it, or say what you need and why.")
        }
    }

    /// Asks the in-app AI model to describe a command for a non-technical person: what it does, and its risk.
    private func explain(_ command: String, for project: LampProject) async -> CommandExplanation? {
        let system = """
        You explain shell commands to people who don't use the command line. An AI agent building a Mac app \
        called "\(project.name)" wants to run a command, and the user has to decide whether to allow it.
        Reply as JSON: {"summary": "<one plain sentence, under 20 words, saying what it does and why it might \
        help, without jargon or command names>", "risk": "low" | "medium" | "high", "why": "<under 15 words: \
        the main reason for that risk level, e.g. what it could change, delete, install or send>"}
        low: only reads, or creates, edits or deletes files inside the app's own folder (the agent's file tools do \
        the same without asking, and every change is kept in the app's history). medium: downloads things, installs tools for \
        this project, or changes files elsewhere that are easy to restore. high: deletes or overwrites files outside \
        the app's folder, needs administrator rights, changes system settings, sends personal data somewhere, reads \
        sign-ins, keys, passwords or browser data, or runs code downloaded from the internet.
        """
        let prompt = "The user's request: \(turns[project.id]?.request ?? "(unknown)")\n\nThe command:\n\(command)"
        guard let (text, _) = try? await AppAI.complete(prompt: prompt, images: [], system: system, json: true),
              let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let summary = (json["summary"] as? String)?.trimmed, !summary.isEmpty else { return nil }
        let risk = (json["risk"] as? String)?.lowercased() ?? "medium"
        // The model judges what a command changes, and calls reading harmless. Reading outside the app's folder
        // is at least what the same read through a file tool is: its contents go to the AI model.
        if risk == "low", Privacy.reachesOutside(command, project: project) {
            return CommandExplanation(summary: summary, risk: "medium", why: Privacy.outsideRead)
        }
        return CommandExplanation(summary: summary, risk: ["low", "medium", "high"].contains(risk) ? risk : "medium",
                                  why: (json["why"] as? String)?.trimmed ?? "")
    }

    /// Waits for the user to allow or deny a shell command. One request per app at a time; others queue.
    /// There's no timeout: commands wait until the user answers, stops the turn, or the turn ends.
    func requestApproval(for project: LampProject, command: String, title: String? = nil,
                         explanation given: CommandExplanation? = nil, shell: Bool = true) async -> Bool {
        guard !command.trimmed.isEmpty else { return false }
        if turns[project.id]?.allowAll == true {
            log(project, .detail, "Ran (allowed for this turn): \(command)")
            return true
        }
        // One request per app at a time, from here on: a second one waits, including through the
        // explanation below, so two can't both put up a card for the same slot.
        while approvals[project.id] != nil || turns[project.id]?.approving == true { try? await Task.sleep(for: .milliseconds(200)) }
        guard let turn = turns[project.id], turn.agent != nil else { return false }   // the agent is gone: nobody to answer for
        turn.approving = true
        defer { turn.approving = false }
        // "Only when risky": a shell command the in-app model rates low risk runs without the card.
        var given = given
        if shell, title == nil, CommandApproval.current == .risky {
            note("Checking a command", for: project)
            if given == nil { given = await explain(command, for: project) }
            guard turn.agent != nil else { return false }
            if let explanation = given, explanation.risk == "low" {
                log(project, .status, "Ran: \(command)")
                log(project, .detail, "Ran without asking (low risk): \(explanation.summary)")
                return true
            }
        }
        NSApp.requestUserAttention(.informationalRequest)
        note(title == nil ? "Waiting for your OK to run a command" : "Waiting for your OK", for: project)
        return await withCheckedContinuation { continuation in
            var pending = PendingApproval(command: command, answer: continuation, explanation: given)
            if let title { pending.title = title }
            approvals[project.id] = pending
            // Explain it while the card is up; the card shows the raw command until (and if) this arrives.
            if given == nil { Task {
                if let explanation = await explain(command, for: project), approvals[project.id]?.id == pending.id {
                    approvals[project.id]?.explanation = explanation
                }
            } }
        }
    }

    func answerApproval(for project: LampProject, allow: Bool, allowAll: Bool = false) {
        guard let pending = approvals.removeValue(forKey: project.id) else { return }
        if allowAll { turns[project.id]?.allowAll = true }
        log(project, .detail, (allow ? "Allowed: " : "Denied: ") + pending.command)
        note(allow && pending.title == PendingApproval.commandTitle ? "Running a command" : "Thinking", for: project)
        pending.answer.resume(returning: allow)
    }

    /// Ends the approvals of one agent run: anything still waiting is denied. "Allow all for this turn" lasts
    /// the turn (its compile and crash fixes are further agent runs), so it resets in finish() and stop().
    private func endApprovals(for project: LampProject) {
        answerApproval(for: project, allow: false)
    }

    /// Stops the agent working on an app, and the build if one is going.
    func stop(_ project: LampProject) {
        guard let turn = turns[project.id], turn.isWorking else { return }
        endApprovals(for: project)   // a command waiting for approval counts as denied
        turn.cancel()
    }

    /// Opens the installed app, or brings it to the front if it's running. Only builds when there's
    /// nothing installed yet (or the installed copy was deleted).
    func open(_ project: LampProject) async {
        if project.platform == .iphone {
            // Running already: bring the simulator forward. Otherwise build (if needed) and launch.
            let toSimulator = !(Experiments.devices && project.device != nil)
            if toSimulator, let running = simulatorApps[project.id], Simulator.isRunning(pid: running.pid), simulatorLeases[running.udid] == project.id { await Simulator.show(); return }
            if FileManager.default.fileExists(atPath: project.builtURL.path), stamps[project.id]?.isOutdated != true {
                guard begin(project) != nil else { return }
                defer { finish(project) }
                await installReportingCrash(project)
            } else {
                await run(project)
            }
            return
        }
        // Built by an older Lamp: rebuild it first, so it gets this Lamp's fixes and building blocks.
        // Not while it's running (that would quit it under the user); if the build fails, the old one opens.
        if stamps[project.id]?.isOutdated == true, !busy.contains(project.id),
           NSRunningApplication.runningApplications(withBundleIdentifier: project.bundleID).isEmpty {
            if await updateForThisForge(project) { return }
        }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: project.bundleID).first {
            // Ask the app to show a window (opening a new one if all were closed); see LampWindows. The app
            // says when it has: a window, or the panel of an app that lives in the menu bar, which isn't an
            // ordinary window and wouldn't be found below.
            let acknowledged = Acknowledgement(name: Edition.notificationPrefix + "windowShown", object: project.bundleID)
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(Edition.notificationPrefix + "showWindow"), object: project.bundleID, userInfo: nil, deliverImmediately: true)
            running.activate()
            // Whatever the app did with that (an app built before the listener existed ignores it; one that
            // replaced New Window can't open one), something has to be on screen: if there's nothing, relaunch it.
            let shown = await acknowledged.wait(seconds: 1.5)
            guard !running.isTerminated else { return }   // it's relaunching itself (LampWindows.relaunch)
            guard !shown, !Self.hasWindow(running.processIdentifier) else { return }
            running.terminate()
            for _ in 0..<30 where !running.isTerminated { try? await Task.sleep(for: .milliseconds(100)) }
            if !running.isTerminated { running.forceTerminate() }
        }
        guard FileManager.default.fileExists(atPath: project.installedURL.path) else {
            await run(project)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.arguments = ["-LampInFront", "YES"]   // see install
        do {
            _ = try await NSWorkspace.shared.openApplication(at: project.installedURL, configuration: config)
        } catch {
            log(project, .error, ErrorMessages.openFailed(error.localizedDescription))
        }
        refreshOpenApps()
    }

    /// The agent's `use_app` tool: hands its clicks, typing and keys to the open app, which performs them on its
    /// own front window (LampDriver in LampSupport), then reports what happened with a fresh picture.
    private func use(_ project: LampProject, request body: Data) async -> (Int, [String: Any]) {
        guard turns[project.id]?.agent != nil else { return (409, ["error": "Lamp isn't working on this app right now."]) }
        guard let request = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let actions = request["actions"] as? [[String: Any]], !actions.isEmpty,
              let json = (try? JSONSerialization.data(withJSONObject: actions)).map({ String(decoding: $0, as: UTF8.self) }) else {
            return (400, ["error": "use_app needs a list of actions."])
        }
        if project.platform == .iphone { return await useOnSimulator(project, actions: actions, json: json) }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: project.bundleID).first else {
            return (200, ["text": "The app isn't open. Call look_at_app first: it builds the app and opens it."])
        }
        guard Self.binary(of: project, contains: "lampUseAppSignature") else {
            return (200, ["text": "The open app was built before use_app could do this. Call look_at_app to rebuild it, then try again."])
        }
        let id = UUID().uuidString
        let printed = Runtime.logSize(project)
        // Signed with the app's token rather than carrying it: distributed notifications reach every process.
        let key = SymmetricKey(data: Data(Template.token(for: project).utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data("\(id)\n\(json)".utf8), using: key)
            .map { String(format: "%02x", $0) }.joined()
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "useApp.\(project.id)"), object: nil,
            userInfo: ["actions": json, "id": id, "lampUseAppSignature": signature], deliverImmediately: true)
        let waits = actions.reduce(0.0) { $0 + (($1["action"] as? String) == "wait" ? min($1["amount"] as? Double ?? 1, 10) : 0) }
        let wait = Double(actions.count) * 0.4 + waits + 5
        guard let report = await Runtime.useReport(of: project, id: id, waiting: wait, while: { !app.isTerminated }) else {
            guard app.isTerminated else {
                return (200, ["text": "The app didn't answer. It may have no window open, or it may be stuck."])
            }
            return (200, ["text": "The app quit or crashed while doing that.\n\n" + (await Runtime.launchReport(project))])
        }
        var text = "What happened:\n\(report)"
        // The agent may have edited the code since: what it's clicking is the app from before those edits.
        if Runtime.sourcesChanged(project) {
            text += "\n\nThis is the app as last built: it doesn't have the changes you've made to the code since. " +
                "Call look_at_app to build and open them."
        }
        text += Privacy.sharesPictures
            ? "\n\nPictures of its windows follow, frontmost first. Points for the next use_app are pixels in the first picture."
            : "\n\n" + Privacy.picturesOff
        if !Privacy.sharesLog { text += " " + Privacy.logOff }
        if Privacy.sharesLog, let lines = Runtime.log(of: project, from: printed) { text += "\n\nWhat it printed meanwhile:\n\(lines)" }
        return (200, ["text": text, "screenshots": Privacy.sharesPictures ? Runtime.pictures(of: project).map(\.path) : []])
    }

    /// `use_app` for an iPhone app: Lamp drives the simulator through the Mac's accessibility system
    /// (Simulator.Driver), then a fresh picture of the screen follows the report.
    private func useOnSimulator(_ project: LampProject, actions: [[String: Any]], json: String) async -> (Int, [String: Any]) {
        guard let running = simulatorApps[project.id], Simulator.isRunning(pid: running.pid) else {
            return (200, ["text": "The app isn't open. Call look_at_app first: it builds the app and opens it in the simulator."])
        }
        // The owner, before any wait; and one Lamp app per simulator, so actions can't land on another's screen.
        guard let owner = turns[project.id] else { return (409, ["error": "Lamp isn't working on this app right now."]) }
        guard simulatorLeases[running.udid] == project.id else {
            return (200, ["text": "Another of the user's apps has taken this simulator since. Call look_at_app to open this app again."])
        }
        if let other = simulatorApps.first(where: { $0.key != project.id && $0.value.udid == running.udid && Simulator.isRunning(pid: $0.value.pid) }),
           let name = projects.first(where: { $0.id == other.key })?.name {
            return (200, ["text": "Another of the user's apps, \(name), is open on the same simulator, so the screen may not be this app's. Ask the user to quit it, or wait and try again."])
        }
        guard Simulator.Driver.isAllowed else {
            Simulator.Driver.ask()
            log(project, .status, "To try iPhone apps for you, Lamp needs to be allowed to control this computer: System Settings → Privacy & Security → Accessibility, then turn on Lamp.")
            return (200, ["text": "Lamp isn't allowed to control the simulator yet. The user has just been asked to allow it (System Settings → " +
                          "Privacy & Security → Accessibility). Say so to the user in plain words, and try again on their next request."])
        }
        guard let screen = await Simulator.Driver.screen(of: running.udid, owner: "\(project.id):\(running.pid)") else {
            return (200, ["text": "Lamp can't find the iPhone's screen in the Simulator window. Make sure the Simulator is open and showing the iPhone, then try again."])
        }
        guard let data = json.data(using: .utf8), let decoded = try? JSONDecoder().decode([Simulator.Driver.Action].self, from: data) else {
            return (400, ["error": "use_app needs a list of actions."])
        }
        let printed = Runtime.logSize(project)
        let picture = Runtime.folder(project).appendingPathComponent("screenshot.png")
        let report = await Simulator.Driver.perform(decoded, on: screen, picture: picture) { [weak self] in
            guard let self, exists(project), turns[project.id] === owner, !owner.stopped else { return false }
            // Still this app's screen: it's running, the device is still leased to this project (a launch by
            // another project takes the lease before anything else), and no other app of Lamp's is running there.
            guard simulatorLeases[running.udid] == project.id, simulatorApps[project.id]?.pid == running.pid, Simulator.isRunning(pid: running.pid) else { return false }
            return !simulatorApps.contains { $0.key != project.id && $0.value.udid == running.udid && Simulator.isRunning(pid: $0.value.pid) }
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["id": UUID().uuidString, "report": report]) {
            try? data.write(to: Runtime.folder(project).appendingPathComponent("use.json"))
        }
        guard Simulator.isRunning(pid: running.pid) else {
            var text = "What happened:\n\(report)\n\nThe app quit or crashed while doing that."
            if Privacy.sharesLog, let tail = Runtime.logTail(project) { text += "\n\nLast lines it printed:\n" + tail }
            return (200, ["text": text])
        }
        var text = "What happened:\n\(report)"
        if Runtime.sourcesChanged(project) {
            text += "\n\nThis is the app as last built: it doesn't have the changes you've made to the code since. " +
                "Call look_at_app to build and open them."
        }
        text += Privacy.sharesPictures
            ? "\n\nA picture of the iPhone's screen follows. Points for the next use_app are pixels in it."
            : "\n\n" + Privacy.picturesOff
        if !Privacy.sharesLog { text += " " + Privacy.logOff }
        if Privacy.sharesLog, let lines = Runtime.log(of: project, from: printed) { text += "\n\nWhat it printed meanwhile:\n\(lines)" }
        return (200, ["text": text, "screenshots": Privacy.sharesPictures ? [picture.path] : []])
    }

    /// `look_at_app` and `use_app` for agents that take tools over MCP (Claude Code and Codex): one streamable-HTTP
    /// endpoint speaking JSON-RPC, with no sessions or streams, that answers each request on the spot. Pictures go
    /// back as image content, so the model sees the windows just as pi's version shows them.
    /// `fileTools` adds `read`, `ls`, `find` and `grep` to the list, for Codex, which has none of its own;
    /// pi and Claude Code keep theirs.
    private func mcp(_ body: Data, for project: LampProject, fileTools: Bool) async -> (Int, [String: Any]) {
        guard let message = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let method = message["method"] as? String else {
            return (400, ["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Not a JSON-RPC request."]])
        }
        let id = message["id"] ?? NSNull()
        func reply(_ result: [String: Any]) -> (Int, [String: Any]) { (200, ["jsonrpc": "2.0", "id": id, "result": result]) }
        switch method {
        case "initialize":
            return reply(["protocolVersion": "2025-03-26", "capabilities": ["tools": [:]],
                          "serverInfo": ["name": "forge", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"]])
        case "ping":
            return reply([:])
        case "tools/list":
            return reply(["tools": Self.mcpTools + (fileTools ? FileTools.definitions : [])])
        case "tools/call":
            let params = message["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            if FileTools.names.contains(name) { return reply(await file(name, arguments, for: project)) }
            let (status, answer): (Int, [String: Any])
            switch name {
            case "look_at_app": (status, answer) = await look(at: project)
            case "use_app":
                let actions = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
                (status, answer) = await use(project, request: actions)
            case "plan":
                // pi's plan reaches the build card through its event stream (Agent.parseLine); here it's set directly.
                let parts = (arguments["parts"] as? [[String: Any]] ?? []).enumerated().compactMap { index, part in
                    (part["title"] as? String).map {
                        PlanPart(id: index, title: $0, done: part["done"] as? Bool ?? false,
                                 files: (part["files"] as? [String] ?? []).map { ($0 as NSString).lastPathComponent })
                    }
                }
                progress[project.id]?.plan = parts
                progress[project.id]?.tickWrittenParts()
                (status, answer) = (200, ["text": "The user can see the plan."])
            case "delete_file":
                (status, answer) = deleteFile(arguments["path"] as? String ?? "", in: project)
            case "list_versions": (status, answer) = await versions("", [:], of: project)
            case "name_version": (status, answer) = await versions("/name", arguments, of: project)
            case "restore_version": (status, answer) = await versions("/restore", arguments, of: project)
            default:
                return (200, ["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Unknown tool \(name)."]])
            }
            if status != 200 {
                return reply(["content": [["type": "text", "text": answer["error"] as? String ?? "Lamp couldn't do that."]], "isError": true])
            }
            var content: [[String: Any]] = [["type": "text", "text": answer["text"] as? String ?? ""]]
            for path in answer["screenshots"] as? [String] ?? [] {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                    content.append(["type": "image", "data": data.base64EncodedString(), "mimeType": "image/png"])
                }
            }
            return reply(["content": content])
        default:
            // Notifications (initialized, cancelled) are acknowledged without a body; unknown requests get an error.
            if message["id"] == nil { return (202, [:]) }
            return (200, ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
    }

    /// One of the file tools, as an MCP tool result. Where it points is checked first, by the rule pi's file
    /// tools follow; a call that names no path works in the app's own folder.
    private func file(_ tool: String, _ arguments: [String: Any], for project: LampProject) async -> [String: Any] {
        func failed(_ message: String) -> [String: Any] { ["content": [["type": "text", "text": message]], "isError": true] }
        let given = (arguments["path"] as? String)?.nilIfEmpty ?? "."
        let (allowed, reason) = await fileAccess(tool: tool, path: given, for: project)
        guard allowed else { return failed(reason ?? "Lamp couldn't do that.") }
        let path = Privacy.resolved(given, in: project.dir)
        // Off the main thread: a search can read thousands of files.
        let result = await Task.detached { () -> Result<FileTools.Reply, FileTools.Failure> in
            do {
                return .success(try FileTools.run(tool, path: path, arguments: arguments, folder: project.dir,
                                                  hidden: { Privacy.hides($0, project: project) }))
            } catch let failure as FileTools.Failure {
                return .failure(failure)
            } catch {
                return .failure(FileTools.Failure(message: error.localizedDescription))
            }
        }.value
        switch result {
        case .failure(let failure): return failed(failure.message)
        case .success(let found):
            var content: [[String: Any]] = [["type": "text", "text": found.text]]
            if let image = found.image {
                content.append(["type": "image", "data": image.data.base64EncodedString(), "mimeType": image.mimeType])
            }
            return ["content": content]
        }
    }

    /// The agent's `delete_file`: one file inside the app's folder, never Lamp's own files, never through a
    /// link that leads out. The same rules as pi's version in lamp-tools.ts.
    private func deleteFile(_ path: String, in project: LampProject) -> (Int, [String: Any]) {
        let root = project.dir.resolvingSymlinksInPath().standardizedFileURL
        let target = URL(fileURLWithPath: path, relativeTo: project.dir).standardizedFileURL
        let relative = target.path.hasPrefix(root.path + "/") || target.path.hasPrefix(project.dir.path + "/")
            ? String(target.path.dropFirst((target.path.hasPrefix(root.path + "/") ? root.path : project.dir.path).count + 1)) : ""
        guard !relative.isEmpty else { return (400, ["error": "Only files inside the app's folder can be deleted."]) }
        // Compared without regard to case: the Mac's usual file system treats "package.swift" as the same file.
        let protected = [".lamp", ".git", ".build", "build", ".gitignore", "Package.swift", "build.sh", "Sources/LampSupport.swift"]
        let lowered = relative.lowercased()
        if protected.contains(where: { lowered == $0.lowercased() || lowered.hasPrefix($0.lowercased() + "/") }) {
            return (400, ["error": "\(relative) belongs to Lamp and can't be deleted."])
        }
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: target.path) else { return (404, ["error": "There's no file at \(relative)."]) }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            return (400, ["error": "\(relative) isn't a file. Only single files can be deleted."])
        }
        // A folder on the way that is really a link could lead outside the app's folder.
        let folder = target.deletingLastPathComponent().resolvingSymlinksInPath().path
        guard folder == root.path || folder.hasPrefix(root.path + "/") else {
            return (400, ["error": "Only files inside the app's folder can be deleted."])
        }
        do { try fm.removeItem(at: target) } catch { return (500, ["error": "Couldn't delete \(relative): \(error.localizedDescription)"]) }
        return (200, ["text": "Deleted \(relative)."])
    }

    /// The tools every engine gets, from Resources/lamp-tools.json: the one place their names, descriptions and
    /// schemas live. pi's extension (lamp-tools.ts) reads the same file, so the two can't drift apart.
    static let mcpTools: [[String: Any]] = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("lamp-tools.json"),
              let data = try? Data(contentsOf: url),
              let tools = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            assertionFailure("lamp-tools.json is missing from the app")
            return []
        }
        // `label` is pi's: MCP clients see name, description and inputSchema.
        return tools.map { tool in tool.filter { $0.key != "label" } }
    }()

    /// Whether the installed app's binary contains a string, which says which Lamp features it was built with.
    private static func binary(of project: LampProject, contains marker: String) -> Bool {
        let binary = project.installedURL.appendingPathComponent("Contents/MacOS/\(project.exe)")
        guard let data = try? Data(contentsOf: binary, options: .alwaysMapped) else { return false }
        return data.range(of: Data(marker.utf8)) != nil
    }

    /// Whether the installed app was built with LampWindows (its binary contains the message name).
    /// One distributed notification, awaited with a time limit.
    private final class Acknowledgement: @unchecked Sendable {
        private let observer: NSObjectProtocol

        init(name: String, object: String) {
            let lock = NSLock()
            var flag = false
            observer = DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: object, queue: nil) { _ in
                lock.lock(); flag = true; lock.unlock()
            }
            check = { lock.lock(); defer { lock.unlock() }; return flag }
        }
        private let check: () -> Bool

        deinit { DistributedNotificationCenter.default().removeObserver(observer) }

        func wait(seconds: Double) async -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if check() { return true }
                try? await Task.sleep(for: .milliseconds(100))
            }
            return check()
        }
    }

    /// Whether a process has a normal window on screen (window list metadata needs no permission).
    private static func hasWindow(_ pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
    }

    /// Rebuilds the app from its code, reinstalls it and relaunches it.
    /// Rebuilds an app made by an older Lamp and opens it. False if it didn't build, leaving the old one in place.
    private func updateForThisForge(_ project: LampProject) async -> Bool {
        guard begin(project) != nil else { return false }
        defer { finish(project) }
        log(project, .status, "Updating \(project.name) for this version of Lamp…")
        guard await build(project) == nil else {
            log(project, .status, "Couldn't update \(project.name), so it opened as it was")
            return false
        }
        await installReportingCrash(project)
        return true
    }

    func run(_ project: LampProject) async {
        guard begin(project) != nil else { return }
        defer { finish(project) }
        if await build(project) == nil {
            await installReportingCrash(project)
        } else {
            log(project, .error, ErrorMessages.appDoesNotBuild)
        }
    }

    /// Goes back to the version before the current one. Like any restore, this is itself a new version.
    func undo(_ project: LampProject) async {
        guard begin(project) != nil else { return }
        defer { finish(project) }
        let versions = await Versions.list(project)
        // A turn that was stopped, or never got the app building, leaves its changes unsaved: Undo discards those first.
        if let current = versions.first, await Versions.hasUnsavedChanges(project) {
            _ = await Versions.restoreFiles(project, to: current)
            log(project, .status, "Discarded the unfinished change")
            if await build(project) == nil { await installReportingCrash(project) }
            return
        }
        guard let (undoing, target) = Versions.undoTarget(in: versions),
              await Versions.restore(project, to: target, message: "Undid “\(undoing.label)”",
                                     trailer: "Lamp-Undid: \(undoing.id)") else {
            log(project, .status, "Nothing to undo")
            return
        }
        Versions.remember(project, restoredTo: target.label, from: target.date)
        log(project, .status, "Undid “\(undoing.label)”")
        await rebuild(project, restoredFrom: target)
    }

    /// Brings back an earlier version's files as a new version, so the restore can be undone too.
    func restore(_ project: LampProject, to version: AppVersion) async {
        guard begin(project) != nil else { return }
        defer { finish(project) }
        guard await Versions.restore(project, to: version, message: Versions.restoredMessage(to: version)) else {
            log(project, .status, "The app is already like “\(version.label)”")
            return
        }
        Versions.remember(project, restoredTo: version.label, from: version.date)
        log(project, .status, Versions.restoredMessage(to: version))
        await rebuild(project, restoredFrom: version)
    }

    /// Goes back to the version a request in the chat made, or to the one before it.
    func restore(_ project: LampProject, toVersionOf line: LogLine, before: Bool) async {
        let versions = await Versions.list(project)
        guard let made = line.version.flatMap({ id in versions.first { $0.id == id } }),
              let target = before ? made.parent.flatMap({ id in versions.first { $0.id == id } }) : made else { return }
        await restore(project, to: target)
    }

    /// Sends a request again in other words, from where the app was when it was first sent. The app's files
    /// go back to that point (as a new version, like any restore, so what came later is still in Versions),
    /// the request and everything after it leave the chat, and the new words go out as an ordinary turn.
    /// The agent keeps its conversation, as it does after Undo, and is told what was taken back: the three
    /// engines can't all be wound back to an earlier message, and a note works the same for each of them.
    /// `attachments` are the files to send with it: the request's own, already in the app's folder, and any added.
    /// False when the app couldn't be taken back, and nothing was sent.
    func sendAgain(_ line: LogLine, as text: String, attachments: [URL], in project: LampProject) async -> Bool {
        guard busy.insert(project.id).inserted else { return false }
        defer { finish(project) }   // which starts the turn queued below
        let versions = await Versions.list(project)
        // Requests from before Lamp noted where they were sent from: the version one made follows that point.
        let start = line.before ?? line.version.flatMap { id in versions.first { $0.id == id }?.parent }
        guard let target = start.flatMap({ id in versions.first { $0.id == id } }),
              await Versions.restoreFiles(project, to: target),
              let chat = logs[project.id], let index = chat.firstIndex(where: { $0.id == line.id }) else {
            log(project, .error, ErrorMessages.restoreFailed)
            return false
        }
        if await Versions.save(project, message: Versions.restoredMessage(to: target)), let head = await Versions.head(project) {
            Versions.copyPicture(in: project, from: target.id, to: head)
            versionsRevision += 1
        }
        // Requests that went out together made one change, so the ones just before this one go out with it again.
        var first = index
        while first > chat.startIndex, chat[first - 1].kind == .user { first -= 1 }
        // They keep what they had taken back themselves: it's the chat's only record of it.
        var again = chat[first..<index].map {
            QueuedMessage(text: $0.text, kept: $0.attachments ?? [], replaces: $0.replaced, tookBack: $0.tookBack ?? [])
        }
        let folder = project.dir.appendingPathComponent(Attachments.folder).standardizedFileURL
        let own = attachments.filter { $0.standardizedFileURL.deletingLastPathComponent() == folder }
        // What the agent is told was taken back is the first request leaving the chat that it actually had:
        // this one, or, when this one's own turn never reached it (the model couldn't be reached, say), the
        // first after it that did. When none did, this one was only standing in for an earlier request, or
        // for nothing, and sending it again takes back what it was taking back.
        let had = chat[index...].first { $0.kind == .user && Self.reachedAgent($0.id, in: chat) }
        let replaces = had.map { Self.label(for: $0) } ?? line.replaced
        // Everything that leaves the chat with it is something the user decided against (for the suggested
        // next message), along with what those had taken back in their turn. Not a request that never got
        // through: that one is only being tried again.
        let gone = chat[index...].filter { $0.kind == .user }.flatMap { request in
            (request.tookBack ?? []) + (Self.reachedAgent(request.id, in: chat) ? [Self.label(for: request)] : [])
        }.filter { $0 != text }
        again.append(QueuedMessage(text: text, attachments: attachments.filter { !own.contains($0) },
                                   kept: own.map(\.lastPathComponent), replaces: replaces, tookBack: gone))
        logs[project.id] = Array(chat[..<first])
        saveChat(project)
        progress[project.id] = nil   // a new app's build card belongs to the request that's gone
        if let replaces { Versions.remember(project, tookBack: replaces) }
        queued[project.id, default: []].insert(contentsOf: again, at: 0)
        return true
    }

    /// Whether the agent got as far as answering a request or working on it: something of its own follows the
    /// request in the chat before the next one. A turn that failed first leaves only Lamp's lines there.
    static func reachedAgent(_ request: UUID, in chat: [LogLine]) -> Bool {
        guard let index = chat.firstIndex(where: { $0.id == request }) else { return false }
        return chat[(index + 1)...].drop { $0.kind == .user }.prefix { $0.kind != .user }
            .contains { $0.kind == .agent || $0.kind == .tool }
    }

    /// After a restore: the new version looks like the old one, so it starts with its picture until the app
    /// takes a fresh one.
    private func rebuild(_ project: LampProject, restoredFrom version: AppVersion) async {
        guard let head = await Versions.head(project) else { return }
        Versions.copyPicture(in: project, from: version.id, to: head)
        versionsRevision += 1
        if await build(project) == nil {
            await installReportingCrash(project)
            keepPicture(of: project, version: head)
        }
    }

    /// Chats from before requests were linked to versions: matches each request to the version whose
    /// message is its text, in order. Requests that made no change, or went out together, stay unlinked.
    func linkOldRequests(_ project: LampProject) async {
        guard var chat = logs[project.id], chat.contains(where: { $0.kind == .user && $0.version == nil }) else { return }
        func plain(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let versions = await Versions.list(project).reversed()
        let linked = Set(chat.compactMap(\.version))
        var index = chat.startIndex
        var links: [UUID: String] = [:]
        for version in versions where !linked.contains(version.id) {
            let message = plain(version.message)
            guard let match = chat[index...].firstIndex(where: {
                $0.kind == .user && $0.version == nil && plain(Self.label(for: $0)) == message
            }) else { continue }
            chat[match].version = version.id
            links[chat[match].id] = version.id
            index = chat.index(after: match)
        }
        // The chat may have moved on while the versions were read: lines added, and a reply being written
        // grows in place. So the links go into the chat as it is now, line by line, never the copy back over it.
        guard !links.isEmpty, var current = logs[project.id] else { return }
        for index in current.indices where current[index].version == nil {
            if let version = links[current[index].id] { current[index].version = version }
        }
        logs[project.id] = current
        saveChat(project)
    }

    /// Gives the newest versions without one a short title from what changed, one at a time. Runs on its
    /// own, so the Versions panel reloading as titles arrive doesn't cancel it.
    func titleVersions(_ project: LampProject, limit: Int = 40) {
        guard titling.insert(project.id).inserted else { return }
        Task {
            defer { titling.remove(project.id) }
            for version in await Versions.list(project).prefix(limit) where version.title == nil && !version.isLampNote {
                guard let title = await VersionTitles.make(for: version, in: project) else { return }
                VersionTitles.save(title, for: version.id, in: project)
                versionsRevision += 1
            }
        }
    }

    /// Apps from before pictures were kept: the current version gets the picture of the current build.
    func fillCurrentPicture(_ project: LampProject, current: AppVersion) async {
        guard !FileManager.default.fileExists(atPath: Versions.pictureURL(in: project, for: current.id).path),
              let screenshot = Runtime.currentScreenshot(of: project), !busy.contains(project.id),
              await !Versions.hasUnsavedChanges(project) else { return }
        Versions.savePicture(screenshot, in: project, for: current.id)
        versionsRevision += 1
    }

    /// Links requests in the chat to the version they made.
    private func link(_ lines: [UUID], to version: String, in project: LampProject) {
        guard var chat = logs[project.id] else { return }
        for index in chat.indices where lines.contains(chat[index].id) { chat[index].version = version }
        logs[project.id] = chat
        saveChat(project)
    }

    /// Notes on requests the version the app was at when they were sent.
    private func mark(_ lines: [UUID], sentFrom version: String, in project: LampProject) {
        guard var chat = logs[project.id] else { return }
        for index in chat.indices where lines.contains(chat[index].id) { chat[index].before = version }
        logs[project.id] = chat
        saveChat(project)
    }

    /// Keeps the picture the app takes of itself shortly after opening, to show with its version.
    private func keepPicture(of project: LampProject, version: String) {
        Task {
            for _ in 0..<40 {
                if let screenshot = Runtime.currentScreenshot(of: project) {
                    Versions.savePicture(screenshot, in: project, for: version)
                    versionsRevision += 1
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Shows the Name… alert for the version the app is at now.
    func nameCurrentVersion(of project: LampProject) async {
        guard let current = await Versions.list(project).first else { return }
        naming = VersionNaming(project: project, version: current)
    }

    func name(_ version: AppVersion, of project: LampProject, as name: String) async {
        await Versions.name(project, version.id, name)
        versionsRevision += 1
    }

    /// Returns nil on success, or the tail of the compiler output on failure.
    private func build(_ project: LampProject) async -> String? {
        guard exists(project) else { return "The app was deleted." }
        log(project, .status, "Building…")
        // Lamp's own files first, and no build without them: the build runs build.sh and Package.swift.
        do {
            try Template.writeOwnedFiles(for: project)
        } catch {
            let problem = "Lamp couldn't write the app's build files: \(error.localizedDescription)"
            log(project, .error, problem)
            return problem
        }
        // Taken before the build, so an edit made while it runs still counts as a change afterwards.
        let fingerprint = Runtime.fingerprint(project)
        var output: [String] = []
        let status = await Shell.run(Shell.compatibleSDK + "./build.sh", cwd: project.dir,
                                     started: { [weak self] in self?.turns[project.id]?.build = $0 }) { output.append($0) }
        turns[project.id]?.build = nil
        guard exists(project) else { return "The app was deleted." }
        guard status != 0 else {
            Runtime.markBuilt(project, from: fingerprint)
            BuildStamp.write(to: project.builtURL)   // deploy signs the app afterwards
            return nil
        }
        let tail = output.suffix(40).joined(separator: "\n")
        log(project, .detail, "Build failed:\n" + tail)
        return tail
    }

    /// Installs and opens the app. Returns what's known about the failure if it died straight away.
    /// `inFront` is false for the agent's looks, which shouldn't pull the app in front of the user mid-turn.
    private func install(_ project: LampProject, inFront: Bool = true) async -> String? {
        guard exists(project) else { return nil }
        // The turn this install belongs to, taken before the icon wait: a Stop during it can end the turn
        // and start the next one's, which must not inherit this launch.
        let owner = turns[project.id]
        await prepareIcon(project)
        if project.platform == .iphone {
            guard let owner, turns[project.id] === owner, !owner.stopped else { return "The app was stopped before it opened." }
            // The person's own phone gets the app when they press Play or a change is finished; the agent's
            // looks (not in front) stay on the simulator, which is the only screen Lamp can see.
            if inFront, Experiments.devices, let udid = project.device {
                return await installOnDevice(project, owner: owner, udid: udid)
            }
            return await installOnSimulator(project, owner: owner, inFront: inFront)
        }
        await quit(project)
        guard exists(project) else { return nil }   // deleted while its old copy was quitting
        do {
            try await deploy(project)
        } catch {
            log(project, .error, ErrorMessages.installFailed(error.localizedDescription))
            return nil
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = inFront
        // An app that lives in the menu bar opens its panel, so there's something to see (LampMenuBar).
        if inFront { config.arguments = ["-LampInFront", "YES"] }
        note("Opening \(project.name)…", for: project)
        var crash: String?
        do {
            let app = try await NSWorkspace.shared.openApplication(at: project.installedURL, configuration: config)
            if await Runtime.diedOnLaunch(app) {
                log(project, .status, "\(project.name) quit right after opening. Looking at why…")
                crash = await Runtime.launchReport(project)
                log(project, .detail, crash!)
            } else if inFront {
                log(project, .status, "\(project.name) is ready")
            }
        } catch {
            log(project, .error, ErrorMessages.openFailed(error.localizedDescription))
        }
        upgradeIconArt(project)
        refreshOpenApps()
        stamps[project.id] = BuildStamp.read(project.installedURL)
        return crash
    }

    /// The iPhone counterpart of `install`: the built app goes into the booted simulator and is launched there,
    /// with what it prints going to the same log the Mac apps use. Returns what's known if it died at once.
    private func installOnSimulator(_ project: LampProject, owner: Turn, inFront: Bool) async -> String? {
        guard let udid = Simulator.device(project.family) else {
            let problem = "No \(project.family.name) simulator with iOS \(Simulator.minimumIOS) or later is installed. Open Xcode once and add one in Settings → Components."
            log(project, .error, problem)
            return problem
        }
        // `owner` is the turn the app belongs to, taken by `install` before anything waited: Delete or Stop
        // can come during any of the waits, and then nothing more is written or launched for it (not even by
        // a later turn of the same app, which would have a launch of its own).
        // Launches on one device go one after another: a launch already under way finishes (and is then
        // closed, below) before the next starts, so two apps can't be racing onto the same screen.
        let previous = simulatorWork[udid]
        let mine = Task<String?, Never> { [self] in
            await previous?.value
            guard turns[project.id] === owner, !owner.stopped else { return "The app was stopped before it opened." }
            return await launchOnSimulator(project, owner: owner, udid: udid, inFront: inFront)
        }
        simulatorWork[udid] = Task { _ = await mine.value }
        return await mine.value
    }

    /// The launch in progress on each simulator, for the next one to wait for.
    private var simulatorWork: [String: Task<Void, Never>] = [:]

    private func launchOnSimulator(_ project: LampProject, owner: Turn, udid: String, inFront: Bool) async -> String? {
        // The device is this project's from here: the driver acts only while the lease is held.
        let before = simulatorLeases[udid]
        simulatorLeases[udid] = project.id
        func stillOwns() -> Bool { exists(project) && turns[project.id] === owner && !owner.stopped && simulatorLeases[udid] == project.id }
        // A launch that doesn't come off gives the device back to whoever had it, so their look_at_app can
        // carry on (and theirs rechecks the lease, so it reopens the app if need be).
        func giveBack(_ message: String) -> String {
            if simulatorLeases[udid] == project.id { simulatorLeases[udid] = before.flatMap { simulatorApps[$0] != nil ? $0 : nil } }
            return message
        }
        note("Opening \(project.name) on the \(project.family.name) simulator…", for: project)
        await finishSimulatorBundle(project)
        do {
            try await Simulator.boot(udid, show: inFront)
            await Simulator.terminate(project.bundleID, on: udid)
            try await Simulator.install(project.builtURL, on: udid)
            guard stillOwns() else { return giveBack("The app was deleted or stopped before it opened.") }
            // One Lamp app per simulator: another project's app on this device is closed first, so what the
            // simulator shows is always the app being worked on (and that app's use_app batch, if any, stops).
            for (other, launched) in simulatorApps where other != project.id && launched.udid == udid {
                if let theirs = projects.first(where: { $0.id == other }) { await Simulator.terminate(theirs.bundleID, on: udid) }
                simulatorApps[other] = nil
            }
            guard stillOwns() else { return giveBack("The app was deleted or stopped before it opened.") }
            Runtime.startLog(project)
            Simulator.Driver.forget(project.id)
            let pid = try await Simulator.launch(project.bundleID, on: udid, log: Runtime.logURL(project))
            // The same could have happened during the launch itself: then the app just started belongs to
            // nobody, and is stopped before anything records it.
            guard stillOwns() else {
                await Simulator.terminate(project.bundleID, on: udid)
                return giveBack("The app was deleted or stopped before it opened.")
            }
            simulatorApps[project.id] = (udid, pid)
            try? await Task.sleep(for: .seconds(3))
            if !Simulator.isRunning(pid: pid) {
                simulatorApps[project.id] = nil
                log(project, .status, "\(project.name) quit right after opening. Looking at why…")
                var crash = "The app quit right after launching."
                if Privacy.sharesLog, let tail = Runtime.logTail(project) { crash += "\n\nLast lines it printed:\n" + tail }
                log(project, .detail, crash)
                refreshOpenApps()
                return crash
            }
            if inFront { log(project, .status, "\(project.name) is ready on the \(project.family.name) simulator") }
        } catch {
            // A failure to boot, install or launch is reported like a crash: the agent must hear about it.
            log(project, .error, ErrorMessages.openFailed(error.localizedDescription))
            refreshOpenApps()
            return giveBack("Couldn't open the app in the simulator: \(error.localizedDescription)")
        }
        refreshOpenApps()
        stamps[project.id] = BuildStamp.read(project.builtURL)
        return nil
    }

    /// Builds the app for the person's own phone with Xcode and puts it there (Devices). Signing is Xcode's
    /// automatic kind for the team chosen in Settings, so the first time can take a while while Xcode
    /// registers the phone and makes a certificate. What the app prints comes back to its log, as on the
    /// simulator. Returns a plain message when it couldn't be done, which the chat shows.
    private func installOnDevice(_ project: LampProject, owner: Turn, udid: String) async -> String? {
        let team = Devices.team
        if devices.first(where: { $0.udid == udid }) == nil { devices = await Devices.list() }
        let device = devices.first(where: { $0.udid == udid })
        // Nothing here is a crash for the agent to fix: a problem is told to the person and that's that.
        if let problem = Devices.problem(device, team: team) {
            log(project, .error, problem)
            return nil
        }
        let name = device?.name ?? "your phone"
        func stillOwns() -> Bool { exists(project) && turns[project.id] === owner && !owner.stopped }
        do {
            try Template.writeDeviceProject(for: project, team: team)
        } catch {
            log(project, .error, "Couldn't prepare the app for \(name): \(error.localizedDescription)")
            return nil
        }
        log(project, .status, "Building for \(name)…")
        var output: [String] = []
        let app: URL
        do {
            // The turn's build while it runs, like the simulator's: Stop ends it, and quitting Lamp asks first.
            app = try await Devices.build(project, team: team, udid: udid, started: { owner.build = $0 }) { output.append($0) }
            owner.build = nil
        } catch {
            owner.build = nil
            // Xcode's own error lines when there are any; the end of its output when not.
            let errors = output.filter { $0.contains("error: ") }.map { $0.replacingOccurrences(of: project.dir.path + "/", with: "") }
            let tail = errors.isEmpty ? Devices.tail(output.joined(separator: "\n")) : errors.joined(separator: "\n")
            let signing = tail.contains("signing") || tail.contains("provisioning") || tail.contains("No Account") || tail.contains("DEVELOPMENT_TEAM")
            let problem = signing
                ? "Xcode couldn't sign the app for \(name). Open Xcode → Settings → Accounts and sign in with the Apple account for team \(team), then try again.\n\n\(tail)"
                : "The app built for the simulator but not for \(name):\n\n\(tail)"
            log(project, .error, problem)
            return nil   // not a crash for the agent to fix: the simulator build is what it works on
        }
        guard stillOwns() else { return "The app was stopped before it opened." }
        log(project, .status, "Putting \(project.name) on \(name)…")
        do {
            try await Devices.install(app, on: udid)
            guard stillOwns() else { return "The app was stopped before it opened." }
            deviceApps[project.id]?.terminate()
            Runtime.startLog(project)
            let attached = try Devices.launch(project.deviceBundleID(team: team), on: udid, log: Runtime.logURL(project))
            deviceApps[project.id] = attached
            // Open while attached: when the app quits on the phone, devicectl ends, and the list follows.
            attached.terminationHandler = { _ in Task { @MainActor in Store.shared.refreshOpenApps() } }
            log(project, .status, "\(project.name) is ready on \(name)")
        } catch {
            log(project, .error, error.localizedDescription)
        }
        refreshOpenApps()
        return nil
    }

    /// For each app on a phone, the devicectl process attached to it: ending the process ends the app.
    private var deviceApps: [String: Process] = [:]

    /// Finishes the bundle build.sh made, the way `deploy` finishes a Mac app's: the reasons iOS shows when
    /// the app first asks for the microphone, photos or calendar (without which it's killed on the spot), the
    /// icon, and the files attached in Lamp's chat, which LampAssets finds next to the executable. Then the
    /// bundle is signed again, ad hoc, which is all the simulator asks for.
    private func finishSimulatorBundle(_ project: LampProject) async {
        let fm = FileManager.default
        let app = project.builtURL
        var script = """
            P="$LAMP_APP/Info.plist"
            plutil -replace CFBundleName -string "$LAMP_NAME" "$P" && \\
            plutil -replace CFBundleDisplayName -string "$LAMP_NAME" "$P"

            """
        // Every usage description, from the one list, so apps made before a reason was added get it too.
        for (key, text) in Template.iosUsageDescriptions {
            let reason = text.replacingOccurrences(of: "{{NAME}}", with: project.name).replacingOccurrences(of: "'", with: "'\\''")
            script += "plutil -replace \(key) -string '\(reason)' \"$P\"\n"
        }
        // What the agent declared in capabilities.json: background work in Info.plist, the rest as
        // entitlements the ad hoc signature carries (the simulator checks them for Health and the like).
        let capabilities = Template.Capabilities.load(project)
        for (key, names) in capabilities.lists.sorted(by: { $0.key < $1.key }) {
            if let json = try? JSONSerialization.data(withJSONObject: names), let text = String(data: json, encoding: .utf8) {
                script += "plutil -replace \(key) -json '\(text)' \"$P\"\n"
            }
        }
        let entitlements = project.dir.appendingPathComponent(".lamp/entitlements.plist")
        try? capabilities.entitlementsPlist.write(to: entitlements, atomically: true, encoding: .utf8)
        // iOS reads icons by name and scale from the bundle itself when told to in Info.plist: the home screen
        // sizes for iPhone (60pt at 2x and 3x) and iPad (76pt and 83.5pt at 2x), all cut from the one square.
        if fm.fileExists(atPath: Icons.squareURL(project).path) {
            let sizes = [("AppIcon60x60@2x", 120), ("AppIcon60x60@3x", 180), ("AppIcon76x76@2x", 152), ("AppIcon83.5x83.5@2x", 167)]
            for (name, pixels) in sizes {
                script += "sips -z \(pixels) \(pixels) \"$LAMP_ICON\" --out \"$LAMP_APP/\(name).png\" >/dev/null && \\\n"
            }
            script += """
                plutil -replace CFBundleIcons -json '{"CFBundlePrimaryIcon":{"CFBundleIconFiles":["AppIcon60x60"]}}' "$P" && \\
                plutil -replace 'CFBundleIcons~ipad' -json '{"CFBundlePrimaryIcon":{"CFBundleIconFiles":["AppIcon60x60","AppIcon76x76","AppIcon83.5x83.5"]}}' "$P"

                """
        }
        _ = await Shell.run(script, cwd: project.dir,
                            env: ["LAMP_APP": app.path, "LAMP_NAME": project.name, "LAMP_ICON": Icons.squareURL(project).path]) { _ in }
        let attachments = project.dir.appendingPathComponent(Attachments.folder)
        try? fm.removeItem(at: app.appendingPathComponent(Attachments.folder))
        if fm.fileExists(atPath: attachments.path) {
            try? fm.copyItem(at: attachments, to: app.appendingPathComponent(Attachments.folder))
        }
        _ = await Shell.run("xattr -cr \"$LAMP_APP\" && codesign --force -s - --entitlements \"$LAMP_ENTITLEMENTS\" \"$LAMP_APP\"", cwd: project.dir,
                            env: ["LAMP_APP": app.path, "LAMP_ENTITLEMENTS": entitlements.path]) { _ in }
    }

    /// iPhone apps running in the simulator: which simulator each was launched on, and its process id.
    private var simulatorApps: [String: (udid: String, pid: Int32)] = [:]
    /// Which project each simulator belongs to right now: taken before a launch's first wait, so two launches
    /// on one device can't both go ahead, and checked before every action the driver takes.
    private var simulatorLeases: [String: String] = [:]

    /// For Open App and Undo, where no agent is running to fix a crash.
    private func installReportingCrash(_ project: LampProject) async {
        if await install(project) != nil {
            log(project, .error, ErrorMessages.crashAfterLaunch(project.name))
        }
    }

    /// Puts the icon into the freshly built bundle, re-signs it, and swaps it into the apps folder.
    /// The swap is atomic, so it's safe even while the app is running.
    private func deploy(_ project: LampProject) async throws {
        let fm = FileManager.default
        let resources = project.builtURL.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        // Without these, macOS kills the app the moment it uses the mic, speech recognition or camera.
        // Added here rather than in build.sh so apps made before this change get them too.
        _ = await Shell.run("""
            P="$LAMP_APP/Contents/Info.plist"
            plutil -replace CFBundleName -string "$LAMP_NAME" "$P" && \
            plutil -replace CFBundleDisplayName -string "$LAMP_NAME" "$P" && \
            plutil -replace NSMicrophoneUsageDescription -string "$LAMP_NAME listens to your microphone." "$P" && \
            plutil -replace NSSpeechRecognitionUsageDescription -string "$LAMP_NAME turns your speech into text." "$P" && \
            plutil -replace NSCameraUsageDescription -string "$LAMP_NAME uses your camera." "$P" && \
            plutil -replace NSCalendarsFullAccessUsageDescription -string "$LAMP_NAME reads and adds calendar events." "$P" && \
            plutil -replace NSRemindersFullAccessUsageDescription -string "$LAMP_NAME reads and adds reminders." "$P" && \
            plutil -replace NSContactsUsageDescription -string "$LAMP_NAME looks up people in your contacts." "$P" && \
            plutil -replace NSAppleEventsUsageDescription -string "$LAMP_NAME reads your email and drafts replies through Mail." "$P"
            """, cwd: project.dir, env: ["LAMP_APP": project.builtURL.path, "LAMP_NAME": project.name]) { _ in }
        if fm.fileExists(atPath: Icons.icnsURL(project).path) {
            try? fm.removeItem(at: resources.appendingPathComponent("AppIcon.icns"))
            try fm.copyItem(at: Icons.icnsURL(project), to: resources.appendingPathComponent("AppIcon.icns"))
            // With Xcode 26, the compiled Icon Composer icon lets macOS 26 draw it in Liquid Glass.
            try? fm.removeItem(at: resources.appendingPathComponent("Assets.car"))
            let hasCar = fm.fileExists(atPath: Icons.carURL(project).path)
            if hasCar { try fm.copyItem(at: Icons.carURL(project), to: resources.appendingPathComponent("Assets.car")) }
            let iconName = hasCar
                ? "plutil -replace CFBundleIconName -string AppIcon \"$LAMP_APP/Contents/Info.plist\""
                : "{ plutil -remove CFBundleIconName \"$LAMP_APP/Contents/Info.plist\" 2>/dev/null || true; }"
            _ = await Shell.run("""
                plutil -replace CFBundleIconFile -string AppIcon "$LAMP_APP/Contents/Info.plist" && \(iconName)
                """, cwd: project.dir, env: ["LAMP_APP": project.builtURL.path]) { _ in }
        }
        // Files attached in Lamp's chat ship inside the app, where LampAssets finds them.
        let attachments = project.dir.appendingPathComponent(Attachments.folder)
        try? fm.removeItem(at: resources.appendingPathComponent(Attachments.folder))
        if fm.fileExists(atPath: attachments.path) {
            try fm.copyItem(at: attachments, to: resources.appendingPathComponent(Attachments.folder))
        }
        // Signed from Lamp's own keychain, which the script unlocks, so nobody is asked for keychain access.
        // Files copied into the bundle (attachments, icon artwork, an edited Info.plist) can carry Finder
        // metadata and resource forks. codesign accepts those for an ad hoc signature but refuses them for a
        // certificate one ("resource fork, Finder information, or similar detritus not allowed"), which is
        // how apps silently ended up ad hoc. Strip them first.
        _ = await Shell.run("xattr -cr \"$LAMP_APP\"", cwd: project.dir, env: ["LAMP_APP": project.builtURL.path]) { _ in }
        let identity = await AppSigning.identity()
        var signed = false
        if identity != "-" {
            var output: [String] = []
            signed = await Shell.run("codesign --force --keychain \"$LAMP_KEYCHAIN\" -s \"$LAMP_IDENTITY\" \"$LAMP_APP\" 2>&1",
                                     cwd: project.dir,
                                     env: ["LAMP_APP": project.builtURL.path, "LAMP_IDENTITY": identity,
                                           "LAMP_KEYCHAIN": AppSigning.keychain]) { output.append($0) } == 0
            // Trust the result, not the exit status: check the app really carries the certificate.
            if signed && !AppSigning.isCertificateSigned(project.builtURL) {
                signed = false
                output.append("codesign returned 0 but the app is not certificate-signed")
            }
            if !signed { print("Signing \(project.name) with \(identity) failed:\n" + output.joined(separator: "\n")) }
        }
        print("Install \(project.name): identity=\(identity) signed=\(signed)")
        if !signed {
            // Ad hoc keeps the app installable, but macOS won't remember its permissions across rebuilds and
            // won't ask for Location Services at all, so this is logged rather than silent.
            _ = await Shell.run("codesign --force -s - \"$LAMP_APP\"", cwd: project.dir,
                                env: ["LAMP_APP": project.builtURL.path]) { _ in }
        }

        // What the copy being replaced was signed as, to notice when this build is signed differently.
        let replaced = await AppSigning.requirement(of: project.installedURL)

        try fm.createDirectory(at: Self.installDir, withIntermediateDirectories: true)
        let staging = Self.installDir.appendingPathComponent(".\(project.exe)-\(UUID().uuidString).app")
        try fm.copyItem(at: project.builtURL, to: staging)
        if fm.fileExists(atPath: project.installedURL.path) {
            _ = try fm.replaceItemAt(project.installedURL, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: project.installedURL)
        }
        // Nudge Finder, the Dock and Launchpad to pick up the new icon.
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: project.installedURL.path)
        _ = await Shell.run(
            Self.lsregister + " -f \"$LAMP_APP\"",
            cwd: project.dir, env: ["LAMP_APP": project.installedURL.path]) { _ in }
        // macOS keeps a permission with the signature it was given to. Signed differently, the app has lost
        // what it had, but System Settings still shows the old entries switched on, and they do nothing.
        if let replaced, let requirement = await AppSigning.requirement(of: project.installedURL), replaced != requirement,
           await AppSigning.forgetPermissions(of: project.bundleID) {
            print("\(project.name) is signed differently from the copy it replaced, so its macOS permissions were cleared:\n"
                  + "  was: \(replaced)\n  now: \(requirement)")
            log(project, .status, signed
                ? "If you gave \(project.name) a permission in System Settings (such as Full Disk Access or Screen Recording), macOS needs it once more: Lamp signs apps with a new certificate. After that it stays on."
                : "Lamp couldn't sign \(project.name) properly, so macOS will ask for its permissions again after every change.")
        }
    }

    // MARK: - Icons

    /// Makes sure icon.json exists, then renders it (with cached artwork if there is any).
    private func prepareIcon(_ project: LampProject) async {
        await iconDesigns[project.id]?.value
        var spec = Icons.load(project)
        if spec == nil && project.untitled { return }   // keeps its placeholder until the first message
        if spec == nil {
            log(project, .status, "Designing an icon…")
            spec = await Icons.design(for: project)
            Icons.save(spec!, for: project)
        }
        await renderIcon(project, spec: spec!)
    }

    private func renderIcon(_ project: LampProject, spec: IconSpec) async {
        do {
            let art = Icons.cachedArt(project, spec: spec)
            if art != nil { artApplied[project.id] = spec }
            icons[project.id] = try await Icons.write(spec, art: art, for: project)
        } catch {
            log(project, .detail, "Icon render failed: \(error.localizedDescription)")
        }
    }

    /// Asks for an OpenRouter key in the app's chat, once per app: the moment an app first wants a picture is
    /// when a key is worth explaining, not the welcome screen.
    private func askForKey(_ project: LampProject, because reason: String) {
        guard !(logs[project.id] ?? []).contains(where: { $0.kind == .needsKey }) else { return }
        log(project, .needsKey, reason)
    }

    /// Generates artwork for the icon's object in the background (best of a few candidates) and swaps it in
    /// when ready, with whatever can make pictures. With nothing, the first app asks for a key instead.
    private func upgradeIconArt(_ project: LampProject) {
        guard let spec = Icons.load(project), !spec.subject.trimmed.isEmpty,
              Icons.cachedArt(project, spec: spec) == nil else { return }
        guard artInProgress.insert(project.id).inserted else { return }
        Task {
            defer { artInProgress.remove(project.id) }
            guard await AppAI.imageRoute() != nil else {
                askForKey(project, because: "Lamp can draw a proper icon for \(project.name), and pictures inside your apps, with an OpenRouter key.")
                return
            }
            do {
                let art = try await Icons.generateBestArt(spec, appName: project.name) { [weak self] in
                    self?.log(project, .detail, $0)
                }
                let url = Icons.artURL(project, spec: spec)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let tiff = art.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?
                    .representation(using: .png, properties: [:]) else { return }
                try png.write(to: url)
                guard Icons.load(project) == spec else { return }   // the icon was redesigned meanwhile
                // During a build the install that ends it picks the artwork up; if that install came first,
                // finish() applies it. Otherwise apply it now.
                // Deploying touches build/ and the installed app, so it owns the app like a turn does. If a
                // turn has it, the install that ends the turn (or finish()) picks the artwork up.
                guard begin(project) != nil else { pendingIconArt.insert(project.id); return }
                await applyIconArt(project, spec: spec)
                finish(project)
            } catch let failure as AppAI.Failure where failure.message == AppAI.noImageRoute {
                // Codex signed out between the check and the pictures: the key card is still the right answer.
                askForKey(project, because: "Lamp can draw a proper icon for \(project.name), and pictures inside your apps, with an OpenRouter key.")
            } catch {
                log(project, .detail, "Icon artwork failed: \(error.localizedDescription)")
            }
        }
    }

    /// Designs a fresh icon (different from the current one) and applies it without restarting the app.
    func newIcon(_ project: LampProject) async {
        guard begin(project) != nil else { return }
        defer { finish(project) }
        log(project, .status, "Designing a new icon…")
        let spec = await Icons.design(for: project, avoiding: Icons.load(project))
        Icons.save(spec, for: project)
        await renderIcon(project, spec: spec)
        if FileManager.default.fileExists(atPath: project.builtURL.path) {
            try? await deploy(project)
        }
        log(project, .status, AppAI.imageRoute != nil ? "New icon applied. Artwork is on its way." : "New icon applied.")
        Task { upgradeIconArt(project) }
    }

    /// Gives apps made before icons existed an icon, once.
    private func backfillIcons() async {
        for project in projects where Icons.load(project) == nil {
            // Owning the app for the whole of it: the icon design is an AI call, and a build starting
            // meanwhile would get a half-finished bundle installed.
            guard begin(project) != nil else { continue }
            await prepareIcon(project)
            if FileManager.default.fileExists(atPath: project.builtURL.path) {
                try? await deploy(project)
            }
            finish(project)
            upgradeIconArt(project)
        }
    }

    /// Keeps `openApps` current as apps launch and quit. Menu bar apps don't always announce themselves,
    /// so it's also checked whenever Lamp comes to the front and after Lamp opens or quits one.
    private func watchOpenApps() {
        refreshOpenApps()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { Store.shared.refreshOpenApps() }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Store.shared.refreshOpenApps() }
        }
    }

    private func refreshOpenApps() {
        let prefix = Edition.appBundlePrefix
        var ids = NSWorkspace.shared.runningApplications
            .compactMap { $0.isTerminated ? nil : $0.bundleIdentifier }
            .filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        simulatorApps = simulatorApps.filter { Simulator.isRunning(pid: $0.value.pid) }
        ids += simulatorApps.keys
        deviceApps = deviceApps.filter { $0.value.isRunning }
        ids += deviceApps.keys
        if Set(ids) != openApps { openApps = Set(ids) }
    }

    /// Quits the app, for the Stop button. Asks it nicely first, then insists.
    func quitApp(_ project: LampProject) async {
        await quit(project)
        refreshOpenApps()
    }

    private func quit(_ project: LampProject) async {
        if project.platform == .iphone {
            if let attached = deviceApps[project.id] {
                if attached.isRunning { attached.terminate() }
                deviceApps[project.id] = nil
            }
            // On the simulator it was launched on, not whichever one would be picked now.
            if let running = simulatorApps[project.id] {
                await Simulator.terminate(project.bundleID, on: running.udid)
                if simulatorLeases[running.udid] == project.id { simulatorLeases[running.udid] = nil }
            }
            simulatorApps[project.id] = nil
            refreshOpenApps()
            return
        }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: project.bundleID) {
            app.terminate()
            for _ in 0..<30 where !app.isTerminated {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if !app.isTerminated { app.forceTerminate() }
        }
    }

    // MARK: - AI gateway for generated apps

    private func startGateway() {
        let gateway = Gateway { request in await Store.shared.handleAI(request) }
        do {
            try gateway.start()
            gateway.setLocalNetwork(Experiments.devices)
            self.gateway = gateway
        } catch {
            NSLog("Lamp AI gateway failed to start: \(error)")
        }
    }

    /// Whether apps on the person's phones may reach Lamp over the local network (Settings → Experimental).
    func setLocalNetwork(_ on: Bool) {
        gateway?.setLocalNetwork(on)
        refreshDevices()
    }

    func handleAI(_ request: Gateway.Request) async -> (Int, [String: Any]) {
        let route = request.path.split(separator: "?").first.map(String.init) ?? request.path
        let paths = ["/ai", "/ai/image", "/ai/decide", "/ai/computer", "/agent/computer", "/agent/look", "/agent/use", "/agent/approve",
                     "/agent/versions", "/agent/versions/name", "/agent/versions/restore", "/mcp", "/pi/key"]
        // MCP clients may try to open a listening stream (GET) or end a session (DELETE): neither is offered.
        if route == "/mcp", request.method != "POST" { return (405, ["error": "Method not allowed"]) }
        guard request.method == "POST", paths.contains(route) else {
            return (404, ["error": "Not found"])
        }
        // Only requests addressed to this Mac: a web page that resolved its own name to 127.0.0.1 (DNS
        // rebinding) arrives with that name as the host, and gets nothing. No Host at all gets nothing either.
        let token = request.headers["authorization"]?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        let agentRoute = route == "/mcp" || route.hasPrefix("/agent/")
        if request.fromNetwork {
            // An app on the person's phone: only the app routes, addressed to this Mac by its network name,
            // with the app's own token like any other. The agent's routes never leave the Mac, and neither
            // does the one that hands pi its key.
            guard !agentRoute, route != "/pi/key", Self.isMacHost(request.headers["host"]) else {
                return (403, ["error": "Not for this host."])
            }
        } else {
            guard Self.isLocalHost(request.headers["host"]) else { return (403, ["error": "Not for this host."]) }
        }
        // pi collecting its provider's key (Agent.keyCommand). The ticket is the whole credential, and it's
        // good once.
        if route == "/pi/key" {
            guard let key = KeyTicket.redeem(token) else { return (403, ["error": "This ticket isn't good any more."]) }
            return (200, ["key": key])
        }
        // A coding agent driving another app's task (ComputerUse.Job): its token opens only the task's own
        // tools, over MCP (Claude Code, Codex) or pi's extension's route, never the build tools.
        if let task = computerTasks[token] {
            guard route == "/mcp" || route == "/agent/computer" else { return (403, ["error": "Not for this task."]) }
            return await computerCall(request, task: task, mcp: route == "/mcp")
        }
        if agentRoute {
            // The agent's routes take only the agent's token for the turn in progress.
            guard let id = agentTokens[token], let project = projects.first(where: { $0.id == id }) else {
                return (401, ["error": "Lamp isn't working on this app right now."])
            }
            guard setup.ready else { return (503, ["error": "Lamp isn't set up yet. Open Lamp to finish setup."]) }
            guard turns[project.id]?.agent != nil else { return (409, ["error": "Lamp isn't working on this app right now."]) }
            return await agentRequest(request, route: route, for: project)
        }
        // The app may have been created since the last reload. A reload rereads every app, so a stale app
        // polling with an old token can't make Lamp do that on every request.
        if tokens[token] == nil, Date().timeIntervalSince(lastReloadForToken) > 5 {
            lastReloadForToken = Date()
            reload()
        }
        guard let id = tokens[token], let project = projects.first(where: { $0.id == id }) else {
            return (401, ["error": "This app isn't registered with Lamp."])
        }
        guard setup.ready else { return (503, ["error": "Lamp isn't set up yet. Open Lamp to finish setup."]) }
        return await appRequest(request, for: project)
    }

    /// Whether a Host header is this Mac's name on the local network (what apps on phones are given), with
    /// an optional port: "matts-macbook-pro.local:47811".
    static func isMacHost(_ header: String?) -> Bool {
        guard let host = header?.trimmed.lowercased(), !host.isEmpty else { return false }
        let name = host.split(separator: ":", maxSplits: 1).first.map(String.init) ?? host
        guard host.count == name.count || host.dropFirst(name.count + 1).allSatisfy(\.isNumber) else { return false }
        return name == Devices.macHost.lowercased()
    }

    /// Whether a Host header names this Mac and nothing else: exactly a loopback name or address, with an
    /// optional numeric port. "localhost.evil.example" and "127.0.0.1.evil.example" are not.
    static func isLocalHost(_ header: String?) -> Bool {
        guard var host = header?.trimmed.lowercased(), !host.isEmpty else { return false }
        if host.hasPrefix("[") {   // an IPv6 address, [::1] or [::1]:port
            guard let close = host.firstIndex(of: "]") else { return false }
            let port = host[host.index(after: close)...]
            guard port.isEmpty || (port.hasPrefix(":") && port.count > 1 && port.dropFirst().allSatisfy(\.isNumber)) else { return false }
            host = String(host[...close])
        } else if let colon = host.firstIndex(of: ":") {
            let port = host[host.index(after: colon)...]
            guard !port.isEmpty, port.allSatisfy(\.isNumber) else { return false }
            host = String(host[..<colon])
        }
        return ["127.0.0.1", "localhost", "[::1]"].contains(host)
    }

    /// The routes the agent uses mid-turn: build and try the app, approvals, versions, and the MCP tools.
    private func agentRequest(_ request: Gateway.Request, route: String, for project: LampProject) async -> (Int, [String: Any]) {
        if route == "/mcp" { return await mcp(request.body, for: project, fileTools: request.path.contains("files=1")) }
        if request.path == "/agent/look" { return await look(at: project) }
        if request.path == "/agent/use" { return await use(project, request: request.body) }
        if request.path.hasPrefix("/agent/versions") {
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            return await versions(String(request.path.dropFirst("/agent/versions".count)), body, of: project)
        }
        if route == "/agent/approve" {
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            // One of the agent's file tools, about to touch something outside the app's folder or in its runtime folder.
            if let tool = body["file_tool"] as? String, let path = body["path"] as? String {
                let (allowed, reason) = await fileAccess(tool: tool, path: path, for: project)
                return (200, reason.map { ["allow": allowed, "reason": $0] } ?? ["allow": allowed])
            }
            // pi's extension sends {"command"}; Claude Code's hook sends {"tool_input": {"command"}}.
            let input = body["tool_input"] as? [String: Any] ?? [:]
            let tool = body["tool_name"] as? String ?? "Bash"
            if request.path.contains("format=claude-file") {
                // One of Claude Code's file tools, before it runs: the same check pi's and Codex's get.
                let names = ["Read": "read", "Edit": "edit", "Write": "write", "Glob": "find", "Grep": "grep"]
                let path = input["file_path"] as? String ?? input["path"] as? String ?? project.dir.path
                var (allowed, reason) = (false, nil as String?)
                if tool == "Glob" || tool == "Grep", Privacy.wouldUncover(root: path, project: project) {
                    reason = "That search would pass over Lamp's own files, which aren't yours to open. Search a narrower folder."
                } else {
                    (allowed, reason) = await fileAccess(tool: names[tool] ?? "read", path: path, for: project)
                }
                var output: [String: Any] = ["hookEventName": "PreToolUse", "permissionDecision": allowed ? "allow" : "deny"]
                if let reason { output["permissionDecisionReason"] = reason }
                return (200, ["hookSpecificOutput": output])
            }
            var command = body["command"] as? String ?? input["command"] as? String ?? ""
            let shell = !command.isEmpty
            if command.isEmpty {   // a non-shell tool Claude Code wants permission for (e.g. a write outside the app)
                let target = input["file_path"] as? String ?? input["url"] as? String ?? input["path"] as? String ?? ""
                command = target.isEmpty ? tool : "\(tool): \(target)"
            }
            // Claude Code already ran its own classifier before asking ("claude-permission"), so ask the user.
            let escalated = request.path.contains("format=claude-permission")
            if request.path.contains("format=codex") {
                // Codex's PreToolUse hook can only block: an empty answer lets the command run.
                let allowed = await approveCommand(command, for: project, escalated: false)
                return (200, allowed ? [:] : ["hookSpecificOutput": ["hookEventName": "PreToolUse",
                                                                     "permissionDecision": "deny",
                                                                     "permissionDecisionReason": "The user denied this command in Lamp."]])
            }
            let allowed = await approveCommand(command, for: project, escalated: escalated, shell: shell)
            let reason = allowed ? "Approved in Lamp." : "The user denied this command in Lamp."
            if escalated {
                let decision: [String: Any] = allowed ? ["behavior": "allow"] : ["behavior": "deny", "message": reason]
                return (200, ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]])
            }
            if request.path.contains("format=claude") {
                return (200, ["hookSpecificOutput": ["hookEventName": "PreToolUse",
                                                     "permissionDecision": allowed ? "allow" : "deny",
                                                     "permissionDecisionReason": reason]])
            }
            return (200, ["allow": allowed, "reason": reason])
        }
        return (404, ["error": "Not found"])
    }

    /// The routes a running app uses: text, pictures, decisions, and using the other apps on the Mac.
    private func appRequest(_ request: Gateway.Request, for project: LampProject) async -> (Int, [String: Any]) {
        if request.path == "/ai/computer" { return await useComputer(for: project, request: request.body) }
        if request.path == "/ai/decide" {
            guard let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any],
                  let state = body["state"], let questions = body["questions"] as? [String: Any], !questions.isEmpty else {
                return (400, ["error": "A decision needs `state` and at least one question."])
            }
            do {
                let (answers, cost) = try await AppAI.decide(state: state, questions: questions,
                                                             model: AppModels.load(project).decision)
                record(project, cost: cost)
                return (200, ["answers": answers])
            } catch let failure as AppAI.Failure {
                return (502, ["error": failure.message])
            } catch {
                return (502, ["error": "Couldn't reach the decision model: \(error.localizedDescription)"])
            }
        }
        guard let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any],
              let prompt = body["prompt"] as? String, !prompt.trimmed.isEmpty else {
            return (400, ["error": "Missing prompt."])
        }
        do {
            let images = (body["images"] as? [[String: String]] ?? []).compactMap { image -> AppAI.Image? in
                guard let type = image["media_type"], let data = image["data"] else { return nil }
                return AppAI.Image(mediaType: type, data: data)
            }
            if request.path == "/ai/image" {
                do {
                    let (png, cost) = try await AppAI.image(prompt: prompt, references: images,
                                                            aspectRatio: body["aspect_ratio"] as? String,
                                                            model: AppModels.load(project).image)
                    record(project, cost: cost)
                    return (200, ["image": png.base64EncodedString(), "media_type": "image/png"])
                } catch let failure as AppAI.Failure where failure.message == AppAI.noImageRoute {
                    askForKey(project, because: "\(project.name) wants to make a picture, and nothing here can yet.")
                    throw failure
                }
            }
            let (text, cost) = try await AppAI.complete(prompt: prompt, images: images,
                                                         system: body["system"] as? String ?? "",
                                                         json: body["json"] as? Bool ?? false,
                                                         appModel: body["model"] as? String ?? AppModels.load(project).text)
            record(project, cost: cost)
            return (200, ["text": text])
        } catch let failure as AppAI.Failure {
            if failure.cost > 0 { record(project, cost: failure.cost) }   // billed even though it failed
            return (502, ["error": failure.message])
        } catch {
            return (502, ["error": "Couldn't reach the AI: \(error.localizedDescription)"])
        }
    }

    /// `LampComputer.ask` / `.perform` from an app: a task done with the other apps on the Mac (see ComputerUse).
    private func useComputer(for project: LampProject, request body: Data) async -> (Int, [String: Any]) {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let task = (json["task"] as? String)?.trimmed, !task.isEmpty else { return (400, ["error": "Missing task."]) }
        let allowActions = json["act"] as? Bool ?? false
        guard ComputerUse.enabled, await ComputerUse.status() == .ready else {
            // Asked once per app per launch: an app that keeps trying would otherwise raise a dialog per call.
            if computerUseRefused.insert(project.id).inserted {
                NSApp.activate()
                let alert = NSAlert()
                alert.messageText = "\(project.name) wants to use your other apps"
                alert.informativeText = "To let apps read and use apps like Slack, Mail or your browser, turn on “Let apps use your other apps” in Lamp's settings."
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Not Now")
                if await present(alert) == .alertFirstButtonReturn {
                    UserDefaults.standard.set("apps", forKey: "settingsTab")
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
            return (503, ["error": "Using other apps is turned off. Turn on “Let apps use your other apps” in Lamp → Settings → Apps, then try again."])
        }
        if let problem = ComputerUse.check() { return (502, ["error": problem.message]) }
        // The model the app chose in its info panel; Sonnet if it hasn't chosen one. Its OpenRouter name with a
        // key, its own name for Claude Code or Codex answering instead.
        let chosen = AppAI.models.first { $0.id == AppModels.load(project).text } ?? AppAI.defaultModel
        let model = Provider.hasKey ? chosen.openRouter : chosen.id
        var allowAll = false
        do {
            let work = try await ComputerUse.Job(task, appName: project.name, allowActions: allowActions) { [weak self] action in
                guard let self, ComputerUse.enabled else { return false }
                if allowAll { return true }
                let answer = await self.confirm(action, for: project)
                if answer == .allowAll { allowAll = true }
                return answer != .deny
            }
            defer { work.close() }
            let token = UUID().uuidString + UUID().uuidString
            computerTasks[token] = work
            defer { computerTasks[token] = nil }
            let (text, cost) = try await ComputerUse.answer(work, model: model, token: token)
            record(project, cost: cost)
            return (200, ["text": text])
        } catch {
            return (502, ["error": error.localizedDescription])
        }
    }

    /// Tasks a coding agent is driving right now, by the token that agent was given.
    private var computerTasks: [String: ComputerUse.Job] = [:]

    /// A coding agent's call into a task: MCP for Claude Code and Codex (list the tools, call one), or pi's
    /// extension's plain POST of {name, arguments}, answered with the text and the pictures.
    private func computerCall(_ request: Gateway.Request, task: ComputerUse.Job, mcp: Bool) async -> (Int, [String: Any]) {
        let json = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        guard mcp else {
            guard let name = json["name"] as? String else { return (400, ["error": "Missing tool name."]) }
            do {
                let (text, pictures) = try await task.call(name, json["arguments"] as? [String: Any] ?? [:])
                return (200, ["text": text, "pictures": pictures.map { ["mimeType": $0.mimeType, "data": $0.data] }])
            } catch {
                return (502, ["error": error.localizedDescription])
            }
        }
        guard let method = json["method"] as? String else {
            return (400, ["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Not a JSON-RPC request."]])
        }
        let id = json["id"] ?? NSNull()
        func reply(_ result: [String: Any]) -> (Int, [String: Any]) { (200, ["jsonrpc": "2.0", "id": id, "result": result]) }
        switch method {
        case "initialize":
            return reply(["protocolVersion": "2025-03-26", "capabilities": ["tools": [:]],
                          "serverInfo": ["name": "lamp", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"]])
        case "ping":
            return reply([:])
        case "tools/list":
            return reply(["tools": task.mcpTools])
        case "tools/call":
            let params = json["params"] as? [String: Any] ?? [:]
            do {
                let (text, pictures) = try await task.call(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:])
                var content: [[String: Any]] = [["type": "text", "text": text]]
                content += pictures.map { ["type": "image", "data": $0.data, "mimeType": $0.mimeType] }
                return reply(["content": content])
            } catch {
                return reply(["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
            }
        default:
            if json["id"] == nil { return (202, [:]) }
            return (200, ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
    }

    private enum ActionAnswer { case allow, allowAll, deny }

    /// Asks the person before an app clicks, types or presses keys in another app.
    private func confirm(_ action: ComputerUse.Action, for project: LampProject) async -> ActionAnswer {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "\(project.name) wants to use \(action.target)"
        alert.informativeText = action.details
            + (action.intent.map { "\n\nThe AI says it's doing this to: \($0)" } ?? "")
        alert.icon = NSWorkspace.shared.icon(forFile: project.installedURL.path)
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Allow All for This Task")
        alert.addButton(withTitle: "Don't Allow")
        switch await present(alert) {
        case .alertFirstButtonReturn: return .allow
        case .alertSecondButtonReturn: return .allowAll
        default: return .deny
        }
    }

    /// Shows an alert without stopping everything else: as a sheet on Lamp's window when there is one, so
    /// other apps' turns and requests carry on while it waits for an answer.
    private func present(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) else {
            return alert.runModal()
        }
        return await alert.beginSheetModal(for: window)
    }

    /// The agent's version tools: `list_versions`, `name_version` and `restore_version`. `action` is "" to
    /// list, "/name" or "/restore", for pi's endpoint and the MCP tools alike.
    private func versions(_ action: String, _ body: [String: Any], of project: LampProject) async -> (Int, [String: Any]) {
        // Only for the agent Lamp is running right now: the app knows the same token, and must not be
        // able to change its own history.
        guard turns[project.id]?.agent != nil else { return (409, ["error": "Lamp isn't working on this app right now."]) }
        let versions = await Versions.list(project)
        let id = (body["version"] as? String)?.trimmed.nilIfEmpty
        let version = id.flatMap { Versions.find($0, in: versions) }
        if id != nil && version == nil {
            return (404, ["error": "There's no version \(id!). Call list_versions for the ids."])
        }
        switch action {
        case "/name":
            guard let name = (body["name"] as? String)?.trimmed.nilIfEmpty else { return (400, ["error": "A name is needed."]) }
            guard let version else {
                turns[project.id]?.pendingName = name
                return (200, ["text": "Lamp will name the version this request makes “\(name)”."])
            }
            await Versions.name(project, version.id, name)
            versionsRevision += 1
            return (200, ["text": "Named \(version.shortID) “\(name)”."])
        case "/restore":
            guard let version else { return (400, ["error": "Say which version to restore."]) }
            guard await Versions.restoreFiles(project, to: version) else {
                return (500, ["error": "Lamp couldn't restore that version."])
            }
            log(project, .status, Versions.restoredMessage(to: version))
            return (200, ["text": """
                The app's files are now as they were in “\(version.label)”. Your changes earlier in this request \
                are gone too. Read files again before editing them. Lamp builds and opens the app when you finish.
                """])
        default:
            return (200, ["text": Versions.describe(versions)])
        }
    }

    /// The agent's `look_at_app` tool: builds what it has written so far, opens the app behind the
    /// user's windows, and reports what happened. The pictures are sent as file paths for pi to read.
    private func look(at project: LampProject) async -> (Int, [String: Any]) {
        // Only for the agent Lamp is running right now. The app knows the same token and must not
        // be able to rebuild itself.
        guard let turn = turns[project.id], turn.agent != nil else {
            return (409, ["error": "Lamp isn't working on this app right now."])
        }
        guard !turn.look.inProgress else { return (200, ["text": "Lamp is already looking at the app. Wait for that result."]) }
        turn.look.inProgress = true
        turn.look.installed = false
        defer { turn.look.inProgress = false }

        try? Template.writeSupport(for: project)
        let changed = Runtime.sourcesChanged(project)
        if changed, let errors = await build(project) {
            return (200, ["text": "The app doesn't build yet. Fix these compiler errors:\n\n\(errors)"])
        }
        var note = "The app built and is running."
        var screenshots: [URL] = []
        if project.platform == .iphone {
            // The simulator photographs the screen; nothing in the app has to cooperate.
            // Open, and the device still this app's: otherwise it's opened again (which takes the device back).
            let running = simulatorApps[project.id].map { Simulator.isRunning(pid: $0.pid) && simulatorLeases[$0.udid] == project.id } ?? false
            if changed || !running {
                let crash = await install(project, inFront: false)
                turn.look.installed = true
                turn.look.crash = crash
                if let crash { return (200, ["text": "The app \(changed ? "built" : "is built"), but it didn't stay open.\n\n\(crash)"]) }
                if !changed { note = "The app is running your latest code; it was reopened without rebuilding." }
            } else {
                note = "The app is running your latest code; nothing needed rebuilding."
            }
            try? await Task.sleep(for: .seconds(1))
            let picture = Runtime.folder(project).appendingPathComponent("screenshot.png")
            if let udid = simulatorApps[project.id]?.udid, await Simulator.screenshot(on: udid, to: picture) { screenshots = [picture] }
            var text = note + " " + (screenshots.isEmpty ? "No picture of the iPhone could be taken."
                : Privacy.sharesPictures ? "A picture of the iPhone's screen follows. Points for use_app are pixels in it." : Privacy.picturesOff)
            if !Privacy.sharesLog { text += " " + Privacy.logOff }
            if Privacy.sharesLog, let tail = Runtime.logTail(project) { text += "\n\nWhat it printed:\n\(tail)" }
            return (200, ["text": text, "screenshots": Privacy.sharesPictures ? screenshots.map(\.path) : []])
        }
        if !changed, NSRunningApplication.runningApplications(withBundleIdentifier: project.bundleID).first != nil {
            // Nothing to rebuild and the app is open: ask it for fresh pictures instead of relaunching it.
            let asked = Date()
            Runtime.requestScreenshots(of: project)
            screenshots = await Runtime.screenshots(of: project, since: asked, waiting: 2)
            note = "The app is running your latest code; nothing needed rebuilding."
            turn.look.installed = !screenshots.isEmpty
            turn.look.crash = nil
        }
        if screenshots.isEmpty {
            let launched = Date()
            let crash = await install(project, inFront: false)
            turn.look.installed = true
            turn.look.crash = crash
            if let crash {
                return (200, ["text": "The app \(changed ? "built" : "is built"), but it quit right after launching.\n\n\(crash)"])
            }
            if !changed { note = "The app is running your latest code; it was reopened without rebuilding." }
            screenshots = await Runtime.screenshots(of: project, since: launched)
        }
        var text = note + " " + (screenshots.isEmpty
            ? "It has no window open, so there's no picture. If it lives in the menu bar, use_app's bar_icon opens its panel."
            : Privacy.sharesPictures ? "Pictures of its windows follow, frontmost first." : Privacy.picturesOff)
        if !Privacy.sharesLog { text += " " + Privacy.logOff }
        if Privacy.sharesLog, let tail = Runtime.logTail(project) { text += "\n\nWhat it printed:\n\(tail)" }
        return (200, ["text": text, "screenshots": Privacy.sharesPictures ? screenshots.map(\.path) : []])
    }

    private func record(_ project: LampProject, cost: Double) {
        usage[project.id, default: AppUsage()].calls += 1
        usage[project.id, default: AppUsage()].cost += cost
        saveUsage(project)
    }

    private func recordAgent(_ project: LampProject, cost: Double) {
        var current = usage[project.id] ?? AppUsage()
        current.agentRuns = (current.agentRuns ?? 0) + 1
        current.agentCost = (current.agentCost ?? 0) + cost
        usage[project.id] = current
        saveUsage(project)
    }

    private func saveUsage(_ project: LampProject) {
        if let data = try? JSONEncoder().encode(usage[project.id]) {
            try? data.write(to: project.dir.appendingPathComponent(".lamp/usage.json"))
        }
    }

    private static let lsregister =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    private static let commit = Versions.commit
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// One app's own choice of models for its AI features, in .lamp/models.json. nil uses Lamp's default
/// from Settings → Apps.
struct AppModels: Codable, Equatable {
    var text: String?       // an id from AppAI.models
    var image: String?      // an id from Icons.artModels
    var decision: String?   // an id from AppAI.decisionModels

    private static func url(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/models.json") }

    static func load(_ project: LampProject) -> AppModels {
        (try? Data(contentsOf: url(project))).flatMap { try? JSONDecoder().decode(AppModels.self, from: $0) } ?? AppModels()
    }

    func save(_ project: LampProject) {
        let url = Self.url(project)
        if self == AppModels() { try? FileManager.default.removeItem(at: url); return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url)
    }
}
