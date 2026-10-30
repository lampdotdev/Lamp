import SwiftUI
import AppKit
import LampSidebarKit
import AVFoundation

/// Lamp's home: every wish in one list (what Lamp came with and what the person made, remixes under their originals),
/// the place to make a new one, by typing it, saying it, or finding it with the agent's help, and the person's devices
/// down the side. Open uses a wish, with its chat beside it; Remix changes it in place; Duplicate…, in its menu, makes
/// a new copy of it to become something else.
struct WishDesk: View {
    @EnvironmentObject private var store: Store
    @StateObject private var dictation = Dictation()
    @State private var hasMicrophone = true
    @FocusState private var barFocused: Bool
    @State private var dropTargeted = false
    /// The bar's frame in the window, for the chat of a wish sent from it to grow out of.
    @State private var barFrame = CGRect.zero
    /// Drawn once, so they don't change under the reader.
    @State private var ideas: [Idea] = []
    /// The ideas, opened by "Not sure?" beside the bar.
    @State private var showingIdeas = false
    /// What's read of each wish for its row, by id (`DeskEntry`).
    @State private var entries: [String: DeskEntry] = [:]
    @State private var picked: LampProject.ID?
    /// Whether the side panel is showing what the picked wish is, from the toolbar's button.
    @AppStorage("deskPanelShown") private var panelShown = true
    /// The list has the keyboard: the arrows move the pick up and down it.
    @FocusState private var listFocused: Bool
    /// The list's width, which decides whether its rows have room for every column.
    @State private var listWidth: CGFloat = 1000
    private var compact: Bool { listWidth < DeskListRow.compactBelow }
    /// The desk's whole width: the side panel shows only where it leaves the list room for its names.
    @State private var deskWidth: CGFloat = 1200
    private static let panelWidth: CGFloat = 320
    /// The narrowest the list may be with the panel beside it.
    private static let listWithPanel: CGFloat = 420
    private var panelFits: Bool { deskWidth - 220 - 40 - Self.panelWidth >= Self.listWithPanel }
    @AppStorage("deskSort") private var column = DeskList.Column.name
    @AppStorage("deskAscending") private var ascending = true
    /// Lamp has looked on the network before, so macOS has asked about it: from then on the desk looks for devices
    /// each time it's shown (`lookForDevices`).
    @AppStorage(Store.localNetworkAskedKey) private var lookedBefore = false
    @State private var lastLook: Date?
    /// How the side panel comes and goes.
    private static let slide = Animation.spring(response: 0.35, dampingFraction: 0.9)
    /// The line between the side, the list and the panel, from the window's top to its foot, title bar and all.
    private static var separator: some View { Paper.divider.frame(width: 1).ignoresSafeArea() }

    /// Where the side's first line and the bar both start, under the window's title.
    private static let top: CGFloat = 14

    /// A wish not yet told is thrown away as the desk comes back (`discardIfUnused`): the rest are on the desk.
    /// A device's setup conversation isn't a wish: it's reached from the device, in Settings → Your Devices.
    private var wishes: [LampProject] { store.wishes.filter { !$0.isDeviceSetup } }

