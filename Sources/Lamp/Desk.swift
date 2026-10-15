import SwiftUI
import AppKit
import AVFoundation

/// Lamp's home: the person's wishes laid out like a desktop, and the place to make a new one, by typing it,
/// saying it, or finding it with the agent's help. A click on a wish uses it; changing it is what its chat is
/// for, a right-click away.
struct WishDesk: View {
    @EnvironmentObject private var store: Store
    @State private var text = ""
    @StateObject private var dictation = Dictation()
    @State private var hasMicrophone = true
    @FocusState private var barFocused: Bool
    /// Drawn once, so they don't change under the reader.
    @State private var ideas: [Idea] = []

    /// A wish not yet told is thrown away as the desk comes back (`discardIfUnused`): the rest are on the desk.
    private var wishes: [LampProject] { store.projects }

    var body: some View {
        ZStack {
            DeskBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, wishes.isEmpty ? 72 : 40)
                    if wishes.isEmpty {
                        if !ideas.isEmpty {
                            StarterIdeas(ideas: ideas) { wish in
                                text = wish
                                barFocused = true
                            }
                            .padding(.top, 40)
                            .padding(.horizontal, 32)
                        }
                    } else {
                        grid.padding(.top, 44)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Lamp")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                    .help("Settings (⌘,)")
            }
        }
        .modifier(ClearToolbar())
        .onAppear {
            hasMicrophone = Dictation.hasMicrophone
            if ideas.isEmpty { ideas = Ideas.starters(made: store.projects.filter { !$0.untitled }.map(\.name)) }
            barFocused = true
        }
        .onChange(of: store.deskFocusRequest) { barFocused = true }
        .onDisappear { dictation.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .AVCaptureDeviceWasConnected)) { _ in hasMicrophone = Dictation.hasMicrophone }
        .onReceive(NotificationCenter.default.publisher(for: .AVCaptureDeviceWasDisconnected)) { _ in hasMicrophone = Dictation.hasMicrophone }
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
    }

    private var header: some View {
        VStack(spacing: 18) {
            Text("What do you wish for?")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            HStack(alignment: .center, spacing: 14) {
                bar
                if hasMicrophone {
                    TalkButton(listening: dictation.isListening, level: dictation.level, action: toggleTalk)
                }
            }
            .frame(maxWidth: 600)
            .padding(.horizontal, 32)
            Button(action: store.findWish) {
                Label("Not sure? Help me find one", systemImage: "sparkle.magnifyingglass")
                    .font(.callout.weight(.medium))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Lamp asks a few questions about your days and writes a wish with you")
        }
    }

    private var bar: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField(dictation.isListening ? "Listening…" : "Type a wish…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                .lineLimit(1...5)
                .focused($barFocused)
                .onSubmit { send() }
            if !text.trimmed.isEmpty {
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Make this wish (Return)")
                .accessibilityLabel("Make this wish")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: text.trimmed.isEmpty)
        .padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 14)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.9), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(Color.primary.opacity(barFocused ? 0.18 : 0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
    }

    private var grid: some View {
        DeskRows(width: 124, spacing: 8, lineSpacing: 22) {
            ForEach(wishes) { project in
                DeskIcon(project: project)
            }
        }
        .frame(maxWidth: 880)
        .padding(.horizontal, 32)
    }

    /// The words heard go in the bar, after whatever was typed; the person sends them when they look right.
    private func toggleTalk() {
        if dictation.isListening {
            dictation.stop()
            barFocused = true
            return
        }
        let typed = text
        let separator = typed.isEmpty || typed.last!.isWhitespace ? "" : " "
        Task {
            await dictation.start { heard, _ in text = typed + separator + heard }
        }
    }

    private func send() {
        let wish = text.trimmed
        guard !wish.isEmpty else { return }
        let spoken = dictation.isListening
        dictation.cancel()
        text = ""
        store.wish(wish, spoken: spoken)
    }
}

