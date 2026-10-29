import SwiftUI
import AppKit
import LampSidebarKit

/// What the desk's list says about a wish, read from its files away from the main thread: its line, who made it, where
/// it runs, when it last changed and, for a remix made here, which wish it's a remix of.
struct DeskEntry: Equatable, Sendable {
    let id: String
    /// What it is, in a line (`AppDescription`).
    var about: String?
    /// The author of the work it's made from, for a wish that came with Lamp ("Mr.doob"), else nil.
    var author: String?
    var isStarter = false
    /// It came from someone else: a shared file or a repository, with no original of it on this desk.
    var arrived = false
    var license: String?
    var places: [Destination] = []
    var changed: Date?
    /// Its identity (`Sharing.identity`), and the identity of the wish it was remixed from, the last link of its chain.
    var identity: String?
    var original: String?
    var picture: URL?
    /// The changes its starter suggests, as the remix box's ideas.
    var ideas: [String] = []

    nonisolated static func read(_ project: LampProject, apps: [LampProject]) -> DeskEntry {
        let credits = Credits.load(project)
        // The work it's made from: the one marked so, else the first named, which a starter lists first.
        let adapted = credits.upstream.first { $0.adapted == true } ?? credits.upstream.first
        let fm = FileManager.default
        // The last version saved is the last change: the wish's history moves with each one.
        let history = project.dir.appendingPathComponent(".git/logs/HEAD")
        let changed = (try? fm.attributesOfItem(atPath: fm.fileExists(atPath: history.path) ? history.path : project.dir.path))?[.modificationDate] as? Date
        let preview = Runtime.previewURL(project)
        // A starter no one has changed yet shows the picture it shipped with: a game's own, taken as it opens, can be of
        // its window before anything is drawn in it.
        let versions = (try? String(contentsOf: history, encoding: .utf8))?.split(separator: "\n").count ?? 0
        let shipped = Starters.isStarter(project) && versions <= 1 ? Starters.shippedPreview(of: project) : nil
        var places: [Destination] = []
        for app in apps.isEmpty ? [project] : apps { for place in app.openPlaces where !places.contains(place) { places.append(place) } }
        return DeskEntry(id: project.id, about: AppDescription.description(of: project), author: adapted?.author,
                         isStarter: Starters.isStarter(project), arrived: !credits.remixOf.isEmpty,
                         license: adapted?.license, places: places, changed: changed,
                         identity: Sharing.identity(of: project, create: false), original: credits.remixOf.last?.wish,
                         picture: shipped ?? (fm.fileExists(atPath: preview.path) ? preview : Starters.shippedPreview(of: project)),
                         ideas: Starters.starter(of: project)?.tweaks.map(\.title) ?? [])
    }
}

/// The desk's wishes as the list shows them: each with what's known of it, remixes made here under their original.
struct DeskList {
    enum Column: String, CaseIterable {
        case name = "Name", madeBy = "Made by", runsOn = "Runs on", changed = "Changed"
    }

    struct Row: Identifiable {
        let project: LampProject
        let entry: DeskEntry?
        let madeBy: String
        /// It's a remix of the row above it, or of another remix of that one.
        let nested: Bool
        var id: String { project.id }
    }

    /// Who made it, as the list says: "You" for what was made or remixed here, its author for a wish that came with
    /// Lamp (Lamp's own when it names none), "Shared" for one that came from someone else.
    static func madeBy(_ entry: DeskEntry?, hasOriginalHere: Bool) -> String {
        guard let entry else { return "" }
        if hasOriginalHere { return "You" }
        if entry.isStarter { return entry.author ?? "Lamp" }
        return entry.arrived ? "Shared" : "You"
    }

