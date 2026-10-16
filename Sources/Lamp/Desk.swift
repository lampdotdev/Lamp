import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Lamp's home: the person's wishes laid out like a desktop, and the place to make a new one, by typing it,
/// saying it, or finding it with the agent's help. A click on a wish opens it, with its chat beside it.
struct WishDesk: View {
    @EnvironmentObject private var store: Store
    @StateObject private var dictation = Dictation()
    @State private var hasMicrophone = true
    @FocusState private var barFocused: Bool
    /// Drawn once, so they don't change under the reader.
    @State private var ideas: [Idea] = []
    /// The ideas under the bar, opened by "Not sure?", and open from the start on an empty desk.
    @State private var showingIdeas = false
    @State private var notSureHovered = false
    /// The room a scroll bar takes: none where scroll bars only show over the content while scrolling.
    @State private var scrollerWidth = WishDesk.scrollerWidth()
    /// How the desk moves when the ideas open or close and wishes come and go: everything on it together,
    /// as one change, so nothing jumps ahead of the rest.
    private static let glide = Animation.spring(response: 0.45, dampingFraction: 0.86)

    /// A wish not yet told is thrown away as the desk comes back (`discardIfUnused`): the rest are on the desk.
    private var wishes: [LampProject] { store.projects }

    var body: some View {
        ZStack {
            DeskBackground().ignoresSafeArea()
            GeometryReader { area in
                ScrollView {
                    // In the middle of the window while it fits, gliding to its new place as ideas open or
                    // close and wishes come and go; from the top, scrolling, once it doesn't.
                    // The wishes come first: using one and changing it is where most wishes start, and a new
                    // one is the way on from there.
                    VStack(spacing: 0) {
                        Text(wishes.isEmpty ? "What do you wish for?" : "Use one, change one, or wish for something new.")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        if !wishes.isEmpty {
                            grid.padding(.top, 36)
                        }
                        header.padding(.top, wishes.isEmpty ? 18 : 40)
                        if showingIdeas && !ideas.isEmpty {
                            DeskIdeas(ideas: ideas, choose: choose, find: store.findWish)
                                .padding(.top, 28)
                                .padding(.horizontal, 32)
                                .transition(.modifier(active: MiddleOut(shown: 0), identity: MiddleOut(shown: 1)))
                        }
                    }
                    .padding(.vertical, 40)
                    // Laid out as if the scroll bar were always there: when one comes and goes as the ideas
                    // open, the desk would otherwise move sideways by its width.
                    .frame(width: max(0, area.size.width - scrollerWidth))
                    .frame(maxWidth: .infinity, minHeight: area.size.height, alignment: .leading)
                    .animation(Self.glide, value: wishes.map(\.id))
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Lamp")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                    .help("Settings (⌘,)")
            }
        }
        .modifier(ClearToolbar())
        // Drawn on Lamp's light page, as in the welcome, whatever the Mac's appearance.
        .environment(\.colorScheme, .light)
        .onAppear {
            hasMicrophone = Dictation.hasMicrophone
            if ideas.isEmpty { ideas = Ideas.starters(made: store.projects.filter { !$0.untitled }.map(\.name)) }
            if wishes.isEmpty { showingIdeas = true }
            barFocused = true
        }
        .onChange(of: store.deskFocusRequest) { barFocused = true }
        // Plugging in a mouse, or changing Show Scroll Bars, changes it.
        .onReceive(NotificationCenter.default.publisher(for: NSScroller.preferredScrollerStyleDidChangeNotification)) { _ in
            scrollerWidth = Self.scrollerWidth()
        }
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
            HStack(alignment: .center, spacing: 14) {
                bar
                if hasMicrophone {
                    TalkButton(listening: dictation.isListening, level: dictation.level, action: toggleTalk)
                }
            }
            .frame(maxWidth: 600)
            .padding(.horizontal, 32)
            Button { withAnimation(Self.glide) { showingIdeas.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb")
                    Text("Not sure what to wish for?")
                    Image(systemName: "chevron.down")
                        .font(.callout.weight(.semibold))
                        .rotationEffect(.degrees(showingIdeas ? 180 : 0))
                }
                .font(.title3.weight(.medium))
                .padding(.horizontal, 20).padding(.vertical, 11)
                .background(Color.white.opacity(notSureHovered ? 0.95 : 0.72), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(notSureHovered ? 0.2 : 0.1), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary.opacity(0.8))
            .onHover { notSureHovered = $0 }
            .help(showingIdeas ? "Hide the ideas" : "Show some ideas, or have Lamp help you find your wish")
        }
    }

    private var bar: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField(dictation.isListening ? "Listening…" : wishes.isEmpty ? "Type a wish…" : "Wish for something new…", text: $store.deskDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                .lineLimit(1...5)
                .focused($barFocused)
                .onSubmit { send() }
            if !store.deskDraft.trimmed.isEmpty {
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
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.deskDraft.trimmed.isEmpty)
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

    static func scrollerWidth() -> CGFloat {
        NSScroller.preferredScrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
    }

    /// An idea goes in the bar to be made the person's own, and the ideas step aside for it.
    private func choose(_ wish: String) {
        store.deskDraft = wish
        withAnimation(Self.glide) { showingIdeas = false }
        barFocused = true
    }

    /// The words heard go in the bar, after whatever was typed; the person sends them when they look right.
    private func toggleTalk() {
        if dictation.isListening {
            dictation.stop()
            barFocused = true
            return
        }
        let typed = store.deskDraft
        let separator = typed.isEmpty || typed.last!.isWhitespace ? "" : " "
        Task {
            await dictation.start { heard, _ in store.deskDraft = typed + separator + heard }
        }
    }

    private func send() {
        let wish = store.deskDraft.trimmed
        guard !wish.isEmpty else { return }
        let spoken = dictation.isListening
        dictation.cancel()
        store.deskDraft = ""
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

/// The ideas open from their middle outward, their edges feathered as they go, rather than sliding in from
/// somewhere: a band across the middle that widens until it holds them all, and narrows again as they close.
private struct MiddleOut: ViewModifier, Animatable {
    var shown: Double
    var animatableData: Double {
        get { shown }
        set { shown = newValue }
    }

    /// How soft the band's edges are, as a share of the ideas' height.
    private static let feather = 0.22

    func body(content: Content) -> some View {
        // Half the band, reaching past the edges once fully shown so that no feather is left on them.
        let half = shown * (0.5 + Self.feather)
        let solid = max(0, half - Self.feather)
        content
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0.5 - half), .init(color: .black, location: 0.5 - solid),
                                       .init(color: .black, location: 0.5 + solid), .init(color: .clear, location: 0.5 + half)],
                               startPoint: .top, endPoint: .bottom)
            }
            .scaleEffect(0.96 + 0.04 * shown)
            .opacity(min(1, shown * 1.6))
    }
}

