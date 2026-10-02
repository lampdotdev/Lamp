import SwiftUI
import AppKit

struct ForgeProject: Identifiable, Hashable {
    let id: String      // folder name; also used in forge:// links
    let name: String    // display name
    let exe: String     // Swift target / executable name
    let dir: URL

    var bundleID: String { "dev.forge.app.\(id)" }
    var builtURL: URL { dir.appendingPathComponent("build/\(exe).app") }
    /// Every successful build is copied here so it shows up in Spotlight and Launchpad.
    var installedURL: URL { Store.installDir.appendingPathComponent("\(name).app") }
}

struct ProjectMeta: Codable {
    var name: String
    var exe: String
}

struct AppUsage: Codable {
    var calls = 0
    var cost = 0.0
}

struct LogLine: Identifiable, Codable {
    enum Kind: String, Codable { case user, agent, status, error, detail }
    var id = UUID()
    let kind: Kind
    let text: String
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var projects: [ForgeProject] = []
    @Published var selection: String?
    @Published var logs: [String: [LogLine]] = [:]
    @Published var busy: Set<String> = []
    @Published var chatFocusRequest = 0
    @Published var setup = SetupCheck()
    @Published var usage: [String: AppUsage] = [:]
    @Published var icons: [String: NSImage] = [:]
    private var artInProgress: Set<String> = []
    private var tokens: [String: String] = [:]   // gateway token → project id
    private var gateway: Gateway?

    nonisolated static let installDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/Forge Apps")

    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Forge/Apps")

    private init() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
        selection = projects.first?.id
        startGateway()
        if !Provider.models.contains(where: { $0.id == UserDefaults.standard.string(forKey: "model") }) {
            UserDefaults.standard.set(Provider.model, forKey: "model")   // from the Claude Code era ("sonnet")
        }
        Task { await recheckSetup() }
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