    private var rows: [DeskList.Row] { DeskList.rows(wishes, entries: entries, by: column, ascending: ascending) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 14) {
                header
                list.onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { listWidth = $0 }
            }
            .padding(.top, Self.top).padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if panelShown, panelFits, let row = rows.first(where: { $0.id == current }) {
                DeskDetail(row: row, remixes: remixes(of: row))
                    .frame(width: Self.panelWidth)
                    .overlay(alignment: .leading) { Self.separator }
                    .transition(.move(edge: .trailing))
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { deskWidth = $0 }
        .animation(Self.slide, value: panelFits)
        .background(DeskBackground().ignoresSafeArea())
        .onChange(of: current, initial: true) { DeskPick.shared.wish = current }
        .navigationTitle("Lamp")
        .toolbar {
            // Only where the panel has room to show: in a narrower window the list keeps the space.
            if panelFits { ToolbarItem(placement: .primaryAction) {
                Button { withAnimation(Self.slide) { panelShown.toggle() } } label: {
                    Label(panelShown ? "Hide Details" : "Show Details", systemImage: "sidebar.right")
                }
                .help(panelShown ? "Hide what the picked wish is" : "Show what the picked wish is")
            } }
        }
        .modifier(ClearToolbar())
        .onAppear {
            hasMicrophone = Dictation.hasMicrophone
            if ideas.isEmpty { ideas = Ideas.starters(made: store.wishes.filter { !$0.untitled }.map(\.name)) }
            barFocused = true
            lookForDevices()
        }
        // Read from the files, once for each change to the wishes and as each turn ends (a change can move a wish to
        // the TV, or give it a new line).
        .task(id: wishes.map(\.id) + store.busy.sorted()) { await readEntries() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in lookForDevices() }
        .onChange(of: store.deskFocusRequest) { barFocused = true }
        .onDisappear {
            dictation.cancel()
            DeskPick.shared.wish = nil
        }
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

    /// The person's devices: what a new wish can be for. Settings at the foot. Its first line starts
    /// where the bar does beside it.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    DeskDevices(wishFor: wishFor)
                }
                .padding(.horizontal, 12).padding(.top, Self.top).padding(.bottom, 20)
            }
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundStyle(Paper.muted)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
            .padding(.leading, 14).padding(.bottom, 12)
        }
        .frame(width: 220)
        .background(Paper.panel)
        .overlay(alignment: .trailing) { Self.separator }
    }

    private var list: some View {
        VStack(spacing: 0) {
            DeskListHeader(column: $column, ascending: $ascending, compact: compact)
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rows) { row in
                            DeskListRow(row: row, selected: row.id == current, compact: compact) {
                                picked = row.id
                                listFocused = true
                            }
                            .id(row.id)
                        }
                        ForEach(store.newerWishes) { NewerWishRow(wish: $0) }
                    }
                    .padding(.top, 6).padding(.bottom, 24)
                }
                .scrollContentBackground(.hidden)
                // Up and down move the pick, the list following it; Return opens it.
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                .onKeyPress(.upArrow) { step(-1, scroller) }
                .onKeyPress(.downArrow) { step(1, scroller) }
                .onKeyPress(.return) {
                    guard let row = rows.first(where: { $0.id == current }) else { return .ignored }
                    store.open(fromDesk: row.project)
                    return .handled
                }
            }
        }
    }

    /// The wish picked: the one clicked or moved to, else the first in the list.
    private var current: LampProject.ID? { rows.contains { $0.id == picked } ? picked : rows.first?.id }

    private func step(_ by: Int, _ scroller: ScrollViewProxy) -> KeyPress.Result {
        let ids = rows.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let at = current.flatMap(ids.firstIndex(of:)) ?? 0
        let next = ids[min(max(at + by, 0), ids.count - 1)]
        picked = next
        scroller.scrollTo(next)
        return .handled
    }

    /// The remixes made here of the row's wish, for its facts.
    private func remixes(of row: DeskList.Row) -> [LampProject] {
        guard let identity = row.entry?.identity else { return [] }
        return wishes.filter { entries[$0.id]?.original == identity && $0.id != row.id }
    }

    private func readEntries() async {
        let read = wishes.map { ($0, store.apps(of: $0)) }
        var found = await Task.detached { read.map { DeskEntry.read($0.0, apps: $0.1) } }.value
        guard !Task.isCancelled else { return }
        entries = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        // Then whether each that arrived from somewhere has been changed since, which asks git: a wish made here has no
        // original to go back to.
        for (index, entry) in found.enumerated() where entry.arrived && !entry.remixedHere {
            guard let project = wishes.first(where: { $0.id == entry.id }) else { continue }
            found[index].changedFromOriginal = await store.original(toStartAgain: project) != nil
            guard !Task.isCancelled else { return }
        }
        entries = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// Something to send: words, or files to make a wish of.
    private var hasWish: Bool { !store.deskDraft.trimmed.isEmpty || !store.deskAttachments.isEmpty }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            bar
            if hasMicrophone {
                TalkButton(listening: dictation.isListening, level: dictation.level, action: toggleTalk)
                    // Laid out no taller than the bar, its round spilling over a little, so the bar starts where the
                    // side's first line does.
                    .frame(height: 42)
            }
            Button { showingIdeas.toggle() } label: {
                Label("Not sure?", systemImage: "lightbulb")
            }
            .buttonStyle(PaperButtonStyle(.outline, height: 40))
            .help("Show some ideas, or have Lamp help you find your wish")
            .popover(isPresented: $showingIdeas, arrowEdge: .bottom) {
                DeskIdeas(ideas: ideas, choose: choose, find: { showingIdeas = false; store.findWish() })
                    .padding(20)
                    .frame(width: 640)
            }
        }
    }

    private var bar: some View {
        VStack(alignment: .leading, spacing: 10) {
            barRow
            // What's attached goes with the wish, shown as the chat's message box shows it.
            if !store.deskAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.deskAttachments, id: \.self) { url in
                            ChatLook.Chip(onRemove: { store.deskAttachments.removeAll { $0 == url } }) {
                                ChatLook.ChipLabel(name: url.lastPathComponent) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 34)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(Paper.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(barFocused || dropTargeted ? Paper.ink.opacity(0.4) : Paper.rule, lineWidth: 1))
        // Files dropped on the bar are attached to the wish; a wish's own icon dropped here isn't a file.
        .overlay(FileDrop(targeted: $dropTargeted) { urls in
            for url in urls where !store.deskAttachments.contains(url) { store.deskAttachments.append(url) }
        })
        // Where the bar is, for the wish's chat to grow out of (`WishArrival`).
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { barFrame = $0 }
    }

    private var barRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: chooseFiles) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Paper.muted)
            .help("Attach a file")
            .accessibilityLabel("Attach a file")
            TextField(dictation.isListening ? "Listening…" : "Wish for something new…", text: $store.deskDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...5)
                .focused($barFocused)
                .onSubmit { send() }
            if hasWish {
                Button { send() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Paper.onInk)
                        .frame(width: 26, height: 26)
                        .background(Paper.ink, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Make this wish (Return)")
                .accessibilityLabel("Make this wish")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasWish)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !store.deskAttachments.contains(url) { store.deskAttachments.append(url) }
        barFocused = true
    }

    /// Looks for the person's devices as the desk is shown and Lamp comes to the front, once Lamp has looked before:
    /// the first look is the person's Find My Devices, since it's the one macOS asks about. Not more than once a minute,
    /// as switching back to Lamp is often a moment's.
    private func lookForDevices() {
        guard lookedBefore, lastLook.map({ Date().timeIntervalSince($0) > 60 }) ?? true else { return }
        lastLook = Date()
        store.refreshDevices()
    }

    /// A ready device in the list goes in the bar: a wish begun for it, or the one being typed made for it.
    private func wishFor(_ device: String) {
        let typed = store.deskDraft.trimmed
        store.deskDraft = typed.isEmpty ? "Something for my \(device) that " : "\(typed) for my \(device)"
        barFocused = true
    }

    /// An idea goes in the bar to be made the person's own, and the ideas close for it.
    private func choose(_ wish: String) {
        store.deskDraft = wish
        showingIdeas = false
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
        let wish = store.deskDraft.trimmed, attachments = store.deskAttachments
        guard !wish.isEmpty || !attachments.isEmpty else { return }
        let spoken = dictation.isListening
        dictation.cancel()
        if let window = NSApp.keyWindow, let content = window.contentView {
            let inWindow = NSRect(x: barFrame.minX, y: content.frame.height - barFrame.maxY, width: barFrame.width, height: barFrame.height)
            WishArrival.wished(wish, from: window.convertToScreen(inWindow))
        }
        store.deskDraft = ""
        store.deskAttachments = []
        store.wish(wish, attachments: attachments, spoken: spoken)
    }
}

