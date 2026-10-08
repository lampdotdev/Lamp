import SwiftUI
import AppKit

/// What a fresh Mac is missing before Lamp can build apps.
struct SetupCheck {
    var checked = false
    var hasBuildTools = true
    var builderProblem: String?
    var hasAgent = true
    /// Lamp has already opened Apple's installer this launch.
    var installRequested = false

    var hasBuilder: Bool { builderProblem == nil }
    var ready: Bool { hasBuildTools && hasBuilder && hasAgent }

    static func run(keeping previous: SetupCheck) async -> SetupCheck {
        var check = SetupCheck(checked: true, hasBuildTools: buildToolsInstalled(), builderProblem: Builder.problem(),
                               hasAgent: Agent.executable != nil)
        check.installRequested = previous.installRequested
        return check
    }

    /// Looks for a Swift compiler without calling /usr/bin/swift or xcrun: on a Mac without the tools,
    /// those shims pop up Apple's installer, which would happen every time Lamp checks.
    static func buildToolsInstalled() -> Bool {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: "/Library/Developer/CommandLineTools/usr/bin/swift") { return true }
        let select = Subprocess.runBlocking("/usr/bin/xcode-select", ["-p"], mergeErrors: false, timeout: 10)
        let developer = select.output.trimmed
        guard select.ok, !developer.isEmpty else { return false }
        return fm.isExecutableFile(atPath: developer + "/usr/bin/swift")
            || fm.isExecutableFile(atPath: developer + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift")
    }

    /// Opens Apple's installer for the free Command Line Tools (no developer account needed).
    static func installBuildTools() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["--install"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

struct SetupView: View {
    @EnvironmentObject private var store: Store
    @State private var key = ""
    @State private var checkingKey = false
    @State private var keyProblem: String?
    @State private var choice = "openrouter"

    /// The ways to build, in the order shown. Claude Code and Codex appear when they're installed.
    private static var choices: [(id: String, title: String, detail: String)] {
        var all: [(id: String, title: String, detail: String)] = [
            ("openrouter", "OpenRouter",
             "Any of hundreds of models, paying OpenRouter only for what you use."),
        ]
        for engine in [Engine.claude, .codex] where ToolLocator.path(for: engine) != nil {
            all.append((engine.rawValue, engine.title,
                        "Uses your \(engine.title) sign-in, for building and for the AI inside your apps."))
        }
        all.append(("local", "A model on this Mac",
                    "Free and private: a model Lamp downloads and runs here. Smaller models build simpler apps."))
        all.append(("other", "Another provider",
                    "Anthropic, OpenAI, Google, Groq, Mistral and about twenty more, with your own key."))
        return all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Welcome to Lamp").font(.largeTitle.bold())
            Text("Describe an app your Mac is missing, and Lamp builds it: a real app you can keep using, change whenever you like, and share. Two one-time steps first, and they can happen at the same time.")
                .foregroundStyle(.secondary)

            if !store.setup.hasAgent {
                Label("Lamp's AI builder is missing from the app. Download Lamp again.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            step(done: store.setup.hasBuildTools,
                 title: "Install Apple's app-building tools",
                 detail: store.setup.installRequested
                    ? "Apple's installer window is open. Click **Install**, then **Agree**. It usually takes 5–10 minutes, and Lamp carries on by itself when it's done."
                    : "Free from Apple, and no developer account needed.") {
                VStack(alignment: .trailing, spacing: 6) {
                    if store.setup.installRequested {
                        ProgressView().controlSize(.small)
                        Button("Show Installer Again", action: SetupCheck.installBuildTools)
                            .buttonStyle(.link)
                            .font(.caption)
                    } else {
                        Button("Install…") { store.requestBuildTools() }
                    }
                }
            }

            step(done: store.setup.hasBuilder,
                 title: "Choose what builds your apps",
                 detail: store.setup.hasBuilder ? Builder.summary
                    : "Any of these works. You can change it later in Settings.") {
                EmptyView()
            }
            if !store.setup.hasBuilder {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $choice) {
                        ForEach(Self.choices, id: \.id) { Text($0.title).tag($0.id) }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    Text(Self.choices.first { $0.id == choice }?.detail ?? "")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    switch choice {
                    case "openrouter":
                        HStack {
                            SecureField("OpenRouter key (sk-or-…)", text: $key)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(saveKey)
                                .onChange(of: key) { keyProblem = nil }
                            if checkingKey {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Save", action: saveKey).disabled(key.trimmed.isEmpty)
                            }
                            Link("Get a key", destination: URL(string: "https://openrouter.ai/keys")!)
                        }
                        if let keyProblem {
                            Label(keyProblem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                        }
                    case "claude", "codex":
                        let engine: Engine = choice == "claude" ? .claude : .codex
                        Button("Use \(engine.title)") { use(engine) }
                    case "local":
                        Button("Choose a Model…") { openSettings(tab: "providers", sheet: Builder.localProvider) }
                    default:
                        Button("Choose a Provider…") { openSettings(tab: "building") }
                    }
                }
                .padding(.leading, 36)
            }
        }
        .padding(40)
        .frame(maxWidth: 600)
    }

    @Environment(\.openSettings) private var openSettingsAction
    @AppStorage("settingsTab") private var settingsTab = "building"
    @AppStorage("settingsSheet") private var settingsSheet = ""

    private func openSettings(tab: String, sheet: String = "") {
        settingsTab = tab
        settingsSheet = sheet
        openSettingsAction()
    }

    private func use(_ engine: Engine) {
        Builder.engine = engine
        Task {
            // Bundled with a desktop app but never signed in on its own: sign in through the browser now.
            if await EngineSignIn.isSignedIn(engine) == false { _ = await EngineSignIn.signIn(engine) }
            await store.recheckSetup()
        }
    }

    /// Checks the key with OpenRouter before saving it, so a typo shows up now rather than at the first build.
    private func saveKey() {
        let candidate = key.trimmed
        guard !candidate.isEmpty, !checkingKey else { return }
        checkingKey = true
        Task {
            defer { checkingKey = false }
            if let problem = await Self.checkOpenRouterKey(candidate) {
                keyProblem = problem
                return
            }
            KeyStore.setOpenRouterKey(candidate)
            key = ""
            Builder.engine = .pi
            Builder.piProvider = "openrouter"
            await store.recheckSetup()
        }
    }

    /// What OpenRouter said about a key.
    enum KeyVerdict: Equatable {
        case accepted
        /// OpenRouter answered, and the key is no use as it is: mistyped, revoked or out of credit.
        case refused(String)
        /// Nothing to go on (offline, or OpenRouter in trouble), so the key may well be a good one.
        case unchecked(String)

        var problem: String? {
            switch self {
            case .accepted: nil
            case .refused(let problem), .unchecked(let problem): problem
            }
        }
    }

    /// nil if OpenRouter accepts the key; otherwise what's wrong, in plain words.
    static func checkOpenRouterKey(_ key: String) async -> String? {
        await openRouterVerdict(key).problem
    }

    /// Asks OpenRouter about a key. Where the person can wait for the answer (the first key, in the Welcome
    /// and the chat) anything but `accepted` stops the save; Settings turns away only a key OpenRouter refused.
    static func openRouterVerdict(_ key: String) async -> KeyVerdict {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/key")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .unchecked("Couldn't reach OpenRouter. Check your internet connection.")
        }
        return verdict(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }

    /// What OpenRouter's answer to "whose key is this?" means for the key.
    static func verdict(status: Int, body: Data) -> KeyVerdict {
        switch status {
        case 200:
            let info = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["data"] as? [String: Any]
            if let remaining = info?["limit_remaining"] as? Double, remaining <= 0 {
                return .refused("That key works, but it has no credit left. Add credit at openrouter.ai, then try again.")
            }
            return .accepted
        case 401, 403: return .refused("OpenRouter didn't accept that key. Copy it again from openrouter.ai/keys.")
        default: return .unchecked("OpenRouter couldn't check the key right now. Try again in a moment.")
        }
    }

    private func step<Accessory: View>(done: Bool, title: String, detail: String,
                                       @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(done ? .green : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(LocalizedStringKey(detail)).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !done { accessory() }
        }
    }
}

struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = "building"
    @AppStorage(Memory.switchKey) private var memory = false

    var body: some View {
        TabView(selection: $tab) {
            BuildingSettings().tabItem { Label("Building", systemImage: "hammer") }.tag("building")
            AppsSettings().tabItem { Label("Apps", systemImage: "square.grid.2x2") }.tag("apps")
            ProvidersSettings().tabItem { Label("Providers", systemImage: "cpu") }.tag("providers")
            // Only while the experiment is on (Building → Experimental): off, there are no notes to show.
            if memory {
                MemorySettings().tabItem { Label("Memory", systemImage: "note.text") }.tag("memory")
            }
        }
        .frame(width: 560)
        .onAppear {
            if tab == "local" { tab = "providers" }   // Local Models is now Native Mac AI, under Providers
            if !(["building", "apps", "providers"] + (memory ? ["memory"] : [])).contains(tab) { tab = "building" }
        }
    }
}

extension View {
    /// A grouped settings form that grows to fit its content, so the Settings window
    /// resizes per tab like Apple's apps, and scrolls only when it's taller than the screen.
    func settingsPane() -> some View { modifier(SettingsPane()) }
}

private struct SettingsPane: ViewModifier {
    @State private var height: CGFloat = 0

