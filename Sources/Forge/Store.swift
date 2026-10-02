import SwiftUI
import AppKit

struct ForgeProject: Identifiable, Hashable {
    let id: String      // folder name; also used in forge:// links
    let name: String    // display name
    let exe: String     // Swift target / executable name
    let dir: URL
    /// Made with New App and not named yet. The first message names it.
    var untitled = false

    var bundleID: String { "dev.forge.app.\(id)" }
    var builtURL: URL { dir.appendingPathComponent("build/\(exe).app") }
    /// Every successful build is copied here so it shows up in Spotlight and Launchpad.
    var installedURL: URL { Store.installDir.appendingPathComponent("\(name).app") }
}

struct ProjectMeta: Codable {
    var name: String
    var exe: String
    var untitled: Bool?
}

struct AppUsage: Codable {
    var calls = 0       // AI calls made by the app itself
    var cost = 0.0
    // Optional so usage.json files from before these were tracked still decode.
    var agentRuns: Int?
    var agentCost: Double?

    var totalCost: Double { cost + (agentCost ?? 0) }
}

struct LogLine: Identifiable, Codable {
    enum Kind: String, Codable { case user, agent, status, error, detail, tool, summary }
    var id = UUID()
    let kind: Kind
    let text: String
    var attachments: [String]? = nil   // names in the app's Attachments/ folder
    var version: String? = nil         // for a request: the version it made

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
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var projects: [ForgeProject] = []
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
    /// Apps that are open right now, however they were started, so Forge can offer to quit them.
    @Published var openApps: Set<String> = []
    @Published var chatFocusRequest = 0
    @Published var setup = SetupCheck()
    @Published var usage: [String: AppUsage] = [:]
    @Published var icons: [String: NSImage] = [:]
    @Published var pendingImport: PendingImport?

    /// A shell command an agent wants to run, waiting for the user (see ApprovalCard).
    struct PendingApproval: Identifiable {
        let id = UUID()
        let command: String
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
    private var allowAllThisTurn: Set<String> = []
    /// The app whose Rename… alert is showing.
    @Published var renaming: ForgeProject?
    /// The app whose Delete confirmation is showing.
    @Published var deleting: ForgeProject?
    /// The version whose Name… alert is showing.
    @Published var naming: VersionNaming?
    /// Bumped when a version is named, so open version lists reload.
    @Published var versionsRevision = 0
    private var running: [String: Process] = [:]    // project id → agent process, for Stop
    private var stopped: Set<String> = []
    private var looks: [String: Look] = [:]         // project id → the agent's looks at the app this turn
    /// A name the agent gave the version its current request will make, applied once that's committed.
    private var pendingNames: [String: String] = [:]
    /// Apps whose versions are getting titles, so only one run at a time asks the model.
    private var titling: Set<String> = []

    /// What the agent's `look_at_app` tool has done during the current turn.
    private struct Look {
        static let limit = 3
        var count = 0
        var inProgress = false
        /// The app was built and opened by the last look, and this is how that launch went.
        var installed = false
        var crash: String?
    }
    private var artInProgress: Set<String> = []
    private var iconDesigns: [String: Task<Void, Never>] = [:]   // icons designed from the first message
    private var tokens: [String: String] = [:]   // gateway token → project id
    private var gateway: Gateway?

    nonisolated static let installDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/Forge Apps")

    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Forge/Apps")

    private init() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
        for project in projects { discardIfUnused(project.id) }
        selection = projects.first?.id
        startGateway()
        watchOpenApps()
        if !Provider.models.contains(where: { $0.id == UserDefaults.standard.string(forKey: "model") }) {
            UserDefaults.standard.set(Provider.model, forKey: "model")   // from the Claude Code era ("sonnet")
        }
        // Finding Claude Code / Codex / opencode means asking the login shell for PATH; do it off the main thread.
        Task.detached(priority: .utility) { _ = ToolLocator.userPath }
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
        if !setup.hasBuildTools && !setup.installRequested { requestBuildTools() }
        if !setup.hasBuildTools { pollSetup() }
        if setup.ready && !wasReady { await backfillIcons() }
    }

