import SwiftUI
import AppKit
import AVFoundation
import QuickLook
import ImagePlayground

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var newName = ""
    @State private var versionName = ""
    @AppStorage(Onboarding.key) private var onboarded = false

    var body: some View {
        Group {
            if !onboarded && !store.welcomeFinished {
                OnboardingView().ignoresSafeArea()
            } else {
                Group {
                    // Only Apple's tools missing (say, still installing after the welcome): Lamp stays usable,
                    // and anything asked for waits in its chat until they're in.
                    if store.setup.checked && !store.setup.ready && !(store.setup.hasBuilder && store.setup.hasAgent) {
                        SetupView()
                    } else {
                        main
                    }
                }
                .frame(minWidth: 760, minHeight: 480)
            }
        }
        .sheet(item: $store.pendingImport) { pending in
            ImportReviewView(pending: pending)
        }
        .modifier(PlaygroundIconSheet())
    }

    private var main: some View {
        NavigationSplitView {
            AppSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            // The banner sits in a stack rather than a top safe-area inset: an inset, even an empty one, keeps
            // the chat's scroll view from reaching the toolbar, and macOS then drops the toolbar's background
            // and divider when the chat scrolls under it.
            VStack(spacing: 0) {
                if store.setup.checked && !store.setup.hasBuildTools { BuildToolsBanner() }
                if let project = store.selected {
                    ProjectView(project: project).id(project.id)
                } else if store.projects.isEmpty {
                    ContentUnavailableView {
                        Label("No apps yet", systemImage: "hammer")
                    } description: {
                        Text("Describe an app and Lamp builds it for you.")
                    } actions: {
                        Button("New App") { store.create() }
                    }
                } else {
                    ContentUnavailableView("Select an app", systemImage: "sidebar.left")
                }
            }
        }
        .alert("Rename “\(store.renaming?.name ?? "")”", isPresented: Binding(
            get: { store.renaming != nil }, set: { if !$0 { store.renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                // Read the field now: by the time the task runs the alert has closed and the field is reset.
                if let project = store.renaming {
                    let name = newName
                    Task { await store.rename(project, to: name) }
                }
            }
            .disabled(newName.trimmed.isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .alert(store.naming?.version.name == nil ? "Name This Version" : "Rename This Version", isPresented: Binding(
            get: { store.naming != nil }, set: { if !$0 { store.naming = nil } })) {
            TextField("Name", text: $versionName)
            Button("Save") {
                if let naming = store.naming {
                    let name = versionName   // same: the field is reset when the alert closes
                    Task { await store.name(naming.version, of: naming.project, as: name) }
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
    private func dialogIcon(for project: LampProject) -> NSImage {
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
                    Image(systemName: "list.bullet").help("Show as List").accessibilityLabel("Show as List").tag(Layout.list)
                    Image(systemName: "square.grid.2x2").help("Show as Tiles").accessibilityLabel("Show as Tiles").tag(Layout.tiles)
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
                store.openPrepared(project)
            }
        }
    }

    private var tiles: some View {
        ScrollView {
            // Tiles line up along the top of their row, as names take one line or two.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 110), spacing: 4, alignment: .top)], spacing: 8) {
                ForEach(store.projects) { project in
                    // A button, so Tab reaches every tile and Space or Return selects it; a double-click opens.
                    Button { store.selection = project.id } label: {
                        AppTile(project: project, selected: store.selection == project.id)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { store.openPrepared(project) })
                    .contextMenu { AppMenu(project: project) }
                    .accessibilityLabel(project.name)
                    .accessibilityAddTraits(store.selection == project.id ? [.isSelected] : [])
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
    let project: LampProject
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
            // Up to two lines, so most names show whole; icons still line up, since rows align at the top.
            // The full name shows on hover.
            Text(project.name)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.tail)
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
    let project: LampProject
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

/// Image Playground, opened from an app's menu to make its icon. The person picks a picture there and Lamp
/// takes it from there; on a Mac without Image Playground there's nothing to open and no menu item for it.
struct PlaygroundIconSheet: ViewModifier {
    @EnvironmentObject private var store: Store

    func body(content: Content) -> some View {
        if #available(macOS 15.1, *) {
            content.imagePlaygroundSheet(isPresented: $store.showingPlayground,
                                         concepts: [.text(store.playgroundPrompt)]) { url in
                // The file is Image Playground's own and temporary, so it's read before anything else happens.
                guard let project = store.playgroundIcon, let picture = try? Data(contentsOf: url) else { return }
                Task { await store.useIconPicture(picture, for: project) }
            }
        } else {
            content
        }
    }
}

struct AppMenu: View {
    @EnvironmentObject private var store: Store
    let project: LampProject

    var body: some View {
        let busy = store.busy.contains(project.id)
        Button("Open") { store.openPrepared(project) }
        Button("Rebuild & Open") { store.runPrepared(project) }
            .disabled(busy)
        Button("Quit") { Task { await store.quitApp(project) } }
            .disabled(!store.openApps.contains(project.id))
        if project.platform == .iphone {
            // Which simulator the app opens in (it's built for both), or which of the person's own phones.
            Menu("Try On") { TryOnChoices(project: project) }
                .disabled(busy)
        }
        Divider()
        Button("Rename…") { store.renaming = project }
            .disabled(busy)
        Button("New Icon") { Task { await store.newIcon(project) } }
            .disabled(busy || project.untitled)
        if Icons.playgroundAvailable {
            // The sheet opens with the icon's own description, so there has to be one.
            Button("Icon from Image Playground…") { store.iconFromPlayground(project) }
                .disabled(project.untitled || Icons.load(project) == nil)
        }
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([project.installedURL])
        }
        Divider()
        if store.canShare(project) {
            Button("Copy App File") { store.copyAppFile(project) }
            ShareLink("Share…", item: SharedApp(project: project),
                      preview: SharePreview(project.name, image: Image(systemName: "app.gift")))
            Button("Export…") { store.chooseExport(project) }
            Divider()
        }
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
    let project: LampProject
    @State private var draft = ""
    @State private var hasMicrophone = true
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
    /// The request taken back into the message box, to change and send again. It and everything after it
    /// are out of sight meanwhile; they only leave the chat, and the app only goes back, when it's sent.
    @State private var replacing: UUID?
    /// What was in the message box before that, put back if the request isn't sent again after all. Kept
    /// with the draft, so it's still there after looking at another app.
    @State private var setAside: Store.Draft?
    /// Lamp's line in the chat saying a request couldn't be sent again. It comes after the lines that are
    /// out of sight, so it's shown with what's left: otherwise Send would seem to do nothing.
    @State private var sendProblem: UUID?
    /// Keep the submitted words and files fixed while setup decides whether they can be sent.
    private var submissionPending: Bool { store.pendingSubmissions.contains(store.current(project)?.id ?? project.id) }
    /// A request on its way out again: what it replaces stays out of sight until the chat has let go of it.
    @State private var sendingAgain: UUID?
    /// How many lines before the latest request the chat reaches back for. Scrolling up towards the earliest
    /// of them raises it.
    @State private var reach = LogLine.recentCount
    /// The chat's scrolling is being watched, so earlier messages come in by themselves.
    @State private var earlierOnScroll = false
    /// Whether the chat is at its end, and so follows what's added there.
    @State private var follow = ChatFollow()
    /// Goes up with each message sent from here, which takes the chat back to its end.
    @State private var sends = 0
    /// What the toolbar knows of the app's history, for which of its buttons can do anything. Nil until read.
    @State private var history: History?

    /// Worked out once per body (see `body`): it filters the whole chat, and body runs on every streamed token.
    private var lines: [LogLine] {
        let all = store.logs[project.id] ?? []
        let hidden = (replacing ?? sendingAgain).flatMap { id in all.firstIndex { $0.id == id } }
        guard let hidden else { return LogLine.visible(all, details: showDetails) }
        let problem = all[hidden...].last { $0.id == sendProblem }
        return LogLine.visible(Array(all[..<hidden]) + (problem.map { [$0] } ?? []), details: showDetails)
    }
    private var busy: Bool { store.busy.contains(project.id) }
    /// How much of its latest message the agent has written so far: a message being written grows without
    /// adding a line, and the chat follows it down.
    private func written(_ lines: [LogLine]) -> Int { busy ? lines.last?.text.count ?? 0 : 0 }
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

    /// The files going with the next message, above the message box.
    private var pendingAttachments: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments, id: \.self) { url in
                    AttachmentChip(url: url, siblings: attachments) {
                        attachments.removeAll { $0 == url }
                        saveDraft()
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 8)
    }

    /// The chat itself, scrolled to its end. Kept out of `body`, like the rows and the message box, because
    /// as one expression the whole view is more than the compiler can type-check in reasonable time.
    private func chat(_ lines: [LogLine]) -> some View {
        // Only the end of a long chat is shown until more is asked for (see `LogLine.recentStart`).
        let start = LogLine.recentStart(in: lines, atLeast: reach)
        let shown = start > 0 ? Array(lines[start...]) : lines
        return ScrollViewReader { proxy in
            GeometryReader { area in
                ScrollView {
                    // Every row shown is laid out, not only the ones in view. A stack that makes its rows as
                    // they scroll into view has to guess the height of the rest, and during a turn that
                    // guessing could go round without ever settling, with Lamp stuck for good.
                    VStack(alignment: .leading, spacing: 0) {
                        // Earlier messages come in as the chat is scrolled up towards them (see `earlier`).
                        // The button is only for when that can't be watched for.
                        if start > 0, !earlierOnScroll {
                            Button("Show Earlier Messages") {
                                guard let top = shown.first?.id else { return }
                                showEarlier(lines, from: start)
                                // They come in above what's being read, which stays where it is.
                                Task { @MainActor in
                                    await Task.yield()
                                    proxy.scrollTo(top, anchor: .top)
                                }
                            }
                            .buttonStyle(.link)
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 24)
                        }
                        // While a new app is being built, its card stays in view above the steps, if there's
                        // room: in a short window a pinned card would fill the chat and hide everything else.
                        chatRows(shown, height: area.size.height,
                                 cardPinned: building != nil && area.size.height >= Self.roomToPinCard)
                    }
                    .background(EarlierOnScroll(more: start > 0, follow: follow, watching: $earlierOnScroll) { showEarlier(lines, from: start) })
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
                // The chat follows what's added at its end, but only from the end: scrolled up to read
                // something earlier, it stays there. Sending a message goes back to the end.
                .onChange(of: lines.count) { followEnd(proxy) }
                .onChange(of: written(lines)) { followEnd(proxy) }
                .onChange(of: queued.count) { followEnd(proxy) }
                .onChange(of: store.progress[project.id]?.plan.count) { followEnd(proxy) }
                .onChange(of: store.progress[project.id]?.screenshot != nil) { followEnd(proxy) }
                .onChange(of: sends) {
                    follow.atEnd = true
                    followEnd(proxy)
                }
            }
        }
    }

    private func followEnd(_ proxy: ScrollViewProxy) {
        if follow.atEnd { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    /// Reaches one more lot back. From what's shown, not from what was asked for: a long turn can take the
    /// chat further back than that, and the next lot has to start beyond it.
    private func showEarlier(_ lines: [LogLine], from start: Int) {
        reach = LogLine.reach(in: lines, from: start) + LogLine.recentCount
    }

    /// The chat's rows: the intro for a new app, the transcript with its build card or activity, and the
    /// messages waiting their turn.
    @ViewBuilder
    private func chatRows(_ lines: [LogLine], height: CGFloat, cardPinned: Bool) -> some View {
        if lines.isEmpty && queued.isEmpty {
            // In the middle of the chat area: less the scroll view's own padding.
            NewAppIntro(project: project, draft: draftBinding)
                .frame(minHeight: height - 32)
        }
        if let card = store.progress[project.id], card.newApp,
           let request = lines.lastIndex(where: { $0.kind == .user }) {
            // The build card goes straight after the request; what the agent says and
            // does follows it.
            transcript(Array(lines[...request]), busy: false)
            BuildCard(project: project, progress: card)
                .padding(.top, 16).padding(.bottom, 12)
                .background(Color(nsColor: .textBackgroundColor))
                // Pinned: once it reaches the top of the chat it stays there, over the steps going by.
                .visualEffect { content, geometry in
                    content.offset(y: cardPinned ? max(0, -geometry.frame(in: .scrollView).minY) : 0)
                }
                .zIndex(1)
            transcript(Array(lines[(request + 1)...]), busy: busy, progressShown: busy)
        } else {
            let progress = busy ? store.progress[project.id] : nil
            transcript(lines, busy: busy, progressShown: progress != nil)
            if let progress { ActivityRow(progress: progress).padding(.top, 12) }
        }
        ForEach(queued) { message in
            QueuedRow(message: message) { store.unqueue(message, from: project) }
                .padding(.top, lines.isEmpty ? 0 : 32)
        }
        Color.clear.frame(height: 1).id("bottom")
    }

    /// The message box with the buttons around it.
    private func composerRow(_ lines: [LogLine]) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button(action: chooseFiles) { Image(systemName: "paperclip").font(.title3) }
                .buttonStyle(.borderless)
                .help("Attach files. You can also paste or drop images and files here.")
                .accessibilityLabel("Attach files")
                .frame(height: Composer.lineHeight)
            Composer(text: draftBinding, height: $composerHeight,
                     placeholder: busy ? "Working… describe the next change"
                        : lines.isEmpty ? "Describe an app…" : "Describe a change…",
                     // No suggestion while a request from the chat is in the box: it would be about a turn
                     // that's on its way out, and Escape, which dismisses one, puts the request back instead.
                     suggestion: replacing == nil ? shownSuggestion : nil,
                     onDismissSuggestion: { dismissedSuggestion = suggestion },
                     onEscape: replacing == nil ? nil : putBack,
                     isEnabled: true, focusRequest: focusRequest,
                     onSubmit: send, onFiles: attach)
                .frame(height: composerHeight)
            if hasMicrophone {
                Button(action: toggleDictation) {
                    Image(systemName: dictation.isListening ? "mic.fill" : "mic").font(.title3)
                        .symbolEffect(.pulse, isActive: dictation.isListening)
                }
                .buttonStyle(.plain)
                .foregroundStyle(dictation.isListening ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .disabled(submissionPending)
                .help(dictation.isListening ? "Stop dictation" : "Dictate a change")
                .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Dictate a change")
                .frame(height: Composer.lineHeight)
            }
            if busy {
                Button { store.stop(project) } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Stop")
                    .accessibilityLabel("Stop")
                    .frame(height: Composer.lineHeight)
            }
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            // A request sent again starts from the app as it was, so it can't wait behind other work.
            .disabled(submissionPending || draft.trimmed.isEmpty && attachments.isEmpty || replacing != nil && busy)
            .help(busy ? "Queue this change. It's sent when the current one is done." : "Send")
            .frame(height: Composer.lineHeight)
        }
        .padding(12)
    }

    struct History: Equatable {
        /// Undo has a version to go back to, or a stopped turn's changes to discard.
        var undoable: Bool
        /// Something has been made: the app is no longer the empty one Lamp starts with. Until then there's
        /// nothing to open, share or look back on. Read from the app's files, not its versions' messages: a
        /// request is saved in its own words, which can look like one of Lamp's own notes ("Rename to …").
        var made: Bool
        /// There's more saved than the version the app started as. Apart from `made`: an Undo back to the
        /// empty app keeps the build it undid, and Versions is how to get it back.
        var saved: Bool

        static func read(_ project: LampProject) async -> History {
            let versions = await Versions.list(project)
            let made = !Template.isScaffold(project)
            let undoable = Versions.undoTarget(in: versions) != nil
            return History(undoable: undoable ? true : await Versions.hasUnsavedChanges(project), made: made,
                           saved: made || versions.count > 1)
        }
    }
    /// The history is read again whenever a turn starts or ends and whenever the chat changes (a rename, an Undo).
    private var historyKey: String { "\(project.id) \(busy) \(store.logs[project.id]?.count ?? 0)" }
    private var undoable: Bool { history?.undoable ?? true }
    private var made: Bool { history?.made ?? true }
    private var saved: Bool { history?.saved ?? true }
    private var inspectorShown: Binding<Bool> {
        Binding(get: { showInfo || (showVersions && saved) }, set: { if !$0 { showInfo = false; showVersions = false } })
    }

    var body: some View {
        let lines = self.lines
        return VStack(spacing: 0) {
            chat(lines)
            Divider()
            if let approval = store.approvals[project.id] {
                ApprovalCard(title: approval.title, command: approval.command, explanation: approval.explanation,
                             onAllow: { store.answerApproval(for: project, allow: true) },
                             onAllowAll: { store.answerApproval(for: project, allow: true, allowAll: true) },
                             onDeny: { store.answerApproval(for: project, allow: false) })
                    .padding(12)
                    // Each request starts with its command hidden, even when one follows another.
                    .id(approval.id)
                // Part of the bottom panel, set off from the message box the way the chat is.
                Divider()
            }
            if !attachments.isEmpty { pendingAttachments }
            composerRow(lines)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 3).padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: Attachments.dropTypes, isTargeted: $dropTargeted) { providers in
            Attachments.load(providers) { attach($0) }
            return true
        }
        .background(Color(nsColor: .textBackgroundColor))
        .inspector(isPresented: inspectorShown) {
            Group {
                if showVersions && saved { VersionsView(project: project) } else { AppInfoView(project: project) }
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
            loadDraft()
        }
        .onChange(of: store.draftUpdates[store.current(project)?.id ?? project.id]) { loadDraft() }
        .onChange(of: project.platform) { PhoneSetup.shared.refreshIfVisible() }
        .onChange(of: draft) { saveDraft() }
        .onChange(of: attachments) { saveDraft() }
        .onChange(of: replacing) { saveDraft() }
        .onAppear { hasMicrophone = Dictation.hasMicrophone }
        // A microphone plugged in (or taken away) while the chat is open shows or hides the button.
        .onReceive(NotificationCenter.default.publisher(for: .AVCaptureDeviceWasConnected)) { _ in hasMicrophone = Dictation.hasMicrophone }
        .onReceive(NotificationCenter.default.publisher(for: .AVCaptureDeviceWasDisconnected)) { _ in hasMicrophone = Dictation.hasMicrophone }
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
        .task(id: historyKey) {
            // A read can outlast the change that started it (the git commands it runs finish even when it's
            // cancelled), so one started before a turn ended mustn't land after the read that followed.
            let read = await History.read(project)
            guard !Task.isCancelled else { return }
            history = read
        }
        .task(id: suggestionTurn) {
            suggestion = nil
            guard suggestionTurn != nil else { return }
            suggestion = await NextStep.suggest(for: project, lines: store.logs[project.id] ?? [])
        }
    }

    private func transcript(_ lines: [LogLine], busy: Bool, progressShown: Bool = false) -> some View {
        Transcript(lines: lines, dir: project.dir, busy: busy, progressShown: progressShown, goBack: { line, before in
            Task { await store.restore(project, toVersionOf: line, before: before) }
        }, sendAgain: self.busy || submissionPending ? nil : takeBack, retryPhone: Experiments.iosApps && project.device != nil ? { udid in
            Task { await store.retryPhone(project, udid: udid) }
        } : nil)
    }

    /// Persist writes synchronously so a check finishing in this event cycle sees the newest input,
    /// including writes from a newly-created chat view after navigation.
    private var draftBinding: Binding<String> {
        Binding(get: { draft }, set: { draft = $0; saveDraft() })
    }

    private func loadDraft() {
        let saved = store.draft(for: store.current(project) ?? project)
        draft = saved.text
        attachments = saved.attachments
        replacing = saved.replacing
        setAside = saved.replacing == nil ? nil
            : Store.Draft(text: saved.setAsideText, attachments: saved.setAsideAttachments)
    }

    private func saveDraft() {
        guard let current = store.current(project) else { return }
        store.saveDraft(Store.Draft(text: draft, attachments: attachments, replacing: replacing,
                                    setAsideText: setAside?.text ?? "", setAsideAttachments: setAside?.attachments ?? []),
                        for: current)
    }

    /// Takes a request out of the chat and into the message box, with the files it was sent with.
    private func takeBack(_ line: LogLine) {
        guard !submissionPending else { return }
        if replacing == nil { setAside = Store.Draft(text: draft, attachments: attachments) }
        dictation.cancel()
        sendProblem = nil
        draft = line.text
        attachments = Attachments.urls(line.attachments ?? [], in: project)
        replacing = line.id
        focusRequest += 1
    }

    /// Not sending it again after all: the chat is as it was, and so is the message box.
    /// Escape in the message box does this. Emptying the box doesn't: that's how someone starts the request
    /// over in new words.
    private func putBack() {
        guard !submissionPending else { return }
        replacing = nil
        sendProblem = nil
        draft = setAside?.text ?? ""
        attachments = setAside?.attachments ?? []
        setAside = nil
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
            // One button: Play while the app is closed, Stop while it's open.
            if store.openApps.contains(project.id) {
                Button { Task { await store.quitApp(project) } } label: {
                    Label("Quit App", systemImage: "stop.fill")
                }
                .help("Quit the app (double-click it in the sidebar to bring it to the front)")
            } else {
                Button { store.openPrepared(project) } label: {
                    Label("Open App", systemImage: "play.fill")
                }
                .disabled(!made)
                .help(made ? "Open the app (right-click it in the sidebar to rebuild)" : "Describe the app first; Lamp opens it once it's built")
            }
        }
        if project.platform == .iphone {
            ToolbarItem {
                // Which simulator the app opens in, beside the Play button where Xcode keeps its destination.
                Menu {
                    TryOnChoices(project: project)
                } label: {
                    let device = store.devices.first { $0.udid == project.device }
                    Label(store.tryOnName(project), systemImage: (device?.family ?? project.family) == .ipad ? "ipad" : "iphone")
                }
                .disabled(busy)
                .help("Where the app opens: a simulator, or your own iPhone or iPad")
            }
        }
        gap
        ToolbarItemGroup {
            Button { Task { await store.undo(project) } } label: {
                Label("Undo Last Change", systemImage: "arrow.uturn.backward")
            }
            .disabled(busy || !undoable)
            .help(undoable ? "Go back to the version before this one" : "Nothing to undo yet")
            Button { store.deleting = project } label: {
                Label("Delete App", systemImage: "trash")
            }
            .help("Delete this app")
            if store.canShare(project) {
                Menu {
                    Button("Copy App File") { store.copyAppFile(project) }
                    ShareLink("Share…", item: SharedApp(project: project),
                              preview: SharePreview(project.name, image: Image(systemName: "app.gift")))
                    Button("Export…") { store.chooseExport(project) }
                } label: {
                    Label("Share App", systemImage: "square.and.arrow.up")
                }
                .disabled(!made)
                .help(made ? "Send this app to someone with Lamp" : "Nothing to share until the app is built")
            }
        }
        gap
        ToolbarItemGroup {
            Toggle(isOn: $showDetails) {
                Label("Agent Details", systemImage: "wrench.and.screwdriver")
            }
            .help("Agent details")
            // Versions and App Info share the side panel: showing one hides the other.
            Toggle(isOn: Binding(get: { showVersions && saved }, set: { showVersions = $0; if $0 { showInfo = false } })) {
                Label("Versions", systemImage: "clock.arrow.circlepath")
            }
            .disabled(!saved)
            .help(saved ? "See earlier versions of this app, name them, and go back to one" : "No versions yet: each change Lamp makes is saved as one")
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
        Task {
            guard !submissionPending else { return }
            await dictation.start { if !submissionPending { draft = typed + separator + $0 } }
        }
    }

    private func send() {
        guard !submissionPending, !draft.trimmed.isEmpty || !attachments.isEmpty else { return }
        let replaced = replacing.flatMap { id in store.logs[project.id]?.first { $0.id == id } }
        guard replaced == nil || !busy else { return }
        dictation.cancel()
        let submitted = Store.Draft(text: draft, attachments: attachments, replacing: replacing,
                                    setAsideText: setAside?.text ?? "", setAsideAttachments: setAside?.attachments ?? [])
        guard let token = store.beginSubmission(project) else { return }
        sends += 1
        store.saveDraft(submitted, for: project)
        PhoneSetup.shared.perform(for: project, in: store, cancelled: {
            finishSubmission(token, captured: submitted, sent: false)
        }) { current in
            sendPrepared(submitted, replacing: replaced, to: current, token: token)
        }
    }

    private func sendPrepared(_ submitted: Store.Draft, replacing replaced: LogLine?, to current: LampProject, token: UUID) {
        let text = submitted.text.trimmed
        let files = submitted.attachments
        guard let replaced else {
            store.send(text, attachments: files, to: current)
            finishSubmission(token, captured: submitted, sent: true)
            return
        }
        sendingAgain = replaced.id
        sendProblem = nil
        Task {
            // Nothing was sent: the words go back in the box, so they aren't lost with it, and the chat
            // keeps saying why.
            let sent = await store.sendAgain(replaced, as: text, attachments: files, in: current)
            if !sent { sendProblem = store.logs[current.id]?.last { $0.kind == .error }?.id }
            sendingAgain = nil
            finishSubmission(token, captured: submitted, sent: sent)
        }
    }

    private func finishSubmission(_ token: UUID, captured: Store.Draft, sent: Bool) {
        if let current = store.current(project) {
            let kept = store.draft(for: current).afterSubmission(captured, sent: sent)
            store.updateDraft(kept, for: current)
        }
        store.endSubmission(token)
    }

    private func attach(_ files: [URL]) {
        store.attach(files, to: project)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Attach screenshots, mockups, images, data or documents"
        guard panel.runModal() == .OK else { return }
        let files = panel.urls
        // Changing the composer here can re-enter the chat's lazy layout while AppKit closes the panel.
        DispatchQueue.main.async { attach(files) }
    }
}

/// The info panel: what an app has cost, which models it uses, and where it lives.
struct AppInfoView: View {
    @EnvironmentObject private var store: Store
    let project: LampProject
    /// This app's own model choices; nil fields follow Settings.
    @State private var models: AppModels

    init(project: LampProject) {
        self.project = project
        _models = State(initialValue: AppModels.load(project))
    }
    /// Bumped when Settings changes, so the defaults shown are current.
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
                Picker("Text", selection: choice(\.text, default: AppAI.model.id)) {
                    ForEach(AppAI.textRouteGroups(including: models.text), id: \.title) { group in
                        Section(group.title) { ForEach(group.routes) { Text(Self.short($0.name)).tag($0.id) } }
                    }
                }
                Picker("Making images", selection: choice(\.image, default: Icons.artModel)) {
                    ForEach(Icons.imageChoices, id: \.id) { Text(Self.short($0.label)).tag($0.id) }
                }
                Picker("Decisions", selection: choice(\.decision, default: AppAI.decisionModel.id)) {
                    ForEach(AppAI.decisionModels, id: \.id) { Text($0.label).tag($0.id) }
                }
                if project.platform == .iphone {
                    Picker("Away from this Mac", selection: choice(\.away, default: AppAI.awayModel.id)) {
                        ForEach(AppAI.anthropicModels, id: \.id) { Text(Self.short($0.label)).tag($0.id) }
                    }
                    Picker("Pictures away", selection: choice(\.awayImage, default: AppAI.awayImageModel)) {
                        ForEach(Icons.artModels, id: \.id) { Text(Self.short($0.label)).tag($0.id) }
                    }
                    Picker("Decisions away", selection: choice(\.awayDecision, default: AppAI.awayDecisionModel.id)) {
                        ForEach(AppAI.awayDecisionModels, id: \.id) { Text($0.label).tag($0.id) }
                    }
                }
            } header: {
                Text("AI inside this app")
            } footer: {
                Text(Provider.hasKey ? "Starts as your choices in Settings. Changes apply straight away, without rebuilding." : "Without an OpenRouter key, text uses whatever builds your apps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                let _ = settingsRevision
                LabeledContent("Agent", value: Builder.engine.title)
                if Builder.engine == .claude || Builder.engine == .codex {
                    let model = Builder.engineModel(Builder.engine)
                    let names = Builder.engine == .claude ? Builder.claudeModels : Builder.codexModels
                    LabeledContent("Building with", value: model.isEmpty ? "\(Builder.engine.title)'s default"
                                   : names.first { $0.id == model }?.label ?? model)
                }
                if Builder.engine == .pi {
                    LabeledContent("Provider", value: providerName)
                    if !Builder.piModel.isEmpty { LabeledContent("Building with", value: buildModel) }
                }
            } header: {
                Text("Building")
            } footer: {
                SettingsLink { Text("Change in Settings…") }
                    .buttonStyle(.link)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("App") {
                if let stamp = store.stamps[project.id] {
                    LabeledContent("Built with") {
                        Text(stamp.summary).foregroundStyle(.secondary)
                    }
                }
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
        .onChange(of: project.id) { models = AppModels.load(project) }
    }

    /// A model's name without the description Settings shows: "Fast & cheap (Claude Haiku)" → "Claude Haiku",
    /// "Nano Banana 2 (Gemini 3.1 Flash Image)" → "Nano Banana 2". The panel is narrow.
    static func short(_ label: String) -> String {
        guard let open = label.firstIndex(of: "(") else { return label }
        let inside = String(label[label.index(after: open)...].prefix { $0 != ")" }).components(separatedBy: ",")[0]
        return inside.hasPrefix("Claude") ? inside : String(label[..<open]).trimmed
    }

    /// One of this app's model choices. Picking the model Settings uses means following Settings, so the app
    /// keeps up if that default changes; any other pick is this app's own.
    private func choice(_ field: WritableKeyPath<AppModels, String?>, default fallback: String) -> Binding<String> {
        Binding(get: { models[keyPath: field] ?? fallback }, set: {
            models[keyPath: field] = $0 == fallback ? nil : $0
            models.save(project)
        })
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

/// While Apple's tools install, above everything: what's happening, and that requests wait for it.
private struct BuildToolsBanner: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Installing Apple's app-building tools. Anything you ask for starts as soon as they're in.")
                .font(.callout)
            Spacer()
            Button(store.setup.installRequested ? "Show Installer" : "Install…") {
                if store.setup.installRequested { SetupCheck.installBuildTools() } else { store.requestBuildTools() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// A message waiting for the current change to finish. It can still be taken back.
struct QueuedRow: View {
    @EnvironmentObject private var store: Store
    let message: QueuedMessage
    let onRemove: () -> Void

    /// The first request, sent from the welcome while Apple's tools were still installing.
    private var waitingForSetup: Bool { !store.setup.ready }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !message.attachments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(message.attachments, id: \.self) { AttachmentChip(url: $0, siblings: message.attachments) }
                }
            }
            HStack(spacing: 6) {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .help("Remove from the queue")
                    .accessibilityLabel("Remove from the queue")
                Text(message.text)
                    .lineSpacing(2)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.secondary)
            }
            // The width limit goes around the button too, so it stays next to the bubble.
            .frame(maxWidth: 480 + 22, alignment: .trailing)
            Label(waitingForSetup ? "Starts when Apple's app-building tools finish installing" : "Queued",
                  systemImage: "clock").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// An app's empty chat: its icon, its name (editable), and what to do next.
struct NewAppIntro: View {
    @EnvironmentObject private var store: Store
    let project: LampProject
    @Binding var draft: String
    @State private var name = ""
    @State private var fresh = false   // nothing built yet (not, say, an imported app)
    /// Drawn once when the chat first shows, so they don't change under the reader or when a draft is cleared.
    @State private var ideas: [Idea] = []
    @FocusState private var editingName: Bool

    @AppStorage("experimentIOSApps") private var iosApps = false

    private var busy: Bool { store.busy.contains(project.id) }

    /// What a new app is made as, chosen before its first message. iPhone and iPad are the same kind of app
    /// to Lamp; the choice is which simulator it opens in.
    private enum Kind: String, CaseIterable { case mac = "Mac", iphone = "iPhone", ipad = "iPad" }

    private var kind: Binding<Kind> {
        Binding {
            project.platform == .mac ? .mac : project.family == .ipad ? .ipad : .iphone
        } set: { kind in
            store.setKind(project, platform: kind == .mac ? .mac : .iphone, family: kind == .ipad ? .ipad : .iphone)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            // Catches the light once the reveal has passed it.
            AppIcon(project: project, size: 112).shine(delay: 0.4)
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
                 ? "Describe the app you wish you had, and Lamp will build it."
                 : "Describe what \(project.name) should do. Lamp builds it and opens it for you.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            if iosApps && !project.scaffolded {   // a draft, so its kind is still open (Store.setKind)
                Picker("Kind", selection: kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .labelsHidden()
                .disabled(busy)
                .padding(.top, 4)
            }
            if fresh && draft.trimmed.isEmpty && !ideas.isEmpty {
                StarterIdeas(ideas: ideas) { prompt in
                    draft = prompt
                    store.chatFocusRequest += 1
                }
                .padding(.top, 18)
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .sparkleReveal()
        .onAppear {
            name = project.untitled ? "" : project.name
            fresh = Template.isScaffold(project)
            if ideas.isEmpty {
                let others = store.projects.filter { $0.id != project.id && !$0.untitled }
                ideas = Ideas.starters(made: others.map(\.name))
            }
        }
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
    /// Opening takes a deliberate click (no Return) when the AI rates the app high, when the code was seen to
    /// do something sensitive, or when nothing checked it and the fixed checks found real capabilities.
    private var deliberate: Bool {
        guard let review else { return false }
        return review.risk == "high" || review.worst == .sensitive || (!review.checked && !review.detected.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(for: .applicationBundle)).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open “\(pending.package.name)”?").font(.title2.bold())
                    Text("Someone shared this app with you. Lamp builds it and opens it here, where it can do anything an app you run can do.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let review {
              // The review scrolls when it's long (an app that does many things); the buttons stay put.
              ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                if !review.summary.isEmpty {
                    section("What it does") { Text(review.summary).fixedSize(horizontal: false, vertical: true) }
                }
                section("What it can do on your Mac") { capabilities(review) }
                if !pending.package.attachments.isEmpty {
                    section("Files the app uses") {
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
                verdict(review)
                if let note = review.note {
                    Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text("Lamp's check is a guide, not a guarantee. Only open apps from people you trust.")
                    .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
              .frame(maxHeight: 520)
              .fixedSize(horizontal: false, vertical: true)   // no taller than its content, up to the limit
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Checking what this app does…").foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
            }

            if let existing = pending.existing {
                // Said before the choice is made: what Update replaces, what it keeps, and the way back.
                Label {
                    Text("You already have this app\(existing.name == pending.package.name ? "" : ", as “\(existing.name)”"). Update replaces its code with this version and keeps its data and its chat. The app as it is now stays in Versions, so you can go back. Keep Both adds this one as a separate app.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                // Escape always cancels. Return builds only when the review is in and not worrying; an app
                // that does something sensitive takes a deliberate click.
                Button("Cancel", role: .cancel) { store.cancelImport() }
                    .keyboardShortcut(.cancelAction)
                if pending.existing != nil {
                    // The app is already here: the file either becomes its next version or a second app.
                    Button("Keep Both") { store.confirmImport() }
                        .disabled(review == nil)
                    if deliberate || review == nil {
                        Button(deliberate ? "Update Anyway" : "Update", role: deliberate ? .destructive : nil) { store.confirmUpdate() }
                            .disabled(review == nil)
                    } else {
                        Button("Update") { store.confirmUpdate() }
                            .keyboardShortcut(.defaultAction)
                    }
                } else if deliberate || review == nil {
                    Button(deliberate ? "Open Anyway" : "Build & Open", role: deliberate ? .destructive : nil) { store.confirmImport() }
                        .disabled(review == nil)
                } else {
                    Button("Build & Open") { store.confirmImport() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    /// One row per kind of access the code was seen to use, worst first, like the permissions list in System
    /// Settings: an icon in a tinted square, the plain-words line, and a word on the right for anything beyond
    /// ordinary. What the AI noticed follows as a line of text: it mostly restates the rows in its own words,
    /// and now and then adds something the fixed checks have no pattern for.
    private func capabilities(_ review: ImportReview) -> some View {
        let found = review.detected.sorted { $0.level > $1.level }
        return VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                if found.isEmpty {
                    // Says what the fixed checks found, not what the app can't do: the AI's line below, or
                    // a check that didn't run, may know more.
                    row(icon: "magnifyingglass", tint: .secondary, text: "Nothing found by Lamp's own checks.")
                }
                ForEach(found) { capability in
                    row(icon: capability.icon, tint: tint(for: capability.level), text: capability.label, badge: badge(for: capability.level))
                    if capability != found.last { Divider().padding(.leading, 44) }
                }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            if !review.capabilities.isEmpty {
                Text("The AI also noticed: " + review.capabilities.joined(separator: "; ") + ".")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(icon: String, tint: Color, text: String, badge: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let badge {
                Text(badge).font(.caption.weight(.medium)).foregroundStyle(tint == .secondary ? Color.secondary : tint)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func tint(for level: Sharing.Capability.Level) -> Color {
        switch level {
        case .ordinary: .blue
        case .powerful: .orange
        case .sensitive: .red
        }
    }

    private func badge(for level: Sharing.Capability.Level) -> String? {
        switch level {
        case .ordinary: nil
        case .powerful: "Powerful"
        case .sensitive: "Sensitive"
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    /// The one-line verdict: the AI's rating, lifted by what the code was seen to do.
    private func verdict(_ review: ImportReview) -> some View {
        let (text, color, icon): (String, Color, String) = switch (review.risk, review.worst) {
        case ("high", _): ("Looks risky. Don't open unless you trust the sender", .red, "xmark.octagon.fill")
        case (_, .sensitive): ("Does sensitive things. Open only if you expected that", .red, "exclamationmark.octagon.fill")
        case ("medium", _), (_, .powerful): ("Powerful, check it's what you expect", .yellow, "exclamationmark.circle.fill")
        case ("low", _): ("Looks safe", .green, "checkmark.seal.fill")
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
    var title = Store.PendingApproval.commandTitle
    let command: String
    let explanation: Store.CommandExplanation?
    let onAllow: () -> Void
    let onAllowAll: () -> Void
    let onDeny: () -> Void
    @State private var showCommand = false

    private var highRisk: Bool { explanation?.risk == "high" }

    /// The same green, yellow and red as app icons' backgrounds. The icon yellow is too pale to read on a
    /// light background, so light mode gets a darker shade of it.
    private var riskColor: Color {
        let hex = switch explanation?.risk {
        case "low": Icons.background(named: "green").bottom
        case "high": Icons.background(named: "red").bottom
        default: Icons.background(named: "yellow").bottom
        }
        let color = Icons.color(hex: hex) ?? .systemOrange
        guard explanation?.risk != "low" && explanation?.risk != "high" else { return Color(nsColor: color) }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? color : color.blended(withFraction: 0.3, of: .black) ?? color
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let explanation {
                // No fixedSize here: it makes SwiftUI size the text for its narrowest possible width, and that
                // height became the whole window's minimum, growing the window past the screen.
                Text(explanation.summary).font(.headline)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Working out what this does…").foregroundStyle(.secondary)
                }
            }
            // Not a DisclosureGroup: on the Mac only its chevron toggles it, so clicking the words did nothing.
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showCommand.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(showCommand ? 90 : 0))
                    Text(showCommand ? "Hide command" : "Show command").font(.caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            if showCommand {
                // A short command takes only the room it needs; a long one scrolls rather than pushing the chat
                // out of the window.
                ViewThatFits(in: .vertical) {
                    commandText
                    ScrollView { commandText }
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                if let explanation {
                    (Text("\(explanation.risk.capitalized) risk").bold() + Text(explanation.why.isEmpty ? "" : ": \(explanation.why)"))
                        .font(.callout)
                        .foregroundStyle(riskColor)
                }
                Spacer()
                if highRisk {
                    // Risky: denying is the default, on Escape as well, and there's no blanket "allow all".
                    Button("Allow", action: onAllow)
                    Button("Deny", role: .cancel, action: onDeny)
                        .keyboardShortcut(.cancelAction)
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
    }

    private var commandText: some View {
        Text(command)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Apps to start from, under a new app's empty chat. Choosing one fills in the request (it isn't sent) so the
/// user can make it theirs first. It opens on the six it's given; Show Me Others pages on from there.
struct StarterIdeas: View {
    let choose: (String) -> Void
    @StateObject private var deck: IdeaDeck
    @State private var hovered: String?

    init(ideas: [Idea], choose: @escaping (String) -> Void) {
        self.choose = choose
        _deck = StateObject(wrappedValue: IdeaDeck(first: ideas))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Need an idea?").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(action: deck.more) {
                    HStack(spacing: 5) {
                        Image(systemName: IdeaDeck.moreSymbol)
                        Text("Show me others")
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                ForEach(Array(deck.ideas.enumerated()), id: \.element.id) { index, example in
                    Button { choose(example.prompt) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            IdeaIcon(symbol: example.symbol, hue: example.hue, size: 22, lit: hovered == example.title)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(example.title).font(.subheadline.weight(.semibold))
                                Text(example.blurb).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        // Just an outline, so the ideas stay quieter than what the user is writing.
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(hovered == example.title ? 0.2 : 0.1), lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 ? example.title : (hovered == example.title ? nil : hovered) }
                    .help("Fills in the request so you can change it before sending")
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94)).animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.04)),
                        removal: .opacity.animation(.easeOut(duration: 0.15))))
                }
            }
        }
        .frame(maxWidth: 600)
        .onAppear { deck.prefetch() }
    }
}

/// The Try On choices: the iPhone and iPad simulators and, when apps may go on the person's own devices,
/// each paired phone. The simulator choice is the family the agent builds and looks at; a phone is where
/// Play puts the app.
private struct TryOnChoices: View {
    @EnvironmentObject private var store: Store
    let project: LampProject
    @State private var olderPhones: [PhoneTools.OlderPhone] = []

    var body: some View {
        Picker("Simulator", selection: Binding(get: { project.device == nil ? project.family : nil },
                                               set: { if let family = $0 { store.setSimulator(project, family) } })) {
            Label("iPhone", systemImage: "iphone").tag(Optional(DeviceFamily.iphone))
            Label("iPad", systemImage: "ipad").tag(Optional(DeviceFamily.ipad))
        }
        .pickerStyle(.inline)
        do {
            let paired = store.devices.filter(\.paired), unpaired = store.devices.filter { !$0.paired }
            Picker("Your Devices", selection: Binding(get: { project.device }, set: { chosen in
                store.choosePreparedDevice(project, chosen)
            })) {
                ForEach(paired) { device in
                    Label(device.name + (device.developerMode ? "" : " (Developer Mode is off)"), systemImage: device.family == .ipad ? "ipad" : "iphone")
                        .tag(Optional(device.udid))
                }
                if let chosen = project.device, !paired.contains(where: { $0.udid == chosen }) {
                    Label("Chosen phone (not paired)", systemImage: "iphone.slash").tag(Optional(chosen))
                }
            }
            .pickerStyle(.inline)
            // A phone that's plugged in but hasn't trusted this Mac yet: pairing puts the question on it.
            ForEach(unpaired) { device in
                Button(store.pairing.contains(device.udid) ? "Pairing with \(device.name)…" : "Pair \(device.name)…") {
                    store.pairDevice(device, for: project)
                }
                .disabled(store.pairing.contains(device.udid))
            }
            ForEach(olderPhones.filter { old in !store.devices.contains(where: { $0.udid == old.id }) }) { phone in
                Button("\(phone.name) (needs iOS \(PhoneTools.minimumIOS))…") {
                    PhoneSetup.shared.show(family: phone.family, phone: phone.id)
                }
            }
            if store.devices.isEmpty && olderPhones.isEmpty {
                Text("No iPhone or iPad found. Plug one in with a cable and unlock it, then look again.")
            }
        }
        Divider()
        Button("Check iPhone & iPad Setup…") { PhoneSetup.shared.show(family: project.family, phone: Experiments.iosApps ? project.device : nil) }
        Button("Look for Devices Again") { refresh() }
            .onAppear { refresh() }
    }

    private func refresh() {
        store.refreshDevices()
        if Experiments.iosApps { Task { olderPhones = await PhoneTools.olderPhones() } }
    }
}