    /// Room left on screen once the window's title bar and toolbar are accounted for.
    private var maxHeight: CGFloat {
        ((NSScreen.main?.visibleFrame.height ?? 800) - 100).rounded()
    }

    func body(content: Content) -> some View {
        ScrollView {
            content
                .formStyle(.grouped)
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollDisabled(height <= maxHeight)
        .frame(height: height == 0 ? nil : min(height, maxHeight))
    }
}

/// Which agent, provider and model build apps.
struct BuildingSettings: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var local = LocalModels.shared
    @AppStorage("engine") private var engine = Engine.pi.rawValue
    @AppStorage("piProvider") private var provider = "openrouter"
    @AppStorage("settingsTab") private var tab = "building"
    @AppStorage("notify") private var notify = true
    @AppStorage("commandApproval") private var approval = CommandApproval.risky.rawValue
    private var approvalChoice: Binding<String> {   // a saved "auto" from before shows as Only when risky
        Binding(get: { CommandApproval(rawValue: approval)?.rawValue ?? CommandApproval.risky.rawValue }, set: { approval = $0 })
    }
    @AppStorage("askOutsideFolder") private var askOutsideFolder = true
    @AppStorage("shareAppLog") private var shareLog = true
    @AppStorage("shareAppPictures") private var sharePictures = true
    @State private var model = Builder.piModel
    @State private var revision = 0   // bumps after key changes so the view re-reads KeyStore
    @State private var notificationsDenied = false

    private var selectedEngine: Engine { Engine(rawValue: engine) ?? .pi }

    // Claude Code's and Codex's sign-ins, checked whenever the agent or where its tool was found changes. Kept
    // per engine, so a check or browser sign-in that finishes after the agent changed only updates its own.
    @State private var signIns: [Engine: Bool] = [:]
    @State private var signingIn: Engine?
    private var signedIn: Bool? { signIns[selectedEngine] }
    /// Changes when the tool turns up (installed while Settings is open) or moves, as well as with the agent.
    private var signInCheck: String { _ = revision; return "\(engine) \(ToolLocator.path(for: selectedEngine) ?? "")" }

    /// What stands between the chosen agent and building, if anything.
    private enum Readiness { case ready, checking, notInstalled, signedOut, problem(String) }

    private var readiness: Readiness {
        _ = revision
        guard selectedEngine != .pi else { return Builder.problem().map(Readiness.problem) ?? .ready }
        guard ToolLocator.path(for: selectedEngine) != nil else { return .notInstalled }
        switch signedIn {
        case nil: return .checking
        case false?: return .signedOut
        case true?: return Builder.problem().map(Readiness.problem) ?? .ready
        }
    }

    /// Not Ready beside the menu when something's wrong (ready says nothing). Where Claude Code or Codex was
    /// found is in its help, for working out which copy runs when there are several.
    @ViewBuilder private var agentStatus: some View {
        Group {
            switch readiness {
            case .ready: EmptyView()
            case .checking: ProgressView().controlSize(.small)
            // Icon and word close together: a Label in a form row spaces them like a list item.
            default: HStack(spacing: 4) { Image(systemName: "exclamationmark.circle.fill"); Text("Not Ready") }.foregroundStyle(.orange)
            }
        }
        .help(ToolLocator.path(for: selectedEngine).map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "")
    }

    /// When the agent isn't ready: why, and the one thing that fixes it.
    @ViewBuilder private var agentFix: some View {
        switch readiness {
        case .notInstalled:
            if let app = selectedEngine.desktopApp {
                LabeledContent("\(selectedEngine.title) comes with the \(app.name) app.") {
                    Link("Download the \(app.name) App", destination: app.download)
                }
            }
        case .signedOut:
            LabeledContent("Sign in to \(selectedEngine.title) to build with it.") {
                if signingIn == selectedEngine {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Finish in your browser…").foregroundStyle(.secondary) }
                } else {
                    Button("Sign In…") { Task { await startSignIn() } }
                }
            }
        case .problem(let problem):
            Text(problem).foregroundStyle(.orange).font(.callout)
        case .ready, .checking:
            EmptyView()
        }
    }

    private func checkSignIn() async {
        let engine = selectedEngine
        guard engine != .pi, ToolLocator.path(for: engine) != nil else { return }
        signIns[engine] = nil
        let signedIn = await EngineSignIn.isSignedIn(engine) ?? true   // can't tell: don't hold it up
        // The check's process outlives a cancelled task; a newer check of this engine has the say.
        guard !Task.isCancelled else { return }
        signIns[engine] = signedIn
    }

    private func startSignIn() async {
        let engine = selectedEngine
        signingIn = engine
        defer { if signingIn == engine { signingIn = nil } }
        _ = await EngineSignIn.signIn(engine)
        signIns[engine] = await EngineSignIn.isSignedIn(engine) ?? true
    }

    /// Providers added in Settings → Providers, plus the current one even if its key was removed.
    private var addedProviders: [PiProvider] {
        _ = revision
        return Provider.apiProviders.filter { KeyStore.key(for: $0.id) != nil || $0.id == provider }
    }

    /// The provider menu's last item switches to the Providers tab instead of choosing a provider.
    private static let configure = "configure-providers"
    private var providerChoice: Binding<String> {
        Binding(get: { provider }, set: { if $0 == Self.configure { tab = "providers" } else { provider = $0 } })
    }

    /// One menu for what builds apps, as Settings → Apps lists what answers inside them: the models under
    /// what runs them (Claude Code, Codex, OpenRouter, Native Mac AI…). Long lists (OpenRouter's, another
    /// key's) are the suggested models and the current one, with "Other model…" opening the search.
    private struct TextChoice: Identifiable { let id: String; let label: String }
    private struct TextGroup: Identifiable { let title: String; let items: [TextChoice]; var id: String { title } }