/// The ideas in as many equal columns of at least `minimum` as fit, each row as tall as its tallest tile, every
/// tile stretched to it so a row's cards line up.
struct IdeaColumns: Layout {
    var minimum: CGFloat
    var spacing: CGFloat

    private func grid(_ subviews: Subviews, width: CGFloat?) -> (columns: Int, column: CGFloat, heights: [CGFloat]) {
        let available = width.flatMap { $0.isFinite ? $0 : nil } ?? 3 * minimum + 2 * spacing
        let columns = max(1, min(subviews.count, Int((available + spacing) / (minimum + spacing))))
        let column = (available - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let heights = stride(from: 0, to: subviews.count, by: columns).map { start in
            subviews[start..<min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
        }
        return (columns, column, heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (columns, column, heights) = grid(subviews, width: proposal.width)
        return CGSize(width: CGFloat(columns) * column + CGFloat(columns - 1) * spacing,
                      height: heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (columns, column, heights) = grid(subviews, width: bounds.width)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            for index in row * columns..<min((row + 1) * columns, subviews.count) {
                let x = bounds.minX + CGFloat(index - row * columns) * (column + spacing)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: column, height: height))
            }
            y += height + spacing
        }
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
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Laid out at once rather than lazily: a lazy grid makes its tiles after placing them, and as the ideas
            // open they slid in from the left edge.
            IdeaColumns(minimum: 230, spacing: 12) {
                ForEach(Array(deck.ideas.prefix(Self.shown).enumerated()), id: \.element.id) { index, idea in
                    Button { choose(idea.blurb) } label: {
                        card(lit: hovered == idea.title) {
                            IdeaIcon(symbol: idea.symbol, hue: idea.hue, size: 32)
                            Text(idea.blurb).font(.title3)
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
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32, height: 32)
                        Text("Help me find my wish")
                            .font(.title3.weight(.semibold))
                            .lineLimit(4, reservesSpace: true)
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? Self.finder : (hovered == Self.finder ? nil : hovered) }
                .help("Lamp asks a few questions about your days and writes a wish with you")
            }
        }
        .frame(maxWidth: 760)
        .onAppear { deck.prefetch() }
    }

    private func card(lit: Bool, accent: Bool = false, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(accent ? Color.accentColor.opacity(0.1) : Paper.card.opacity(0.7),
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

/// "Getting it ready…" under a starter's name while it's built for its first opening, with a sheen crossing it so the
/// wait never looks frozen. Where the person asked for less motion it stays still.
struct DeskStatusLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let words = "Getting it ready…"
    private static let sheen = 2.2

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Text(Self.words)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(style(at: timeline.date))
                .frame(maxWidth: .infinity)
        }
        .accessibilityHidden(true)
    }

    /// Secondary text, with a band of brighter light crossing it every couple of seconds.
    private func style(at date: Date) -> AnyShapeStyle {
        let dim = Color.primary.opacity(0.5)
        guard !reduceMotion else { return AnyShapeStyle(Color.primary.opacity(0.6)) }
        let at = (date.timeIntervalSinceReferenceDate / Self.sheen).truncatingRemainder(dividingBy: 1) * 1.6 - 0.3
        let stops: [Gradient.Stop] = [
            .init(color: dim, location: 0),
            .init(color: dim, location: min(max(at - 0.25, 0), 1)),
            .init(color: .primary.opacity(0.95), location: min(max(at, 0), 1)),
            .init(color: dim, location: min(max(at + 0.25, 0), 1)),
            .init(color: dim, location: 1),
        ]
        return AnyShapeStyle(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
    }
}

/// Where files are dropped on the desk's bar. Its text field would take a dropped file itself and type its path, so
/// an AppKit view lies over the bar to take it first: a drop goes to the view registered for it, while a click passes
/// through to the field. Takes files from Finder, a screenshot's thumbnail (a file promised, not yet written) and a
/// picture from a browser or Photos (saved as a PNG). Folders aren't taken: only files go with a wish.
struct FileDrop: NSViewRepresentable {
    @Binding var targeted: Bool
    let dropped: @MainActor ([URL]) -> Void

    func makeNSView(context: Context) -> Catcher { Catcher() }

    func updateNSView(_ view: Catcher, context: Context) {
        view.targeted = { targeted = $0 }
        view.dropped = dropped
    }

    final class Catcher: NSView {
        var targeted: (Bool) -> Void = { _ in }
        var dropped: @MainActor ([URL]) -> Void = { _ in }

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([.fileURL, .png, .tiff] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        }
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            // A wish's own icon carries no file, and isn't this view's to take.
            guard Self.takes(sender.draggingPasteboard) else { return [] }
            targeted(true)
            return .copy
        }
        override func draggingExited(_ sender: NSDraggingInfo?) { targeted(false) }
        override func draggingEnded(_ sender: NSDraggingInfo) { targeted(false) }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let pasteboard = sender.draggingPasteboard
            guard Self.takes(pasteboard) else { return false }
            let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            if !files.isEmpty {
                dropped(files)
                return true
            }
            if let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver], !promises.isEmpty {
                let folder = Self.folder()
                for promise in promises {
                    // Received off the main queue: the source may still be writing the file (a large picture from Photos).
                    promise.receivePromisedFiles(atDestination: folder, operationQueue: Self.receiving) { [dropped] url, error in
                        if error == nil { Task { @MainActor in dropped([url]) } }
                    }
                }
                return true
            }
            guard let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
            let url = Self.folder().appendingPathComponent("Dropped image.png")
            guard (try? png.write(to: url)) != nil else { return false }
            dropped([url])
            return true
        }

