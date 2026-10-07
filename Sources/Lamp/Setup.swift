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

    /// nil if OpenRouter accepts the key; otherwise what's wrong, in plain words.
    static func checkOpenRouterKey(_ key: String) async -> String? {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/key")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return "Couldn't reach OpenRouter. Check your internet connection."
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200:
            let info = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["data"] as? [String: Any]
            if let remaining = info?["limit_remaining"] as? Double, remaining <= 0 {
                return "That key works, but it has no credit left. Add credit at openrouter.ai, then try again."
            }
            return nil
        case 401, 403: return "OpenRouter didn't accept that key. Copy it again from openrouter.ai/keys."
        default: return "OpenRouter couldn't check the key right now. Try again in a moment."
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

    var body: some View {
        TabView(selection: $tab) {
            BuildingSettings().tabItem { Label("Building", systemImage: "hammer") }.tag("building")
            AppsSettings().tabItem { Label("Apps", systemImage: "square.grid.2x2") }.tag("apps")
            ProvidersSettings().tabItem { Label("Providers", systemImage: "cpu") }.tag("providers")
        }
        .frame(width: 560)
        .onAppear {
            if tab == "local" { tab = "providers" }   // Local Models is now Native Mac AI, under Providers
            if !["building", "apps", "providers"].contains(tab) { tab = "building" }
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

    /// The model Claude Code or Codex builds with ("" for the tool's default).
    private func engineModel(_ engine: Engine) -> Binding<String> {
        Binding(get: { _ = revision; return Builder.engineModel(engine) },
                set: { Builder.setEngineModel($0, for: engine); revision += 1 })
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

    var body: some View {
        Form {
            Section {
                Picker("Agent", selection: $engine) {
                    ForEach(Engine.allCases) { option in
                        let missing = option != .pi && ToolLocator.path(for: option) == nil
                        Text(option.title + (missing ? " (not installed)" : "")).tag(option.rawValue)
                    }
                }

                if selectedEngine == .pi {
                    Picker("Provider", selection: providerChoice) {
                        let hasPiSetup = FileManager.default.fileExists(atPath: Agent.userConfigDir)
                        if !addedProviders.isEmpty || hasPiSetup {
                            Section("Cloud") {
                                ForEach(addedProviders) { Text($0.name).tag($0.id) }
                                if hasPiSetup {
                                    Text("My pi setup (logins and subscriptions)").tag(Builder.myPiProvider)
                                }
                            }
                        }
                        Section("Local") {
                            Text("Native Mac AI").tag(Builder.localProvider)
                            ForEach(local.external.keys.sorted { LocalModels.externalName($0) < LocalModels.externalName($1) },
                                    id: \.self) { Text(LocalModels.externalName($0)).tag($0) }
                        }
                        Divider()
                        Text("Configure providers…").tag(Self.configure)
                    }
                    // Keys are managed in Providers; only ask here if the chosen provider has lost its key.
                    if let api = Provider.apiProvider(provider), KeyStore.key(for: api.id) == nil {
                        KeyRow(provider: api) { revision += 1; recheck() }
                    }
                    ModelPicker(provider: provider, model: $model, revision: revision)
                } else {
                    let path = ToolLocator.path(for: selectedEngine)
                    if let path, let app = ToolLocator.desktopApp(for: path) {
                        LabeledContent("Installed", value: "With \(app)")
                            .help((path as NSString).abbreviatingWithTildeInPath)
                    } else {
                        LabeledContent("Installed", value: path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Not found")
                    }
                    if path != nil {
                        EngineSignInRow(engine: selectedEngine)
                    }
                    if selectedEngine == .claude {
                        Picker("Model", selection: engineModel(.claude)) {
                            ForEach(Builder.claudeModels, id: \.id) { Text($0.label).tag($0.id) }
                        }
                    } else if selectedEngine == .codex {
                        if Builder.codexModels.count > 1 {
                            Picker("Model", selection: engineModel(.codex)) {
                                ForEach(Builder.codexModels, id: \.id) { Text($0.label).tag($0.id) }
                            }
                        } else {
                            TextField("Model", text: engineModel(.codex), prompt: Text("Codex's default"))
                        }
                    }
                    Text(selectedEngine == .codex
                         ? "Codex runs commands inside its own sandbox, limited to the app's folder."
                         : "Uses your Claude Code sign-in, without your personal hooks, plugins or connectors.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let problem = Builder.problem() {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                }
            }
            Section {
                Picker("Ask before running commands", selection: approvalChoice) {
                    ForEach(CommandApproval.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Text((CommandApproval(rawValue: approval) ?? .risky).detail)
                    .font(.caption).foregroundStyle(.secondary)
                if (CommandApproval(rawValue: approval) ?? .risky).isAutomatic && CommandApproval.claudeAutoUnavailable && selectedEngine == .claude {
                    Text("Claude Code's auto mode isn't available for your account, so Lamp asks before every command.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Privacy") {
                Toggle("Ask before the agent opens files outside an app's folder", isOn: $askOutsideFolder)
                Text("The agent works in the app's own folder. Anything else on your Mac it wants to read or change, it asks for first; system and developer files don't count. Lamp's keys and your other apps are always off limits."
                     + (selectedEngine == .claude ? " This applies to Lamp's built-in agent and Codex; Claude Code follows its own rules." : ""))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show the agent what an app prints while it runs", isOn: $shareLog)
                Toggle("Show the agent pictures of an app's windows", isOn: $sharePictures)
                Text("Both help the agent find and fix problems, and both go to the AI model you chose. Turn them off for apps that show or print things you'd rather keep to yourself.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Notify me when an app is ready or needs me", isOn: $notify)
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
        }
        .onChange(of: engine) { recheck() }
        .onChange(of: provider) { model = Builder.piModel; recheck() }
        .onChange(of: model) { Builder.piModel = model; recheck() }
        .onAppear { revision += 1 }   // keys may have changed in the Providers tab
        .task { await local.detectExternal() }
    }

    private func recheck() { Task { await store.recheckSetup() } }
}

/// The AI, images and decisions that apps use while they run.
struct AppsSettings: View {
    @AppStorage("appModel") private var appModel = AppAI.defaultModel.id
    @AppStorage("imageModel") private var imageModel = Icons.artModels[0].id
    @AppStorage("decisionModel") private var decisionModel = AppAI.decisionModel.id
    @State private var revision = 0   // bumps after key changes so the view re-reads KeyStore

    var body: some View {
        Form {
            Section {
                Picker("Inside your apps", selection: $appModel) {
                    ForEach(AppAI.models, id: \.id) { Text($0.label).tag($0.id) }
                }
                Picker("Images (icons and in-app)", selection: $imageModel) {
                    ForEach(Icons.imageChoices, id: \.id) { Text($0.label).tag($0.id) }
                }
                let _ = revision   // re-read KeyStore after the TypeSafe key changes
                Text(KeyStore.openRouterKey == nil
                     ? "Without an OpenRouter key, your apps' text AI goes through \(Builder.engine == .pi ? "the builder's provider" : Builder.engine.title) with your sign-in, and pictures come from \(AppAI.imageRouteName ?? "nowhere: an app that wants one will ask for a key"). Add a key in Providers for the models above."
                     : "Image generation and the in-app models above use your OpenRouter key.")
                    .font(.caption).foregroundStyle(.secondary)

                Picker("Decision model", selection: $decisionModel) {
                    ForEach(AppAI.decisionModels, id: \.id) { Text($0.label).tag($0.id) }
                }
                if decisionModel.hasPrefix("typesafe:") {
                    if KeyStore.key(for: Provider.typesafe.id) == nil {
                        KeyRow(provider: Provider.typesafe, label: "TypeSafe key") { revision += 1 }
                    }
                } else if KeyStore.openRouterKey == nil {
                    Text(AppAI.canAnswer
                         ? "No key for this yet, so decisions are made by \(AppAI.fastModelName) instead: slower and less exact than Jev. Add an OpenRouter key in Providers, or switch to TypeSafe."
                         : "Add an OpenRouter key in Providers, or switch to TypeSafe.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("Fast, cheap typed judgments for apps: yes/no probabilities, picking from options, and rating on a scale, each with a calibrated confidence. Text in, decisions out.")
                    .font(.caption).foregroundStyle(.secondary)
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
    @AppStorage("experimentDevices") private var devices = false
    @AppStorage("appleTeam") private var team = ""
    @State private var teams: [(id: String, name: String)] = []

    var body: some View {
        Section {
            Toggle("iPhone and iPad apps", isOn: $iosApps)
                .onChange(of: iosApps) { store.setLocalNetwork(Experiments.devices) }
            Text("Adds New iPhone & iPad App. Lamp builds the app and tries it in the iPhone or iPad simulator on this Mac (Try On, beside the Play button): that needs Xcode (free on the Mac App Store) and, the first time it tries an app, permission to control this computer.")
                .font(.caption).foregroundStyle(.secondary)
            if iosApps {
                Toggle("Put apps on your own iPhone or iPad", isOn: $devices)
                    .onChange(of: devices) { store.setLocalNetwork(Experiments.devices) }
                if devices {
                    if teams.isEmpty {
                        TextField("Apple Team ID", text: $team, prompt: Text("Ten letters and digits, from Xcode → Settings → Accounts"))
                    } else {
                        Picker("Apple Team", selection: $team) {
                            ForEach(teams, id: \.id) { Text("\($0.name) (\($0.id))").tag($0.id) }
                            if !team.isEmpty, !teams.contains(where: { $0.id == team }) { Text(team).tag(team) }
                        }
                    }
                }
                Text("Sign in to your Apple account in Xcode → Settings → Accounts (a free account will do: its apps last a week on the phone, a paid one's a year). Then plug the phone in with a cable: Try On, beside the Play button, offers to pair it (tap Trust on the phone), and tells you when to turn on Developer Mode there. Choose the phone under Try On and press Play. The app's AI goes through Lamp over your Wi‑Fi, so the phone and this Mac must be on the same network and Lamp must be open. The agent still tries the app on the simulator: it can't see the phone's screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
        Section {
            Toggle("Let apps use your other apps", isOn: Binding(get: { enabled }, set: { on in
                if on { Task { await turnOn() } } else { enabled = false; problem = nil }
            }))
            .disabled(working != nil)
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
            Text("Lets your apps read and use your other apps, such as Slack, Mail, or Gmail and LinkedIn in your browser, with the accounts you're already signed in to. Apps ask before every click or keystroke.")
                .font(.caption).foregroundStyle(.secondary)
            if CodexComputerUse.server != nil {
                // The ChatGPT app's Computer Use is on this Mac: it does the looking and clicking, unless the
                // person would rather keep CuaDriver.
                Toggle("Use the ChatGPT app's Computer Use", isOn: Binding(get: { !codexOff }, set: { useCodex in
                    codexOff = !useCodex
                    // Back to CuaDriver while the feature is on: it has to be installed and allowed, like a first turn-on.
                    Task { if enabled, !useCodex { await turnOn() } else { status = await ComputerUse.status() } }
                }))
                .disabled(working != nil)
                Text(codexOff
                     ? "CuaDriver (from Cua, open source) does the looking and clicking: turning the switch above on adds it to Applications, and macOS asks you to allow it Accessibility and Screen Recording."
                     : "The ChatGPT app has Computer Use installed, so it does the looking and clicking, with the permissions you gave it there. It sends real clicks to the app in the background and reads its contents without moving your pointer. Switch it off to use CuaDriver instead.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Turning it on adds CuaDriver (from Cua, open source) to Applications, and macOS asks you to allow it Accessibility and Screen Recording. With the ChatGPT app and its Computer Use plugin installed, Lamp uses that instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { status = await ComputerUse.status() }
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

/// Native Mac AI, Ollama and LM Studio, then the providers you've added a key for.
/// Double-click one to see its models or change its key.
struct ProvidersSettings: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var local = LocalModels.shared
    @AppStorage("settingsSheet") private var pendingSheet = ""   // set by the setup screen
    @State private var selection: String?
    @State private var showing: ProviderDetail?
    @State private var removing: PiProvider?
    @State private var revision = 0   // bumps after key changes so the view re-reads KeyStore

    private var added: [PiProvider] {
        _ = revision
        return Provider.keyProviders.filter { KeyStore.key(for: $0.id) != nil }
    }

    private var addable: [PiProvider] {
        _ = revision
        return Provider.keyProviders.filter { KeyStore.key(for: $0.id) == nil }
    }

    /// Local first (always there, as are Ollama and LM Studio), then the cloud providers with keys.
    private var rows: [String] {
        [Builder.localProvider] + LocalModels.externalIDs + added.map(\.id)
    }

    var body: some View {
        Form {
            Section {
                List(rows, id: \.self, selection: $selection) { id in
                    HStack(spacing: 10) {
                        ProviderLogo(id: id, size: 24)
                        Text(ProviderDetail.name(id))
                        Spacer()
                        Text(detail(id)).font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .tag(id)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first {
                        Button(Provider.keyProvider(id) == nil ? "Show Models…" : "Edit…") { showing = ProviderDetail(id) }
                        if let provider = Provider.keyProvider(id) {
                            Button("Remove…", role: .destructive) { removing = provider }
                        }
                    }
                } primaryAction: { ids in
                    showing = ids.first.map(ProviderDetail.init)
                }
                .onDeleteCommand { removing = selection.flatMap(Provider.keyProvider) }
                .scrollDisabled(true)
                .frame(height: CGFloat(rows.count) * 40)

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
                    .help("Native Mac AI, Ollama and LM Studio can't be removed")
                    Spacer()
                }
            } footer: {
                Text("Ollama and LM Studio models show up while those apps are running. Pick which provider builds apps in Building.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .settingsPane()
        .sheet(item: $showing) { detail in
            switch detail {
            case .key(let provider): ProviderSheet(provider: provider) { changed() }
            case .local: LocalAISheet()
            case .server(let id): ServerSheet(id: id)
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
        .onAppear(perform: openPending)
        .onChange(of: pendingSheet) { openPending() }
        .task { local.refresh(); await local.detectExternal() }
    }

    private func detail(_ id: String) -> String {
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

    init(_ id: String) {
        if id == Builder.localProvider { self = .local }
        else if let provider = Provider.keyProvider(id) { self = .key(provider) }
        else { self = .server(id) }
    }

    var id: String {
        switch self {
        case .key(let provider): provider.id
        case .local: Builder.localProvider
        case .server(let id): id
        }
    }

    static func name(_ id: String) -> String {
        if id == Builder.localProvider { return "Native Mac AI" }
        if id.hasPrefix("ext-") { return LocalModels.externalName(id) }
        return Provider.keyProvider(id)?.name ?? id
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
                Link("Get a key from \(provider.name)", destination: URL(string: provider.keyURL)!)
                    .font(.callout)
            }
            HStack {
                if hasKey {
                    Button("Remove Key", role: .destructive) {
                        KeyStore.setKey(nil, for: provider.id)
                        onChange()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(hasKey ? "Save" : "Add", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func save() {
        guard !key.trimmed.isEmpty else { return }
        KeyStore.setKey(key, for: provider.id)
        onChange()
        dismiss()
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
struct KeyRow: View {
    let provider: PiProvider
    var label: String?
    var onChange: () -> Void
    @State private var key = ""
    @State private var saved = false

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
                        Button("Save", action: save).disabled(key.trimmed.isEmpty)
                        Link("Get one", destination: URL(string: provider.keyURL)!)
                    }
                }
            }
        }
        .onAppear { saved = KeyStore.key(for: provider.id) != nil }
        .onChange(of: provider) { saved = KeyStore.key(for: provider.id) != nil; key = "" }
    }

    private func save() {
        KeyStore.setKey(key, for: provider.id)
        key = ""
        saved = true
        onChange()
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
        case Builder.localProvider: models = local.installed.map(\.id)
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

/// Whether Claude Code or Codex is signed in, with a button that signs in through the browser.
struct EngineSignInRow: View {
    let engine: Engine
    @State private var signedIn: Bool?
    @State private var signingIn = false

    var body: some View {
        LabeledContent("Signed in") {
            if signingIn {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Finish in your browser…").foregroundStyle(.secondary) }
            } else {
                switch signedIn {
                case true?: Label("Yes", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case false?: Button("Sign In…") { Task { await signIn() } }
                case nil: ProgressView().controlSize(.small)
                }
            }
        }
        .task(id: engine) {
            signedIn = nil
            signedIn = await EngineSignIn.isSignedIn(engine) ?? true
        }
    }

    private func signIn() async {
        signingIn = true
        _ = await EngineSignIn.signIn(engine)
        signedIn = await EngineSignIn.isSignedIn(engine) ?? true
        signingIn = false
    }
}