/// The ideas "Not sure?" opens: a few wishes someone might have, each put in the bar when chosen, and last
/// the way to find one's own with Lamp, in a new wish's chat (`Store.findWish`).
struct DeskIdeas: View {
    let choose: (String) -> Void
    let find: () -> Void
    @StateObject private var deck: IdeaDeck
    @State private var hovered: String?

    /// Five ideas and the finder make two rows of three.
    private static let shown = 5
    private static let finder = "finder"

    init(ideas: [Idea], choose: @escaping (String) -> Void, find: @escaping () -> Void) {
        self.choose = choose
        self.find = find
        _deck = StateObject(wrappedValue: IdeaDeck(first: ideas))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                ForEach(Array(deck.ideas.prefix(Self.shown).enumerated()), id: \.element.id) { index, idea in
                    Button { choose(idea.blurb) } label: {
                        card(lit: hovered == idea.title) {
                            IdeaIcon(symbol: idea.symbol, hue: idea.hue, size: 26)
                            Text(idea.blurb).font(.subheadline)
                                .lineLimit(4, reservesSpace: true)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 ? idea.title : (hovered == idea.title ? nil : hovered) }
                    .help("Puts this in the box so you can change it before sending")
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94)).animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.04)),
                        removal: .opacity.animation(.easeOut(duration: 0.15))))
                }
                Button(action: find) {
                    card(lit: hovered == Self.finder, accent: true) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 26, height: 26)
                        Text("Help me find my wish")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(4, reservesSpace: true)
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? Self.finder : (hovered == Self.finder ? nil : hovered) }
                .help("Lamp asks a few questions about your days and writes a wish with you")
            }
        }
        .frame(maxWidth: 640)
        .onAppear { deck.prefetch() }
    }

    private func card(lit: Bool, accent: Bool = false, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(accent ? Color.accentColor.opacity(0.1) : Color(nsColor: .textBackgroundColor).opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            // On hover only the outline darkens, as the ideas under a new wish's chat do.
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent ? Color.accentColor.opacity(lit ? 0.6 : 0.35) : Color.primary.opacity(lit ? 0.2 : 0.1), lineWidth: 1))
            .contentShape(Rectangle())
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