        private static let receiving: OperationQueue = {
            let queue = OperationQueue()
            queue.qualityOfService = .userInitiated
            return queue
        }()

        private static func takes(_ pasteboard: NSPasteboard) -> Bool {
            // A wish's icon is dragged as a file promised too (to the Finder), but it isn't one to attach.
            guard !(pasteboard.types ?? []).contains(WishDrag.Source.wishType) else { return false }
            return pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
                || pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self])
                || NSImage.canInit(with: pasteboard)
        }

        /// A folder of its own for each drop, so two pictures dropped with the same name don't land on one file.
        private static func folder() -> URL {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-dropped/\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
    }
}

/// A wish dragged out of Lamp: dropped on the Trash it's deleted, as Delete… does once asked (the Trash gives it back);
/// in the Dock or the Applications folder it's the app itself; anywhere else it's the wish's shared file, as Share…
/// makes it. Nothing in Lamp takes it: the desk's order is its sorting, not where wishes are dragged. A wish being
/// changed stays where it is. Behind its row and never in its way, so a click, a double click and the menu stay
/// SwiftUI's: the drag is started from the window's own mouse events.
struct WishDrag: NSViewRepresentable {
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
                let installed = project.hasMac && FileManager.default.fileExists(atPath: project.installedURL.path)
                    ? project.installedURL : nil
                let payload = Payload(project: project, app: installed) { [weak self] in self?.publish() }
                self.payload = payload
                writer = Promise(payload: payload, name: "\(project.name).lampapp", wish: project.id, delegate: self)
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
            // Nothing inside Lamp takes it: a chat's drop would only make the wish's file an attachment.
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