    func requestBuildTools() {
        SetupCheck.installBuildTools()
        setup.installRequested = true
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
            if setup.ready { await backfillIcons() }
        }
    }

    var selected: ForgeProject? { projects.first { $0.id == selection } }

    /// Clears the "ready" dot for the app on screen. Also called when Forge comes back to the front.
    func markRead() {
        if let selection, NSApp?.isActive ?? true { unread.remove(selection) }
    }

    /// Forge is in front with this app's chat on screen.
    func isWatching(_ id: String?) -> Bool {
        id != nil && selection == id && NSApp.isActive
    }

    func reload() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        projects = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(".forge/meta.json")),
                  let meta = try? JSONDecoder().decode(ProjectMeta.self, from: data) else { return nil }
            return ForgeProject(id: dir.lastPathComponent, name: meta.name, exe: meta.exe, dir: dir,
                                untitled: meta.untitled ?? false)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        for project in projects {
            tokens[Template.token(for: project)] = project.id
            if icons[project.id] == nil, let image = NSImage(contentsOf: Icons.previewURL(project)) {
                icons[project.id] = image
            }
        }
        for project in projects where logs[project.id] == nil {
            let forge = project.dir.appendingPathComponent(".forge")
            if let data = try? Data(contentsOf: forge.appendingPathComponent("chat.json")),
               let saved = try? JSONDecoder().decode([LogLine].self, from: data) {
                logs[project.id] = saved.map(\.upgraded)
            }
            if let data = try? Data(contentsOf: forge.appendingPathComponent("usage.json")),
               let saved = try? JSONDecoder().decode(AppUsage.self, from: data) {
                usage[project.id] = saved
            }
        }
    }

    func log(_ project: ForgeProject, _ kind: LogLine.Kind, _ text: String, attachments: [String]? = nil) {
        logs[project.id, default: []].append(LogLine(kind: kind, text: text, attachments: attachments))
        if kind == .status, text.hasSuffix("…") { note(text, for: project) }   // "Building…"
        saveChat(project)
    }

    private func saveChat(_ project: ForgeProject) {
        if let data = try? JSONEncoder().encode(logs[project.id]) {
            try? data.write(to: project.dir.appendingPathComponent(".forge/chat.json"))
        }
    }

    /// Updates what the app's turn is doing right now, for the build card and the activity line.
    /// `file` is the file being written or edited, when that's the step.
    private func note(_ activity: String, file: String? = nil, for project: ForgeProject) {
        guard let current = progress[project.id], current.activity != activity || current.currentFile != file else { return }
        progress[project.id]?.activity = activity
        progress[project.id]?.currentFile = file
    }

    // MARK: - Drafts

    /// What's typed but not sent in an app's chat.
    struct Draft {
        var text = ""
        var attachments: [URL] = []
    }

    private var drafts: [String: Draft] = [:]

    /// Each app keeps its own draft, so it's still there after switching apps. The text also survives a
    /// restart (.forge/draft.txt); attached files are only remembered while Forge runs.
    func draft(for project: ForgeProject) -> Draft {
        if let draft = drafts[project.id] { return draft }
        let text = try? String(contentsOf: project.dir.appendingPathComponent(".forge/draft.txt"), encoding: .utf8)
        return Draft(text: text ?? "")
    }

    func saveDraft(_ draft: Draft, for project: ForgeProject) {
        drafts[project.id] = draft
        let file = project.dir.appendingPathComponent(".forge/draft.txt")
        if draft.text.isEmpty {
            try? FileManager.default.removeItem(at: file)
        } else {
            try? draft.text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    func handle(url: URL) {
        if url.isFileURL && url.pathExtension == "forgeapp" {
            importApp(from: url)
            return
        }
        guard url.scheme == "forge",
              let slug = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "app" })?.value else { return }
        showChat(slug)
    }

    /// Brings Forge to the front on an app's chat, ready to type.
    func showChat(_ id: String) {
        reload()
        selection = id
        chatFocusRequest += 1
        NSApp.activate()
    }

    // MARK: - Actions

    /// New App: an untitled app, straight into its chat. Its first message names it and designs its icon.
    func create() {
        let project: ForgeProject
        do {
            project = try Template.scaffold(name: uniqueName("Untitled"), untitled: true, in: root)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        reload()
        selection = project.id
        chatFocusRequest += 1
        Task { await initRepo(project, message: "Scaffold") }
    }

    private func initRepo(_ project: ForgeProject, message: String) async {
        _ = await Shell.run("git init -q && git add -A && \(Self.commit) -qm \"$FORGE_MESSAGE\"", cwd: project.dir,
                            env: ["FORGE_MESSAGE": message]) { _ in }
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
    private func isPristine(_ project: ForgeProject) async -> Bool {
        var output: [String] = []
        let status = await Shell.run("test $(git rev-list --count HEAD) -eq 1 && git status --porcelain -- . ':!\(Attachments.folder)'",
                                     cwd: project.dir) { output.append($0) }
        return status == 0 && output.allSatisfy { $0.trimmed.isEmpty }
    }

    /// Renames an app. Before any work happens it is scaffolded afresh under the new name, so its folder,
    /// executable and bundle ID match. After that only the display name changes: the bundle ID stays,
    /// so the app keeps its settings and data. Returns the app as it is now.
    func rename(_ project: ForgeProject, to name: String) async {
        guard busy.insert(project.id).inserted else { return }
        finish(await performRename(project, to: name))
    }

    /// Renames while the app is marked busy, so nothing else starts on it meanwhile.
    private func performRename(_ project: ForgeProject, to rawName: String) async -> ForgeProject {
        let name = rawName.trimmed.filter { !"\"\\<>&/:".contains($0) }
        guard !name.isEmpty, name != project.name || project.untitled,
              let current = projects.first(where: { $0.id == project.id }) else { return project }
        let unique = uniqueName(name, ignoring: current.id)
        if await isPristine(current) {
            return await rescaffold(current, as: unique)
        }

        let fm = FileManager.default
        let renamed = ForgeProject(id: current.id, name: unique, exe: current.exe, dir: current.dir)
        try? JSONEncoder().encode(ProjectMeta(name: unique, exe: current.exe))
            .write(to: current.dir.appendingPathComponent(".forge/meta.json"))
        if fm.fileExists(atPath: current.installedURL.path) {
            try? fm.moveItem(at: current.installedURL, to: renamed.installedURL)
            _ = await Shell.run(Self.lsregister + " -f \"$FORGE_APP\"", cwd: current.dir,
                                env: ["FORGE_APP": renamed.installedURL.path]) { _ in }
        }
        // The old name in window titles and APP.md. Anything subtler is left for the agent.
        let sources = current.dir.appendingPathComponent("Sources")
        let files = (fm.enumerator(at: sources, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "ForgeSupport.swift" }
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let updated = text.replacingOccurrences(of: "\"\(current.name)\"", with: "\"\(unique)\"")
            if updated != text { try? updated.write(to: file, atomically: true, encoding: .utf8) }
        }
        let appMd = current.dir.appendingPathComponent("APP.md")
        if let text = try? String(contentsOf: appMd, encoding: .utf8), text.hasPrefix("# \(current.name)\n") {
            try? ("# \(unique)\n" + text.dropFirst(current.name.count + 3)).write(to: appMd, atomically: true, encoding: .utf8)
        }
        _ = await Shell.run("git add -A && \(Self.commit) -qm \"$FORGE_MESSAGE\"", cwd: current.dir,
                            env: ["FORGE_MESSAGE": "Rename to \(unique)"]) { _ in }
        reload()
        log(renamed, .status, "Renamed to \(unique)")
        return renamed
    }

    /// Replaces an untouched app with a fresh scaffold under its new name, carrying over its chat and queue.
    private func rescaffold(_ old: ForgeProject, as name: String) async -> ForgeProject {
        let fm = FileManager.default
        let project: ForgeProject
        do {
            project = try Template.scaffold(name: name, in: root)
        } catch {
            NSAlert(error: error).runModal()
            return old
        }
        for path in [".forge/chat.json", ".forge/usage.json", Attachments.folder] {
            let from = old.dir.appendingPathComponent(path)
            if fm.fileExists(atPath: from.path) {
                try? fm.copyItem(at: from, to: project.dir.appendingPathComponent(path))
            }
        }
        await initRepo(project, message: "Scaffold")
        await quit(old)
        try? fm.removeItem(at: old.installedURL)
        try? fm.removeItem(at: old.dir)

        logs[project.id] = logs.removeValue(forKey: old.id)
        usage[project.id] = usage.removeValue(forKey: old.id)
        queued[project.id] = queued.removeValue(forKey: old.id)
        if busy.remove(old.id) != nil { busy.insert(project.id) }
        if unread.remove(old.id) != nil { unread.insert(project.id) }
        tokens = tokens.filter { $0.value != old.id }
        reload()
        if selection == old.id { selection = project.id }
        return project
    }

    /// Display names must be unique: each app installs as "<name>.app" in ~/Applications/Forge Apps.
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
        panel.allowedContentTypes = [.forgeApp]
        panel.message = "Choose a Forge app someone shared with you"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importApp(from: url)
    }

    /// Puts the app's .forgeapp file on the clipboard, ready to paste into Slack, Messages, Mail or Finder.
    func copyAppFile(_ project: ForgeProject) {
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

    func chooseExport(_ project: ForgeProject) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.forgeApp]
        panel.nameFieldStringValue = "\(project.name).forgeapp"
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

    /// Opens a shared `.forgeapp`: unpacks it, then shows a review (fixed checklist + AI check) before building.
    func importApp(from file: URL) {
        NSApp.activate()
        guard setup.ready else {
            let alert = NSAlert()
            alert.messageText = "Finish setting up Forge first"
            alert.informativeText = "Then open the shared app again."
            alert.runModal()
            return
        }
        let package: Sharing.Package
        do {
            package = try Sharing.open(file)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        if let previous = pendingImport { try? FileManager.default.removeItem(at: previous.package.folder) }
        let pending = PendingImport(package: package)
        pendingImport = pending
        Task {
            let review = await Sharing.review(package)
            if pendingImport?.id == pending.id { pendingImport?.review = review }
        }
    }

    func cancelImport() {
        if let pending = pendingImport { try? FileManager.default.removeItem(at: pending.package.folder) }
        pendingImport = nil
    }

    func confirmImport() {
        guard let pending = pendingImport else { return }
        pendingImport = nil
        finishImport(pending.package)
    }

    private func finishImport(_ package: Sharing.Package) {
        defer { try? FileManager.default.removeItem(at: package.folder) }
        let fm = FileManager.default
        let project: ForgeProject
        do {
            project = try Template.scaffold(name: uniqueName(package.name), in: root)
            // Swap the scaffold's code for the shared code; keep Forge's own ForgeSupport.swift.
            let sources = project.dir.appendingPathComponent("Sources")
            for item in try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            where item.lastPathComponent != "ForgeSupport.swift" {
                try fm.removeItem(at: item)
            }
            let sharedSources = package.folder.appendingPathComponent("Sources").standardizedFileURL.path + "/"
            for file in package.sources where file.lastPathComponent != "ForgeSupport.swift" {
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
                // Files from older Forge versions carry full-square artwork; only cut-out objects fit the new icons.
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
    func send(_ prompt: String, attachments: [URL] = [], to project: ForgeProject) {
        queued[project.id, default: []].append(QueuedMessage(text: prompt, attachments: attachments))
        startQueued(project)
    }

    /// The first message bootstraps the app: it names an untitled app, then designs the icon
    /// while the agent builds the first version. Returns the app as it is now.
    private func bootstrap(_ project: ForgeProject, brief: String) async -> ForgeProject {
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
                }
                iconDesigns[designing.id] = nil
            }
        }
        return project
    }

    func unqueue(_ message: QueuedMessage, from project: ForgeProject) {
        queued[project.id]?.removeAll { $0.id == message.id }
    }

    private func startQueued(_ project: ForgeProject) {
        guard let messages = queued[project.id], !messages.isEmpty,
              busy.insert(project.id).inserted else { return }
        queued[project.id] = nil
        let first = !(logs[project.id] ?? []).contains { $0.kind == .user }
        // An imported app's first message isn't a new app: it has already been built.
        let newApp = first && Template.isScaffold(project)
        progress[project.id] = TurnProgress(newApp: newApp)
        Task {
            var project = project
            let saved = post(messages, to: project)
            let asked = (logs[project.id] ?? []).filter { $0.kind == .user }.suffix(messages.count).map(\.id)
            if first {
                let untitled = project
                project = await bootstrap(project, brief: messages.map(\.text).joined(separator: "\n\n"))
                if project.id != untitled.id { progress[project.id] = progress.removeValue(forKey: untitled.id) }
            }
            var worked = false
            var result = TurnResult(end: .failed, watched: true)
            defer {
                // A new app's card stays, showing the result; a later turn's activity line goes away.
                if newApp { progress[project.id]?.finish(worked: worked) } else { progress[project.id] = nil }
                if selection != project.id || !NSApp.isActive { unread.insert(project.id) }
                // Messages queued meanwhile start the next turn straight away; tell the user once it's all done.
                if !result.watched, (queued[project.id] ?? []).isEmpty { notify(project, after: result.end) }
                finish(project)
            }
            result = await turn(messages, attachments: saved, asked: asked, on: project)
            worked = result.end != .failed
            if newApp && worked { await showResult(of: project) }
        }
    }

    /// Puts the app's real window on its build card, once it has opened and saved a picture of itself.
    private func showResult(of project: ForgeProject) async {
        guard let started = progress[project.id]?.started,
              NSRunningApplication.runningApplications(withBundleIdentifier: project.bundleID).first != nil,
              let picture = await Runtime.screenshots(of: project, since: started, waiting: 4).first,
              let image = NSImage(contentsOf: picture) else { return }
        progress[project.id]?.screenshot = image
    }

    /// Posts a notification for a turn that ended while the user was looking elsewhere.
    /// Nothing for a turn the user stopped: it ends without an error.
    private func notify(_ project: ForgeProject, after end: TurnEnd) {
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
    private func finish(_ project: ForgeProject) {
        busy.remove(project.id)
        startQueued(project)
    }

    /// Puts the messages in the chat and their files in Attachments/. Returns the saved file names.
    private func post(_ messages: [QueuedMessage], to project: ForgeProject) -> [String] {
        var saved: [String] = []
        for message in messages {
            let names = Attachments.save(message.attachments, to: project)
            log(project, .user, message.text, attachments: names.isEmpty ? nil : names)
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
                      on project: ForgeProject) async -> TurnResult {
        let prompt = messages.map(\.text).joined(separator: "\n\n")

        let files = Attachments.inline(saved, in: project).map { "\(Attachments.folder)/\($0)" }
        let notes = Attachments.note(for: saved) + Versions.note(for: project) + Runtime.crashNote(for: project)
            + Runtime.screenshotNote(for: project)
        currentRequests[project.id] = prompt
        looks[project.id] = Look()
        pendingNames[project.id] = nil
        guard await runAgent(prompt + notes, files: files, on: project) else {
            return TurnResult(end: .failed, watched: isWatching(project.id))
        }
        // Only build when something changed: not after a question, and not again when the agent's last
        // look already built and opened exactly this code.
        try? Template.writeSupport(for: project)
        let changed = Runtime.sourcesChanged(project)
        if changed {
            guard await buildFixingErrors(project) else { return TurnResult(end: .failed, watched: isWatching(project.id)) }
        }
        // Opening the app brings it in front of Forge, so whether the user was watching is decided first.
        let watched = isWatching(project.id)
        // Nothing is committed when the agent changed no files.
        var committed = await Shell.run("git add -A && \(Self.commit) -qm \"$FORGE_PROMPT\"", cwd: project.dir,
                                        env: ["FORGE_PROMPT": prompt]) { _ in } == 0
        let edited = changed || committed
        var crash: String?
        if changed {
            crash = await install(project)
        } else if let look = looks[project.id], look.installed {
            crash = look.crash
            if crash == nil {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: project.bundleID).first {
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
            log(project, .error, "\(project.name) still quits right after opening. Try describing the change differently, or press Undo.")
        }
        // After the crash fixes, which amend the commit, so the name and the links stay on the version that's kept.
        if committed || pendingNames[project.id] != nil, let head = await Versions.head(project) {
            if let name = pendingNames.removeValue(forKey: project.id) { await Versions.name(project, head, name) }
            if committed {
                link(asked, to: head, in: project)
                if crash == nil { keepPicture(of: project, version: head) }
                titleVersions(project, limit: 1)
            }
            versionsRevision += 1
        }
        return TurnResult(end: crash != nil ? .failed : edited ? .changed : .replied, watched: watched)
    }

    /// Builds the app, sending compiler errors back to the agent up to three times. False when it still doesn't build.
    private func buildFixingErrors(_ project: ForgeProject) async -> Bool {
        var errors = await build(project)
        for _ in 0..<3 where errors != nil {
            log(project, .status, "Fixing a build problem…")
            guard await runAgent("The app failed to build. Fix these compiler errors:\n\n\(errors!)",
                                 on: project) else { return false }
            errors = await build(project)
        }
        if errors != nil {
            log(project, .error, "Sorry, I couldn't get that change working. Try describing it differently, or press Undo.")
        }
        return errors == nil
    }

    /// Returns false when the agent couldn't run at all (bad key, no credit, …), after telling the user why.
    private func runAgent(_ prompt: String, files: [String] = [], on project: ForgeProject) async -> Bool {
        try? Template.writeSupport(for: project)
        if let problem = Builder.problem() {
            log(project, .error, "\(problem) Open Forge → Settings (⌘,) to fix it.")
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
        stopped.remove(project.id)
        let sessionFile = Self.sessionFile(for: project, engine: engine)
        let run = Agent.run(prompt: prompt, files: files, project: project,
                            session: engine == .pi ? Self.piSession(for: project) : Self.savedSession(sessionFile))
        let status = await Shell.run(run.command, cwd: project.dir, env: run.env,
                                     started: { [weak self] in self?.running[project.id] = $0 }) { [weak self] line in
            guard let self else { return }
            for event in Agent.parseLine(line) {
                switch event {
                case .text(let text):
                    progress[project.id]?.upcoming = nil
                    log(project, .agent, text)
                case .step(let tool):
                    streamingTool = tool
                    streamingArguments = ""
                    let activity = TurnProgress.activity(tool: tool, partialArguments: "")
                    note(activity, for: project)
                    if progress[project.id]?.upcoming != activity { progress[project.id]?.upcoming = activity }
                case .stepArgs(let piece):
                    // The file name is among the first arguments; the rest is the file itself.
                    guard streamingArguments.count < 600 else { break }
                    streamingArguments += piece
                    let call = TurnProgress.call(tool: streamingTool, partialArguments: streamingArguments)
                    note(TurnProgress.activity(for: call), file: TurnProgress.file(changedBy: call), for: project)
                    let activity = TurnProgress.activity(for: call)
                    if progress[project.id]?.upcoming != activity { progress[project.id]?.upcoming = activity }
                case .plan(let parts):
                    progress[project.id]?.plan = parts
                    progress[project.id]?.tickWrittenParts()
                case .tool(let text, let fullCall):
                    progress[project.id]?.upcoming = nil
                    log(project, .tool, text)
                    let call = ToolCall(text)
                    note(TurnProgress.activity(for: call), file: TurnProgress.file(changedBy: call), for: project)
                    if call.action == .write || call.action == .edit, !call.argument.isEmpty,
                       progress[project.id]?.files.last != call.argument {
                        progress[project.id]?.files.removeAll { $0 == call.argument }
                        progress[project.id]?.files.append(call.argument)
                        progress[project.id]?.tickWrittenParts()
                    }
                    toolCalls += 1
                    // Compared in full: six different searches of one file all read "grep cache.json".
                    repeats = fullCall == lastTool ? repeats + 1 : 1
                    lastTool = fullCall
                    if repeats >= 6 || toolCalls > 150, failure == nil {
                        failure = repeats >= 6
                            ? "The model got stuck repeating the same step (\(text)), so Forge stopped it."
                            : "The model made over 150 changes in one go, so Forge stopped it."
                        running[project.id]?.terminate()
                    }
                case .cost(let amount): cost += amount
                case .failed(let text): failure = text
                case .raw(let text): log(project, .detail, text)
                case .session(let id): if engine != .pi { try? id.write(to: sessionFile, atomically: true, encoding: .utf8) }
                }
            }
        }
        running[project.id] = nil
        progress[project.id]?.upcoming = nil
        endApprovals(for: project)
        log(project, .summary, LogLine.workSummary(seconds: Date().timeIntervalSince(started), cost: cost))
        recordAgent(project, cost: cost)
        if stopped.remove(project.id) != nil {
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
        if engine == .claude, CommandApproval.current == .auto, !CommandApproval.claudeAutoUnavailable,
           lower.contains("auto"), lower.contains("mode") || lower.contains("permission") {
            CommandApproval.claudeAutoUnavailable = true
            log(project, .status, "Claude Code's auto mode isn't available, so Forge will ask before every command.")
            return await runAgent(prompt, files: files, on: project)
        }
        log(project, .error, Provider.friendlyError(failure))
        return false
    }

    /// One pi conversation per app, so the agent remembers earlier requests, including ones that were undone.
    private static func piSession(for project: ForgeProject) -> String {
        let url = project.dir.appendingPathComponent(".forge/pi-session")
        if let id = (try? String(contentsOf: url, encoding: .utf8))?.trimmed, !id.isEmpty { return id }
        let id = "forge-" + UUID().uuidString.lowercased()
        try? id.write(to: url, atomically: true, encoding: .utf8)
        return id
    }

    /// External engines report their own conversation ids; Forge keeps one per engine per app.
    private static func sessionFile(for project: ForgeProject, engine: Engine) -> URL {
        project.dir.appendingPathComponent(".forge/session-\(engine.rawValue)")
    }

    private static func savedSession(_ url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8))?.trimmed.nilIfEmpty
    }

    /// Deletes an app: quits it, stops its agent, and moves its source and built app to the Trash.
    func delete(_ project: ForgeProject) async {
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
        busy.remove(project.id)
        unread.remove(project.id)
        tokens = tokens.filter { $0.value != project.id }
        if selection == project.id {
            selection = index.flatMap { projects.indices.contains($0) ? projects[$0] : projects.last }?.id
        }
    }

    // MARK: - Approvals

    /// The latest request per app, so the decision model can judge commands against what the user asked for.
    private var currentRequests: [String: String] = [:]

    /// Applies Settings → Building → "Ask before running commands" to one command.
    private func approveCommand(_ command: String, for project: ForgeProject, escalated: Bool) async -> Bool {
        switch CommandApproval.current {
        case .never:
            log(project, .status, "Ran: \(command)")
            return true
        case .auto where !escalated:
            if await commandLooksSafe(command, for: project) {
                log(project, .status, "Ran: \(command)")
                return true
            }
            return await requestApproval(for: project, command: command)
        default:
            return await requestApproval(for: project, command: command)
        }
    }

    /// For agents without their own classifier (pi): obviously risky commands always go to the user; the rest
    /// are judged by the decision model against the user's request. No decision model available → ask.
    private func commandLooksSafe(_ command: String, for project: ForgeProject) async -> Bool {
        let risky = #"\bsudo\b|\|\s*(ba|z)?sh\b|\brm\s+-[a-zA-Z]*[rf][a-zA-Z]*\s+[~/]|\bgit\s+push\b|\bchmod\s+-R\b|\bkillall\b|\blaunchctl\b|\bdefaults\s+write\b|\bcurl\b[^|]*\|"#
        if command.range(of: risky, options: .regularExpression) != nil { return false }
        let state: [String: Any] = [
            "command": command,
            "user_request": currentRequests[project.id] ?? "",
            "working_folder": "The app's own project folder: \(project.dir.path)",
        ]
        let question: [String: Any] = [
            "type": "noul",
            "instructions": "Is it safe to run `command` without asking the user first, given `user_request`?",
            "criteria": [
                "true": "Routine and low-risk for building this app: listing, reading or searching files; git status, log, diff, or cloning a repository the user mentioned; inspecting or converting files inside the working folder; fetching a public web page; running the app's own build or tests.",
                "false": "Could cause harm or surprise: deleting or overwriting files outside the working folder, needing administrator rights, changing system settings, installing software system-wide, running downloaded scripts, sending files or data somewhere, pushing to a remote, or doing something the user didn't ask for.",
            ],
        ]
        guard let (answers, cost) = try? await AppAI.decide(state: state, questions: ["safe": question]),
              let probability = (answers["safe"] as? [String: Any])?["noul"] as? Double else { return false }
        _ = cost
        return probability >= 0.85
    }

    /// Commands that only read (Codex explores with its shell): every part of a pipeline or `&&` chain is a known
    /// read-only program, with no redirection or command substitution. Anything else gets the normal approval.
    nonisolated static func isReadOnly(_ raw: String) -> Bool {
        var command = raw.trimmed
        // Codex wraps commands as /bin/zsh -lc '…'.
        if let match = command.firstMatch(of: #/^/bin/(?:ba|z)?sh\s+-l?c\s+(['"])([\s\S]*)\1$/#) { command = String(match.2) }
        if command.isEmpty || command.contains(">") || command.contains("`") || command.contains("$(") { return false }
        let readers: Set<String> = ["cat", "ls", "head", "tail", "wc", "pwd", "echo", "rg", "grep", "egrep", "fgrep", "stat",
                                    "file", "which", "tree", "sort", "uniq", "cut", "tr", "basename", "dirname", "realpath",
                                    "du", "nl", "diff", "cd", "true", "test", "printf", "find", "sed", "git"]
        let gitReads: Set<String> = ["status", "log", "diff", "show", "ls-files", "branch", "rev-parse", "blame", "grep"]
        let parts = command.split(whereSeparator: { "|;&\n".contains($0) }).map { String($0).trimmed }.filter { !$0.isEmpty }
        for part in parts {
            let words = part.split(separator: " ").map(String.init).drop { $0.contains("=") && !$0.hasPrefix("-") }
            guard let program = words.first.map({ ($0 as NSString).lastPathComponent }), readers.contains(program) else { return false }
            let args = Array(words.dropFirst())
            switch program {
            case "find": if args.contains(where: { ["-exec", "-execdir", "-delete", "-ok", "-fprint"].contains($0) }) { return false }
            case "sed": if !args.contains("-n") || args.contains(where: { $0.hasPrefix("-i") }) { return false }
            case "git": if !gitReads.contains(args.first(where: { !$0.hasPrefix("-") }) ?? "") { return false }
            default: break
            }
        }
        return true
    }

    /// Asks the in-app AI model to describe a command for a non-technical person: what it does, and its risk.
    private func explain(_ command: String, for project: ForgeProject) async -> CommandExplanation? {
        let system = """
        You explain shell commands to people who don't use the command line. An AI agent building a Mac app \
        called "\(project.name)" wants to run a command, and the user has to decide whether to allow it.
        Reply as JSON: {"summary": "<one plain sentence, under 20 words, saying what it does and why it might \
        help, without jargon or command names>", "risk": "low" | "medium" | "high", "why": "<under 15 words: \
        the main reason for that risk level, e.g. what it could change, delete, install or send>"}
        low: only reads, or changes files inside the app's own folder. medium: downloads things, installs tools for \
        this project, or changes files elsewhere that are easy to restore. high: deletes or overwrites files outside \
        the app's folder, needs administrator rights, changes system settings, sends personal data somewhere, or \
        runs code downloaded from the internet.
        """
        let prompt = "The user's request: \(currentRequests[project.id] ?? "(unknown)")\n\nThe command:\n\(command)"
        guard let (text, _) = try? await AppAI.complete(prompt: prompt, images: [], system: system, json: true),
              let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let summary = (json["summary"] as? String)?.trimmed, !summary.isEmpty else { return nil }
        let risk = (json["risk"] as? String)?.lowercased() ?? "medium"
        return CommandExplanation(summary: summary, risk: ["low", "medium", "high"].contains(risk) ? risk : "medium",
                                  why: (json["why"] as? String)?.trimmed ?? "")
    }

    /// Waits for the user to allow or deny a shell command. One request per app at a time; others queue.
    /// There's no timeout: commands wait until the user answers, stops the turn, or the turn ends.
    func requestApproval(for project: ForgeProject, command: String) async -> Bool {
        guard !command.trimmed.isEmpty else { return false }
        if allowAllThisTurn.contains(project.id) {
            log(project, .detail, "Ran (allowed for this turn): \(command)")
            return true
        }
        while approvals[project.id] != nil { try? await Task.sleep(for: .milliseconds(200)) }
        guard busy.contains(project.id) else { return false }   // the turn ended while queued
        NSApp.requestUserAttention(.informationalRequest)
        note("Waiting for your OK to run a command", for: project)
        return await withCheckedContinuation { continuation in
            let pending = PendingApproval(command: command, answer: continuation)
            approvals[project.id] = pending
            // Explain it while the card is up; the card shows the raw command until (and if) this arrives.
            Task {
                if let explanation = await explain(command, for: project), approvals[project.id]?.id == pending.id {
                    approvals[project.id]?.explanation = explanation
                }
            }
        }
    }

    func answerApproval(for project: ForgeProject, allow: Bool, allowAll: Bool = false) {
        guard let pending = approvals.removeValue(forKey: project.id) else { return }
        if allowAll { allowAllThisTurn.insert(project.id) }
        log(project, .detail, (allow ? "Allowed: " : "Denied: ") + pending.command)
        note(allow ? "Running a command" : "Thinking", for: project)
        pending.answer.resume(returning: allow)
    }

    /// Ends approvals with the turn: anything still waiting is denied, and "allow all" resets.
    private func endApprovals(for project: ForgeProject) {
        answerApproval(for: project, allow: false)
        allowAllThisTurn.remove(project.id)
    }

    /// Stops the agent working on an app.
    func stop(_ project: ForgeProject) {
        guard let process = running[project.id] else { return }
        stopped.insert(project.id)
        endApprovals(for: project)   // a command waiting for approval counts as denied
        process.terminate()
    }

    /// Opens the installed app, or brings it to the front if it's running. Only builds when there's
    /// nothing installed yet (or the installed copy was deleted).
    func open(_ project: ForgeProject) async {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: project.bundleID).first {
            // Ask the app to show a window (opening a new one if all were closed); see ForgeWindows.
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("dev.forge.showWindow"), object: project.bundleID, userInfo: nil, deliverImmediately: true)
            running.activate()
            // Apps built before this listener existed ignore the message: if one has no window on screen, relaunch it.
            guard !Self.listensForShowWindow(project) else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Self.hasWindow(running.processIdentifier) else { return }
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
        do {
            _ = try await NSWorkspace.shared.openApplication(at: project.installedURL, configuration: config)
        } catch {
            log(project, .error, "Couldn't open the app: \(error.localizedDescription)")
        }
        refreshOpenApps()
    }

    /// Whether the installed app was built with ForgeWindows (its binary contains the message name).
    private static func listensForShowWindow(_ project: ForgeProject) -> Bool {
        let binary = project.installedURL.appendingPathComponent("Contents/MacOS/\(project.exe)")
        guard let data = try? Data(contentsOf: binary, options: .alwaysMapped) else { return false }
        return data.range(of: Data("dev.forge.showWindow".utf8)) != nil
    }

    /// Whether a process has a normal window on screen (window list metadata needs no permission).
    private static func hasWindow(_ pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
    }

    /// Rebuilds the app from its code, reinstalls it and relaunches it.
    func run(_ project: ForgeProject) async {
        guard busy.insert(project.id).inserted else { return }
        defer { finish(project) }
        if await build(project) == nil {
            await installReportingCrash(project)
        } else {
            log(project, .error, "This app doesn't build right now. Describe a change and I'll fix it, or press Undo.")
        }
    }

    /// Goes back to the version before the current one. Like any restore, this is itself a new version.
    func undo(_ project: ForgeProject) async {
        guard busy.insert(project.id).inserted else { return }
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
                                     trailer: "Forge-Undid: \(undoing.id)") else {
            log(project, .status, "Nothing to undo")
            return
        }
        Versions.remember(project, restoredTo: target.label, from: target.date)
        log(project, .status, "Undid “\(undoing.label)”")
        await rebuild(project, restoredFrom: target)
    }

    /// Brings back an earlier version's files as a new version, so the restore can be undone too.
    func restore(_ project: ForgeProject, to version: AppVersion) async {
        guard busy.insert(project.id).inserted else { return }
        defer { finish(project) }
        guard await Versions.restore(project, to: version, message: "Restored to “\(version.label)”") else {
            log(project, .status, "The app is already like “\(version.label)”")
            return
        }
        Versions.remember(project, restoredTo: version.label, from: version.date)
        log(project, .status, "Restored to “\(version.label)”")
        await rebuild(project, restoredFrom: version)
    }

    /// Goes back to the version a request in the chat made, or to the one before it.
    func restore(_ project: ForgeProject, toVersionOf line: LogLine, before: Bool) async {
        let versions = await Versions.list(project)
        guard let made = line.version.flatMap({ id in versions.first { $0.id == id } }),
              let target = before ? made.parent.flatMap({ id in versions.first { $0.id == id } }) : made else { return }
        await restore(project, to: target)
    }

    /// After a restore: the new version looks like the old one, so it starts with its picture until the app
    /// takes a fresh one.
    private func rebuild(_ project: ForgeProject, restoredFrom version: AppVersion) async {
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
    func linkOldRequests(_ project: ForgeProject) async {
        guard var chat = logs[project.id], chat.contains(where: { $0.kind == .user && $0.version == nil }) else { return }
        func plain(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let versions = await Versions.list(project).reversed()
        let linked = Set(chat.compactMap(\.version))
        var index = chat.startIndex
        var changed = false
        for version in versions where !linked.contains(version.id) {
            let message = plain(version.message)
            guard let match = chat[index...].firstIndex(where: {
                $0.kind == .user && $0.version == nil && plain($0.text) == message
            }) else { continue }
            chat[match].version = version.id
            index = chat.index(after: match)
            changed = true
        }
        guard changed, logs[project.id]?.count == chat.count else { return }
        logs[project.id] = chat
        saveChat(project)
    }

    /// Gives the newest versions without one a short title from what changed, one at a time. Runs on its
    /// own, so the Versions panel reloading as titles arrive doesn't cancel it.
    func titleVersions(_ project: ForgeProject, limit: Int = 40) {
        guard titling.insert(project.id).inserted else { return }
        Task {
            defer { titling.remove(project.id) }
            for version in await Versions.list(project).prefix(limit) where version.title == nil && !version.isForgeNote {
                guard let title = await VersionTitles.make(for: version, in: project) else { return }
                VersionTitles.save(title, for: version.id, in: project)
                versionsRevision += 1
            }
        }
    }

    /// Apps from before pictures were kept: the current version gets the picture of the current build.
    func fillCurrentPicture(_ project: ForgeProject, current: AppVersion) async {
        guard !FileManager.default.fileExists(atPath: Versions.pictureURL(in: project, for: current.id).path),
              let screenshot = Runtime.currentScreenshot(of: project), !busy.contains(project.id),
              await !Versions.hasUnsavedChanges(project) else { return }
        Versions.savePicture(screenshot, in: project, for: current.id)
        versionsRevision += 1
    }

    /// Links requests in the chat to the version they made.
    private func link(_ lines: [UUID], to version: String, in project: ForgeProject) {
        guard var chat = logs[project.id] else { return }
        for index in chat.indices where lines.contains(chat[index].id) { chat[index].version = version }
        logs[project.id] = chat
        saveChat(project)
    }

    /// Keeps the picture the app takes of itself shortly after opening, to show with its version.
    private func keepPicture(of project: ForgeProject, version: String) {
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
    func nameCurrentVersion(of project: ForgeProject) async {
        guard let current = await Versions.list(project).first else { return }
        naming = VersionNaming(project: project, version: current)
    }

    func name(_ version: AppVersion, of project: ForgeProject, as name: String) async {
        await Versions.name(project, version.id, name)
        versionsRevision += 1
    }

    /// Returns nil on success, or the tail of the compiler output on failure.
    private func build(_ project: ForgeProject) async -> String? {
        log(project, .status, "Building…")
        try? Template.writeSupport(for: project)
        Template.upgradeBuildScript(for: project)
        var output: [String] = []
        let status = await Shell.run(Shell.compatibleSDK + "./build.sh", cwd: project.dir) { output.append($0) }
        guard status != 0 else {
            Runtime.markBuilt(project)
            return nil
        }
        let tail = output.suffix(40).joined(separator: "\n")
        log(project, .detail, "Build failed:\n" + tail)
        return tail
    }

    /// Installs and opens the app. Returns what's known about the failure if it died straight away.
    /// `inFront` is false for the agent's looks, which shouldn't pull the app in front of the user mid-turn.
    private func install(_ project: ForgeProject, inFront: Bool = true) async -> String? {
        await prepareIcon(project)
        await quit(project)
        do {
            try await deploy(project)
        } catch {
            log(project, .error, "Couldn't install the app: \(error.localizedDescription)")
            return nil
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = inFront
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
            log(project, .error, "Couldn't open the app: \(error.localizedDescription)")
        }
        upgradeIconArt(project)
        refreshOpenApps()
        return crash
    }

    /// For Open App and Undo, where no agent is running to fix a crash.
    private func installReportingCrash(_ project: ForgeProject) async {
        if await install(project) != nil {
            log(project, .error, "\(project.name) crashes when it opens. Ask me to fix the crash, or press Undo.")
        }
    }

    /// Puts the icon into the freshly built bundle, re-signs it, and swaps it into ~/Applications/Forge Apps.
    /// The swap is atomic, so it's safe even while the app is running.
    private func deploy(_ project: ForgeProject) async throws {
        let fm = FileManager.default
        let resources = project.builtURL.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        // Without these, macOS kills the app the moment it uses the mic, speech recognition or camera.
        // Added here rather than in build.sh so apps made before this change get them too.
        _ = await Shell.run("""
            P="$FORGE_APP/Contents/Info.plist"
            plutil -replace CFBundleName -string "$FORGE_NAME" "$P" && \
            plutil -replace CFBundleDisplayName -string "$FORGE_NAME" "$P" && \
            plutil -replace NSMicrophoneUsageDescription -string "$FORGE_NAME listens to your microphone." "$P" && \
            plutil -replace NSSpeechRecognitionUsageDescription -string "$FORGE_NAME turns your speech into text." "$P" && \
            plutil -replace NSCameraUsageDescription -string "$FORGE_NAME uses your camera." "$P"
            """, cwd: project.dir, env: ["FORGE_APP": project.builtURL.path, "FORGE_NAME": project.name]) { _ in }
        if fm.fileExists(atPath: Icons.icnsURL(project).path) {
            try? fm.removeItem(at: resources.appendingPathComponent("AppIcon.icns"))
            try fm.copyItem(at: Icons.icnsURL(project), to: resources.appendingPathComponent("AppIcon.icns"))
            // With Xcode 26, the compiled Icon Composer icon lets macOS 26 draw it in Liquid Glass.
            try? fm.removeItem(at: resources.appendingPathComponent("Assets.car"))
            let hasCar = fm.fileExists(atPath: Icons.carURL(project).path)
            if hasCar { try fm.copyItem(at: Icons.carURL(project), to: resources.appendingPathComponent("Assets.car")) }
            let iconName = hasCar
                ? "plutil -replace CFBundleIconName -string AppIcon \"$FORGE_APP/Contents/Info.plist\""
                : "{ plutil -remove CFBundleIconName \"$FORGE_APP/Contents/Info.plist\" 2>/dev/null || true; }"
            _ = await Shell.run("""
                plutil -replace CFBundleIconFile -string AppIcon "$FORGE_APP/Contents/Info.plist" && \(iconName)
                """, cwd: project.dir, env: ["FORGE_APP": project.builtURL.path]) { _ in }
        }
        // Files attached in Forge's chat ship inside the app, where ForgeAssets finds them.
        let attachments = project.dir.appendingPathComponent(Attachments.folder)
        try? fm.removeItem(at: resources.appendingPathComponent(Attachments.folder))
        if fm.fileExists(atPath: attachments.path) {
            try fm.copyItem(at: attachments, to: resources.appendingPathComponent(Attachments.folder))
        }
        _ = await Shell.run("codesign --force -s - \"$FORGE_APP\"", cwd: project.dir,
                            env: ["FORGE_APP": project.builtURL.path]) { _ in }

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
            Self.lsregister + " -f \"$FORGE_APP\"",
            cwd: project.dir, env: ["FORGE_APP": project.installedURL.path]) { _ in }
    }

    // MARK: - Icons

    /// Makes sure icon.json exists, then renders it (with cached artwork if there is any).
    private func prepareIcon(_ project: ForgeProject) async {
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

    private func renderIcon(_ project: ForgeProject, spec: IconSpec) async {
        do {
            icons[project.id] = try await Icons.write(spec, art: Icons.cachedArt(project, spec: spec), for: project)
        } catch {
            log(project, .detail, "Icon render failed: \(error.localizedDescription)")
        }
    }

    /// With an OpenRouter key, generates artwork for the icon's object in the background (best of a few
    /// candidates) and swaps it in when ready.
    private func upgradeIconArt(_ project: ForgeProject) {
        guard Provider.hasKey,
              let spec = Icons.load(project), !spec.subject.trimmed.isEmpty,
              Icons.cachedArt(project, spec: spec) == nil,
              artInProgress.insert(project.id).inserted else { return }
        Task {
            defer { artInProgress.remove(project.id) }
            do {
                let art = try await Icons.generateBestArt(spec, appName: project.name) { [weak self] in
                    self?.log(project, .detail, $0)
                }
                let url = Icons.artURL(project, spec: spec)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let tiff = art.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?
                    .representation(using: .png, properties: [:]) else { return }
                try png.write(to: url)
                // Only apply if the spec hasn't changed meanwhile and no build is in flight.
                guard Icons.load(project) == spec, !busy.contains(project.id) else { return }
                await renderIcon(project, spec: spec)
                try await deploy(project)
                log(project, .status, "New icon artwork is in. It shows in the Dock after the app restarts.")
            } catch {
                log(project, .detail, "Icon artwork failed: \(error.localizedDescription)")
            }
        }
    }

    /// Designs a fresh icon (different from the current one) and applies it without restarting the app.
    func newIcon(_ project: ForgeProject) async {
        guard busy.insert(project.id).inserted else { return }
        defer { finish(project) }
        log(project, .status, "Designing a new icon…")
        let spec = await Icons.design(for: project, avoiding: Icons.load(project))
        Icons.save(spec, for: project)
        await renderIcon(project, spec: spec)
        if FileManager.default.fileExists(atPath: project.builtURL.path) {
            try? await deploy(project)
        }
        log(project, .status, Provider.hasKey ? "New icon applied. Artwork is on its way." : "New icon applied.")
        Task { upgradeIconArt(project) }
    }

    /// Gives apps made before icons existed an icon, once.
    private func backfillIcons() async {
        for project in projects where Icons.load(project) == nil && !busy.contains(project.id) {
            await prepareIcon(project)
            if FileManager.default.fileExists(atPath: project.builtURL.path) {
                try? await deploy(project)
            }
            upgradeIconArt(project)
        }
    }

    /// Keeps `openApps` current as apps launch and quit. Menu bar apps don't always announce themselves,
    /// so it's also checked whenever Forge comes to the front and after Forge opens or quits one.
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
        let prefix = "dev.forge.app."
        let ids = NSWorkspace.shared.runningApplications
            .compactMap { $0.isTerminated ? nil : $0.bundleIdentifier }
            .filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        if Set(ids) != openApps { openApps = Set(ids) }
    }

    /// Quits the app, for the Stop button. Asks it nicely first, then insists.
    func quitApp(_ project: ForgeProject) async {
        await quit(project)
        refreshOpenApps()
    }

    private func quit(_ project: ForgeProject) async {
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
            self.gateway = gateway
        } catch {
            NSLog("Forge AI gateway failed to start: \(error)")
        }
    }

    func handleAI(_ request: Gateway.Request) async -> (Int, [String: Any]) {
        let route = request.path.split(separator: "?").first.map(String.init) ?? request.path
        let paths = ["/ai", "/ai/image", "/ai/decide", "/agent/look", "/agent/approve",
                     "/agent/versions", "/agent/versions/name", "/agent/versions/restore"]
        guard request.method == "POST", paths.contains(route) else {
            return (404, ["error": "Not found"])
        }
        let token = request.headers["authorization"]?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        if tokens[token] == nil { reload() }   // app may have been created since the last reload
        guard let id = tokens[token], let project = projects.first(where: { $0.id == id }) else {
            return (401, ["error": "This app isn't registered with Forge."])
        }
        guard setup.ready else { return (503, ["error": "Forge isn't set up yet. Open Forge to finish setup."]) }
        if request.path == "/agent/look" { return await look(at: project) }
        if request.path.hasPrefix("/agent/versions") { return await versions(request, of: project) }
        if route == "/agent/approve" {
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            // pi's extension sends {"command"}; Claude Code's hook sends {"tool_input": {"command"}}.
            let input = body["tool_input"] as? [String: Any] ?? [:]
            let tool = body["tool_name"] as? String ?? "Bash"
            var command = body["command"] as? String ?? input["command"] as? String ?? ""
            if command.isEmpty {   // a non-shell tool Claude Code wants permission for (e.g. a write outside the app)
                let target = input["file_path"] as? String ?? input["url"] as? String ?? input["path"] as? String ?? ""
                command = target.isEmpty ? tool : "\(tool): \(target)"
            }
            // Claude Code already ran its own classifier before asking ("claude-permission"), so ask the user.
            let escalated = request.path.contains("format=claude-permission")
            if request.path.contains("format=codex") {
                // Codex's PreToolUse hook can only block: an empty answer lets the command run.
                if Self.isReadOnly(command) { return (200, [:]) }
                let allowed = await approveCommand(command, for: project, escalated: false)
                return (200, allowed ? [:] : ["hookSpecificOutput": ["hookEventName": "PreToolUse",
                                                                     "permissionDecision": "deny",
                                                                     "permissionDecisionReason": "The user denied this command in Forge."]])
            }
            let allowed = await approveCommand(command, for: project, escalated: escalated)
            let reason = allowed ? "Approved in Forge." : "The user denied this command in Forge."
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
        if request.path == "/ai/decide" {
            guard let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any],
                  let state = body["state"], let questions = body["questions"] as? [String: Any], !questions.isEmpty else {
                return (400, ["error": "A decision needs `state` and at least one question."])
            }
            do {
                let (answers, cost) = try await AppAI.decide(state: state, questions: questions)
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
                let (png, cost) = try await AppAI.image(prompt: prompt, references: images,
                                                        aspectRatio: body["aspect_ratio"] as? String)
                record(project, cost: cost)
                return (200, ["image": png.base64EncodedString(), "media_type": "image/png"])
            }
            let (text, cost) = try await AppAI.complete(prompt: prompt, images: images,
                                                         system: body["system"] as? String ?? "",
                                                         json: body["json"] as? Bool ?? false)
            record(project, cost: cost)
            return (200, ["text": text])
        } catch let failure as AppAI.Failure {
            return (502, ["error": failure.message])
        } catch {
            return (502, ["error": "Couldn't reach the AI: \(error.localizedDescription)"])
        }
    }

    /// The agent's version tools: `list_versions`, `name_version` and `restore_version`.
    private func versions(_ request: Gateway.Request, of project: ForgeProject) async -> (Int, [String: Any]) {
        // Only for the agent Forge is running right now: the app knows the same token, and must not be
        // able to change its own history.
        guard running[project.id] != nil else { return (409, ["error": "Forge isn't working on this app right now."]) }
        let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        let versions = await Versions.list(project)
        let id = (body["version"] as? String)?.trimmed.nilIfEmpty
        let version = id.flatMap { Versions.find($0, in: versions) }
        if id != nil && version == nil {
            return (404, ["error": "There's no version \(id!). Call list_versions for the ids."])
        }
        switch request.path {
        case "/agent/versions/name":
            guard let name = (body["name"] as? String)?.trimmed.nilIfEmpty else { return (400, ["error": "A name is needed."]) }
            guard let version else {
                pendingNames[project.id] = name
                return (200, ["text": "Forge will name the version this request makes “\(name)”."])
            }
            await Versions.name(project, version.id, name)
            versionsRevision += 1
            return (200, ["text": "Named \(version.shortID) “\(name)”."])
        case "/agent/versions/restore":
            guard let version else { return (400, ["error": "Say which version to restore."]) }
            guard await Versions.restoreFiles(project, to: version) else {
                return (500, ["error": "Forge couldn't restore that version."])
            }
            log(project, .status, "Restored to “\(version.label)”")
            return (200, ["text": """
                The app's files are now as they were in “\(version.label)”. Your changes earlier in this request \
                are gone too. Read files again before editing them. Forge builds and opens the app when you finish.
                """])
        default:
            return (200, ["text": Versions.describe(versions)])
        }
    }

    /// The agent's `look_at_app` tool: builds what it has written so far, opens the app behind the
    /// user's windows, and reports what happened. The pictures are sent as file paths for pi to read.
    private func look(at project: ForgeProject) async -> (Int, [String: Any]) {
        // Only for the agent Forge is running right now. The app knows the same token and must not
        // be able to rebuild itself.
        guard running[project.id] != nil, var look = looks[project.id] else {
            return (409, ["error": "Forge isn't working on this app right now."])
        }
        guard !look.inProgress else { return (200, ["text": "Forge is already looking at the app. Wait for that result."]) }
        guard look.count < Look.limit else {
            return (200, ["text": "You've used your looks for this request. Finish up: Forge builds and opens the app when you're done."])
        }
        look.count += 1
        look.inProgress = true
        look.installed = false
        looks[project.id] = look
        defer { looks[project.id]?.inProgress = false }

        try? Template.writeSupport(for: project)
        let changed = Runtime.sourcesChanged(project)
        if changed, let errors = await build(project) {
            return (200, ["text": "The app doesn't build yet. Fix these compiler errors:\n\n\(errors)"])
        }
        var note = "The app built and is running."
        var screenshots: [URL] = []
        if !changed, NSRunningApplication.runningApplications(withBundleIdentifier: project.bundleID).first != nil {
            // Nothing to rebuild and the app is open: ask it for fresh pictures instead of relaunching it.
            let asked = Date()
            Runtime.requestScreenshots(of: project)
            screenshots = await Runtime.screenshots(of: project, since: asked, waiting: 2)
            note = "The app is running your latest code; nothing needed rebuilding."
            looks[project.id]?.installed = !screenshots.isEmpty
            looks[project.id]?.crash = nil
        }
        if screenshots.isEmpty {
            let launched = Date()
            let crash = await install(project, inFront: false)
            looks[project.id]?.installed = true
            looks[project.id]?.crash = crash
            if let crash {
                return (200, ["text": "The app \(changed ? "built" : "is built"), but it quit right after launching.\n\n\(crash)"])
            }
            if !changed { note = "The app is running your latest code; it was reopened without rebuilding." }
            screenshots = await Runtime.screenshots(of: project, since: launched)
        }
        var text = note + " " + (screenshots.isEmpty
            ? "It has no window open, so there's no picture."
            : "Pictures of its windows follow, frontmost first.")
        if let tail = Runtime.logTail(project) { text += "\n\nWhat it printed:\n\(tail)" }
        return (200, ["text": text, "screenshots": screenshots.map(\.path)])
    }

    private func record(_ project: ForgeProject, cost: Double) {
        usage[project.id, default: AppUsage()].calls += 1
        usage[project.id, default: AppUsage()].cost += cost
        saveUsage(project)
    }

    private func recordAgent(_ project: ForgeProject, cost: Double) {
        var current = usage[project.id] ?? AppUsage()
        current.agentRuns = (current.agentRuns ?? 0) + 1
        current.agentCost = (current.agentCost ?? 0) + cost
        usage[project.id] = current
        saveUsage(project)
    }

    private func saveUsage(_ project: ForgeProject) {
        if let data = try? JSONEncoder().encode(usage[project.id]) {
            try? data.write(to: project.dir.appendingPathComponent(".forge/usage.json"))
        }
    }

    private static let lsregister =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    private static let commit = Versions.commit
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