    @State private var otherModel = false   // "Other model…" chosen: the search list is shown

    private var textChoices: [TextGroup] {
        _ = revision
        var groups: [TextGroup] = []
        // The sign-ins, each model they offer; an uninstalled one is a single entry so it can still be picked
        // and its fix shown.
        if ToolLocator.path(for: .claude) != nil {
            // The tool's own default stays on offer, so the account's choice can be returned to.
            groups.append(TextGroup(title: "Claude Code", items: Builder.claudeModels.map { TextChoice(id: "claude:\($0.id)", label: $0.label) }))
        } else {
            groups.append(TextGroup(title: "Claude Code", items: [TextChoice(id: "claude:", label: "Not installed")]))
        }
        if ToolLocator.path(for: .codex) != nil {
            groups.append(TextGroup(title: "Codex", items: Builder.codexModels.map { TextChoice(id: "codex:\($0.id)", label: $0.label) }))
        } else {
            groups.append(TextGroup(title: "Codex", items: [TextChoice(id: "codex:", label: "Not installed")]))
        }
        for api in addedProviders {
            var items: [TextChoice] = []
            let current = Builder.piModel(for: api.id)
            if api.id == "openrouter" {
                items = Provider.models.map { TextChoice(id: "pi:openrouter:\($0.id)", label: $0.label) }
                if !current.isEmpty, !Provider.models.contains(where: { $0.id == current }) {
                    items.append(TextChoice(id: "pi:openrouter:\(current)", label: current))
                }
            } else if !current.isEmpty {
                items.append(TextChoice(id: "pi:\(api.id):\(current)", label: current))
            }
            items.append(TextChoice(id: "pi-other:\(api.id)", label: "Other model…"))
            groups.append(TextGroup(title: api.name, items: items))
        }
        if FileManager.default.fileExists(atPath: Agent.userConfigDir) {
            var items: [TextChoice] = []
            let current = Builder.piModel(for: Builder.myPiProvider)
            if !current.isEmpty { items.append(TextChoice(id: "pi:\(Builder.myPiProvider):\(current)", label: current)) }
            items.append(TextChoice(id: "pi-other:\(Builder.myPiProvider)", label: "Other model…"))
            groups.append(TextGroup(title: "Your own pi setup", items: items))
        }
        var onMac = local.installed.filter { !LocalModels.isDecisionModel($0.id) }
            .map { TextChoice(id: "pi:\(Builder.localProvider):\($0.id)", label: $0.name) }
        if onMac.isEmpty { onMac.append(TextChoice(id: "pi-other:\(Builder.localProvider)", label: "No models yet")) }
        groups.append(TextGroup(title: "Native Mac AI", items: onMac))
        for id in local.external.keys.sorted(by: { LocalModels.externalName($0) < LocalModels.externalName($1) }) {
            let items = (local.external[id] ?? []).map { TextChoice(id: "pi:\(id):\($0)", label: $0) }
            if !items.isEmpty { groups.append(TextGroup(title: LocalModels.externalName(id), items: items)) }
        }
        return groups
    }

    private var textChoice: Binding<String> {
        Binding(get: {
            _ = revision
            switch selectedEngine {
            case .claude: return "claude:\(Builder.engineModel(.claude))"
            case .codex: return "codex:\(Builder.engineModel(.codex))"
            case .pi: return otherModel || model.isEmpty ? "pi-other:\(provider)" : "pi:\(provider):\(model)"
            }
        }, set: { choice in
            if choice == Self.configure { tab = "providers"; return }
            let parts = choice.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            switch parts[0] {
            case "claude", "codex":
                let which: Engine = parts[0] == "claude" ? .claude : .codex
                Builder.setEngineModel(parts.count > 1 ? parts[1] : "", for: which)
                engine = which.rawValue
                otherModel = false
            case "pi":
                // The model is saved under its provider before the provider changes, so the change reads it back.
                Builder.piProvider = parts[1]
                Builder.piModel = parts[2]
                provider = parts[1]
                model = parts[2]
                engine = Engine.pi.rawValue
                otherModel = false
            case "pi-other":
                provider = parts[1]
                engine = Engine.pi.rawValue
                otherModel = true
            default: break
            }
            revision += 1
        })
    }

