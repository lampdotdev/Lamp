import SwiftUI
import AppKit
import QuickLook

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var showingNew = false

    var body: some View {
        Group {
            if store.setup.checked && !store.setup.ready {
                SetupView()
            } else {
                main
            }
        }
        .sheet(item: $store.pendingImport) { pending in
            ImportReviewView(pending: pending)
        }
    }

    private var main: some View {
        NavigationSplitView {
            AppSidebar(showingNew: $showingNew)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            if let project = store.selected {
                ProjectView(project: project).id(project.id)
            } else if store.projects.isEmpty {
                ContentUnavailableView {
                    Label("No apps yet", systemImage: "hammer")
                } description: {
                    Text("Describe an app and Forge builds it for you.")
                } actions: {
                    Button("New App") { showingNew = true }
                }
            } else {
                ContentUnavailableView("Select an app", systemImage: "sidebar.left")
            }
        }
        .sheet(isPresented: $showingNew) { NewAppSheet() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.markRead()
        }
    }
}

/// The app list, as rows or as icon tiles. Double-click an app to build and open it.
struct AppSidebar: View {
    enum Layout: String { case list, tiles }

    @EnvironmentObject private var store: Store
    @Binding var showingNew: Bool
    @AppStorage("sidebarLayout") private var layout = Layout.list

    var body: some View {
        Group {
            switch layout {
            case .list: list
            case .tiles: tiles
            }
        }
        .scrollContentBackground(.hidden)
        .background(SidebarMaterial().ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            HStack {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                    .buttonStyle(.borderless)
                    .help("Settings (⌘,)")
                Spacer()
                Picker("Layout", selection: $layout) {
                    Image(systemName: "list.bullet").help("Show as List").tag(Layout.list)
                    Image(systemName: "square.grid.2x2").help("Show as Tiles").tag(Layout.tiles)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .labelStyle(.iconOnly)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var list: some View {
        List(selection: $store.selection) {
            ForEach(store.projects) { project in
                HStack(spacing: 8) {
                    Label {
                        Text(project.name)
                    } icon: {
                        AppIcon(project: project, size: 24)
                    }
                    Spacer()
                    if store.busy.contains(project.id) {
                        ProgressView().controlSize(.small)
                    } else if store.unread.contains(project.id) {
                        ReadyDot()
                    }
                }
                .tag(project.id)
            }
            Button { showingNew = true } label: {
                Label {
                    Text("New App")
                } icon: {
                    Image(systemName: "plus").frame(width: 24, height: 24)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, store.projects.isEmpty ? 0 : 12)
        }
        .listStyle(.sidebar)
        .environment(\.sidebarRowSize, .large)
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let project = store.projects.first(where: { $0.id == id }) {
                AppMenu(project: project)
            }
        } primaryAction: { ids in
            for project in store.projects where ids.contains(project.id) {
                Task { await store.run(project) }
            }
        }
    }

    private var tiles: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 110), spacing: 4)], spacing: 8) {
                ForEach(store.projects) { project in
                    AppTile(project: project, selected: store.selection == project.id)
                        .onTapGesture(count: 2) { Task { await store.run(project) } }
                        .simultaneousGesture(TapGesture().onEnded { store.selection = project.id })
                        .contextMenu { AppMenu(project: project) }
                }
                Button { showingNew = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.title)
                            .frame(width: 56, height: 56)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        Text("New App").font(.callout)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }
}

struct AppTile: View {
    @EnvironmentObject private var store: Store
    let project: ForgeProject
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            AppIcon(project: project, size: 56)
                .overlay(alignment: .topTrailing) {
                    if store.busy.contains(project.id) {
                        ProgressView().controlSize(.small)
                            .padding(3)
                            .background(.regularMaterial, in: Circle())
                            .offset(x: 6, y: -6)
                    } else if store.unread.contains(project.id) {
                        ReadyDot(size: 12)
                            .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                            .offset(x: 4, y: -4)
                    }
                }
            Text(project.name)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(selected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .help(project.name)
    }
}