    /// What a drag hands over: the wish's shared file, or the app itself where an app belongs. The file is made again
    /// as the drag starts, in the background, and is the one Share… and Copy Wish File hand on: it takes the old one's
    /// place whole, in one step, so an app given it by this drag or an earlier one finds a file there whenever it
    /// reads it, and dragging again and again leaves one file per wish.
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

        init(project: LampProject, app: URL?, in folder: URL = Store.sharedFolder, whenWritten: @escaping @MainActor () -> Void) {
            self.app = app
            let file = folder.appendingPathComponent("\(project.name).lampapp")
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
            // not; else it's centered, as long as an estimate from what it holds.
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
        /// The wish's id, for the desk to know it by.
        let wish: String

        init(payload: Payload, name: String, wish: String, delegate: NSFilePromiseProviderDelegate) {
            self.payload = payload
            self.name = name
            self.wish = wish
            super.init()
            fileType = UTType.lampApp.identifier
            self.delegate = delegate
        }

        override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
            super.writableTypes(for: pasteboard) + [Source.wishType]
        }

        override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
            type == Source.wishType ? wish : super.pasteboardPropertyList(forType: type)
        }
    }
}

/// Where a wish lives once it's made, read from its files: for its caption on the desk, and for what the desk
/// says when it's used and nothing comes to the front to say so itself.
enum WishPlace: Equatable {
    case window, menuBar, widget, background, iPhone, iPhoneAndWatch, everywhere, device
    /// Somewhere a kind of its own runs (an Android device, a TV): its caption and symbol (`Target.Identity.place`).
    case elsewhere(String, symbol: String)