    var body: some View {
        Form {
            Section("AI settings for Lamp") {
                LabeledContent("Text generation") {
                    HStack(spacing: 10) {
                        agentStatus
                        Picker("Text generation", selection: textChoice) {
                            ForEach(textChoices) { group in
                                Section(group.title) {
                                    ForEach(group.items, id: \.id) { Text($0.label).tag($0.id) }
                                }
                            }
                            Divider()
                            Text("Configure providers…").tag(Self.configure)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                agentFix
                if selectedEngine == .pi {
                    // Keys are managed in Providers; only ask here if the chosen provider has lost its key.
                    if let api = Provider.apiProvider(provider), KeyStore.key(for: api.id) == nil {
                        KeyRow(provider: api) { revision += 1; recheck() }
                    }
                    if otherModel { ModelPicker(provider: provider, model: $model, revision: revision) }
                }
                Picker("Image generation", selection: Binding(get: { _ = revision; return Icons.iconModel }, set: { Icons.iconModel = $0; revision += 1 })) {
                    ForEach(Icons.imageChoices, id: \.id) { Text($0.label).tag($0.id) }
                }
            }
            Section {
                Picker("Ask before running commands", selection: approvalChoice) {
                    ForEach(CommandApproval.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if (CommandApproval(rawValue: approval) ?? .risky).isAutomatic && CommandApproval.claudeAutoUnavailable && selectedEngine == .claude {
                    Text("Claude Code's auto mode isn't available for your account, so Lamp asks before every command.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Permissions and Privacy") {
                // One row of checkboxes, box first, as Finder's settings have them: in a stack, so the form
                // doesn't lay each out as a label with its control at the far end.
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Ask before the agent opens files outside an app's folder", isOn: $askOutsideFolder)
                    Toggle("Show the agent what an app prints while it runs", isOn: $shareLog)
                    Toggle("Let the agent see the content of app windows", isOn: $sharePictures)
                    Toggle("Notify me when an app is ready or needs me", isOn: $notify)
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                if notify && notificationsDenied {
                    HStack {
                        Text("Notifications are turned off for Lamp in System Settings.")
                            .font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button("Open System Settings") {
                            let id = Bundle.main.bundleIdentifier ?? ""
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")!)
                        }
                        .controlSize(.small)
                    }
                }
            }
            ExperimentalSettings()
        }
        .settingsPane()
        .onChange(of: notify) { Notifier.shared.setBadge(store.unread.count) }
        .task { notificationsDenied = await Notifier.shared.isDenied() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { notificationsDenied = await Notifier.shared.isDenied() }
            revision += 1   // looks for the agent's tool again: it may have been installed meanwhile
        }
        .onChange(of: engine) { recheck() }
        .task(id: signInCheck) { await checkSignIn() }
        .onChange(of: provider) { model = Builder.piModel; recheck() }
        .onChange(of: model) { Builder.piModel = model; recheck() }
        .onAppear { revision += 1 }   // keys may have changed in the Providers tab
        .task { await local.detectExternal() }
    }

    private func recheck() { Task { await store.recheckSetup() } }
}

/// The AI, images and decisions that apps use while they run.
struct AppsSettings: View {
    @AppStorage("appModel") private var appModel = AppAI.defaultRoute.id
    @AppStorage("awayModel") private var awayModel = ""
    @AppStorage("awayImageModel") private var awayImageModel = ""
    @AppStorage("awayDecisionModel") private var awayDecisionModel = ""
    @ObservedObject private var local = LocalModels.shared
    @AppStorage("experimentIOSApps") private var iosApps = false
    @AppStorage("settingsTab") private var settingsTab = "building"
    @AppStorage("settingsSheet") private var settingsSheet = ""
    @AppStorage("imageModel") private var imageModel = Icons.artModels[0].id
    @AppStorage("decisionModel") private var decisionModel = AppAI.decisionModel.id
    @State private var revision = 0   // bumps after key changes so the view re-reads KeyStore

    var body: some View {
        Form {
            Section("Models used in apps") {
                Picker("Text generation", selection: Binding(get: { AppAI.canonicalRoute(appModel) }, set: { appModel = $0 })) {
                    ForEach(AppAI.textRouteGroups(including: appModel), id: \.title) { group in
                        Section(group.title) { ForEach(group.routes) { Text($0.name).tag($0.id) } }
                    }
                }
                Picker("Image generation", selection: $imageModel) {
                    ForEach(Icons.imageChoices, id: \.id) { Text($0.label).tag($0.id) }
                }
                let _ = revision   // re-read KeyStore after keys change
                if AppAI.allTextRoutes.first(where: { $0.id == appModel })?.available == false {
                    KeyNote(text: "That model needs an OpenRouter key. Until there is one, text inside apps goes through \(AppAI.defaultRoute.label.replacingOccurrences(of: "Your ", with: "your ")).")
                }
                if let maker = AppAI.imageRouteName {
                    // A cloud model chosen with no key behind it isn't what makes the pictures: say what does, and why.
                    if !Provider.hasKey, imageModel != Icons.localArt {
                        KeyNote(text: "\(Icons.artModels.first { $0.id == imageModel }?.label ?? "That model") needs an OpenRouter key. Until there is one, pictures come from \(maker).")
                    }
                } else {
                    KeyNote(text: "Pictures need an OpenRouter key or a picture model on this Mac: a \(Builder.engine == .pi ? "builder's" : Builder.engine.title) sign-in can't make them.")
                }

                Picker("Decision model", selection: $decisionModel) {
                    ForEach(AppAI.decisionModels, id: \.id) { Text($0.label).tag($0.id) }
                }
                let decisionChoice = AppAI.decisionModels.first { $0.id == decisionModel } ?? AppAI.decisionModel
                switch decisionChoice.provider {
                case "typesafe", "openai":
                    if let provider = Provider.keyProvider(decisionChoice.provider), KeyStore.key(for: provider.id) == nil {
                        KeyRow(provider: provider, label: "\(provider.name) key") { revision += 1 }
                    }
                case "local":
                    if let spec = LocalModels.decisionCatalog.first, !local.isInstalled(spec) {
                        if let progress = local.progress[spec.id] {
                            ProgressView(value: progress) { Text("Downloading \(spec.name)…") }.font(.caption)
                        } else {
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(spec.name) isn't on this Mac yet (\(spec.sizeGB, specifier: "%.1f") GB). Until it is, decisions are made by \(AppAI.fastModelName).")
                                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Button("Download") { local.download(spec) }.controlSize(.small)
                            }
                        }
                    }
                case "text":
                    Text("A small text model (\(AppAI.fastModelName)) answers the questions as JSON: slower and less exact than a decision model, but needs nothing more.")
                        .font(.caption).foregroundStyle(.secondary)
                default:
                    if KeyStore.openRouterKey == nil {
                        KeyNote(text: AppAI.canAnswer
                                ? "Needs an OpenRouter key. Until there is one, decisions are made by \(AppAI.fastModelName) instead: slower and less exact than Jev."
                                : "Needs an OpenRouter key, or pick another.")
                    }
                }
                Text("Fast, cheap typed judgments for apps: yes/no probabilities, picking from options, and rating on a scale, each with a calibrated confidence.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if iosApps {
                // An app on the person's phone can only reach OpenRouter when it can't reach this Mac, so the
                // choice here is among OpenRouter's models, and it's the one thing a phone needs a key for.
                Section("iOS apps away from this Mac (through OpenRouter)") {
                    Picker("Text generation", selection: Binding(get: { AppAI.awayModel.id }, set: { awayModel = $0 })) {
                        ForEach(AppAI.anthropicModels, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    Picker("Image generation", selection: Binding(get: { AppAI.awayImageModel }, set: { awayImageModel = $0 })) {
                        ForEach(Icons.artModels, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    Picker("Decision model", selection: Binding(get: { AppAI.awayDecisionModel.id }, set: { awayDecisionModel = $0 })) {
                        ForEach(AppAI.awayDecisionModels, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    if Provider.hasKey {
                        Text("When an app can't reach this Mac it goes to OpenRouter with your key. What it spends then isn't shown in Lamp.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        KeyNote(text: "Needs an OpenRouter key: without one, apps on your phone can only use AI near this Mac.")
                    }
                }
            }
            ComputerUseSettings()
        }
        .settingsPane()
        .onAppear { revision += 1 }   // keys may have changed in the Providers tab
    }
}

/// What's in Lamp but not yet for everyone: each switch here brings a feature into the interface.
struct ExperimentalSettings: View {
    @EnvironmentObject private var store: Store
    @AppStorage("experimentIOSApps") private var iosApps = false
    @AppStorage(Memory.switchKey) private var memory = false
    @AppStorage("appleTeam") private var team = ""
    @AppStorage("settingsTab") private var settingsTab = "building"
    @AppStorage("settingsSheet") private var settingsSheet = ""
    @State private var teams: [(id: String, name: String)] = []

    var body: some View {
        Section {
            // A checkbox, as in Permissions and Privacy. Where an app opens (a simulator or the person's own
            // phone) is chosen per app under Try On, so there's nothing more to switch here: just the team the
            // phone builds are signed for.
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Build iOS apps", isOn: $iosApps)
                    .onChange(of: iosApps) { store.updateLocalNetwork() }
                Text("Choose iPhone or iPad when you start a new app, then where it opens under Try On: a simulator on this Mac, or your own iPhone or iPad. Needs Xcode.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
            if iosApps {
                Button("Check iPhone & iPad Setup…") { PhoneSetup.shared.show() }
                Group {
                    if teams.isEmpty {
                        TextField("Apple Team ID", text: $team, prompt: Text("Ten letters and digits, from Xcode → Settings → Accounts"))
                    } else {
                        Picker("Apple Team", selection: $team) {
                            ForEach(teams, id: \.id) { Text("\($0.name) (\($0.id))").tag($0.id) }
                            if !team.isEmpty, !teams.contains(where: { $0.id == team }) { Text(team).tag(team) }
                        }
                    }
                    Text("For putting an app on your own iPhone or iPad: sign in to your Apple account in Xcode, plug the phone in, and Try On offers to pair it. What the app uses away from this Mac is chosen under Apps.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !Provider.hasKey {
                        KeyNote(text: "Needs an OpenRouter key: without one, apps on your phone can only use AI near this Mac.")
                    }
                }
                .padding(.leading, 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Remember how I like things", isOn: $memory)
                Text(memory ? "Lamp keeps short notes on your taste and on what you decided about each app, whichever AI is building. See and change them under Memory, above."
                     : "Lamp keeps short notes on your taste and on what you decided about each app, so a new app starts out in your style, whichever AI is building.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
        } header: { Text("Experimental") }
        .task {
            teams = await Devices.knownTeams()
            // The account signed in to Xcode is the one that can sign, so its team is the first choice
            // whenever the stored one isn't among Xcode's.
            let signedIn = Devices.xcodeTeams()
            if let first = signedIn.first, !signedIn.contains(where: { $0.id == team }) { team = first.id }
            else if team.isEmpty, let first = teams.first { team = first.id }
        }
    }
}

/// Turns apps' use of the other apps on the Mac (LampComputer) on or off. Turning it on installs CuaDriver if
/// needed and asks for its permissions; turning it off stops apps using it (CuaDriver stays installed).
struct ComputerUseSettings: View {
    @AppStorage("computerUse") private var enabled = false
    @AppStorage("codexComputerUseOff") private var codexOff = false
    @State private var status: ComputerUse.Status?
    @State private var working: String?
    @State private var problem: String?

    var body: some View {
        Section("Permissions and Privacy") {
            // Checkboxes with their descriptions under their words, as in Building's Permissions and Privacy;
            // the choice of what does the clicking is a part of the first, so it's indented under it.
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Let apps use your other apps", isOn: Binding(get: { enabled }, set: { on in
                    if on { Task { await turnOn() } } else { enabled = false; problem = nil }
                }))
                .disabled(working != nil)
                note("Lets your apps read and use your other apps, such as Slack, Mail, or Gmail and LinkedIn in your browser, with the accounts you're already signed in to. Apps ask before every click or keystroke.")
                if CodexComputerUse.server != nil {
                    // The ChatGPT app's Computer Use is on this Mac: it does the looking and clicking, unless the
                    // person would rather keep CuaDriver.
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Use the ChatGPT app's Computer Use", isOn: Binding(get: { !codexOff }, set: { useCodex in
                            codexOff = !useCodex
                            // Back to CuaDriver while the feature is on: it has to be installed and allowed, like a first turn-on.
                            Task { if enabled, !useCodex { await turnOn() } else { status = await ComputerUse.status() } }
                        }))
                        .disabled(working != nil)
                        note(codexOff
                             ? "CuaDriver (from Cua, open source) does the looking and clicking: turning the setting above on adds it to Applications, and macOS asks you to allow it Accessibility and Screen Recording."
                             : "The ChatGPT app has Computer Use installed, so it does the looking and clicking, with the permissions you gave it there. It sends real clicks to the app in the background and reads its contents without moving your pointer. Turn it off to use CuaDriver instead.")
                    }
                    .padding(.top, 6)
                    .padding(.leading, 20)
                } else {
                    note("Turning it on adds CuaDriver (from Cua, open source) to Applications, and macOS asks you to allow it Accessibility and Screen Recording. With the ChatGPT app and its Computer Use plugin installed, Lamp uses that instead.")
                }
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let working {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(working).foregroundStyle(.secondary) }
                    .font(.callout)
            } else if enabled, status == .needsPermission {
                LabeledContent("CuaDriver needs permission") {
                    Button("Allow Access…") { Task { await allow() } }
                }
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
        }
        .task { status = await ComputerUse.status() }
    }

    /// A checkbox's description, lined up with its words.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 20)
    }

    private func turnOn() async {
        problem = nil
        if CodexComputerUse.isAvailable {   // nothing to install: the ChatGPT app's helper has the permissions
            status = .ready
            enabled = true
            return
        }
        do {
            try await ComputerUse.install { working = $0 }
            status = await ComputerUse.status()
            if status != .ready { await allow() }
            enabled = status == .ready
        } catch {
            problem = error.localizedDescription
        }
        working = nil
    }

    private func allow() async {
        working = "Waiting for you to allow access in System Settings…"
        await ComputerUse.requestPermissions()
        status = await ComputerUse.status()
        working = nil
        if status == .ready {
            enabled = true
        } else {
            problem = "CuaDriver doesn't have both permissions yet. Allow Accessibility and Screen Recording for CuaDriver in System Settings → Privacy & Security, then try again."
        }
    }
}

/// What's on this Mac (Native Mac AI, Ollama, LM Studio, and the Claude Code and Codex sign-ins), then the
/// providers you've added a key for. Each row says what it's doing for Lamp right now. Double-click one to
/// see its models, sign in, or change its key.
struct ProvidersSettings: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var local = LocalModels.shared
    @AppStorage("settingsSheet") private var pendingSheet = ""   // set by the setup screen
    @AppStorage("appModel") private var appModel = ""            // read so the badges follow the picker
    @State private var selection: String?
    @State private var showing: ProviderDetail?
    @State private var removing: PiProvider?
    @State private var revision = 0   // bumps after key changes so the view re-reads KeyStore
    @State private var signedIn: [Engine: Bool?] = [:]

    private var added: [PiProvider] {
        _ = revision
        return Provider.keyProviders.filter { KeyStore.key(for: $0.id) != nil }
    }

    private var addable: [PiProvider] {
        _ = revision
        return Provider.keyProviders.filter { KeyStore.key(for: $0.id) == nil }
    }

    /// On this Mac: Native Mac AI, Ollama and LM Studio (always there), and the coding agents when installed.
    private var onThisMac: [String] {
        [Builder.localProvider] + LocalModels.externalIDs
            + [Engine.claude, .codex].filter { ToolLocator.path(for: $0) != nil }.map { "engine:\($0.rawValue)" }
    }

    /// What each row is doing for Lamp right now, so the tab shows what's used for what.
    private func jobs(_ id: String) -> [String] {
        _ = revision
        _ = appModel
        var jobs: [String] = []
        let builder = Builder.engine == .pi ? Builder.piProvider : "engine:\(Builder.engine.rawValue)"
        if builder == id { jobs.append("Builds apps") }
        let answers: String
        switch AppAI.model.kind {
        case .openRouter: answers = "openrouter"
        case .engine(.pi, _): answers = Builder.piProvider
        case .engine(let engine, _): answers = "engine:\(engine.rawValue)"
        case .localModel(let provider, _): answers = provider
        }
        if answers == id { jobs.append("Answers apps") }
        switch AppAI.imageRoute {
        case .openRouter: if id == "openrouter" { jobs.append("Pictures") }
        case .local: if id == Builder.localProvider { jobs.append("Pictures") }
        case .codex: if id == "engine:codex" { jobs.append("Pictures") }
        case nil: break
        }
        let decision = AppAI.decisionModel
        let decides: String
        switch decision.provider {
        case "local": decides = AppAI.localDecisionModel() != nil ? Builder.localProvider : answers
        case "text": decides = answers
        default: decides = KeyStore.key(for: decision.provider) != nil ? decision.provider : answers
        }
        if decides == id { jobs.append("Decisions") }
        return jobs
    }

    /// One row: logo, name, what it's doing, and its state.
    private func row(_ id: String) -> some View {
        HStack(spacing: 10) {
            ProviderLogo(id: id, size: 24)
            Text(ProviderDetail.name(id))
            ForEach(jobs(id), id: \.self) { job in
                Text(job).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            }
            Spacer()
            Text(detail(id)).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .tag(id)
    }

    private func list(_ rows: [String]) -> some View {
        List(rows, id: \.self, selection: $selection) { id in row(id) }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first {
                    if id.hasPrefix("engine:") {
                        Button("Sign In…") { showing = ProviderDetail(id) }
                    } else {
                        Button(Provider.keyProvider(id) == nil ? "Show Models…" : "Edit…") { showing = ProviderDetail(id) }
                    }
                    if let provider = Provider.keyProvider(id) {
                        Button("Remove…", role: .destructive) { removing = provider }
                    }
                }
            } primaryAction: { ids in
                showing = ids.first.map(ProviderDetail.init)
            }
            .onDeleteCommand { removing = selection.flatMap(Provider.keyProvider) }
            .scrollDisabled(true)
            .frame(height: CGFloat(max(rows.count, 1)) * 40)
    }

    var body: some View {
        Form {
            Section {
                list(onThisMac)
                if Experiments.iosApps {
                    Text("These stay on this Mac: iOS apps can use them only on the same Wi‑Fi network as it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("On this Mac") }
            Section {
                if added.isEmpty {
                    Text("No keys yet. OpenRouter gives apps the most to choose from and makes pictures\(Experiments.iosApps ? ", and goes with an app to your iPhone or iPad" : "").")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    list(added.map(\.id))
                }
                HStack(spacing: 0) {
                    Menu {
                        ForEach(addable) { provider in
                            Button(provider.name) { showing = .key(provider) }
                        }
                    } label: {
                        Image(systemName: "plus").frame(width: 24, height: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(addable.isEmpty)
                    Divider().frame(height: 16).padding(.horizontal, 4)
                    Button {
                        removing = selection.flatMap(Provider.keyProvider)
                    } label: {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selection.flatMap(Provider.keyProvider) == nil)
                    .help("Only keys can be removed")
                    Spacer()
                    if Experiments.iosApps {
                        Text("A key can go with an app to your iPhone or iPad.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("With your key") }
        }
        .settingsPane()
        .sheet(item: $showing) { detail in
            switch detail {
            case .key(let provider): ProviderSheet(provider: provider) { changed() }
            case .local: LocalAISheet()
            case .server(let id): ServerSheet(id: id)
            case .engine(let engine): EngineSheet(engine: engine, signedIn: signedIn[engine] ?? nil) { refreshSignIns() }
            }
        }
        .confirmationDialog("Remove \(removing?.name ?? "provider")?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) {
                if let removing { KeyStore.setKey(nil, for: removing.id) }
                selection = nil
                changed()
            }
        } message: {
            Text("Lamp forgets its API key. Apps and builds that use it stop working until you add it again.")
        }
        .onAppear { openPending(); refreshSignIns(); KeyStore.preload() }   // a key declined at launch is asked for again
        .onChange(of: pendingSheet) { openPending() }
        .task { local.refresh(); await local.detectExternal() }
    }

    private func refreshSignIns() {
        Task {
            for engine in [Engine.claude, .codex] where ToolLocator.path(for: engine) != nil {
                signedIn[engine] = await EngineSignIn.isSignedIn(engine)
            }
        }
    }

    private func detail(_ id: String) -> String {
        if id.hasPrefix("engine:"), let engine = Engine(rawValue: String(id.dropFirst(7))) {
            switch signedIn[engine] {
            case .some(.some(true)): return "Signed in"
            case .some(.some(false)): return "Not signed in"
            default: return "Checking…"
            }
        }
        if id == Builder.localProvider {
            guard !local.installed.isEmpty else { return "No models yet" }
            let bytes = local.installed.reduce(Int64(0)) { $0 + $1.bytes }
            return "\(Self.models(local.installed.count)) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        }
        if id.hasPrefix("ext-") {
            guard let models = local.external[id] else { return "Not running" }
            return "Running · \(Self.models(models.count))"
        }
        return KeyStore.usesKeychain ? "Key in Keychain" : "Key saved"
    }

    private static func models(_ count: Int) -> String { count == 1 ? "1 model" : "\(count) models" }

    private func openPending() {
        guard !pendingSheet.isEmpty else { return }
        showing = ProviderDetail(pendingSheet)
        pendingSheet = ""
    }

    private func changed() {
        revision += 1
        Task { await store.recheckSetup() }
    }
}

/// What double-clicking a provider opens.
private enum ProviderDetail: Identifiable {
    case key(PiProvider)
    case local
    case server(String)
    case engine(Engine)

    init(_ id: String) {
        if id == Builder.localProvider { self = .local }
        else if id.hasPrefix("engine:"), let engine = Engine(rawValue: String(id.dropFirst(7))) { self = .engine(engine) }
        else if let provider = Provider.keyProvider(id) { self = .key(provider) }
        else { self = .server(id) }
    }

    var id: String {
        switch self {
        case .key(let provider): provider.id
        case .local: Builder.localProvider
        case .server(let id): id
        case .engine(let engine): "engine:\(engine.rawValue)"
        }
    }

    static func name(_ id: String) -> String {
        if id == Builder.localProvider { return "Native Mac AI" }
        if id.hasPrefix("ext-") { return LocalModels.externalName(id) }
        if id.hasPrefix("engine:"), let engine = Engine(rawValue: String(id.dropFirst(7))) { return engine.title }
        return Provider.keyProvider(id)?.name ?? id
    }
}

/// Claude Code or Codex: signed in or not, and the way to sign in. What they do for Lamp is on the row.
private struct EngineSheet: View {
    let engine: Engine
    let signedIn: Bool?
    let changed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProviderHeader(id: "engine:\(engine.rawValue)",
                           detail: signedIn == true ? "Signed in. Builds apps and answers inside them with your \(engine == .claude ? "Claude" : "ChatGPT") subscription."
                                : signedIn == false ? "Not signed in yet." : "Checking the sign-in…")
            if Experiments.iosApps {
                Text("The sign-in stays on this Mac: iOS apps can use it only on the same Wi‑Fi network as it. Away from it they need an OpenRouter key.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(working ? "Signing In…" : "Sign In…") {
                    working = true
                    Task { _ = await EngineSignIn.signIn(engine); working = false; changed() }
                }
                .keyboardShortcut(.defaultAction).disabled(working || signedIn == true)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// Header shared by the provider sheets: logo, name and one line about it.
private struct ProviderHeader: View {
    let id: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            ProviderLogo(id: id, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(ProviderDetail.name(id)).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Models an Ollama or LM Studio server offers. They're managed in that app, not here.
private struct ServerSheet: View {
    let id: String
    @ObservedObject private var local = LocalModels.shared
    @Environment(\.dismiss) private var dismiss
    @State private var checking = false

    var body: some View {
        let name = LocalModels.externalName(id)
        let models = local.external[id]
        VStack(alignment: .leading, spacing: 16) {
            ProviderHeader(id: id, detail: models == nil ? "Not running" : "Running on this Mac")
            if let models {
                List(models, id: \.self) { Text($0) }
                    .frame(height: min(CGFloat(max(models.count, 3)) * 32 + 16, 320))
                Text("Add or remove models in \(name). Pick one to build apps with in Building.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Open \(name) with at least one model, and its models show up here and in Building.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if models == nil {
                    Button(checking ? "Checking…" : "Check Again") {
                        checking = true
                        Task { await local.detectExternal(); checking = false }
                    }
                    .disabled(checking)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// Add, replace or remove one provider's API key.
private struct ProviderSheet: View {
    let provider: PiProvider
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @StateObject private var check = KeyCheck()
    private let hasKey: Bool

    init(provider: PiProvider, onChange: @escaping () -> Void) {
        self.provider = provider
        self.onChange = onChange
        hasKey = KeyStore.key(for: provider.id) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProviderLogo(id: provider.id, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name).font(.headline)
                    Text(hasKey ? (KeyStore.usesKeychain ? "Key saved in Keychain" : "Key saved") : "Not added yet")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Form {
                SecureField(hasKey ? "New key" : "API key", text: $key, prompt: Text("Paste key"))
                    .onSubmit(save)
                    .onChange(of: key) { check.edited() }
                Link("Get a key from \(provider.name)", destination: URL(string: provider.keyURL)!)
                    .font(.callout)
            }
            if let problem = check.problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if hasKey {
                    Button("Remove Key", role: .destructive) {
                        KeyStore.setKey(nil, for: provider.id)
                        onChange()
                        dismiss()
                    }
                    .disabled(check.checking)
                }
                Spacer()
                if check.checking { ProgressView().controlSize(.small) }
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(check.canSaveUnchecked ? "Save Anyway" : hasKey ? "Save" : "Add", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.trimmed.isEmpty || check.checking)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onDisappear { check.cancel() }   // closed while OpenRouter was being asked: nothing is saved
    }

    private func save() {
        check.save(key, for: provider) {
            onChange()
            dismiss()
        }
    }
}

/// Saves a key typed into Settings, asking OpenRouter about its own first, as the key card in the chat does:
/// a key it refuses isn't saved, so a slip shows up here and not later as a build or a picture that fails.
/// The other providers' keys are saved as typed; each would need its own question.
///
/// Settings is also where a key is put in ahead of time, perhaps with no connection, so when OpenRouter
/// can't be asked the key isn't turned away: the person is told, and saving again keeps it unchecked.
@MainActor
final class KeyCheck: ObservableObject {
    @Published private(set) var checking = false
    @Published private(set) var problem: String?
    /// The key OpenRouter couldn't be asked about; saving it again goes ahead without asking.
    @Published private var unchecked: String?
    private var task: Task<Void, Never>?

    var canSaveUnchecked: Bool { unchecked != nil }

    /// The field changed: what was said about the old text no longer holds.
    func edited() {
        cancel()
        problem = nil
        unchecked = nil
    }

    func cancel() {
        task?.cancel()
        task = nil
        checking = false
    }

    func save(_ typed: String, for provider: PiProvider, saved: @escaping () -> Void) {
        let key = typed.trimmed
        guard !key.isEmpty, !checking else { return }
        guard provider.id == "openrouter", key != unchecked else {
            KeyStore.setKey(key, for: provider.id)
            edited()
            return saved()
        }
        checking = true
        problem = nil
        task = Task {
            let verdict = await SetupView.openRouterVerdict(key)
            guard !Task.isCancelled else { return }
            checking = false
            switch verdict {
            case .accepted:
                KeyStore.setKey(key, for: provider.id)
                saved()
            case .refused(let why):
                problem = why
            case .unchecked(let why):
                problem = why + " You can save the key without checking it."
                unchecked = key
            }
        }
    }
}

/// A provider's logo on a white rounded tile, like an app icon. Falls back to its initial.
struct ProviderLogo: View {
    let id: String
    let size: CGFloat

    private static var cache: [String: NSImage] = [:]
    /// Logos that are already a full icon, drawn edge to edge instead of on a tile.
    private static let fullBleed: Set<String> = ["typesafe"]

    private var image: NSImage? {
        if let cached = Self.cache[id] { return cached }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("ProviderLogos/\(id).png"),
              let image = NSImage(contentsOf: url) else { return nil }
        Self.cache[id] = image
        return image
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        ZStack {
            shape.fill(.white)
            if id == Builder.localProvider {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: size * 0.5)).foregroundStyle(.black.opacity(0.75))
            } else if id.hasPrefix("engine:") {
                Image(systemName: id == "engine:claude" ? "asterisk" : "terminal")
                    .font(.system(size: size * 0.5)).foregroundStyle(.black.opacity(0.75))
            } else if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .padding(Self.fullBleed.contains(id) ? 0 : size * 0.18)
            } else {
                Text(ProviderDetail.name(id).prefix(1))
                    .font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.black.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.black.opacity(0.1), lineWidth: 0.5))
    }
}

/// API key for one provider: shows "saved" with a Remove button, or a field to add one.
/// A note that something needs an OpenRouter key, with the way to add one at its right: the same wherever
/// Settings asks for a key, so the person always has the button to hand.
struct KeyNote: View {
    let text: String
    @AppStorage("settingsTab") private var settingsTab = "building"
    @AppStorage("settingsSheet") private var settingsSheet = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Add a Key…") { settingsSheet = "openrouter"; settingsTab = "providers" }.controlSize(.small)
        }
    }
}

struct KeyRow: View {
    let provider: PiProvider
    var label: String?
    var onChange: () -> Void
    @State private var key = ""
    @State private var saved = false
    @StateObject private var check = KeyCheck()

    var body: some View {
        Group {
            if saved {
                LabeledContent(label ?? "\(provider.name) key") {
                    HStack {
                        Text(KeyStore.usesKeychain ? "Saved in Keychain" : "Saved").foregroundStyle(.secondary)
                        Button("Remove", role: .destructive) {
                            KeyStore.setKey(nil, for: provider.id)
                            saved = false
                            onChange()
                        }
                    }
                }
            } else {
                LabeledContent(label ?? "\(provider.name) key") {
                    HStack {
                        SecureField("", text: $key, prompt: Text("Paste key"))
                            .onSubmit(save)
                            .onChange(of: key) { check.edited() }
                        if check.checking {
                            ProgressView().controlSize(.small)
                        } else {
                            Button(check.canSaveUnchecked ? "Save Anyway" : "Save", action: save).disabled(key.trimmed.isEmpty)
                        }
                        Link("Get one", destination: URL(string: provider.keyURL)!)
                    }
                }
                if let problem = check.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { saved = KeyStore.key(for: provider.id) != nil }
        .onChange(of: provider) { saved = KeyStore.key(for: provider.id) != nil; key = "" }
        .onDisappear { check.cancel() }
    }

    private func save() {
        check.save(key, for: provider) {
            key = ""
            saved = true
            onChange()
        }
    }
}

/// Searchable model list for a provider (from pi's catalog, downloaded local models, or a detected server).
struct ModelPicker: View {
    let provider: String
    @Binding var model: String
    let revision: Int
    @ObservedObject private var local = LocalModels.shared
    @State private var models: [String] = []
    @State private var search = ""
    @State private var loading = false

    private var filtered: [String] {
        let query = search.trimmed.lowercased()
        return query.isEmpty ? models : models.filter { $0.lowercased().contains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Model") {
                Text(model.isEmpty ? "None chosen" : model).foregroundStyle(model.isEmpty ? .orange : .primary)
                    .lineLimit(1).truncationMode(.middle)
            }
            if provider == Builder.localProvider && local.installed.isEmpty {
                Text("No models downloaded yet. Double-click Native Mac AI in Providers to get one.").font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("Search models", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if filtered.isEmpty && !search.trimmed.isEmpty { model = search.trimmed } }
                List(filtered, id: \.self, selection: Binding(get: { model }, set: { if let value = $0 { model = value } })) {
                    Text($0).tag($0)
                }
                .frame(height: 150)
                .overlay {
                    if loading { ProgressView().controlSize(.small) }
                    else if filtered.isEmpty {
                        Text(search.isEmpty ? "No models found" : "Press Return to use “\(search.trimmed)”")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: "\(provider)-\(revision)-\(local.installed.count)") { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        switch provider {
        case Builder.localProvider: models = local.installed.filter { !LocalModels.isDecisionModel($0.id) }.map(\.id)
        case let id where id.hasPrefix("ext-"): models = local.external[id] ?? []
        default: models = await Agent.listModels(provider: provider)
        }
        if provider == "openrouter" {   // suggested models first
            let suggested = Provider.models.map(\.id)
            models = suggested + models.filter { !suggested.contains($0) }
        }
        if model.isEmpty, let first = models.first { model = first }
    }
}

/// Native Mac AI: models on this Mac (shared with Local and the Hugging Face cache), plus downloads.
private struct LocalAISheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var local = LocalModels.shared
    @ObservedObject private var images = ImageModels.shared
    @ObservedObject private var tools = PythonTools.shared
    @State private var repo = ""
    @State private var custom: [LocalModelSpec] = []
    @State private var adding = false
    @State private var addError: String?

    private var downloadable: [LocalModelSpec] {
        (LocalModels.catalog + custom).filter { !local.isInstalled($0) }
    }

    /// Tall enough for a good look at the list, short enough to leave the screen around it.
    private var listHeight: CGFloat {
        min(560, ((NSScreen.main?.visibleFrame.height ?? 800) - 320).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProviderHeader(id: Builder.localProvider,
                           detail: "Private and offline. Slower and less capable than the best cloud models, especially for whole apps.")
                .padding(20)
            Divider()
            Form {
                Section {
                    if local.installed.isEmpty {
                        Text("No models yet. Download one below.").foregroundStyle(.secondary)
                    }
                    ForEach(local.installed) { installedRow($0) }
                } header: { Text("On this Mac") } footer: {
                    Text("Shared with Local and other tools through the Hugging Face cache.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    ForEach(downloadable) { downloadRow($0) }
                    HStack {
                        TextField("owner/Model-GGUF or a Hugging Face link", text: $repo)
                        Button("Add") { add() }.disabled(repo.trimmed.isEmpty || adding)
                    }
                    if adding { ProgressView().controlSize(.small) }
                    if let addError { Text(addError).font(.caption).foregroundStyle(.red) }
                } header: { Text("Download") } footer: {
                    Text("This Mac has \(LocalModels.ramGB) GB of memory. Any model repo in GGUF form works: Lamp picks the version that fits a Mac best, with image support when the model has it.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    if !ImageModels.hasMflux {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("mflux").font(.headline)
                                Text("Runs picture models. A one-time install of about 1.3 GB.")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let error = tools.errors[.mflux] { Text(error).font(.caption).foregroundStyle(.red) }
                            }
                            Spacer()
                            if tools.installing.contains(.mflux) { ProgressView().controlSize(.small) }
                            else { Button("Install") { Task { await tools.install(.mflux) } } }
                        }
                    }
                    ForEach(ImageModels.catalog) { imageRow($0) }
                } header: { Text("Pictures") } footer: {
                    Text(ImageModels.ready
                         ? "Apps' pictures and icon artwork are made here with \(images.chosen?.name ?? "the chosen model") when there's no OpenRouter key. About 10–30 seconds a picture."
                         : "Pictures made on this Mac, free and private, when there's no OpenRouter key. Slower than the cloud models, and they can't edit existing pictures.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("Model servers") {
                        HStack {
                            Text(local.serverRunning || local.mlxModel != nil ? "Running" : "Start when needed").foregroundStyle(.secondary)
                            if local.serverRunning || local.mlxModel != nil { Button("Stop") { local.stopServer() } }
                        }
                    }
                } header: { Text("Servers") } footer: {
                    Text("Models in GGUF form run on Lamp's own server; MLX models run on mlx-lm, which Lamp installs when one needs it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(height: listHeight)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 560)
        .task { local.refresh() }
    }

    private func installedRow(_ model: InstalledModel) -> some View {
        let inUse = Builder.engine == .pi && Builder.piProvider == Builder.localProvider && Builder.piModel == model.id
        let needsMLX = model.format == .mlx && LocalModels.mlxServerPath == nil
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(model.name).font(.headline)
                    Text(model.format == .mlx ? "MLX" : "GGUF").font(.caption2).padding(.horizontal, 5)
                        .background(.quaternary, in: Capsule())
                    if inUse { Text("In use").font(.caption).padding(.horizontal, 6).background(.green.opacity(0.2), in: Capsule()) }
                }
                Text("\(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file)) · \(model.source)\(model.vision ? " · sees images" : "")")
                    .font(.caption).foregroundStyle(.secondary)
                if needsMLX { Text("Needs a one-time install before it can run.").font(.caption).foregroundStyle(.orange) }
                if needsMLX, let error = tools.errors[.mlx] { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Spacer()
            if needsMLX {
                if tools.installing.contains(.mlx) { ProgressView().controlSize(.small) }
                else { Button("Install") { installMLX() } }
            } else if !inUse {
                Button("Use") { use(model.id) }
            }
            if model.deletable { Button("Delete", role: .destructive) { local.delete(model.id) } }
        }
    }

    private func downloadRow(_ spec: LocalModelSpec) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.name).font(.headline)
                Text(spec.blurb).font(.caption).foregroundStyle(.secondary)
                let tight = spec.minRAMGB > LocalModels.ramGB
                Text(String(format: "%.1f GB download · needs %d GB memory%@", spec.sizeGB, spec.minRAMGB,
                            tight ? " (more than this Mac has)" : ""))
                    .font(.caption).foregroundStyle(tight ? .orange : .secondary)
                if let error = local.errors[spec.id] { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Spacer()
            if let progress = local.progress[spec.id] {
                ProgressView(value: progress).frame(width: 90)
                Button("Cancel") { local.cancel(spec.id) }
            } else {
                Button("Download") { local.download(spec) }
            }
        }
    }

    private func imageRow(_ spec: ImageModelSpec) -> some View {
        let installed = ImageModels.isInstalled(spec)
        let inUse = installed && images.chosen?.id == spec.id
        let tight = spec.minRAMGB > LocalModels.ramGB
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(spec.name).font(.headline)
                    if inUse { Text("In use").font(.caption).padding(.horizontal, 6).background(.green.opacity(0.2), in: Capsule()) }
                }
                Text(spec.blurb).font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.1f GB · needs %d GB memory%@", spec.sizeGB, spec.minRAMGB, tight ? " (more than this Mac has)" : ""))
                    .font(.caption).foregroundStyle(tight ? .orange : .secondary)
                if let error = local.errors["image:" + spec.id] { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Spacer()
            if let progress = local.progress["image:" + spec.id] {
                ProgressView(value: progress).frame(width: 90)
                Button("Cancel") { local.cancel("image:" + spec.id) }
            } else if installed {
                if !inUse { Button("Use") { images.choose(spec) } }
                Button("Delete", role: .destructive) { images.delete(spec) }
            } else {
                Button("Download") { images.download(spec) }
            }
        }
    }

    /// What MLX models run on. Afterwards the model can build, so the setup check is run again.
    private func installMLX() {
        Task {
            await tools.install(.mlx)
            await store.recheckSetup()
        }
    }

    private func use(_ id: String) {
        Builder.engine = .pi
        Builder.piProvider = Builder.localProvider
        Builder.piModel = id
        local.objectWillChange.send()
        Task { await store.recheckSetup() }
    }

    private func add() {
        adding = true
        addError = nil
        Task {
            defer { adding = false }
            do {
                let spec = try await local.spec(forRepo: repo)
                if !custom.contains(spec) && !LocalModels.catalog.contains(where: { $0.repo == spec.repo }) { custom.append(spec) }
                repo = ""
                local.download(spec)
            } catch {
                addError = error.localizedDescription
            }
        }
    }
}