struct AppIcon: View {
    @EnvironmentObject private var store: Store
    let project: ForgeProject
    let size: CGFloat

    var body: some View {
        if let icon = store.icons[project.id] {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .resizable().scaledToFit().fontWeight(.light)
                .foregroundStyle(.secondary)
                .padding(size * 0.08)
                .frame(width: size, height: size)
        }
    }
}

/// Shown next to an app when its chat has a finished reply you haven't seen.
struct ReadyDot: View {
    var size: CGFloat = 9
    var body: some View {
        Circle().fill(Color.accentColor).frame(width: size, height: size)
            .help("Ready")
            .accessibilityLabel("Ready")
    }
}

struct AppMenu: View {
    @EnvironmentObject private var store: Store
    let project: ForgeProject

    var body: some View {
        let busy = store.busy.contains(project.id)
        Button("Run") { Task { await store.run(project) } }
            .disabled(busy)
        Divider()
        Button("New Icon") { Task { await store.newIcon(project) } }
            .disabled(busy)
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([project.installedURL])
        }
        Divider()
        Button("Copy App File") { store.copyAppFile(project) }
        ShareLink("Share…", item: SharedApp(project: project),
                  preview: SharePreview(project.name, image: Image(systemName: "app.gift")))
        Button("Export…") { store.chooseExport(project) }
    }
}