    /// Reads the app's files: not on the main thread. A Mac app's place is read from its code; every other kind
    /// says its own.
    static func of(_ project: LampProject) -> WishPlace {
        // A wish whose apps are all in folders of their own lives where they do: one app's place, or several named.
        if !project.holdsApp {
            let places = Parts.load(project).map(of)
            // One with no app at all lives nowhere: only its name, chat and history are left, until it's given one.
            guard !places.isEmpty else { return .elsewhere("No apps", symbol: "square.dashed") }
            guard places.count > 1 else { return places[0] }
            return .elsewhere(places.map { $0.caption ?? "Mac" }.joined(separator: " and "), symbol: places[0].symbol)
        }
        if let place = project.platform.target.identity.place(project) { return place }
        if Template.isWidgetOnly(project) { return .widget }
        let code = sources(of: project)
        // An app with a window lives there, whatever else it has: one with a menu bar item beside its window opens
        // its window, and its chat goes beside it.
        let hasWindow = code.contains("WindowGroup") || code.contains("Window(")
        // Called either way: `LampMenuBar("Name", …) { … }` or with its content alone, `LampMenuBar { … }`.
        if code.range(of: #"\bLampMenuBar\s*[({]"#, options: .regularExpression) != nil, !hasWindow { return .menuBar }
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
        case .elsewhere(let caption, _): caption
        case .device: "Device"
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
        case .elsewhere(_, let symbol): symbol
        case .device: "shippingbox"
        }
    }
}