/// The desk's icons in rows of equal columns, each row centered under the wish bar, as a few wishes look
/// lost at the left of a wide window. Every icon takes `width`; a row lines up along its top.
struct DeskRows: Layout {
    var width: CGFloat
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private func columns(in available: CGFloat?) -> Int {
        guard let available, available.isFinite else { return 6 }
        return max(1, Int((available + spacing) / (width + spacing)))
    }

    private func rows(_ subviews: Subviews, columns: Int) -> [[LayoutSubviews.Element]] {
        stride(from: 0, to: subviews.count, by: columns).map { Array(subviews[$0..<min($0 + columns, subviews.count)]) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let count = columns(in: proposal.width)
        let lines = rows(subviews, columns: count)
        let heights = lines.map { $0.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }.max() ?? 0 }
        let used = CGFloat(min(count, subviews.count)) * (width + spacing) - spacing
        return CGSize(width: proposal.width ?? max(0, used),
                      height: heights.reduce(0, +) + CGFloat(max(0, lines.count - 1)) * lineSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = columns(in: bounds.width)
        var y = bounds.minY
        for line in rows(subviews, columns: count) {
            let used = CGFloat(line.count) * (width + spacing) - spacing
            var x = bounds.midX - used / 2
            var tallest: CGFloat = 0
            for view in line {
                let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
                view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: size.height))
                tallest = max(tallest, size.height)
                x += width + spacing
            }
            y += tallest + lineSpacing
        }
    }
}

/// The button that listens: Lamp's light as a round glow, which breathes with the voice while it listens.
struct TalkButton: View {
    let listening: Bool
    let level: Double
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if listening {
                    // The halo grows with the voice.
                    Circle()
                        .fill(RadialGradient(colors: [Self.glow.opacity(0.55), .clear], center: .center, startRadius: 18, endRadius: 46))
                        .frame(width: 92, height: 92)
                        .scaleEffect(1 + level * 0.45)
                        .animation(.easeOut(duration: 0.12), value: level)
                }
                TimelineView(.animation(paused: !listening)) { context in
                    let turn = listening ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6 : 0
                    Circle()
                        .fill(AngularGradient(colors: Self.colors, center: .center, angle: .degrees(turn * 360)))
                        .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.45), .clear], center: .center,
                                                              startRadius: 0, endRadius: 26)))
                }
                .frame(width: 52, height: 52)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .shadow(color: Self.glow.opacity(listening ? 0.6 : 0.3), radius: listening ? 14 : 8, y: 3)
                .scaleEffect(listening ? 1 + level * 0.12 : hovered ? 1.05 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: level)
                Image(systemName: listening ? "waveform" : "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, isActive: listening)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            }
            .frame(width: 60, height: 60)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovered)
        .help(listening ? "Stop listening" : "Say your wish")
        .accessibilityLabel(listening ? "Stop listening" : "Say your wish")
    }

    /// The colors of the wish icon's dusk, going round.
    private static let colors = [Color(red: 1.0, green: 0.72, blue: 0.36), Color(red: 0.95, green: 0.45, blue: 0.45),
                                 Color(red: 0.55, green: 0.38, blue: 0.85), Color(red: 0.35, green: 0.55, blue: 0.95),
                                 Color(red: 1.0, green: 0.72, blue: 0.36)]
    private static let glow = Color(red: 1.0, green: 0.62, blue: 0.3)
}

/// One wish on the desk: its icon, its name, and under it where it lives or what it's waiting for. A click
/// uses it (`Store.use`); a wish still coming true, or one with a question for the person, opens its chat.
struct DeskIcon: View {
    @EnvironmentObject private var store: Store
    let project: LampProject
    @State private var hovered = false
    @State private var place: WishPlace?

    private var busy: Bool { store.busy.contains(project.id) }