    /// The rows in order: sorted by `column`, each wish followed by its remixes (sorted the same way), as deep as they go.
    static func rows(_ projects: [LampProject], entries: [String: DeskEntry], by column: Column, ascending: Bool) -> [Row] {
        let byIdentity = Dictionary(projects.compactMap { project in entries[project.id]?.identity.map { ($0, project.id) } },
                                    uniquingKeysWith: { first, _ in first })
        func parent(_ project: LampProject) -> String? {
            entries[project.id]?.original.flatMap { byIdentity[$0] }.flatMap { $0 == project.id ? nil : $0 }
        }
        func made(_ project: LampProject) -> String { madeBy(entries[project.id], hasOriginalHere: parent(project) != nil) }
        func before(_ a: LampProject, _ b: LampProject) -> Bool {
            let order: ComparisonResult
            switch column {
            case .name: order = a.title.localizedStandardCompare(b.title)
            case .madeBy: order = made(a).localizedStandardCompare(made(b))
            case .runsOn:
                let (x, y) = (entries[a.id]?.places.count ?? 0, entries[b.id]?.places.count ?? 0)
                order = x == y ? .orderedSame : x < y ? .orderedAscending : .orderedDescending
            case .changed:
                let (x, y) = (entries[a.id]?.changed ?? .distantPast, entries[b.id]?.changed ?? .distantPast)
                order = x == y ? .orderedSame : x < y ? .orderedAscending : .orderedDescending
            }
            if order == .orderedSame { return a.title.localizedStandardCompare(b.title) == .orderedAscending }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
        let children = Dictionary(grouping: projects.filter { parent($0) != nil }, by: { parent($0)! })
        var result: [Row] = []
        var seen = Set<String>()
        func add(_ project: LampProject, nested: Bool) {
            guard seen.insert(project.id).inserted else { return }
            result.append(Row(project: project, entry: entries[project.id], madeBy: made(project), nested: nested))
            for child in (children[project.id] ?? []).sorted(by: before) { add(child, nested: true) }
        }
        for project in projects.filter({ parent($0) == nil }).sorted(by: before) { add(project, nested: false) }
        // A loop of remixes (one the other's original) has no top: each still gets its row.
        for project in projects.sorted(by: before) { add(project, nested: false) }
        return result
    }

    /// When it last changed, as the list says it: "Today", "Yesterday", or the day.
    static func when(_ date: Date?) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: .now)
        return date.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
    }

    /// Open's and Remix's symbols, alone on a row's buttons and beside their words in the side panel.
    static let openSymbol = "arrow.up.right"
    static let remixSymbol = "dot.circle.and.hand.point.up.left.fill"

    static func symbol(_ place: Destination) -> String {
        switch place {
        case .mac: "laptopcomputer"
        case .ios: "iphone"
        case .android: "candybarphone"
        case .androidTV, .tv: "tv"
        case .device: "gamecontroller"
        }
    }
}

/// The list's header: each column's name, a click sorting by it, and again the other way.
struct DeskListHeader: View {
    @Binding var column: DeskList.Column
    @Binding var ascending: Bool

    var body: some View {
        HStack(spacing: 12) {
            sorter(.name).padding(.leading, DeskListRow.pictureWidth + 12).frame(maxWidth: .infinity, alignment: .leading)
            sorter(.madeBy).frame(width: DeskListRow.madeByWidth, alignment: .leading)
            sorter(.runsOn).frame(width: DeskListRow.placesWidth, alignment: .leading)
            sorter(.changed).frame(width: DeskListRow.changedWidth, alignment: .leading)
            Color.clear.frame(width: DeskListRow.buttonsWidth, height: 1)
        }
        .padding(.horizontal, 10).padding(.bottom, 7)
        .overlay(alignment: .bottom) { Paper.rule.frame(height: 1) }
    }

    private func sorter(_ which: DeskList.Column) -> some View {
        Button {
            if column == which { ascending.toggle() } else { column = which; ascending = which != .changed }
        } label: {
            HStack(spacing: 4) {
                Text(which.rawValue.uppercased())
                if column == which { Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .heavy)) }
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(column == which ? Paper.ink : Paper.muted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sort by \(which.rawValue.lowercased())")
        .accessibilityAddTraits(column == which ? .isSelected : [])
    }
}

/// One wish in the desk's list: its picture, name and line, who made it, where it runs, when it changed, and Open
/// with Remix beside it. A remix sits under its original, joined to it by the stripes' line.
struct DeskListRow: View {
    @EnvironmentObject private var store: Store
    let row: DeskList.Row
    let selected: Bool
    let select: () -> Void
    @State private var picture: NSImage?
    @State private var hovered = false

