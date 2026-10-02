import SwiftUI
import AppKit

/// What a fresh Mac is missing before Forge can build apps.
struct SetupCheck {
    var checked = false
    var hasBuildTools = true
    var builderProblem: String?
    var hasAgent = true
    /// Forge has already opened Apple's installer this launch.
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
    /// those shims pop up Apple's installer, which would happen every time Forge checks.
    static func buildToolsInstalled() -> Bool {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: "/Library/Developer/CommandLineTools/usr/bin/swift") { return true }
        let select = Process()
        select.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        select.arguments = ["-p"]
        let pipe = Pipe()
        select.standardOutput = pipe
        select.standardError = FileHandle.nullDevice
        guard (try? select.run()) != nil else { return false }
        select.waitUntilExit()
        let developer = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmed ?? ""
        guard select.terminationStatus == 0, !developer.isEmpty else { return false }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Welcome to Forge").font(.largeTitle.bold())
            Text("Two one-time steps and you're ready to build apps. Both can happen at the same time.")
                .foregroundStyle(.secondary)

            if !store.setup.hasAgent {
                Label("Forge's AI builder is missing from the app. Download Forge again.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            step(done: store.setup.hasBuildTools,
                 title: "Install Apple's app-building tools",
                 detail: store.setup.installRequested
                    ? "Apple's installer window is open. Click **Install**, then **Agree**. It usually takes 5–10 minutes, and Forge carries on by itself when it's done."
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
                 title: "Choose the AI that builds your apps",
                 detail: "The easiest option is an OpenRouter key, which also powers AI features and images inside your apps.") {
                EmptyView()
            }
            if !store.setup.hasBuilder {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SecureField("OpenRouter key (sk-or-…)", text: $key)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveKey)
                        Button("Save", action: saveKey).disabled(key.trimmed.isEmpty)
                        Link("Get a key", destination: URL(string: "https://openrouter.ai/keys")!)
                    }
                    Text("Or use something you already have:").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        ForEach(Engine.allCases.filter { $0 != .pi && ToolLocator.path(for: $0) != nil }) { engine in
                            Button(engine.title) { use(engine) }
                        }
                        Button("A model on this Mac…") { openSettings(tab: "local") }
                        Button("Other providers…") { openSettings(tab: "ai") }
                    }
                    .controlSize(.small)
                }
                .padding(.leading, 36)
            }
        }
        .padding(40)
        .frame(maxWidth: 600)
    }

    @Environment(\.openSettings) private var openSettingsAction
    @AppStorage("settingsTab") private var settingsTab = "ai"

    private func openSettings(tab: String) {
        settingsTab = tab
        openSettingsAction()
    }

    private func use(_ engine: Engine) {
        Builder.engine = engine
        Task { await store.recheckSetup() }
    }

    private func saveKey() {
        KeyStore.setOpenRouterKey(key)
        key = ""
        Builder.engine = .pi
        Builder.piProvider = "openrouter"
        Task { await store.recheckSetup() }
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
            }
            Spacer()
            if !done { accessory() }
        }
    }
}

struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = "ai"

    var body: some View {
        TabView(selection: $tab) {
            AISettings().tabItem { Label("AI", systemImage: "sparkles") }.tag("ai")
            LocalModelsSettings().tabItem { Label("Local Models", systemImage: "desktopcomputer") }.tag("local")
        }
        .frame(width: 560)
    }
}