    /// What's under the name: what's going on with it, else where it lives.
    private var caption: String? {
        if busy { return store.progress[project.id]?.newApp == true || project.untitled ? "Coming true…" : "Changing…" }
        if Talk.open(in: store.logs[project.id] ?? []) != nil { return "Has a question" }
        if store.queued[project.id]?.isEmpty == false { return "Waiting to start" }
        if project.finding { return "Finding a wish" }
        if store.unread.contains(project.id) { return "Ready" }
        return place?.caption
    }

    var body: some View {
        Button { store.use(project) } label: {
            VStack(spacing: 6) {
                AppIcon(project: project, size: 76)
                    .overlay(alignment: .topTrailing) {
                        if busy {
                            ProgressView().controlSize(.small)
                                .padding(3)
                                .background(.regularMaterial, in: Circle())
                                .offset(x: 2, y: -2)
                        } else if store.unread.contains(project.id) {
                            ReadyDot(size: 12)
                                .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                                .offset(x: -2, y: 2)
                        }
                    }
                    .scaleEffect(hovered ? 1.06 : 1)
                    .offset(y: hovered ? -2 : 0)
                Text(project.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.tail)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8).padding(.horizontal, 4)
            .background(Color.primary.opacity(hovered ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
        .background(ShareAnchor(origin: .app(project.id)))
        .contextMenu {
            Button("Change…") { store.showChat(project.id) }
            Divider()
            AppMenu(project: project)
        }
        .help(project.title)
        .accessibilityLabel(project.title)
        .accessibilityHint(caption ?? "")
        // Read again as a turn ends: a change can move it, say, into the menu bar.
        .task(id: busy) {
            let current = project
            place = await Task.detached { WishPlace.of(current) }.value
        }
    }
}

/// Where a wish lives once it's made, read from its files: for its caption on the desk, and for what the desk
/// says when it's used and nothing comes to the front to say so itself.
enum WishPlace: Equatable {
    case window, menuBar, widget, background, iPhone, iPhoneAndWatch, everywhere

    /// Reads the app's files: not on the main thread.
    static func of(_ project: LampProject) -> WishPlace {
        switch project.platform {
        case .iphone: return Template.hasWatch(project) ? .iPhoneAndWatch : .iPhone
        case .universal: return .everywhere
        case .mac: break
        }
        if Template.isWidgetOnly(project) { return .widget }
        let code = sources(of: project)
        if code.contains("LampMenuBar(") { return .menuBar }
        if Template.Capabilities.load(project).background == true, !code.contains("WindowGroup"), !code.contains("Window(") {
            return .background
        }
        return .window
    }

    /// The app's own code, Lamp's support file, comments and strings left out.
    private static func sources(of project: LampProject) -> String {
        let folder = project.dir.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return files.filter { $0.pathExtension == "swift" && $0.lastPathComponent != "LampSupport.swift" }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .map(Template.code(in:))
            .joined(separator: "\n")
    }

    var caption: String? {
        switch self {
        case .window: nil
        case .menuBar: "Menu bar"
        case .widget: "Widget"
        case .background: "In the background"
        case .iPhone: "iPhone"
        case .iPhoneAndWatch: "iPhone and watch"
        case .everywhere: "Mac and iPhone"
        }
    }

    var symbol: String {
        switch self {
        case .window: "macwindow"
        case .menuBar: "menubar.arrow.up.rectangle"
        case .widget: "widget.small"
        case .background: "gearshape.2"
        case .iPhone: "iphone"
        case .iPhoneAndWatch: "applewatch"
        case .everywhere: "laptopcomputer.and.iphone"
        }
    }
}

/// The desk's backdrop: the window's own color, lit from above by the lamp.
struct DeskBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { area in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.45).opacity(scheme == .dark ? 0.22 : 0.35), .clear],
                               center: UnitPoint(x: 0.5, y: -0.05), startRadius: 0, endRadius: max(area.size.width, area.size.height) * 0.7)
                RadialGradient(colors: [Color(red: 0.55, green: 0.42, blue: 0.85).opacity(scheme == .dark ? 0.18 : 0.12), .clear],
                               center: UnitPoint(x: 0.9, y: 1.05), startRadius: 0, endRadius: max(area.size.width, area.size.height) * 0.6)
            }
        }
    }
}