    func reload() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        projects = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(".forge/meta.json")),
                  let meta = try? JSONDecoder().decode(ProjectMeta.self, from: data) else { return nil }
            return ForgeProject(id: dir.lastPathComponent, name: meta.name, exe: meta.exe, dir: dir)
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
                logs[project.id] = saved
            }
            if let data = try? Data(contentsOf: forge.appendingPathComponent("usage.json")),
               let saved = try? JSONDecoder().decode(AppUsage.self, from: data) {
                usage[project.id] = saved
            }
        }
    }

    func log(_ project: ForgeProject, _ kind: LogLine.Kind, _ text: String) {
        logs[project.id, default: []].append(LogLine(kind: kind, text: text))
        if let data = try? JSONEncoder().encode(logs[project.id]) {
            try? data.write(to: project.dir.appendingPathComponent(".forge/chat.json"))
        }
    }

    func handle(url: URL) {
        guard url.scheme == "forge",
              let slug = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "app" })?.value else { return }
        reload()
        selection = slug
        chatFocusRequest += 1
        NSApp.activate()
    }

    // MARK: - Actions

    func create(name: String, brief: String) {
        let project: ForgeProject
        do {
            project = try Template.scaffold(name: name, in: root)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        reload()
        selection = project.id
        Task {
            _ = await Shell.run("git init -q && git add -A && \(Self.commit) -qm 'Scaffold'", cwd: project.dir) { _ in }
            if brief.trimmed.isEmpty {
                await run(project)
            } else {
                await send(brief.trimmed, to: project)
            }
        }
    }

    /// One turn of the loop: agent edits → build (agent fixes failures) → commit → relaunch.
    func send(_ prompt: String, to project: ForgeProject) async {
        guard busy.insert(project.id).inserted else { return }
        defer { busy.remove(project.id) }
        log(project, .user, prompt)

        guard await runAgent(prompt, on: project) else { return }
        var errors = await build(project)
        for _ in 0..<3 where errors != nil {
            log(project, .status, "Fixing a build problem…")
            guard await runAgent("The app failed to build. Fix these compiler errors:\n\n\(errors!)",
                                 on: project) else { return }
            errors = await build(project)
        }
        guard errors == nil else {
            log(project, .error, "Sorry, I couldn't get that change working. Try describing it differently, or press Undo.")
            return
        }
        _ = await Shell.run("git add -A && \(Self.commit) -qm \"$FORGE_PROMPT\"", cwd: project.dir,
                            env: ["FORGE_PROMPT": prompt]) { _ in }
        await install(project)
    }

    /// Returns false when the agent couldn't run at all (bad key, no credit, …), after telling the user why.
    private func runAgent(_ prompt: String, on project: ForgeProject) async -> Bool {
        try? Template.writeSupport(for: project)
        let started = Date()
        var cost = 0.0
        var failure: String?
        let env = Agent.environment(prompt: prompt, session: Self.agentSession(for: project),
                                    sessionDir: project.dir.appendingPathComponent(".forge/pi-sessions").path)
        let status = await Shell.run(Agent.command, cwd: project.dir, env: env) { [weak self] line in
            guard let self else { return }
            for event in Agent.parse(line) {
                switch event {
                case .text(let text): log(project, .agent, text)
                case .tool(let text): log(project, .detail, text)
                case .cost(let amount): cost += amount
                case .failed(let text): failure = text
                case .raw(let text): log(project, .detail, text)
                }
            }
        }
        log(project, .detail, String(format: "Agent %@ · %.0fs · $%.2f", failure == nil ? "done" : "error",
                                     Date().timeIntervalSince(started), cost))
        if status != 0 && failure == nil { failure = "Agent exited with status \(status)" }
        guard let failure else { return true }
        log(project, .detail, failure)
        log(project, .error, Provider.friendlyError(failure))
        return false
    }

    /// One pi conversation per app, so the agent remembers earlier requests. Undo starts a new one.
    private static func agentSession(for project: ForgeProject) -> String {
        let url = project.dir.appendingPathComponent(".forge/pi-session")
        if let id = (try? String(contentsOf: url, encoding: .utf8))?.trimmed, !id.isEmpty { return id }
        let id = "forge-" + UUID().uuidString.lowercased()
        try? id.write(to: url, atomically: true, encoding: .utf8)
        return id
    }

    func run(_ project: ForgeProject) async {
        guard busy.insert(project.id).inserted else { return }
        defer { busy.remove(project.id) }
        if await build(project) == nil {
            await install(project)
        } else {
            log(project, .error, "This app doesn't build right now. Describe a change and I'll fix it, or press Undo.")
        }
    }

    func undo(_ project: ForgeProject) async {
        guard busy.insert(project.id).inserted else { return }
        defer { busy.remove(project.id) }
        let status = await Shell.run(
            "test $(git rev-list --count HEAD) -gt 1 && git reset -q --hard HEAD~1", cwd: project.dir) { _ in }
        guard status == 0 else {
            log(project, .status, "Nothing to undo")
            return
        }
        // The agent's conversation still remembers the reverted change, so start fresh.
        try? FileManager.default.removeItem(at: project.dir.appendingPathComponent(".forge/pi-session"))
        log(project, .status, "Undid the last change")
        if await build(project) == nil { await install(project) }
    }

    /// Returns nil on success, or the tail of the compiler output on failure.
    private func build(_ project: ForgeProject) async -> String? {
        log(project, .status, "Building…")
        try? Template.writeSupport(for: project)
        var output: [String] = []
        let status = await Shell.run("./build.sh", cwd: project.dir) { output.append($0) }
        guard status != 0 else { return nil }
        let tail = output.suffix(40).joined(separator: "\n")
        log(project, .detail, "Build failed:\n" + tail)
        return tail
    }

    private func install(_ project: ForgeProject) async {
        await prepareIcon(project)
        await quit(project)
        do {
            try await deploy(project)
        } catch {
            log(project, .error, "Couldn't install the app: \(error.localizedDescription)")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: project.installedURL, configuration: config)
            log(project, .status, "\(project.name) is ready")
        } catch {
            log(project, .error, "Couldn't open the app: \(error.localizedDescription)")
        }
        upgradeIconArt(project)
    }

    /// Puts the icon into the freshly built bundle, re-signs it, and swaps it into ~/Applications/Forge Apps.
    /// The swap is atomic, so it's safe even while the app is running.
    private func deploy(_ project: ForgeProject) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: Icons.icnsURL(project).path) {
            let resources = project.builtURL.appendingPathComponent("Contents/Resources")
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            try? fm.removeItem(at: resources.appendingPathComponent("AppIcon.icns"))
            try fm.copyItem(at: Icons.icnsURL(project), to: resources.appendingPathComponent("AppIcon.icns"))
            _ = await Shell.run("""
                plutil -replace CFBundleIconFile -string AppIcon "$FORGE_APP/Contents/Info.plist" && \
                codesign --force -s - "$FORGE_APP"
                """, cwd: project.dir, env: ["FORGE_APP": project.builtURL.path]) { _ in }
        }

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
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f \"$FORGE_APP\"",
            cwd: project.dir, env: ["FORGE_APP": project.installedURL.path]) { _ in }
    }

    // MARK: - Icons

    /// Makes sure icon.json exists, then renders it (with cached artwork if there is any).
    private func prepareIcon(_ project: ForgeProject) async {
        var spec = Icons.load(project)
        if spec == nil {
            log(project, .status, "Designing an icon…")
            spec = await Icons.design(for: project)
            Icons.save(spec!, for: project)
        }
        renderIcon(project, spec: spec!)
    }

    private func renderIcon(_ project: ForgeProject, spec: IconSpec) {
        do {
            icons[project.id] = try Icons.write(spec, art: Icons.cachedArt(project, spec: spec), for: project)
        } catch {
            log(project, .detail, "Icon render failed: \(error.localizedDescription)")
        }
    }

    /// With an OpenRouter key, generates illustrated artwork in the background and swaps it in when ready.
    private func upgradeIconArt(_ project: ForgeProject) {
        guard Provider.hasKey,
              let spec = Icons.load(project), let prompt = spec.art_prompt, !prompt.trimmed.isEmpty,
              Icons.cachedArt(project, spec: spec) == nil,
              artInProgress.insert(project.id).inserted else { return }
        Task {
            defer { artInProgress.remove(project.id) }
            do {
                let data = try await Icons.generateArt(prompt)
                let url = Icons.artURL(project, prompt: prompt)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
                // Only apply if the spec hasn't changed meanwhile and no build is in flight.
                guard Icons.load(project) == spec, !busy.contains(project.id) else { return }
                renderIcon(project, spec: spec)
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
        defer { busy.remove(project.id) }
        log(project, .status, "Designing a new icon…")
        let spec = await Icons.design(for: project, avoiding: Icons.load(project))
        Icons.save(spec, for: project)
        renderIcon(project, spec: spec)
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
        guard request.method == "POST", request.path == "/ai" else { return (404, ["error": "Not found"]) }
        let token = request.headers["authorization"]?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        if tokens[token] == nil { reload() }   // app may have been created since the last reload
        guard let id = tokens[token], let project = projects.first(where: { $0.id == id }) else {
            return (401, ["error": "This app isn't registered with Forge."])
        }
        guard setup.ready else { return (503, ["error": "Forge isn't set up yet. Open Forge to finish setup."]) }
        guard let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any],
              let prompt = body["prompt"] as? String, !prompt.trimmed.isEmpty else {
            return (400, ["error": "Missing prompt."])
        }
        do {
            let images = (body["images"] as? [[String: String]] ?? []).compactMap { image -> AppAI.Image? in
                guard let type = image["media_type"], let data = image["data"] else { return nil }
                return AppAI.Image(mediaType: type, data: data)
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

    private func record(_ project: ForgeProject, cost: Double) {
        usage[project.id, default: AppUsage()].calls += 1
        usage[project.id, default: AppUsage()].cost += cost
        if let data = try? JSONEncoder().encode(usage[project.id]) {
            try? data.write(to: project.dir.appendingPathComponent(".forge/usage.json"))
        }
    }

    private static let commit = "git -c user.name=Forge -c user.email=forge@localhost commit"
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