/// The desk's backdrop: Lamp's page, as in the welcome.
struct DeskBackground: View {
    var body: some View {
        Paper.page
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
    /// A change asked of a wish from the desk's panel: sent to this wish, as if typed in its chat, which opens beside it
    /// (`open(fromDesk:)`). It changes in place, a version of its own that Undo and Versions take back; a starter or a
    /// wish from GitHub is already the person's own copy, so the original is never touched. Nothing asked only opens it.
    func change(_ project: LampProject, asking request: String) {
        let request = request.trimmed
        if !request.isEmpty { send(request, to: project) }
        open(fromDesk: project)
    }

    /// The version a starter's copy, or a wish opened from GitHub or a shared file, last arrived as ("From Lamp", or what
    /// an update brought), when the wish has changed since: what Start Again from the Original goes back to. Nil for a
    /// wish unchanged since, one remixed here, and one with no such version. What's on disk counts, saved or not; Lamp's
    /// own files, rewritten by each Lamp, aren't a change, nor are files attached to requests.
    func original(toStartAgain project: LampProject) async -> AppVersion? {
        guard !FileManager.default.fileExists(atPath: project.dir.appendingPathComponent(Self.remixedHereMark).path),
              let arrival = await Versions.list(project).first(where: { Self.arrivalMessages.contains($0.message) }) else { return nil }
        let owned = Set(GitHubRepo.ownedPaths(in: project))
        var changed = false
        let paths = "-- . ':!.lamp' ':!\(Attachments.folder)'"
        func look(_ line: String) { if !line.trimmed.isEmpty, !owned.contains(line.trimmed) { changed = true } }
        // The arrival against the files as they are, then files git doesn't know yet.
        _ = await Versions.git("git diff --name-only \"$LAMP_VERSION\" \(paths)", cwd: project.dir,
                               env: ["LAMP_VERSION": arrival.id], onLine: look)
        if !changed { _ = await Versions.git("git ls-files --others --exclude-standard \(paths)", cwd: project.dir, onLine: look) }
        return changed ? arrival : nil
    }

    /// Start Again from the Original: the wish's files go back to the version it arrived as, as a new version (so this
    /// too is undone with Undo), and it opens with its chat, which says so (`opening`; from the chat it's open already).
    func startAgain(_ project: LampProject, opening: Bool = true) async {
        // The wish's work is held from the first look to the restore, so no request or other restore comes between.
        guard begin(project) != nil else { return }
        defer { finish(project) }
        guard let arrival = await original(toStartAgain: project) else { return }
        // What a stopped or failed turn left unsaved is kept as a version first, so Undo brings that back too; a restore
        // would otherwise overwrite it for good.
        if await Versions.hasUnsavedChanges(project),
           await Versions.commitAll("-qm \"$LAMP_MESSAGE\"", in: project.dir, env: ["LAMP_MESSAGE": "Unfinished change"]) != .saved {
            log(project, .error, "Lamp couldn't save the unfinished change, so it didn't start again.")
            return
        }
        // A Send Changes Back card holds the changes being taken back: there's nothing left to send.
        ContributeCards.shared.close(project)
        if opening { open(fromDesk: project) }
        await restoreBegun(project, to: arrival)
    }

    /// Duplicate the Original: a fresh copy of the starter a changed copy came from, as this Lamp ships it, put on the
    /// desk as a remix link from the site puts one (`put(starter:)`), and opened with its chat. The changed copy stays.
    func duplicateOriginal(of project: LampProject) {
        guard let name = Starters.starter(of: project)?.name, let starter = Starters.bundled.first(where: { $0.name == name }),
              let copy = put(starter: starter) else {
            NSAlert(error: Sharing.ImportError("Lamp couldn't make a copy of the original \(project.name).")).runModal()
            return
        }
        open(fromDesk: copy)
    }

    /// Send Changes Back… from the desk: the wish's chat, with the card that sends them (`ContributeCards`), as the
    /// chat's Share menu opens it.
    func sendChangesBack(_ project: LampProject) {
        open(fromDesk: project)
        ContributeCards.shared.open(project)
    }

    /// Wish Info from the desk: the wish's chat, on its info panel, with its credits first.
    func showInfo(_ project: LampProject) {
        SidebarServer.shared.show(.info, for: project)
        open(fromDesk: project)
    }

    /// Change… on a wish: its chat beside it in its own window, opening it when it's closed, for a Mac app with
    /// windows that has been made; anything else (a wish still being found, a menu bar app, a widget, an iPhone
    /// app) in Lamp's panel, beside whatever shows it or on its own (`ChatPanel`).
    func change(_ project: LampProject) {
        Task {
            let app = chatApp(of: project)
            guard !project.finding, FileManager.default.fileExists(atPath: app.installedURL.path),
                  await MagicPanel.chatsInApp(project) else { return showChat(project.id) }
            let running = !macCopies(of: app).isEmpty
            // A copy built before the chat could be asked for this way keeps its chat in Lamp's window.
            guard !running || MagicPanel.runningCopiesTakeTheChat(project) else { return showChat(project.id) }
            unread.remove(project.id)
            // A wish Lamp came with, opened for the first time, is seen on its own a moment before its chat comes.
            if running || !MagicPanel.shared.startWithChat(project) { MagicPanel.shared.openChat(in: project) }
            // The copy open here may be older than the code (changed for another place since): it's brought up to date.
            if running {
                updatePlaces(of: project)
                if project.platform.choosesPlace, project.destination == .mac, Runtime.sourcesChanged(project) { openPrepared(project) }
            }
            if !running {
                openWish(project)
                MagicPanel.shared.showChatIfAppNeverComes(project)
            }
        }
    }

    /// An app's chat where it lives: beside the app when it has a window to be beside (`change`, which opens the app
    /// when it's closed), else in Lamp's panel.
    func openChat(_ id: String) {
        guard let project = projects.first(where: { $0.id == id }) else { return showChat(id) }
        change(project)
    }

    /// A wish clicked on the desk: it opens with its chat beside it, to use
    /// and to change at once, as a document opens ready to edit (`change`). A wish that opens no Mac window (the menu
    /// bar, a widget, the background, a simulator, a phone) is used (`use`), the desk says where it is, and its chat
    /// comes up in Lamp's panel, beside what shows it or on its own. A wish Lamp came with that isn't built yet spins
    /// and opens when it's ready.
    func open(fromDesk project: LampProject) {
        // A wish whose apps are all in folders of their own has no window of its own for its chat to go beside. One
        // that plays on another device shows its chat in Lamp's panel too, as a wish holding such an app does below:
        // once that app is running there, using the wish opens nothing and the chat would be the only thing to show. A
        // starter still being made opens when it is ready, without its chat in between (`use`).
        guard project.holdsApp else {
            use(project)
            if Self.playsAwayFromMac(apps(of: project)), !openWhenReady.contains(project.id) { showChat(project.id) }
            return
        }
        let made = FileManager.default.fileExists(atPath: project.installedURL.path)
            || FileManager.default.fileExists(atPath: project.builtURL.path)
        if !made, canPrepare(project), preparing.contains(project.id) || needsPreparing(project) {
            openWhenReady.insert(project.id)
            prepareStarters()
            return
        }
        Task {
            let place = await Task.detached { WishPlace.of(project) }.value
            // A game played on this Mac opens in its window with its chat beside it, as a Mac app does.
            guard place == .window, project.platform == .mac || (project.platform.target.hostedByLamp && project.destination == .mac) else {
                use(project)
                return showChat(project.id)
            }
            change(project)
        }
    }

    /// Whether one of a wish's apps opens somewhere other than this Mac now (a phone, an Android device, a TV), by the
    /// place Try On points at rather than its kind's: a web app or a game says it has a window wherever it plays.
    nonisolated static func playsAwayFromMac(_ apps: [LampProject]) -> Bool {
        apps.contains { $0.destination != .mac }
    }

    /// A wish double-clicked on the desk: used when it's made and nothing's waiting on it, else its chat is shown.
    /// Where opening it brings nothing to the front (the menu bar, a widget, the background, the person's own
    /// phone), the desk says where it is.
    func use(_ project: LampProject) {
        let made = apps(of: project).contains { app in
            FileManager.default.fileExists(atPath: app.installedURL.path) || FileManager.default.fileExists(atPath: app.builtURL.path)
        }
        // A wish Lamp came with that hasn't been built yet, or is being built now: its icon spins, and it
        // opens as soon as it's ready, without its chat in between.
        if !made, canPrepare(project), preparing.contains(project.id) || needsPreparing(project) {
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
            // A window's chat opens beside it (`MagicPanel.startWithChat`); anything else has its chat opened in Lamp's
            // panel the first time it's used.
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
            case .device:
                let device = DeviceApps.integration(for: project)?.name ?? "device"
                WishHUD.show(icon: icon, symbol: place.symbol, title: "\(project.name) is opening on your \(device).")
            case .iPhone, .iPhoneAndWatch, .everywhere, .elsewhere:
                if project.onIOS, project.device != nil {
                    WishHUD.show(icon: icon, symbol: "iphone", title: "\(project.name) is opening on your iPhone.")
                }
            case .window:
                break
            }
            openWish(project)
        }
    }
}