/// Lets the desk's light run up behind the title bar, where macOS allows it.
private struct ClearToolbar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}

/// What the desk says when a wish is used and nothing comes forward to show it: a large, translucent square in
/// the middle of the screen, as macOS once showed the volume, with the wish's icon and a few words. It takes
/// no clicks and goes by itself.
@MainActor
enum WishHUD {
    private static var panel: NSPanel?
    private static var hiding: DispatchWorkItem?

    static func show(icon: NSImage?, symbol: String, title: String, detail: String? = nil) {
        hiding?.cancel()
        let panel = panel ?? make()
        Self.panel = panel
        let view = HUDContent(icon: icon, symbol: symbol, title: title, detail: detail)
        let host = NSHostingView(rootView: view)
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 22
        effect.layer?.masksToBounds = true
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor), host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor), host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
        // Where the volume used to show: centered, in the lower part of the screen in use.
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.2))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        let hide = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.5
                panel.animator().alphaValue = 0
            }, completionHandler: { if panel.alphaValue == 0 { panel.orderOut(nil) } })
        }
        hiding = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: hide)
    }

    private static func make() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 220),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        return panel
    }

    private struct HUDContent: View {
        let icon: NSImage?
        let symbol: String
        let title: String
        let detail: String?

        var body: some View {
            VStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let icon {
                            Image(nsImage: icon).resizable().interpolation(.high)
                        } else {
                            Image(systemName: symbol).resizable().scaledToFit().padding(10)
                        }
                    }
                    .frame(width: 104, height: 104)
                    if icon != nil {
                        Image(systemName: symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(.thickMaterial, in: Circle())
                            .offset(x: 6, y: 4)
                    }
                }
                VStack(spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    if let detail {
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                }
            }
            .padding(18)
            .frame(width: 220, height: 220)
            .foregroundStyle(.primary)
        }
    }
}

extension Store {
    /// A wish clicked on the desk: used when it's made and nothing's waiting on it, else its chat is shown.
    /// Where opening it brings nothing to the front (the menu bar, a widget, the background, the person's own
    /// phone), the desk says where it is.
    func use(_ project: LampProject) {
        let made = FileManager.default.fileExists(atPath: project.installedURL.path)
            || FileManager.default.fileExists(atPath: project.builtURL.path)
        guard made, !project.finding, !busy.contains(project.id), Talk.open(in: logs[project.id] ?? []) == nil,
              queued[project.id]?.isEmpty != false else {
            return showChat(project.id)
        }
        unread.remove(project.id)
        Task {
            let place = await Task.detached { WishPlace.of(project) }.value
            let icon = icons[project.id]
            switch place {
            case .widget:
                // Nothing to open: the widget is the wish.
                if placedWidgets.contains(project.id) {
                    WishHUD.show(icon: icon, symbol: place.symbol, title: "\(project.name) is on your desktop.")
                } else {
                    WishHUD.show(icon: icon, symbol: place.symbol, title: "Add \(project.name) to your desktop.",
                                 detail: "Right-click the desktop and choose Edit Widgets.")
                }
                return
            case .menuBar:
                WishHUD.show(icon: icon, symbol: place.symbol, title: "\(project.name) is in your menu bar.")
            case .background:
                WishHUD.show(icon: icon, symbol: place.symbol, title: "\(project.name) is running in the background.")
            case .iPhone, .iPhoneAndWatch, .everywhere:
                if project.onIOS, project.device != nil {
                    WishHUD.show(icon: icon, symbol: "iphone", title: "\(project.name) is opening on your iPhone.")
                }
            case .window:
                break
            }
            openPrepared(project)
        }
    }
}