/// One wish on the desk: its icon, its name, and under it where it lives or what it's waiting for. A click opens
/// it, with its chat beside it to change it (`Store.open(fromDesk:)`).
struct DeskIcon: View {
    @EnvironmentObject private var store: Store
    let project: LampProject
    @State private var hovered = false
    @State private var place: WishPlace?

    private var busy: Bool { store.busy.contains(project.id) }

    /// What's under the name: what's going on with it, else, while the pointer is on it, what a click does,
    /// else where it lives.
    private var caption: String? {
        if let status { return status }
        return hovered ? "Open and change" : place?.caption
    }

    private var status: String? {
        // A wish Lamp came with, built for the first time out of sight: nothing shows until it's clicked, and then it
        // says it's opening, which it does by itself once it's ready.
        if store.openWhenReady.contains(project.id) { return "Opening…" }
        if store.preparing.contains(project.id) { return nil }
        if busy { return store.progress[project.id]?.newApp == true || project.untitled ? "Coming true…" : "Changing…" }
        if Talk.waiting(in: store.logs[project.id] ?? []) != nil { return "Has a question" }
        if store.queued[project.id]?.isEmpty == false { return "Waiting to start" }
        if project.finding { return "Finding a wish" }
        if store.unread.contains(project.id) { return "Ready" }
        return nil
    }