/// The translucent, behind-window sidebar material System Settings uses.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct ProjectView: View {
    @EnvironmentObject private var store: Store
    let project: ForgeProject
    @State private var draft = ""
    @State private var attachments: [URL] = []
    @State private var composerHeight = Composer.lineHeight
    @State private var focusRequest = 0
    @State private var dropTargeted = false
    @StateObject private var dictation = Dictation()
    @AppStorage("showDetails") private var showDetails = false
    @AppStorage("showInfo") private var showInfo = false
    @State private var iconPreview: URL?
    @State private var suggestion: String?
    @State private var dismissedSuggestion: String?

    private var lines: [LogLine] {
        (store.logs[project.id] ?? []).filter { showDetails || $0.kind != .detail }
    }
    private var busy: Bool { store.busy.contains(project.id) }
    private var queued: [QueuedMessage] { store.queued[project.id] ?? [] }
    /// The finished agent turn a suggestion follows up on. Nil while working, so none shows mid-turn.
    private var suggestionTurn: UUID? { busy ? nil : NextStep.turn(in: store.logs[project.id] ?? []) }
    private var shownSuggestion: String? {
        guard suggestionTurn != nil, let suggestion, suggestion != dismissedSuggestion else { return nil }
        return suggestion
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if lines.isEmpty {
                            Text("Describe what \(project.name) should do, or what to change. Forge builds it and opens it for you. While using the app, press ⇧⌘E to come back here and ask for changes.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(lines) { LogRow(line: $0, dir: project.dir) }
                        ForEach(queued) { message in
                            QueuedRow(message: message) { store.unqueue(message, from: project) }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .onChange(of: lines.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: queued.count) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            Divider()
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachments, id: \.self) { url in
                            AttachmentChip(url: url) { attachments.removeAll { $0 == url } }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.top, 8)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: chooseFiles) { Image(systemName: "paperclip").font(.title3) }
                    .buttonStyle(.borderless)
                    .help("Attach files. You can also paste or drop images and files here.")
                    .frame(height: Composer.lineHeight)
                Composer(text: $draft, height: $composerHeight,
                         placeholder: busy ? "Working… describe the next change" : "Describe a change…",
                         suggestion: shownSuggestion, onDismissSuggestion: { dismissedSuggestion = suggestion },
                         isEnabled: true, focusRequest: focusRequest,
                         onSubmit: send, onFiles: { attachments.append(contentsOf: $0) })
                    .frame(height: composerHeight)
                Button(action: toggleDictation) {
                    Image(systemName: dictation.isListening ? "mic.fill" : "mic").font(.title3)
                        .symbolEffect(.pulse, isActive: dictation.isListening)
                }
                .buttonStyle(.plain)
                .foregroundStyle(dictation.isListening ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .help(dictation.isListening ? "Stop dictation" : "Dictate a change")
                .frame(height: Composer.lineHeight)
                if busy {
                    ProgressView().controlSize(.small).frame(height: Composer.lineHeight)
                    Button { store.stop(project) } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Stop")
                        .frame(height: Composer.lineHeight)
                }
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmed.isEmpty && attachments.isEmpty)
                .help(busy ? "Queue this change. It's sent when the current one is done." : "Send")
                .frame(height: Composer.lineHeight)
            }
            .padding(12)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 3).padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: Attachments.dropTypes, isTargeted: $dropTargeted) { providers in
            Attachments.load(providers) { attachments.append(contentsOf: $0) }
            return true
        }
        .background(Color(nsColor: .textBackgroundColor))
        .inspector(isPresented: $showInfo) {
            AppInfoView(project: project)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .navigationTitle(project.name)
        .navigationSubtitle(usageSummary)
        .toolbar { toolbar }
        .onAppear { focusRequest += 1 }
        .onDisappear { dictation.cancel() }
        .alert(dictation.problem?.title ?? "Dictation",
               isPresented: Binding(get: { dictation.problem != nil }, set: { if !$0 { dictation.problem = nil } }),
               presenting: dictation.problem) { problem in
            if let url = problem.settingsURL {
                Button(problem.settingsButton) { NSWorkspace.shared.open(url) }
                Button("Not Now", role: .cancel) {}
            } else {
                Button("OK") {}
            }
        } message: { problem in
            Text(problem.message)
        }
        .onChange(of: store.chatFocusRequest) { focusRequest += 1 }
        .task(id: suggestionTurn) {
            suggestion = nil
            guard suggestionTurn != nil else { return }
            suggestion = await NextStep.suggest(for: project, lines: store.logs[project.id] ?? [])
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .navigation) { titleIcon }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { titleIcon }
        }
        ToolbarItem {
            Button { Task { await store.run(project) } } label: {
                Label("Open App", systemImage: "play.fill")
            }
            .disabled(busy)
        }
        gap
        ToolbarItemGroup {
            Button { Task { await store.undo(project) } } label: {
                Label("Undo Last Change", systemImage: "arrow.uturn.backward")
            }
            .disabled(busy)
            Menu {
                Button("Copy App File") { store.copyAppFile(project) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                ShareLink("Share…", item: SharedApp(project: project),
                          preview: SharePreview(project.name, image: Image(systemName: "app.gift")))
                Button("Export…") { store.chooseExport(project) }
            } label: {
                Label("Share App", systemImage: "square.and.arrow.up")
            }
            .help("Send this app to someone with Forge")
        }
        gap
        ToolbarItemGroup {
            Toggle(isOn: $showDetails) {
                Label("Agent Details", systemImage: "wrench.and.screwdriver")
            }
            .help("Agent details")
            Toggle(isOn: $showInfo) {
                Label("App Info", systemImage: "info.circle")
            }
            .help("Show usage, cost and models for this app")
        }
    }

    /// Separates the toolbar's groups. macOS 26 has a native spacer; earlier versions get a little blank space.
    @ToolbarContentBuilder
    private var gap: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        } else {
            ToolbarItem { Color.clear.frame(width: 8, height: 1) }
        }
    }

    private var titleIcon: some View {
        Button { iconPreview = Icons.largePreview(project) } label: {
            AppIcon(project: project, size: 30)
        }
        .buttonStyle(.plain)
        .help("Show \(project.name)'s icon")
        .quickLookPreview($iconPreview)
    }

    private var usageSummary: String {
        guard let usage = store.usage[project.id], usage.calls > 0 else { return "" }
        return String(format: "AI: %d call%@ · $%.2f", usage.calls, usage.calls == 1 ? "" : "s", usage.cost)
    }

    /// Dictated words are appended to whatever was already typed.
    private func toggleDictation() {
        if dictation.isListening { return dictation.stop() }
        let typed = draft
        let separator = typed.isEmpty || typed.last!.isWhitespace ? "" : " "
        focusRequest += 1
        Task { await dictation.start { draft = typed + separator + $0 } }
    }

    private func send() {
        let text = draft.trimmed
        guard !text.isEmpty || !attachments.isEmpty else { return }
        dictation.cancel()
        let files = attachments
        draft = ""
        attachments = []
        store.send(text.isEmpty ? "Use the attached files." : text, attachments: files, to: project)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Attach screenshots, mockups, images, data or documents"
        if panel.runModal() == .OK { attachments.append(contentsOf: panel.urls) }
    }
}

