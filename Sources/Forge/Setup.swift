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
                        Button("Other providers…") { openSettings(tab: "building") }
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
    @AppStorage("settingsTab") private var settingsTab = "building"

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
    @AppStorage("settingsTab") private var tab = "building"

    var body: some View {
        TabView(selection: $tab) {
            BuildingSettings().tabItem { Label("Building", systemImage: "hammer") }.tag("building")
            AppsSettings().tabItem { Label("Apps", systemImage: "square.grid.2x2") }.tag("apps")
            ProvidersSettings().tabItem { Label("Providers", systemImage: "cpu") }.tag("providers")
            LocalModelsSettings().tabItem { Label("Local Models", systemImage: "desktopcomputer") }.tag("local")
        }
        .frame(width: 560)
        .onAppear { if !["building", "apps", "providers", "local"].contains(tab) { tab = "building" } }
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
    @State private var model = Builder.piModel
    @State private var revision = 0   // bumps after key changes so the view re-reads KeyStore

    private var selectedEngine: Engine { Engine(rawValue: engine) ?? .pi }

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
                Text(selectedEngine.detail).font(.caption).foregroundStyle(.secondary)

                if selectedEngine == .pi {
                    Picker("Provider", selection: providerChoice) {
                        ForEach(addedProviders) { Text($0.name).tag($0.id) }
                        if !addedProviders.isEmpty { Divider() }
                        Text("On this Mac (local models)").tag(Builder.localProvider)
                        ForEach(local.external.keys.sorted(), id: \.self) { Text(LocalModels.externalName($0)).tag($0) }
                        if FileManager.default.fileExists(atPath: Agent.userConfigDir) {
                            Text("My pi setup (logins and subscriptions)").tag(Builder.myPiProvider)
                        }
                        Divider()
                        Text("Configure providers…").tag(Self.configure)
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
            }
        }
        .settingsPane()
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
    @EnvironmentObject private var store: Store
    @AppStorage("appModel") private var appModel = "haiku"
    @AppStorage("imageModel") private var imageModel = Icons.artModels[0].id
    @AppStorage("decisionModel") private var decisionModel = AppAI.decisionModel.id
    @State private var revision = 0   // bumps after key changes so the view re-reads KeyStore

    var body: some View {
        Form {
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

                Picker("Decision model", selection: $decisionModel) {
                    ForEach(AppAI.decisionModels, id: \.id) { Text($0.label).tag($0.id) }
                }
                if decisionModel.hasPrefix("typesafe:") {
                    KeyRow(provider: Provider.typesafe, label: "TypeSafe key") { revision += 1 }
                } else if KeyStore.openRouterKey == nil {
                    Text("Add an OpenRouter key above, or switch to TypeSafe.").font(.caption).foregroundStyle(.orange)
                }
                Text("Fast, cheap typed judgments for apps: yes/no probabilities, picking from options, and rating on a scale, each with a calibrated confidence. Text in, decisions out.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .settingsPane()
    }

    private func recheck() { Task { await store.recheckSetup() } }
}

/// The providers you've added a key for. Double-click one to change or remove its key.
struct ProvidersSettings: View {
    @EnvironmentObject private var store: Store
    @State private var selection: String?
    @State private var editing: PiProvider?
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

    var body: some View {
        Form {
            Section {
                if added.isEmpty {
                    Text("No providers yet. Click + to add one with its API key.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    List(added, selection: $selection) { provider in
                        HStack(spacing: 10) {
                            ProviderLogo(id: provider.id, size: 24)
                            Text(provider.name)
                            Spacer()
                            Text(KeyStore.usesKeychain ? "Key in Keychain" : "Key saved")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .tag(provider.id)
                    }
                    .contextMenu(forSelectionType: String.self) { ids in
                        if let provider = ids.first.flatMap(Provider.keyProvider) {
                            Button("Edit…") { editing = provider }
                            Button("Remove…", role: .destructive) { removing = provider }
                        }
                    } primaryAction: { ids in
                        editing = ids.first.flatMap(Provider.keyProvider)
                    }
                    .onDeleteCommand { removing = selection.flatMap(Provider.keyProvider) }
                    .scrollDisabled(true)
                    .frame(height: CGFloat(added.count) * 40)
                }
                HStack(spacing: 0) {
                    Menu {
                        ForEach(addable) { provider in
                            Button(provider.name) { editing = provider }
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
                    .disabled(selection == nil)
                    Spacer()
                }
            } footer: {
                Text("Keys are used to build apps and for the AI inside them. Pick which provider builds apps in Building.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .settingsPane()
        .sheet(item: $editing) { provider in
            ProviderSheet(provider: provider) { changed() }
        }
        .confirmationDialog("Remove \(removing?.name ?? "provider")?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) {
                if let removing { KeyStore.setKey(nil, for: removing.id) }
                selection = nil
                changed()
            }
        } message: {
            Text("Forge forgets its API key. Apps and builds that use it stop working until you add it again.")
        }
    }

    private func changed() {
        revision += 1
        Task { await store.recheckSetup() }
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
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .padding(Self.fullBleed.contains(id) ? 0 : size * 0.18)
            } else {
                Text(Provider.keyProvider(id)?.name.prefix(1) ?? "?")
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

/// Models on this Mac (shared with Local and the Hugging Face cache), plus downloads.
struct LocalModelsSettings: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var local = LocalModels.shared
    @State private var repo = ""
    @State private var custom: [LocalModelSpec] = []
    @State private var adding = false
    @State private var addError: String?

    private var downloadable: [LocalModelSpec] {
        (LocalModels.catalog + custom).filter { !local.isInstalled($0) }
    }

    var body: some View {
        Form {
            Section {
                Text("Models run privately on this Mac. This Mac has \(LocalModels.ramGB) GB of memory. Local models are slower and less capable than the best cloud models, especially for whole apps.")
                    .font(.callout).foregroundStyle(.secondary)
                if local.installed.isEmpty {
                    Text("No models yet. Download one below.").foregroundStyle(.secondary)
                }
                ForEach(local.installed) { installedRow($0) }
            } header: { Text("On this Mac") } footer: {
                Text("Includes models in the Hugging Face cache (~/.cache/huggingface/hub) and Local's folder, so they're shared with Local and other tools. GGUF models run on Forge's llama.cpp; MLX models run on mlx-lm\(LocalModels.mlxServerPath == nil ? " (not installed: `uv tool install mlx-lm`)" : "").")
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
                Text("Downloads go into the Hugging Face cache. Any GGUF repo works: Forge picks the Q4_K_M version, plus image support if there is one.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Model servers") {
                    HStack {
                        Text(local.serverRunning || local.mlxModel != nil ? "Running" : "Start when needed").foregroundStyle(.secondary)
                        if local.serverRunning || local.mlxModel != nil { Button("Stop") { local.stopServer() } }
                    }
                }
                if local.external.isEmpty {
                    Text("Ollama or LM Studio models show up here automatically when they're running.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(local.external.keys.sorted(), id: \.self) { id in
                    LabeledContent(LocalModels.externalName(id), value: "\(local.external[id]?.count ?? 0) models")
                }
                Button("Look Again") { local.refresh(); Task { await local.detectExternal() } }
            } header: { Text("Servers") }
        }
        .settingsPane()
        .task { local.refresh(); await local.detectExternal() }
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
                if needsMLX { Text("Needs mlx-lm: `uv tool install mlx-lm`").font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            if !inUse { Button("Use") { use(model.id) }.disabled(needsMLX) }
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