    var body: some View {
        VStack(spacing: 6) {
            AppIcon(project: project, size: 76)
                .overlay(alignment: .topTrailing) {
                    if busy && !store.preparing.contains(project.id) || store.openWhenReady.contains(project.id) {
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
            // Its line is always kept, so the hint coming and going on hover never moves the icons below.
            Text(caption ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityHidden(caption == nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8).padding(.horizontal, 4)
        .background(Color.primary.opacity(hovered ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { store.open(fromDesk: project) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.open(fromDesk: project) }
        .accessibilityAction(named: "Use") { store.use(project) }
        // With keyboard navigation on, Tab reaches it, and Return opens it.
        .focusable(interactions: .activate)
        .onKeyPress(.return) { store.open(fromDesk: project); return .handled }
        .onHover { hovered = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
        .background(ShareAnchor(origin: .app(project.id)))
        .background(WishDrag(project: project))
        .contextMenu {
            Button("Open") { store.open(fromDesk: project) }
            Button("Change…") { store.change(project) }
            Divider()
            AppMenu(project: project)
        }
        .help("Click to use \(project.title) and change it")
        .accessibilityLabel(project.title)
        .accessibilityHint(status ?? place?.caption ?? "")
        // Read again as a turn ends: a change can move it, say, into the menu bar.
        .task(id: busy) {
            let current = project
            place = await Task.detached { WishPlace.of(current) }.value
        }
    }
}

/// A wish dragged off the desk. Dropped on the Trash it's deleted, as Delete… does once asked (the Trash gives it
/// back); in the Dock or the Applications folder it's the app itself; anywhere else it's the wish's shared file,
/// as Share… makes it. A wish being changed stays where it is. Behind the icon and never in its way, so a click,
/// a double click and the menu stay SwiftUI's: the drag is started from the window's own mouse events.
private struct WishDrag: NSViewRepresentable {
    @EnvironmentObject private var store: Store
    let project: LampProject

    func makeNSView(context: Context) -> Source { Source(store: store, project: project) }
    func updateNSView(_ view: Source, context: Context) { view.project = project }

    final class Source: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
        private let store: Store
        var project: LampProject
        private var monitor: Any?
        private var pressed: NSEvent?
        /// What one drag hands over, made once whichever way the other app asks for it.
        private var payload: Payload?
        private weak var session: NSDraggingSession?

        init(store: Store, project: LampProject) {
            self.store = store
            self.project = project
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            switch event.type {
            case .leftMouseDown:
                // Only a plain press on this icon, in a window with nothing over it: a control-click is the menu.
                let inside = event.window === window && window?.attachedSheet == nil
                    && bounds.contains(convert(event.locationInWindow, from: nil))
                pressed = inside && !event.modifierFlags.contains(.control) && !store.busy.contains(project.id) ? event : nil
            case .leftMouseDragged:
                guard let pressed else { break }
                let moved = hypot(event.locationInWindow.x - pressed.locationInWindow.x,
                                  event.locationInWindow.y - pressed.locationInWindow.y)
                guard moved > 4 else { break }
                self.pressed = nil
                // A turn may have begun since the press.
                guard !store.busy.contains(project.id) else { break }
                begin(from: pressed)
                return nil
            default:
                pressed = nil
            }
            return event
        }

        private func begin(from event: NSEvent) {
            let writer: NSPasteboardWriting
            if store.canShare(project) {
                let installed = project.platform.hasMac && FileManager.default.fileExists(atPath: project.installedURL.path)
                    ? project.installedURL : nil
                let payload = Payload(project: project, app: installed) { [weak self] in self?.publish() }
                self.payload = payload
                writer = Promise(payload: payload, name: "\(project.name).lampapp", delegate: self)
            } else {
                // A draft has nothing to share yet, but can still go to the Trash.
                payload = nil
                let item = NSPasteboardItem()
                item.setString(project.id, forType: Self.wishType)
                writer = item
            }
            let item = NSDraggingItem(pasteboardWriter: writer)
            let size = CGSize(width: 76, height: 76)
            let point = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size),
                                  contents: store.iconImage(for: project))
            session = beginDraggingSession(with: [item], event: event, source: self)
        }

        static let wishType = NSPasteboard.PasteboardType("dev.lamp.wish")

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            // Inside Lamp a wish's file has nowhere to go: dropped on a chat it would only be an attachment.
            guard context == .outsideApplication else { return [] }
            return payload == nil ? .delete : [.copy, .link, .delete]
        }

        func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
            guard let payload, payload.app != nil else { return }
            let overDock = Payload.dockIsUnder(screenPoint)
            guard overDock != payload.overDock else { return }
            payload.overDock = overDock
            publish()
        }

        /// Apps that take a file by its address (the Dock, Slack, most mail apps) read it from the drag as they please,
        /// so the drag gives one only for what exists: the app while it's over the Dock, the shared file once it's
        /// written, and none between (off the Dock before the file is whole, or when it couldn't be made). An address
        /// can be added to a drag under way and changed in it, but not taken out, so none is an empty one; Finder's
        /// promise stays as it was.
        private func publish() {
            guard let session, let payload, payload.address != payload.published else { return }
            let url = payload.address
            payload.published = url
            let pasteboard = session.draggingPasteboard
            if let url, let list = (url as NSURL).pasteboardPropertyList(forType: .fileURL) {
                pasteboard.setPropertyList(list, forType: .fileURL)
            } else {
                pasteboard.setData(Data(), forType: .fileURL)
            }
            pasteboard.setPropertyList(url.map { [$0.path] } ?? [], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            payload = nil
            guard operation == .delete, let wish = store.projects.first(where: { $0.id == project.id }) else { return }
            Task { await store.delete(wish) }
        }

        // The file promise, for Finder, Mail, Messages and the rest that take one: written on a queue of its own,
        // so the drop never waits on the main thread.
        nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
            (provider as? Promise)?.name ?? "Wish.lampapp"
        }

        nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                                             completionHandler: @escaping (Error?) -> Void) {
            guard let payload = (provider as? Promise)?.payload else { return completionHandler(CocoaError(.fileNoSuchFile)) }
            do {
                if let app = payload.app, Payload.isApplications(url.deletingLastPathComponent()) {
                    try Payload.alias(to: app, in: url.deletingLastPathComponent())
                } else {
                    try? FileManager.default.removeItem(at: url)
                    try FileManager.default.copyItem(at: try payload.sharedFile(), to: url)
                }
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }

        nonisolated func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue { Source.queue }

        nonisolated private static let queue: OperationQueue = {
            let queue = OperationQueue()
            queue.qualityOfService = .userInitiated
            return queue
        }()
    }

    /// What a drag hands over: the wish's shared file, or the app itself where an app belongs. The file is begun as
    /// the drag starts, in the background, in a folder of the drag's own so nothing stale is ever there.
    final class Payload: @unchecked Sendable {
        /// The installed Mac app, when there is one.
        let app: URL?
        /// Whether the pointer is over the Dock.
        @MainActor var overDock = false
        /// The shared file, once it's whole.
        @MainActor private var written: URL?
        /// What the drag last gave as its address.
        @MainActor var published: URL?
        private let made = DispatchGroup()
        private var result: Result<URL, Error>?

        init(project: LampProject, app: URL?, whenWritten: @escaping @MainActor () -> Void) {
            self.app = app
            let file = Store.sharedFolder.appendingPathComponent(UUID().uuidString).appendingPathComponent("\(project.name).lampapp")
            made.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let result = Result { try Store.sharedFile(of: project, at: file) }
                self.result = result
                made.leave()
                DispatchQueue.main.async {
                    switch result {
                    case .success(let url):
                        self.written = url
                        whenWritten()
                    case .failure(let error):
                        NSAlert(error: error).runModal()
                    }
                }
            }
        }

        /// The address the drag gives now, if any.
        @MainActor var address: URL? { overDock && app != nil ? app : written }

        /// The .lampapp, once it's written. A failure is told once, as Share… tells it: the app it was dropped on
        /// only gets nothing.
        func sharedFile() throws -> URL {
            made.wait()
            return try result!.get()
        }

        /// Whether the Dock is under a point on screen. Nothing in a drag says where it is, and the Dock settles what
        /// it's being given (an app among the apps, a file beside the Trash) as soon as it's reached, so this goes by
        /// where the Dock sits rather than by its window, which a hidden Dock shows only once it's out.
        static func dockIsUnder(_ point: NSPoint) -> Bool {
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return false }
            let dock = UserDefaults(suiteName: "com.apple.dock")
            let frame = screen.frame, visible = screen.visibleFrame
            // How far in the point is from the Dock's edge, and how much of the screen a Dock that stays keeps.
            let inset: CGFloat, depth: CGFloat
            switch side(of: dock) {
            case "left": (inset, depth) = (point.x - frame.minX, visible.minX - frame.minX)
            case "right": (inset, depth) = (frame.maxX - point.x, frame.maxX - visible.maxX)
            default: (inset, depth) = (point.y - frame.minY, visible.minY - frame.minY)
            }
            let tile = CGFloat(dock?.double(forKey: "tilesize") ?? 0)
            let icons = tile > 0 ? tile : 48
            // Far from the edge it's the window there, without asking anything more.
            guard inset <= (depth > 4 ? depth : icons + 24) else { return false }
            // Along the edge the Dock is only as long as what it holds: past its ends is the desktop. Where Lamp may
            // ask the Dock (Accessibility, which trying iPhone apps asks for) it says where its icons are, hidden or
            // not; else it's centred, as long as an estimate from what it holds.
            let bottom = side(of: dock) == "bottom"
            let along = bottom ? point.x : point.y
            if let span = span(bottom: bottom) {
                guard along >= span.lowerBound - icons, along <= span.upperBound + icons else { return false }
            } else {
                guard abs(along - (bottom ? frame.midX : frame.midY)) <= length(of: dock, icons: icons) / 2 else { return false }
            }
            if depth > 4 { return inset <= depth }
            // A Dock that hides comes out when the pointer reaches the edge, about as deep as its icons, and only while
            // it's out is the strip beside the edge the Dock rather than the window behind it.
            return inset <= 1 || inset <= icons + 24 && dockIsOut()
        }

        /// Where the Dock's icons run along its edge, as the Dock itself says.
        private static func span(bottom: Bool) -> ClosedRange<CGFloat>? {
            guard AXIsProcessTrusted(),
                  let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
            else { return nil }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.1)
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success,
                  let list = (children as? [AXUIElement])?.first(where: { element in
                      var role: CFTypeRef?
                      AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
                      return role as? String == kAXListRole
                  }) else { return nil }
            var position: CFTypeRef?, size: CFTypeRef?
            var origin = CGPoint.zero, extent = CGSize.zero
            guard AXUIElementCopyAttributeValue(list, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(list, kAXSizeAttribute as CFString, &size) == .success,
                  let position, let size,
                  AXValueGetValue(position as! AXValue, .cgPoint, &origin),
                  AXValueGetValue(size as! AXValue, .cgSize, &extent),
                  extent.width > 0, extent.height > 0 else { return nil }
            if bottom { return origin.x...(origin.x + extent.width) }
            // Accessibility measures from the top of the main screen; the screen from its bottom.
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            return (top - origin.y - extent.height)...(top - origin.y)
        }

        private static func side(of dock: UserDefaults?) -> String {
            dock?.string(forKey: "orientation").flatMap { ["left", "right"].contains($0) ? $0 : nil } ?? "bottom"
        }

        /// Without Accessibility, about how long the Dock is: its icons (Finder, the apps kept in it and the others open, recent ones when
        /// it shows them, its files and folders, the Trash) and the space between its sections, with an icon's room
        /// at each end for the pointer's sake and for magnified icons. Over rather than under: past the ends is only a
        /// strip of desktop a hand's width from the edge.
        private static func length(of dock: UserDefaults?, icons: CGFloat) -> CGFloat {
            let kept = (dock?.array(forKey: "persistent-apps") as? [[String: Any]] ?? [])
                .compactMap { ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String }
            let open = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && !kept.contains($0.bundleIdentifier ?? "") && $0.bundleIdentifier != "com.apple.finder" }
            let recent = dock?.object(forKey: "show-recents") as? Bool ?? true ? (dock?.array(forKey: "recent-apps")?.count ?? 0) : 0
            let others = dock?.array(forKey: "persistent-others")?.count ?? 0
            let count = 1 + kept.count + open.count + recent + others + 1
            return CGFloat(count) * icons * 1.25 + icons * 4
        }