/// Which agent and model build apps, plus in-app AI, images and the OpenRouter key.
struct AISettings: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var local = LocalModels.shared
    @AppStorage("engine") private var engine = Engine.pi.rawValue
    @AppStorage("piProvider") private var provider = "openrouter"
    @AppStorage("appModel") private var appModel = "haiku"
    @AppStorage("imageModel") private var imageModel = Icons.artModels[0].id
    @AppStorage("decisionModel") private var decisionModel = AppAI.decisionModel.id
    @State private var model = Builder.piModel
    @State private var revision = 0   // bumps after key changes so the view re-reads KeyStore

    private var selectedEngine: Engine { Engine(rawValue: engine) ?? .pi }

    var body: some View {
        Form {
            Section {
                Picker("Agent", selection: $engine) {
                    ForEach(Engine.allCases) { option in
                        let missing = option != .pi && ToolLocator.path(for: option) == nil
                        Text(option.title + (missing ? " (not installed)" : "")).tag(option.rawValue)
                    }
                }
                Text(selectedEngine.detail).font(.caption).foregroundStyle(.secondary)

                if selectedEngine == .pi {
                    Picker("Provider", selection: $provider) {
                        ForEach(Provider.apiProviders) { Text($0.name).tag($0.id) }
                        Divider()
                        Text("On this Mac (local models)").tag(Builder.localProvider)
                        ForEach(local.external.keys.sorted(), id: \.self) { Text(LocalModels.externalName($0)).tag($0) }
                        if FileManager.default.fileExists(atPath: Agent.userConfigDir) {
                            Text("My pi setup (logins and subscriptions)").tag(Builder.myPiProvider)
                        }
                    }
                    if let api = Provider.apiProvider(provider) {
                        KeyRow(provider: api) { revision += 1; recheck() }
                    }
                    ModelPicker(provider: provider, model: $model, revision: revision)
                } else {
                    let path = ToolLocator.path(for: selectedEngine)
                    LabeledContent("Installed", value: path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Not found")
                    Text("Forge lets it read and edit the app's files, but not run commands; Forge builds the app itself.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let problem = Builder.problem() {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                }
            } header: {
                Text("Building apps")
            }

            Section {
                Picker("Inside your apps", selection: $appModel) {
                    ForEach(AppAI.models, id: \.id) { Text($0.label).tag($0.id) }
                }
                Text("Used when you have an OpenRouter key. Without one, apps use the model that builds them.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Images (icons and in-app)", selection: $imageModel) {
                    ForEach(Icons.artModels, id: \.id) { Text($0.label).tag($0.id) }
                }
                if let openRouter = Provider.apiProvider("openrouter") {
                    KeyRow(provider: openRouter, label: "OpenRouter key") { revision += 1; recheck() }
                }
                Text("Image generation and the in-app models above need an OpenRouter key.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("AI and images inside your apps")
            }

            Section {
                Picker("Decision model", selection: $decisionModel) {
                    ForEach(AppAI.decisionModels, id: \.id) { Text($0.label).tag($0.id) }
                }
                if decisionModel.hasPrefix("typesafe:") {
                    KeyRow(provider: Self.typesafe, label: "TypeSafe key") { revision += 1 }
                } else if KeyStore.openRouterKey == nil {
                    Text("Add an OpenRouter key above, or switch to TypeSafe.").font(.caption).foregroundStyle(.orange)
                }
                Text("Fast, cheap typed judgments for apps: yes/no probabilities, picking from options, and rating on a scale, each with a calibrated confidence. Text in, decisions out.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Decisions inside your apps")
            }
        }
        .formStyle(.grouped)
        .onChange(of: engine) { recheck() }
        .onChange(of: provider) { model = Builder.piModel; recheck() }
        .onChange(of: model) { Builder.piModel = model; recheck() }
        .task { await local.detectExternal() }
    }

    private func recheck() { Task { await store.recheckSetup() } }

    static let typesafe = PiProvider(id: "typesafe", name: "TypeSafe", envVar: "TYPESAFE_API_KEY",
                                     keyURL: "https://typesafe.ai")
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
                Text("No models downloaded yet. Get one in the Local Models tab.").font(.caption).foregroundStyle(.secondary)
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
        case Builder.localProvider: models = local.installed
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

/// Download and manage models that run on this Mac.
struct LocalModelsSettings: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var local = LocalModels.shared
    @State private var repo = ""
    @State private var custom: [LocalModelSpec] = []
    @State private var adding = false
    @State private var addError: String?

    private var specs: [LocalModelSpec] {
        let known = LocalModels.catalog + custom
        let extra = local.installed.filter { id in !known.contains { $0.id == id } }.map {
            LocalModelSpec(id: $0, name: $0, repo: "", files: [], sizeGB: 0, minRAMGB: 0, blurb: "Downloaded")
        }
        return known + extra
    }

    var body: some View {
        Form {
            Section {
                Text("Models run privately on this Mac with llama.cpp. This Mac has \(LocalModels.ramGB) GB of memory. Local models are slower and less capable than the best cloud models, especially for whole apps.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(specs) { spec in row(spec) }
            } header: { Text("Models") }

            Section {
                HStack {
                    TextField("owner/Model-GGUF or a Hugging Face link", text: $repo)
                    Button("Add") { add() }.disabled(repo.trimmed.isEmpty || adding)
                }
                if adding { ProgressView().controlSize(.small) }
                if let addError { Text(addError).font(.caption).foregroundStyle(.red) }
                Text("Any GGUF model on Hugging Face works. Forge picks the Q4_K_M version, plus image support if there is one.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Add from Hugging Face") }

            Section {
                LabeledContent("Forge's model server") {
                    HStack {
                        Text(local.serverRunning ? "Running" : "Starts when needed").foregroundStyle(.secondary)
                        if local.serverRunning { Button("Stop") { local.stopServer() } }
                    }
                }
                if local.external.isEmpty {
                    Text("Ollama or LM Studio models show up here automatically when they're running.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(local.external.keys.sorted(), id: \.self) { id in
                    LabeledContent(LocalModels.externalName(id), value: "\(local.external[id]?.count ?? 0) models")
                }
                Button("Look Again") { Task { await local.detectExternal() } }
            } header: { Text("Servers") }
        }
        .formStyle(.grouped)
        .task { local.refresh(); await local.detectExternal() }
    }

    @ViewBuilder private func row(_ spec: LocalModelSpec) -> some View {
        let installed = local.installed.contains(spec.id)
        let inUse = Builder.engine == .pi && Builder.piProvider == Builder.localProvider && Builder.piModel == spec.id
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(spec.name).font(.headline)
                    if inUse { Text("In use").font(.caption).padding(.horizontal, 6).background(.green.opacity(0.2), in: Capsule()) }
                }
                Text(spec.blurb).font(.caption).foregroundStyle(.secondary)
                if spec.sizeGB > 0 {
                    let tight = spec.minRAMGB > LocalModels.ramGB
                    Text(String(format: "%.1f GB download · needs %d GB memory%@", spec.sizeGB, spec.minRAMGB,
                                tight ? " (more than this Mac has)" : ""))
                        .font(.caption).foregroundStyle(tight ? .orange : .secondary)
                }
                if let error = local.errors[spec.id] { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Spacer()
            if let progress = local.progress[spec.id] {
                ProgressView(value: progress).frame(width: 90)
                Button("Cancel") { local.cancel(spec.id) }
            } else if installed {
                if !inUse { Button("Use") { use(spec.id) } }
                Button("Delete", role: .destructive) { local.delete(spec.id) }
            } else if !spec.files.isEmpty {
                Button("Download") { local.download(spec) }
            }
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
                if !custom.contains(spec) && !LocalModels.catalog.contains(where: { $0.id == spec.id }) { custom.append(spec) }
                repo = ""
                local.download(spec)
            } catch {
                addError = error.localizedDescription
            }
        }
    }
}
