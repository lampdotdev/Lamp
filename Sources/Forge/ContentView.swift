import SwiftUI
import AppKit
import QuickLook

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var newName = ""
    @State private var versionName = ""

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
            AppSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            if let project = store.selected {
                ProjectView(project: project).id(project.id)
            } else if store.projects.isEmpty {
                FirstAppView()
            } else {
                ContentUnavailableView("Select an app", systemImage: "sidebar.left")
            }
        }
        .alert("Rename “\(store.renaming?.name ?? "")”", isPresented: Binding(
            get: { store.renaming != nil }, set: { if !$0 { store.renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let project = store.renaming { Task { await store.rename(project, to: newName) } }
            }
            .disabled(newName.trimmed.isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .alert(store.naming?.version.name == nil ? "Name This Version" : "Rename This Version", isPresented: Binding(
            get: { store.naming != nil }, set: { if !$0 { store.naming = nil } })) {
            TextField("Name", text: $versionName)
            Button("Save") {
                if let naming = store.naming {
                    Task { await store.name(naming.version, of: naming.project, as: versionName) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A name makes this version easy to find, and to go back to later.")
        }
        .onChange(of: store.naming) { versionName = store.naming?.version.name ?? "" }
        .confirmationDialog("Delete “\(store.deleting?.name ?? "")”?", isPresented: Binding(
            get: { store.deleting != nil }, set: { if !$0 { store.deleting = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let project = store.deleting { Task { await store.delete(project) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app, its chat and its history are moved to the Trash.")
        }
        .dialogIcon(store.deleting.map { Image(nsImage: dialogIcon(for: $0)) })
        .onChange(of: store.renaming) { newName = store.renaming.map { $0.untitled ? "" : $0.name } ?? "" }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.markRead()
        }
    }

    /// The app's own icon, or its blueprint stand-in if it doesn't have one yet.
    private func dialogIcon(for project: ForgeProject) -> NSImage {
        if let icon = store.icons[project.id] { return icon }
        let renderer = ImageRenderer(content: BlueprintIcon(letter: project.untitled ? nil : project.name.first, size: 128))
        renderer.scale = 2
        return renderer.nsImage ?? NSApp.applicationIconImage
    }
}

/// The app list, as rows or as icon tiles. Double-click an app to build and open it.
struct AppSidebar: View {
    enum Layout: String { case list, tiles }

    @EnvironmentObject private var store: Store
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
            Button { store.create() } label: {
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
                Task { await store.open(project) }
            }
        }
    }

    private var tiles: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 110), spacing: 4)], spacing: 8) {
                ForEach(store.projects) { project in
                    AppTile(project: project, selected: store.selection == project.id)
                        .onTapGesture(count: 2) { Task { await store.open(project) } }
                        .simultaneousGesture(TapGesture().onEnded { store.selection = project.id })
                        .contextMenu { AppMenu(project: project) }
                }
                Button { store.create() } label: {
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
            BlueprintIcon(letter: project.untitled ? nil : project.name.first, size: size)
        }
    }
}

/// The stand-in icon until the real one is designed: a blueprint of an app icon, with Apple's icon grid
/// drawn on it and the app's initial in the middle.
struct BlueprintIcon: View {
    let letter: Character?
    let size: CGFloat

    var body: some View {
        // Same footprint as a real macOS icon: an 824pt tile on a 1024pt canvas.
        let side = size * 824 / 1024
        let shape = RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(red: 0.20, green: 0.46, blue: 0.86),
                                               Color(red: 0.10, green: 0.30, blue: 0.66)],
                                      startPoint: .top, endPoint: .bottom))
            Canvas { context, canvas in
                let w = canvas.width
                let thin = max(0.5, w / 400)
                var grid = Path()
                for i in 1..<8 {
                    let p = w * CGFloat(i) / 8
                    grid.move(to: CGPoint(x: p, y: 0)); grid.addLine(to: CGPoint(x: p, y: w))
                    grid.move(to: CGPoint(x: 0, y: p)); grid.addLine(to: CGPoint(x: w, y: p))
                }
                if w > 40 { context.stroke(grid, with: .color(.white.opacity(0.12)), lineWidth: thin) }
                var guides = Path()
                guides.move(to: .zero); guides.addLine(to: CGPoint(x: w, y: w))
                guides.move(to: CGPoint(x: w, y: 0)); guides.addLine(to: CGPoint(x: 0, y: w))
                for r in [0.19, 0.31] { guides.addEllipse(in: CGRect(x: w * (0.5 - r), y: w * (0.5 - r), width: w * r * 2, height: w * r * 2)) }
                guides.addRect(CGRect(x: w * 0.16, y: w * 0.16, width: w * 0.68, height: w * 0.68))
                context.stroke(guides, with: .color(.white.opacity(0.28)), lineWidth: thin * 1.5)
            }
            .clipShape(shape)
            shape.strokeBorder(.white.opacity(0.35), lineWidth: max(0.5, side / 160))
            if let letter {
                Text(String(letter).uppercased())
                    .font(.system(size: side * 0.48, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: side / 60, y: side / 120)
            }
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.18), radius: size / 60, y: size / 80)
        .frame(width: size, height: size)
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
        Button("Open") { Task { await store.open(project) } }
        Button("Rebuild & Open") { Task { await store.run(project) } }
            .disabled(busy)
        Button("Quit") { Task { await store.quitApp(project) } }
            .disabled(!store.openApps.contains(project.id))
        Divider()
        Button("Rename…") { store.renaming = project }
            .disabled(busy)
        Button("New Icon") { Task { await store.newIcon(project) } }
            .disabled(busy || project.untitled)
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([project.installedURL])
        }
        Divider()
        Button("Copy App File") { store.copyAppFile(project) }
        ShareLink("Share…", item: SharedApp(project: project),
                  preview: SharePreview(project.name, image: Image(systemName: "app.gift")))
        Button("Export…") { store.chooseExport(project) }
        Divider()
        Button("Delete…", role: .destructive) { store.deleting = project }
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
    @AppStorage("showVersions") private var showVersions = false
    @State private var suggestion: String?
    @State private var dismissedSuggestion: String?

    private var lines: [LogLine] {
        (store.logs[project.id] ?? []).filter { showDetails || !$0.isDetail }
    }
    private var busy: Bool { store.busy.contains(project.id) }
    /// The chat area has to be about twice the build card's height before the card is pinned.
    private static let roomToPinCard: CGFloat = 560

    /// The first turn of a new app, while it's still running.
    private var building: TurnProgress? {
        store.progress[project.id].flatMap { $0.newApp && $0.finished == nil ? $0 : nil }
    }
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
                GeometryReader { area in
                    ScrollView {
                        // While a new app is being built, its card stays in view above the steps, if there's
                        // room: in a short window a pinned card would fill the chat and hide everything else.
                        LazyVStack(alignment: .leading, spacing: 0,
                                   pinnedViews: building != nil && area.size.height >= Self.roomToPinCard ? [.sectionHeaders] : []) {
                            if lines.isEmpty && queued.isEmpty {
                                NewAppIntro(project: project)
                            }
                            if let card = store.progress[project.id], card.newApp,
                               let request = lines.lastIndex(where: { $0.kind == .user }) {
                                // The build card goes straight after the request; what the agent says and
                                // does follows it.
                                transcript(Array(lines[...request]), busy: false)
                                Section {
                                    transcript(Array(lines[(request + 1)...]), busy: busy)
                                } header: {
                                    BuildCard(project: project, progress: card)
                                        .padding(.top, 16).padding(.bottom, 12)
                                        .background(Color(nsColor: .textBackgroundColor))
                                }
                            } else {
                                transcript(lines, busy: busy)
                                if let progress = store.progress[project.id], busy,
                                   !(lines.last.map { $0.kind == .status && $0.text.hasSuffix("…") } ?? false) {
                                    // Not next to a status like "Building…", which says the same thing.
                                    ActivityRow(progress: progress).padding(.top, 12)
                                }
                            }
                            ForEach(queued) { message in
                                QueuedRow(message: message) { store.unqueue(message, from: project) }
                                    .padding(.top, lines.isEmpty ? 0 : 32)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        // A readable line length; wide windows get margins instead of longer lines.
                        .frame(maxWidth: 640)
                        .padding(.horizontal, 20).padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        // At least as tall as the chat area, so a short chat still sits at the top.
                        .frame(minHeight: area.size.height, alignment: .top)
                    }
                    // A chat opens on its latest messages: the scroll view starts at the bottom, with
                    // no scrolling to get there.
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: lines.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                    .onChange(of: queued.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                    .onChange(of: store.progress[project.id]?.plan.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                    .onChange(of: store.progress[project.id]?.screenshot != nil) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            Divider()
            if let approval = store.approvals[project.id] {
                ApprovalCard(command: approval.command, explanation: approval.explanation,
                             onAllow: { store.answerApproval(for: project, allow: true) },
                             onAllowAll: { store.answerApproval(for: project, allow: true, allowAll: true) },
                             onDeny: { store.answerApproval(for: project, allow: false) })
                    .padding(.horizontal, 12).padding(.top, 10)
            }
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
        .inspector(isPresented: Binding(get: { showInfo || showVersions },
                                        set: { if !$0 { showInfo = false; showVersions = false } })) {
            Group {
                if showVersions { VersionsView(project: project) } else { AppInfoView(project: project) }
            }
            .inspectorColumnWidth(min: 240, ideal: 300, max: 420)
        }
        .navigationTitle(project.name)
        .navigationSubtitle(usageSummary)
        .toolbarTitleMenu {
            Button("Rename…") { store.renaming = project }
                .disabled(busy)
        }
        .toolbar { toolbar }
        .task { await store.linkOldRequests(project) }
        .onAppear {
            focusRequest += 1
            let saved = store.draft(for: project)
            draft = saved.text
            attachments = saved.attachments
        }
        .onChange(of: draft) { store.saveDraft(Store.Draft(text: draft, attachments: attachments), for: project) }
        .onChange(of: attachments) { store.saveDraft(Store.Draft(text: draft, attachments: attachments), for: project) }
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

    private func transcript(_ lines: [LogLine], busy: Bool) -> some View {
        Transcript(lines: lines, dir: project.dir, busy: busy) { line, before in
            Task { await store.restore(project, toVersionOf: line, before: before) }
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
            Button { Task { await store.open(project) } } label: {
                Label("Open App", systemImage: "play.fill")
            }
            .help("Open the app (right-click it in the sidebar to rebuild)")
        }
        ToolbarItem {
            Button { Task { await store.quitApp(project) } } label: {
                Label("Quit App", systemImage: "stop.fill")
            }
            .disabled(!store.openApps.contains(project.id))
            .help(store.openApps.contains(project.id) ? "Quit the app" : "The app isn't open")
        }
        gap
        ToolbarItemGroup {
            Button { Task { await store.undo(project) } } label: {
                Label("Undo Last Change", systemImage: "arrow.uturn.backward")
            }
            .disabled(busy)
            .help("Go back to the version before this one")
            Button { store.deleting = project } label: {
                Label("Delete App", systemImage: "trash")
            }
            .help("Delete this app")
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
            // Versions and App Info share the side panel: showing one hides the other.
            Toggle(isOn: Binding(get: { showVersions }, set: { showVersions = $0; if $0 { showInfo = false } })) {
                Label("Versions", systemImage: "clock.arrow.circlepath")
            }
            .help("See earlier versions of this app, name them, and go back to one")
            Toggle(isOn: Binding(get: { showInfo }, set: { showInfo = $0; if $0 { showVersions = false } })) {
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
        case Builder.localProvider: "Native Mac AI"
        case let id where id.hasPrefix("ext-"): LocalModels.externalName(id)
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
                    .lineSpacing(2)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.secondary)
            }
            // The width limit goes around the button too, so it stays next to the bubble.
            .frame(maxWidth: 480 + 22, alignment: .trailing)
            Label("Queued", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// An app's empty chat: its icon, its name (editable), and what to do next.
struct NewAppIntro: View {
    @EnvironmentObject private var store: Store
    let project: ForgeProject
    @State private var name = ""
    @FocusState private var editingName: Bool

    private var busy: Bool { store.busy.contains(project.id) }

    var body: some View {
        VStack(spacing: 14) {
            AppIcon(project: project, size: 112)
            TextField("Name", text: $name, prompt: Text(project.untitled ? "Untitled" : project.name))
                .textFieldStyle(.plain)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
                .focused($editingName)
                .onSubmit(commit)
                .disabled(busy)
                .frame(maxWidth: 360)
                .help("Rename this app")
            Text(project.untitled
                 ? "Describe the app you want below. Forge names it, designs an icon and builds it, unless you name it here first."
                 : "Describe what \(project.name) should do. Forge builds it and opens it for you.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Text("While using the app, press ⇧⌘E to come back here and ask for changes.")
                .font(.callout).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .onAppear { name = project.untitled ? "" : project.name }
        .onChange(of: editingName) { if !editingName { commit() } }
    }

    private func commit() {
        let typed = name.trimmed
        guard !typed.isEmpty, typed != project.name || project.untitled else { return }
        Task { await store.rename(project, to: typed) }
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

/// A shell command the agent wants to run, explained in plain words. Nothing runs until the user allows it.
struct ApprovalCard: View {
    let command: String
    let explanation: Store.CommandExplanation?
    let onAllow: () -> Void
    let onAllowAll: () -> Void
    let onDeny: () -> Void
    @State private var showCommand = false

    private var highRisk: Bool { explanation?.risk == "high" }

    private var footnote: String {
        switch explanation?.risk {
        case "low": ""
        case "high": "Only allow this if you're sure it's what you asked for."
        default: "Check it's something you expected."
        }
    }

    private var riskColor: Color {
        switch explanation?.risk {
        case "low": .green
        case "high": .red
        default: .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The agent wants to run a command").font(.caption).foregroundStyle(.secondary)
            if let explanation {
                Text(explanation.summary).font(.headline).fixedSize(horizontal: false, vertical: true)
                Label {
                    Text("\(explanation.risk.capitalized) risk").bold() + Text(explanation.why.isEmpty ? "" : ": \(explanation.why)")
                } icon: {
                    Image(systemName: explanation.risk == "low" ? "checkmark.shield" : "exclamationmark.triangle")
                }
                .font(.callout)
                .foregroundStyle(riskColor)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Working out what this does…").foregroundStyle(.secondary)
                }
            }
            DisclosureGroup(isExpanded: $showCommand) {
                ScrollView {
                    Text(command)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            } label: {
                Text("Show command").font(.caption)
            }
            HStack {
                Text(footnote).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if highRisk {
                    // Risky: denying is the default, and there's no blanket "allow all".
                    Button("Allow", action: onAllow)
                    Button("Deny", action: onDeny)
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Deny", role: .cancel, action: onDeny)
                        .keyboardShortcut(.escape, modifiers: [])
                    Button("Allow All This Turn", action: onAllowAll)
                    Button("Allow", action: onAllow)
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(12)
        .background(riskColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(riskColor.opacity(0.35)))
        .onAppear { showCommand = false }
    }
}

/// Shown before the first app: what Forge is for, with a few apps to start from.
struct FirstAppView: View {
    @EnvironmentObject private var store: Store

    /// Starting points, each showing something different a Mac app can do. Choosing one fills in the first
    /// request for the user to edit and send.
    static let examples: [(title: String, symbol: String, blurb: String, prompt: String)] = [
        ("Downloads Tidy", "folder.badge.gearshape", "Watches Downloads and sorts what lands there, from the menu bar.",
         "Downloads Tidy: a menu bar app that watches my Downloads folder and groups new files by what they are (receipts, installers, screenshots, documents), suggesting a clear name for each. Nothing moves or gets renamed until I approve it."),
        ("Screenshot Notes", "camera.viewfinder", "Reads the text in screenshots and makes it searchable.",
         "Screenshot Notes: I drop screenshots on it and it pulls out the text and the key details (who, what, dates, amounts) into a searchable list, with the picture alongside."),
        ("Clipboard Shelf", "list.clipboard", "Remembers what you copy, one shortcut away.",
         "Clipboard Shelf: keeps the last 200 things I copy (text and images). A shortcut (⌃⌥V) opens a small searchable panel from any app; Return copies the item back so I can paste it. Let me pin items so they stay at the top."),
        ("Reading Queue", "list.star", "Ranks PDFs and links by what matters to your work.",
         "Reading Queue: I drop in PDFs, documents and links, and it ranks them by how much they matter for what I'm working on, which I describe in a box at the top. Each item gets a one-line summary and why it's ranked there."),
        ("Focus Timer", "timer", "A menu bar timer with breaks, notifications and daily totals.",
         "Focus Timer: a menu bar timer for 25-minute focus sessions with 5-minute breaks. It shows the time left in the menu bar, notifies me when a session or break ends, keeps a daily total, and has an Open at Login option in Settings."),
        ("Photo Studio", "photo.on.rectangle.angled", "Cleans up product photos and makes new versions with AI.",
         "Photo Studio: I drop in product photos and it puts each one on a clean white background, then lets me ask for variations in plain words (\"on a wooden table\", \"warmer light\"). Show before and after side by side, and export the ones I like."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Image(systemName: "hammer").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("What's your Mac missing?").font(.title.bold())
                    Text("Describe a tool for something you do every week, and Forge builds it as a real Mac app. Keep changing it until it works exactly your way.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        .frame(maxWidth: 460)
                }
                Button("New App") { store.create() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Or start from an idea, then make it yours").font(.callout).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                        ForEach(Self.examples, id: \.title) { example in
                            Button { store.create(draft: example.prompt) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: example.symbol).frame(width: 22).foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(example.title).font(.headline)
                                        Text(example.blurb).font(.callout).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Fills in the request so you can change it before sending")
                        }
                    }
                }
                .frame(maxWidth: 620)
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }
}