    static let pictureWidth: CGFloat = 64
    static let madeByWidth: CGFloat = 96
    static let placesWidth: CGFloat = 84
    static let changedWidth: CGFloat = 76
    static let buttonsWidth: CGFloat = 72
    static let nest: CGFloat = 30

    private var project: LampProject { row.project }
    /// A starter clicked before Lamp had built it, which opens by itself once it's ready: the one wait the desk shows.
    private var opening: Bool { store.openWhenReady.contains(project.id) }

    var body: some View {
        HStack(spacing: 0) {
            if row.nested { line }
            HStack(spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(project.title).font(.system(size: 14.5, weight: .bold)).lineLimit(1)
                        if !opening && store.unread.contains(project.id) { ReadyDot(size: 8) }
                    }
                    if opening {
                        DeskStatusLine().frame(maxWidth: .infinity, alignment: .leading)
                    } else if let about = row.entry?.about {
                        Text(about).font(.system(size: 12.5)).foregroundStyle(Paper.muted).lineLimit(1).truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.madeBy).font(.system(size: 13)).lineLimit(1).frame(width: Self.madeByWidth, alignment: .leading)
                HStack(spacing: 4) {
                    ForEach(row.entry?.places ?? [], id: \.self) { place in
                        Image(systemName: DeskList.symbol(place)).help(GameKit.placeName(place))
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(Paper.ink.opacity(0.75))
                .frame(width: Self.placesWidth, alignment: .leading)
                Text(DeskList.when(row.entry?.changed)).font(.system(size: 13)).foregroundStyle(Paper.muted)
                    .frame(width: Self.changedWidth, alignment: .leading)
                HStack(spacing: 6) {
                    Button { store.open(fromDesk: project) } label: { Label("Open", systemImage: DeskList.openSymbol) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(PaperButtonStyle(.ink, square: true))
                        .help("Open \(project.title)")
                    Button { Task { await store.remix(project) } } label: { Label("Remix", systemImage: DeskList.remixSymbol) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(PaperButtonStyle(.outline, square: true))
                        .disabled(!canRemix)
                        .help("Remix: make a new copy of \(project.title) to change. The original stays as it is.")
                }
                .frame(width: Self.buttonsWidth, alignment: .trailing)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Paper.rule, lineWidth: 1) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.open(fromDesk: project) }
        .onTapGesture(perform: select)
        .onHover { hovered = $0 }
        .background(ShareAnchor(origin: .app(project.id)))
        // Dragged out of Lamp it's the wish's shared file, or the app itself in the Dock or the Applications folder.
        .background(WishDrag(project: project))
        .contextMenu {
            Button("Open") { store.open(fromDesk: project) }
            Button("Change…") { store.change(project) }
            Divider()
            AppMenu(project: project)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(project.title)
        .accessibilityValue(status)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .task(id: row.entry?.picture) { picture = await Self.load(row.entry?.picture) }
    }

    /// What's going on with it, for VoiceOver: on screen the status line and the dot say it.
    private var status: String {
        if opening { return "Opening…" }
        if store.preparing.contains(project.id) { return "" }
        if store.busy.contains(project.id) { return store.progress[project.id]?.newApp == true || project.untitled ? "Coming true…" : "Changing…" }
        if Talk.waiting(in: store.logs[project.id] ?? []) != nil { return "Has a question" }
        if store.queued[project.id]?.isEmpty == false { return "Waiting to start" }
        if project.finding { return "Finding a wish" }
        if store.unread.contains(project.id) { return "Ready" }
        return ""
    }

    private var canRemix: Bool {
        !store.busy.contains(project.id) && project.scaffolded && !project.untitled && AppUpdates.mayRemix(project)
    }

    private var background: Color {
        selected ? Paper.card : hovered ? Paper.ink.opacity(0.04) : .clear
    }

    /// The stripes' line from the original down to the remix, turning in to meet it.
    private var line: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(gradient: Paper.stripeGradient, startPoint: .top, endPoint: .bottom)
                .frame(width: 3)
                .clipShape(Capsule())
                .padding(.bottom, 26)
                .offset(x: Self.nest + 10 - Self.pictureWidth / 2 - 1)
            Paper.stripes[5].frame(width: 12, height: 3).clipShape(Capsule())
                .offset(x: Self.nest + 10 - Self.pictureWidth / 2 - 1, y: 25)
        }
        .frame(width: Self.nest, height: 52, alignment: .topLeading)
        .padding(.top, -6)
        .accessibilityHidden(true)
    }

    private var thumbnail: some View {
        ZStack {
            Paper.ink
            if let picture {
                Image(nsImage: picture).resizable().interpolation(.high).antialiased(true).aspectRatio(contentMode: .fill)
            } else {
                AppIcon(project: project, size: 30)
            }
        }
        .frame(width: Self.pictureWidth, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private static func load(_ url: URL?) async -> NSImage? {
        guard let url else { return nil }
        return await Task.detached { NSImage(contentsOf: url) }.value
    }
}

/// The wish picked in the list, beside it: its picture and what it is, a few facts, and a box to remix it with a change,
/// which makes a new copy and asks for that change in its chat.
struct DeskDetail: View {
    @EnvironmentObject private var store: Store
    let row: DeskList.Row
    let remixes: [LampProject]
    @State private var change = ""
    @State private var picture: NSImage?
    @FocusState private var focused: Bool

    private var project: LampProject { row.project }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Filled into a box of the panel's width: the picture sits over it, so its own width never widens the
                // panel past the room it's given.
                Paper.ink
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .overlay {
                        if let picture { Image(nsImage: picture).resizable().interpolation(.high).antialiased(true).aspectRatio(contentMode: .fill) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(project.title).font(.system(size: 23, weight: .heavy)).tracking(-0.8)
                    if let about = row.entry?.about {
                        Text(about).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                    fact("Made by", [row.madeBy, row.entry?.license].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    fact("Runs on", (row.entry?.places ?? []).map(GameKit.placeName).joined(separator: ", "))
                    if !remixes.isEmpty { fact("Remixes", remixes.map(\.title).joined(separator: ", ")) }
                }
                .font(.system(size: 13))
                Button { store.open(fromDesk: project) } label: { Label("Open", systemImage: DeskList.openSymbol) }
                    .buttonStyle(PaperButtonStyle(.outline, height: 34))
                Paper.rule.frame(height: 1)
                remixBox
            }
            .foregroundStyle(Paper.ink)
            .padding(18)
        }
        .background(Paper.card)
        .task(id: row.entry?.picture) {
            guard let url = row.entry?.picture else { picture = nil; return }
            picture = await Task.detached { NSImage(contentsOf: url) }.value
        }
        .onChange(of: project.id) { change = "" }
    }

    private var remixBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remix it").font(.system(size: 15, weight: .heavy))
            TextField("What would you change?", text: $change, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(2...5)
                .focused($focused)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Paper.page, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Paper.rule, lineWidth: 1))
                .onSubmit(remix)
            if !(row.entry?.ideas ?? []).isEmpty {
                IdeaChips(ideas: row.entry?.ideas ?? []) { idea in
                    change = idea
                    focused = true
                }
            }
            Button(action: remix) { Label("Remix", systemImage: DeskList.remixSymbol) }
                .buttonStyle(PaperButtonStyle(.ink, height: 34))
                .disabled(store.busy.contains(project.id) || !project.scaffolded || project.untitled || !AppUpdates.mayRemix(project))
                .help("Make a new copy of \(project.title) with this change. The original stays as it is.")
        }
    }

    private func remix() {
        let asked = change.trimmed
        change = ""
        Task { await store.remix(project, change: asked.isEmpty ? nil : asked) }
    }

    @ViewBuilder private func fact(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            GridRow {
                Text(label).foregroundStyle(Paper.muted)
                Text(value).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The changes a starter suggests, as small buttons that put one in the remix box.
private struct IdeaChips: View {
    let ideas: [String]
    let choose: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
    }

    private var chips: some View {
        ForEach(ideas, id: \.self) { idea in
            Button { choose(idea) } label: {
                Text(idea).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    .padding(.horizontal, 10).frame(height: 27)
                    .overlay(Capsule().strokeBorder(Paper.rule, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