        /// The Dock's window is on screen only while the Dock is.
        private static func dockIsOut() -> Bool {
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            return windows.contains { window in
                guard let pid = window[kCGWindowOwnerPID as String] as? pid_t else { return false }
                return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock"
                    && window[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.dockWindow))
            }
        }

        static func isApplications(_ folder: URL) -> Bool {
            let folders = FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
            return folders.contains { $0.standardizedFileURL.resolvingSymlinksInPath() == folder.standardizedFileURL.resolvingSymlinksInPath() }
        }

        /// An alias to the app rather than the app: Lamp keeps the app where it builds it, and a copy moved away
        /// would be left behind by the next change.
        static func alias(to app: URL, in folder: URL) throws {
            let name = app.deletingPathExtension().lastPathComponent
            var target = folder.appendingPathComponent(name)
            var count = 2
            while FileManager.default.fileExists(atPath: target.path) {
                target = folder.appendingPathComponent("\(name) \(count)")
                count += 1
            }
            let bookmark = try app.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
            try URL.writeBookmarkData(bookmark, to: target)
        }
    }

    /// The promise Finder takes. The file's address, for the apps that read only that, is added to the drag once it
    /// exists (`publish`).
    final class Promise: NSFilePromiseProvider {
        let payload: Payload
        let name: String

        init(payload: Payload, name: String, delegate: NSFilePromiseProviderDelegate) {
            self.payload = payload
            self.name = name
            super.init()
            fileType = UTType.lampApp.identifier
            self.delegate = delegate
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
        // An app with a window lives there, whatever else it has: one with a menu bar item beside its window opens
        // its window, and its chat goes beside it.
        let hasWindow = code.contains("WindowGroup") || code.contains("Window(")
        if code.contains("LampMenuBar("), !hasWindow { return .menuBar }
        if Template.Capabilities.load(project).background == true, !hasWindow { return .background }
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

/// The desk's backdrop: Lamp's page, as in the welcome.
struct DeskBackground: View {
    var body: some View {
        Color(nsColor: LampBackdrop.page)
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
    /// Change… on a wish: its chat beside it in its own window, opening it when it's closed, for a Mac app with
    /// windows that has been made; anything else (a wish still being found, a menu bar app, a widget, an iPhone
    /// app) in Lamp's window.
    func change(_ project: LampProject) {
        Task {
            guard !project.finding, FileManager.default.fileExists(atPath: project.installedURL.path),
                  await MagicPanel.chatsInApp(project) else { return showChat(project.id) }
            let running = !macCopies(of: project).isEmpty
            // A copy built before the chat could be asked for this way keeps its chat in Lamp's window.
            guard !running || MagicPanel.runningCopiesTakeTheChat(project) else { return showChat(project.id) }
            unread.remove(project.id)
            // A wish Lamp came with, opened for the first time, is seen on its own a moment before its chat comes.
            if running || !MagicPanel.shared.startWithChat(project) { MagicPanel.shared.openChat(in: project) }
            if !running { openPrepared(project) }
        }
    }

    /// A wish clicked on the desk: it opens with its chat beside it, to use
    /// and to change at once, as a document opens ready to edit (`change`). A wish that opens no window (the menu
    /// bar, a widget, the background, a phone) is used instead (`use`), and the desk says where it is. A wish Lamp
    /// came with that isn't built yet spins and opens when it's ready.
    func open(fromDesk project: LampProject) {
        let made = FileManager.default.fileExists(atPath: project.installedURL.path)
            || FileManager.default.fileExists(atPath: project.builtURL.path)
        if !made, setup.hasBuildTools, preparing.contains(project.id) || needsPreparing(project) {
            openWhenReady.insert(project.id)
            prepareStarters()
            return
        }
        Task {
            let place = await Task.detached { WishPlace.of(project) }.value
            guard place == .window, project.platform == .mac else { return use(project) }
            change(project)
        }
    }

    /// A wish double-clicked on the desk: used when it's made and nothing's waiting on it, else its chat is shown.
    /// Where opening it brings nothing to the front (the menu bar, a widget, the background, the person's own
    /// phone), the desk says where it is.
    func use(_ project: LampProject) {
        let made = FileManager.default.fileExists(atPath: project.installedURL.path)
            || FileManager.default.fileExists(atPath: project.builtURL.path)
        // A wish Lamp came with that hasn't been built yet, or is being built now: its icon spins, and it
        // opens as soon as it's ready, without its chat in between.
        if !made, setup.hasBuildTools, preparing.contains(project.id) || needsPreparing(project) {
            openWhenReady.insert(project.id)
            prepareStarters()
            return
        }
        guard made, !project.finding, !busy.contains(project.id), Talk.waiting(in: logs[project.id] ?? []) == nil,
              queued[project.id]?.isEmpty != false else {
            return showChat(project.id)
        }
        unread.remove(project.id)
        let firstUse = Starters.isFirstUse(project)
        Task {
            let place = await Task.detached { WishPlace.of(project) }.value
            let icon = icons[project.id]
            // A window's chat opens beside it (`MagicPanel.startWithChat`); anything else has its chat opened here, behind
            // the app, the first time it's used.
            if firstUse, place != .window { showChat(project.id) }
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