/// The info panel: what an app has cost, which models it uses, and where it lives.
struct AppInfoView: View {
    @EnvironmentObject private var store: Store
    let project: ForgeProject
    @AppStorage("appModel") private var appModel = AppAI.model.id
    @AppStorage("imageModel") private var imageModel = Icons.artModel
    /// Bumped when Settings changes the builder, whose model lives under a per-provider key.
    @State private var settingsRevision = 0

    private var usage: AppUsage { store.usage[project.id] ?? AppUsage() }
    private var requests: Int { (store.logs[project.id] ?? []).filter { $0.kind == .user }.count }
    private var lastBuilt: Date? {
        try? project.installedURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    AppIcon(project: project, size: 64)
                    Text(project.name).font(.headline)
                    if let lastBuilt {
                        Text("Built \(lastBuilt, format: .relative(presentation: .named))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Section("Usage") {
                LabeledContent("Total cost", value: dollars(usage.totalCost))
                LabeledContent("Changes requested", value: "\(requests)")
                LabeledContent("Building the app") {
                    Text(runs(usage.agentRuns ?? 0, "agent run") + " · " + dollars(usage.agentCost ?? 0))
                }
                LabeledContent("AI inside the app") {
                    Text(runs(usage.calls, "call") + " · " + dollars(usage.cost))
                }
            }
            Section {
                let _ = settingsRevision
                LabeledContent("Agent", value: Builder.engine.title)
                if Builder.engine == .pi {
                    LabeledContent("Provider", value: providerName)
                    if !Builder.piModel.isEmpty { LabeledContent("Building with", value: buildModel) }
                }
                LabeledContent("Inside your apps", value: Provider.hasKey
                               ? AppAI.models.first { $0.id == appModel }?.label ?? appModel
                               : "Same as building")
                LabeledContent("Images", value: label(Icons.artModels, imageModel))
            } header: {
                Text("Models")
            } footer: {
                SettingsLink { Text("Change in Settings…") }
                    .buttonStyle(.link)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("App") {
                LabeledContent("Bundle ID") { Text(project.bundleID).textSelection(.enabled) }
                Button("Show App in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([project.installedURL])
                }
                Button("Show Source Code in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([project.dir])
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            settingsRevision += 1
        }
    }

    private var providerName: String {
        switch Builder.piProvider {
        case Builder.localProvider: "On this Mac"
        case Builder.myPiProvider: "Your pi setup"
        case let id: Provider.apiProvider(id)?.name ?? id
        }
    }

    private var buildModel: String {
        let id = Builder.piModel
        return Builder.piProvider == "openrouter" ? label(Provider.models, id) : id
    }

    private func dollars(_ amount: Double) -> String { String(format: "$%.2f", amount) }
    private func runs(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
    private func label(_ models: [(id: String, label: String)], _ id: String) -> String {
        models.first { $0.id == id }?.label ?? id
    }
}

/// A message waiting for the current change to finish. It can still be taken back.
struct QueuedRow: View {
    let message: QueuedMessage
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !message.attachments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(message.attachments, id: \.self) { AttachmentChip(url: $0) }
                }
            }
            HStack(spacing: 6) {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .help("Remove from the queue")
                Text(message.text)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.secondary)
            }
            Label("Queued", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct LogRow: View {
    let line: LogLine
    let dir: URL

    var body: some View {
        switch line.kind {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                if let names = line.attachments, !names.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(names, id: \.self) { name in
                            let url = dir.appendingPathComponent(Attachments.folder).appendingPathComponent(name)
                            Button { NSWorkspace.shared.open(url) } label: {
                                if Attachments.isImage(url) {
                                    AttachmentThumbnail(url: url, size: 72)
                                } else {
                                    AttachmentChip(url: url)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(name)
                        }
                    }
                }
                Text(line.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .agent:
            Text((try? AttributedString(markdown: line.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                 ?? AttributedString(line.text))
                .textSelection(.enabled)
        case .status:
            Label(line.text, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error:
            Label(line.text, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .detail:
            Text(line.text)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(12)
        }
    }
}

struct NewAppSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brief = ""

    var body: some View {
        Form {
            TextField("Name", text: $name, prompt: Text("Standup Notes"))
            TextField("What should it do?", text: $brief,
                      prompt: Text("Optional: a menu of today's meetings with a notes field for each"),
                      axis: .vertical)
                .lineLimit(3...8)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    store.create(name: name, brief: brief)
                    dismiss()
                }
                .disabled(name.trimmed.isEmpty)
            }
        }
    }
}

/// Shown before building an app someone else shared: what it does, what it can access, and any red flags.
struct ImportReviewView: View {
    @EnvironmentObject private var store: Store
    let pending: Store.PendingImport

    private var review: ImportReview? { pending.review }
    private var highRisk: Bool { review?.risk == "high" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open “\(pending.package.name)”?").font(.title2.bold())
            Text("Someone shared this app with you. Forge will build it and open it on your Mac, where it can do anything an app you run can do.")
                .foregroundStyle(.secondary)

            if let review {
                if !review.summary.isEmpty {
                    section("What it does") { Text(review.summary) }
                }
                if !review.detected.isEmpty || !review.capabilities.isEmpty {
                    section("What it can access") {
                        ForEach(review.detected + review.capabilities.filter { !review.detected.contains($0) }, id: \.self) {
                            Label($0, systemImage: "checkmark.shield").labelStyle(.titleAndIcon)
                        }
                    }
                }
                if !pending.package.attachments.isEmpty {
                    section("Included files") {
                        Text(pending.package.attachments.map(\.lastPathComponent).joined(separator: ", "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if !review.concerns.isEmpty {
                    section("Concerns") {
                        ForEach(review.concerns, id: \.self) {
                            Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                }
                riskBadge(review.risk)
                if let note = review.note {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
                Text("Forge's check is a guide, not a guarantee. Only open apps from people you trust.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Checking what this app does…").foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { store.cancelImport() }
                    .keyboardShortcut(highRisk || review == nil ? .defaultAction : .cancelAction)
                Button(highRisk ? "Open Anyway" : "Build & Open", role: highRisk ? .destructive : nil) {
                    store.confirmImport()
                }
                .disabled(review == nil)
                .keyboardShortcut(highRisk || review == nil ? .cancelAction : .defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    private func riskBadge(_ risk: String) -> some View {
        let (text, color, icon): (String, Color, String) = switch risk {
        case "low": ("Looks safe", .green, "checkmark.seal.fill")
        case "medium": ("Powerful, check it's what you expect", .yellow, "exclamationmark.circle.fill")
        case "high": ("Looks risky. Don't open unless you trust the sender", .red, "xmark.octagon.fill")
        default: ("Not checked by AI", .secondary, "questionmark.circle")
        }
        return Label(text, systemImage: icon)
            .font(.callout.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
