import SwiftUI
import LampSidebarKit
import AppKit
import AVFoundation
import QuickLook
import ImagePlayground

/// The desk's window: the welcome until it's done, then the desk. Each wish's chat has a window of its own
/// (`WishWindow`).
struct ContentView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.openWindow) private var openWindow
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
        .modifier(StoreDialogs(active: store.selection == nil))
        .background(WindowKeyWatcher { store.selection = nil })
        .onAppear { LampWindows.open = openWindow }
    }

    private var main: some View {
        VStack(spacing: 0) {
            if store.setup.checked && !store.setup.hasBuildTools { BuildToolsBanner() }
            WishDesk()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.markRead()
        }
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
            StandInIcon(project: project, size: size, color: store.standInColor(for: project))
        }
    }
}

/// What stands for an app that has no icon yet: the lamp's light for a wish still waiting to be told or sent
/// (it isn't an app yet), a blueprint for a named one.
struct StandInIcon: View {
    let project: LampProject
    let size: CGFloat
    /// The icon's background once it's chosen (`Store.standInColor`), so the tile is the icon's color from the start.
    var color: String?

    var body: some View {
        if project.untitled {
            WishIcon(size: size)
        } else {
            BlueprintIcon(letter: project.name.first ?? "A", size: size,
                          ground: color.map { BlueprintTile.ground(Icons.background(named: $0)) } ?? BlueprintTile.gray)
        }
    }
}

/// The lamp's light, as the site draws it under a wish: dusk warming to a glow, with one spark in it.
struct WishIcon: View {
    let size: CGFloat

    var body: some View {
        // Same footprint as a real macOS icon: an 824pt tile on a 1024pt canvas.
        let side = size * 824 / 1024
        let shape = RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(red: 0.36, green: 0.27, blue: 0.50), Color(red: 0.93, green: 0.60, blue: 0.33),
                                               Color(red: 1.0, green: 0.80, blue: 0.47)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.fill(RadialGradient(colors: [Color(red: 1.0, green: 0.93, blue: 0.72).opacity(0.95), .clear],
                                      center: .center, startRadius: 0, endRadius: side * 0.42))
            Spark().fill(.white)
                .frame(width: side * 0.34, height: side * 0.34)
                .shadow(color: Color(red: 1.0, green: 0.72, blue: 0.3).opacity(0.9), radius: side / 14)
            shape.strokeBorder(.white.opacity(0.35), lineWidth: max(0.5, side / 160))
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.18), radius: size / 60, y: size / 80)
        .frame(width: size, height: size)
    }

    /// The four-pointed spark of the site's wish button.
    private struct Spark: Shape {
        func path(in rect: CGRect) -> Path {
            let c = CGPoint(x: rect.midX, y: rect.midY), r = rect.width / 2, pinch = r * 0.2
            var path = Path()
            path.move(to: CGPoint(x: c.x, y: c.y - r))
            for (tip, side) in [(CGPoint(x: c.x + r, y: c.y), CGPoint(x: c.x + pinch, y: c.y - pinch)),
                                (CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x + pinch, y: c.y + pinch)),
                                (CGPoint(x: c.x - r, y: c.y), CGPoint(x: c.x - pinch, y: c.y + pinch)),
                                (CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x - pinch, y: c.y - pinch))] {
                path.addQuadCurve(to: tip, control: side)
            }
            path.closeSubpath()
            return path
        }
    }
}

/// The stand-in icon until the real one is designed: a blueprint of an app icon, with Apple's icon grid
/// drawn on it and the app's initial in the middle.
struct BlueprintIcon: View {
    let letter: Character?
    let size: CGFloat
    var ground = BlueprintTile.gray

    var body: some View {
        // Same footprint as a real macOS icon: an 824pt tile on a 1024pt canvas.
        let side = size * 824 / 1024
        BlueprintTile(letter: letter, ground: ground)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: max(0.5, side / 160)))
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.18), radius: size / 60, y: size / 80)
            .frame(width: size, height: size)
    }
}

/// The blueprint itself, square and full bleed: gray until the icon is designed, then in the design's colors with
/// a stand-in in place of the initial while its artwork is drawn (`Icons.Artwork.waiting`), so something has moved
/// on without passing for the icon itself.
struct BlueprintTile: View {
    /// The initial; nil once the icon is designed and its artwork is on its way.
    let letter: Character?
    var ground = gray

    struct Ground {
        let top: Color
        let bottom: Color
        /// Lines and marks dark on a light ground.
        var light = false
    }

    static let gray = Ground(top: Color(white: 0.56), bottom: Color(white: 0.40))

    /// The ground for an icon's background, the same gradient its tile has at every later stage.
    static func ground(_ background: Icons.Background) -> Ground {
        Ground(top: Color(nsColor: background.gradient.top), bottom: Color(nsColor: background.gradient.bottom),
               light: background.isLight)
    }

    var body: some View {
        GeometryReader { area in
            let side = area.size.width
            let ink: Color = ground.light ? .black : .white
            ZStack {
                LinearGradient(colors: [ground.top, ground.bottom], startPoint: .top, endPoint: .bottom)
                Canvas { context, canvas in
                    let w = canvas.width
                    let thin = max(0.5, w / 400)
                    var grid = Path()
                    for i in 1..<8 {
                        let p = w * CGFloat(i) / 8
                        grid.move(to: CGPoint(x: p, y: 0)); grid.addLine(to: CGPoint(x: p, y: w))
                        grid.move(to: CGPoint(x: 0, y: p)); grid.addLine(to: CGPoint(x: w, y: p))
                    }
                    if w > 40 { context.stroke(grid, with: .color(ink.opacity(0.12)), lineWidth: thin) }
                    var guides = Path()
                    guides.move(to: .zero); guides.addLine(to: CGPoint(x: w, y: w))
                    guides.move(to: CGPoint(x: w, y: 0)); guides.addLine(to: CGPoint(x: 0, y: w))
                    for r in [0.19, 0.31] { guides.addEllipse(in: CGRect(x: w * (0.5 - r), y: w * (0.5 - r), width: w * r * 2, height: w * r * 2)) }
                    guides.addRect(CGRect(x: w * 0.16, y: w * 0.16, width: w * 0.68, height: w * 0.68))
                    context.stroke(guides, with: .color(ink.opacity(0.28)), lineWidth: thin * 1.5)
                }
                Group {
                    if let letter {
                        Text(String(letter).uppercased())
                            .font(.system(size: side * 0.48, weight: .medium, design: .rounded))
                    } else {
                        Image(systemName: "app.background.dotted")
                            .font(.system(size: side * 0.44, weight: .regular))
                    }
                }
                .foregroundStyle(ground.light ? Color.black.opacity(0.55) : .white)
                .shadow(color: .black.opacity(0.15), radius: side / 60, y: side / 120)
            }
        }
        .aspectRatio(1, contentMode: .fit)
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

/// Image Playground, opened to make an app's icon when the person chose to draw icons themselves: by New
/// Icon in the app's menu and by the chat's Draw Icon… buttons. The person picks a picture there and Lamp
/// takes it from there. It has no menu item of its own: New Icon draws with whatever Settings says draws.
struct PlaygroundIconSheet: ViewModifier {
    @EnvironmentObject private var store: Store
    /// The window in front: only it shows the sheet.
    var active = true

    func body(content: Content) -> some View {
        if #available(macOS 15.1, *) {
            content.imagePlaygroundSheet(isPresented: Binding(get: { active && store.showingPlayground },
                                                              set: { if active { store.showingPlayground = $0 } }),
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
        // The whole wish, as Play and Stop are: each app's own menu in the toolbar is for that app alone.
        Button("Open") { store.openWish(project) }
        Button("Rebuild & Open") { store.runPrepared(project) }
            .disabled(busy)
        Button("Quit") { Task { await store.quitWish(project) } }
            .disabled(!store.isWishOpen(project))
        if project.holdsApp, project.platform.target.places != [.mac] {
            // Which simulator the app opens in (it's built for both), or which of the person's own phones.
            Menu("Try On") { TryOnChoices(project: project) }
                .disabled(busy)
        }
        Divider()
        Button("Rename…") { store.renaming = project }
            // Still being found: the wish it becomes names it. A device's setup is never named.
            .disabled(busy || project.makesNoApp)
        Button("Duplicate") { Task { await store.duplicate(project) } }
            .disabled(busy || !project.scaffolded || project.untitled)
        Button("New Icon") { Task { await store.newIcon(project) } }
            .disabled(busy || project.untitled)
        // Only once there's an app to show: a wish not yet made has nothing in Finder.
        if FileManager.default.fileExists(atPath: project.installedURL.path) {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([project.installedURL])
            }
        }
        Divider()
        if store.canShare(project) {
            Button("Copy Wish File") { store.copyAppFile(project) }
            Button { Sharing.share(project, from: .app(project.id)) } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Button("Export…") { store.chooseExport(project) }
            Divider()
        }
        Button("Delete…", role: .destructive) { store.deleting = project }
    }
}

/// The wish's info (Wish Info in the chat's bar): what it has cost, what answers its AI, how Lamp builds it and where it
/// lives, as plain rows the chat's info panel draws (`InfoPanel`). It chooses nothing: its buttons lead to where things
/// are chosen.
enum AppInfoView {
    static let useSettingsChoices = "settingsChoices"
    static let basedOnPage = "basedOnPage"

    /// A button of the panel's, here or in the chat beside the app: Settings opened at its tab, the app or its code
    /// shown in Finder, or this app's own model choices undone.
    @MainActor static func perform(_ action: String, for project: LampProject, openSettings: (String) -> Void) {
        switch action {
        case "providers", "building": openSettings(action)
        case useSettingsChoices: AppModels().save(project)
        case "showApp": NSWorkspace.shared.activateFileViewerSelecting([project.installedURL])
        case "showSource": NSWorkspace.shared.activateFileViewerSelecting([project.dir])
        case basedOnPage:
            if let page = Credits.load(project).upstream.first?.url.flatMap(URL.init(string:)) { NSWorkspace.shared.open(page) }
        default: break
        }
    }

    /// What the panel says, as plain rows (a nil value is Not Ready) and the buttons under them: drawn here and in
    /// the chat beside the app (`SidebarServer`) from this one list, so the two never say different things.
    @MainActor static func sections(for project: LampProject, models: AppModels, store: Store) -> [SidebarInfoSection] {
        let usage = store.usage[project.id] ?? AppUsage()
        let requests = (store.logs[project.id] ?? []).filter { $0.kind == .user }.count
        var sections = [SidebarInfoSection(title: "Usage", rows: [
            SidebarInfoRow(label: "Total cost", value: dollars(usage.totalCost)),
            SidebarInfoRow(label: "Changes requested", value: "\(requests)"),
            SidebarInfoRow(label: "Building the app", value: runs(usage.agentRuns ?? 0, "agent run") + " · " + dollars(usage.agentCost ?? 0)),
            SidebarInfoRow(label: "AI inside the app", value: runs(usage.calls, "call") + " · " + dollars(usage.cost)),
        ])]
        // What answers this app, read-only: models are chosen in Settings. Nothing that answers is Not Ready.
        func answer(_ title: String, _ resolution: Resolution) -> SidebarInfoRow {
            SidebarInfoRow(label: title, value: resolution.tier == .none ? nil : short(resolution.answer ?? ""))
        }
        var ai = Capability.allCases.filter { $0 != .browser }.map { answer($0.title, AppAI.resolve($0, for: project)) }
        if project.hasIOS {
            // Away from the Mac a phone answers only through the OpenRouter key: without one, one row says so.
            if Provider.hasKey {
                ai += Capability.allCases.filter { $0 != .browser }.map { answer("\($0.title) away", AppAI.resolve($0, for: project, in: .phoneAway)) }
            } else {
                ai.append(SidebarInfoRow(label: "Away from this Mac", value: nil))
            }
        }
        var aiButtons = [SidebarInfoButton(title: "Configure Providers…", action: "providers")]
        // Choices an earlier Lamp let this app make for itself: the one thing left to change here.
        if models != AppModels() { aiButtons.append(SidebarInfoButton(title: "Use Settings' Choices", action: useSettingsChoices)) }
        sections.append(SidebarInfoSection(title: "AI inside this app", rows: ai, buttons: aiButtons))
        if let credits = creditsSection(Credits.load(project)) { sections.insert(credits, at: 0) }
        var building = [SidebarInfoRow(label: "Agent", value: Builder.engine.title)]
        if Builder.engine == .claude || Builder.engine == .codex {
            let model = Builder.engineModel(Builder.engine)
            let names = Builder.engine == .claude ? Builder.claudeModels : Builder.codexModels
            building.append(SidebarInfoRow(label: "Building with", value: model.isEmpty ? "\(Builder.engine.title)'s default"
                                           : names.first { $0.id == model }?.label ?? model))
        }
        if Builder.engine == .pi {
            building.append(SidebarInfoRow(label: "Provider", value: providerName))
            if !Builder.piModel.isEmpty { building.append(SidebarInfoRow(label: "Building with", value: buildModel)) }
        }
        sections.append(SidebarInfoSection(title: "Building", rows: building,
                                           buttons: [SidebarInfoButton(title: "Building Settings…", action: "building")]))
        // Of the app in the wish's own folder: a wish whose apps are all in folders of their own has only its code.
        guard project.holdsApp else {
            sections.append(SidebarInfoSection(title: "App", rows: [], buttons: [SidebarInfoButton(title: "Show Source Code in Finder", action: "showSource")]))
            return sections
        }
        var app: [SidebarInfoRow] = []
        if let stamp = store.stamps[project.id] { app.append(SidebarInfoRow(label: "Built with", value: stamp.summary)) }
        app.append(SidebarInfoRow(label: "Bundle ID", value: project.bundleID))
        sections.append(SidebarInfoSection(title: "App", rows: app, buttons: [
            SidebarInfoButton(title: "Show App in Finder", action: "showApp"),
            SidebarInfoButton(title: "Show Source Code in Finder", action: "showSource"),
        ]))
        return sections
    }

    /// Where the wish came from, first, since it's the one thing here that's about someone else: the work it's based on
    /// and its licence, anything else it uses, and the wishes it was remixed from. A wish with no credits has none.
    static func creditsSection(_ credits: Credits) -> SidebarInfoSection? {
        guard !credits.isEmpty else { return nil }
        var rows: [SidebarInfoRow] = []
        // The work it's based on and its licence, each a row; anything else it uses a row of its own, named after it, with
        // who made it and its licence when that's a plain id (terms of its own, `LicenseRef-`, would make the row too long
        // for the panel's one line; they're in the About window). Every row's label is its own: the panel tells rows apart
        // by their labels.
        var labels: Set<String> = ["Based on", "License", "Made with AI", "Remixed from"]
        for (index, source) in credits.upstream.enumerated() {
            if index == 0 {
                rows.append(SidebarInfoRow(label: "Based on", value: Credits.line(for: source)))
                rows.append(SidebarInfoRow(label: "License", value: source.license ?? "None given"))
                continue
            }
            var label = source.name
            while !labels.insert(label).inserted { label += " " }
            let license = source.license.map { $0.hasPrefix("LicenseRef-") ? nil : $0 } ?? "no licence"
            rows.append(SidebarInfoRow(label: label, value: [source.author, license].compactMap { $0 }.joined(separator: " · ")))
        }
        if !credits.generated.isEmpty {
            rows.append(SidebarInfoRow(label: "Made with AI", value: credits.generated.count == 1 ? "1 picture" : "\(credits.generated.count) pictures"))
        }
        if !credits.remixOf.isEmpty {
            rows.append(SidebarInfoRow(label: "Remixed from", value: credits.remixOf.map { $0.name + ($0.starter != nil ? " (Lamp)" : "") }.joined(separator: " → ")))
        }
        let page = credits.upstream.first.flatMap { source in source.url.map { _ in SidebarInfoButton(title: "Visit \(source.name)", action: basedOnPage) } }
        return SidebarInfoSection(title: "Credits", rows: rows, buttons: page.map { [$0] } ?? [])
    }

    /// A model's name without the description Settings shows: "Fast & cheap (Claude Haiku)" → "Claude Haiku",
    /// "Nano Banana 2 (Gemini 3.1 Flash Image)" → "Nano Banana 2". The panel is narrow.
    static func short(_ label: String) -> String {
        guard let open = label.firstIndex(of: "(") else { return label }
        let inside = String(label[label.index(after: open)...].prefix { $0 != ")" }).components(separatedBy: ",")[0]
        return inside.hasPrefix("Claude") ? inside : String(label[..<open]).trimmed
    }

    private static var providerName: String {
        Builder.piProvider == Builder.localProvider ? "Native Mac AI" : Provider.openRouter
    }

    private static var buildModel: String {
        let id = Builder.piModel
        return Builder.piProvider == "openrouter" ? Provider.models.first { $0.id == id }?.label ?? id : id
    }

    private static func dollars(_ amount: Double) -> String { String(format: "$%.2f", amount) }
    private static func runs(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}

/// While Apple's tools install, above everything: what's happening, and that requests wait for it.
struct BuildToolsBanner: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Installing Apple's app-building tools. Anything you ask for starts as soon as they're in.")
                .font(.callout)
            Spacer()
            Button(store.setup.installRequested ? "Show Installer" : "Install…") {
                if store.setup.installRequested { SetupCheck.showInstaller() } else { store.requestBuildTools() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Hands over the window a view is in, once it is in one.
private struct WindowFinder: NSViewRepresentable {
    let found: (NSWindow) -> Void

    final class Probe: NSView {
        var found: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // After this pass: a sheet's window knows its parent only once it has been attached.
            if let window { DispatchQueue.main.async { [weak self] in self?.found?(window) } }
        }
    }

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.found = found
        return view
    }

    func updateNSView(_ view: Probe, context: Context) { view.found = found }
}

/// Shown before building an app someone else shared: finds what `ImportReviewCard` draws (the pending file,
/// its icon, the room under the sheet) and passes it in.
struct ImportReviewView: View {
    @EnvironmentObject private var store: Store
    let pending: Store.PendingImport

    /// The app's own icon, once drawn from the file; the plain app icon until then, and for a file without one.
    @State private var icon: NSImage?
    /// How tall the sheet may be where it hangs: from its top down to the bottom of the screen's usable area
    /// (above the Dock). Unlimited until the sheet is on screen.
    @State private var room = CGFloat.infinity
    @State private var sheet: NSWindow?

    var body: some View {
        ImportReviewCard(name: pending.package.name, description: pending.package.description, icon: icon,
                         review: pending.review, existing: pending.existing?.name, room: room,
                         cancel: store.cancelImport, open: store.confirmImport, update: store.confirmUpdate,
                         android: pending.package.platform.target.recipe.language == .kotlin)
            .task { icon = await Sharing.icon(of: pending.package) }
            .background(WindowFinder { sheet = $0; fit() })
            // The window can be moved with the sheet down, and the Dock can come and go.
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { _ in fit() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in fit() }
    }

    private func fit() {
        guard let window = sheet?.sheetParent, let screen = window.screen else { return }
        room = Self.room(below: window.frame.minY + window.contentLayoutRect.maxY, on: screen.visibleFrame)
    }

    /// The height a sheet can take when its top edge sits at `top` (screen coordinates, y up) on a screen
    /// whose usable area is `visible`: down to the bottom of that area, less a margin.
    nonisolated static func room(below top: CGFloat, on visible: CGRect) -> CGFloat {
        (top - visible.minY - 12).rounded(.down)
    }
}

/// The review of a shared app, drawn from plain values so the gallery shows what people see: the app, what it
/// does, what to weigh before opening it, and what it can do on the Mac.
struct ImportReviewCard: View {
    let name: String
    /// What the app says it does, in its sender's words, when the file has that.
    let description: String?
    let icon: NSImage?
    /// Nil while the check runs.
    let review: ImportReview?
    /// The name of the wish already here that this file is another version of, if any.
    let existing: String?
    var room = CGFloat.infinity
    let cancel: () -> Void
    let open: () -> Void
    let update: () -> Void
    /// An Android app's reach is the phone's, not the Mac's.
    var android = false

    /// The heights of what stays put, measured as laid out: the app's name and description at the top, the
    /// review's summary, the line about the copy already here when there is one, and the buttons.
    @State private var fixed: [Part: CGFloat] = [:]
    private enum Part { case name, summary, existing, buttons }
    /// The height of Things to consider as laid out in full; nil when there's nothing to consider.
    @State private var considering: CGFloat?
    /// What the two scrolling parts share: the room under the sheet's top less the fixed parts, the sheet's
    /// padding (48) and a 16-point gap after each part but the last (the fixed ones, and the two that scroll).
    private var budget: CGFloat {
        let scrolling: CGFloat = considering == nil ? 1 : 2
        return room - fixed.values.reduce(0, +) - 48 - 16 * (CGFloat(fixed.count) + scrolling - 1)
    }
    /// The two share what's left and never take more between them, whatever the screen: Things to consider is
    /// shown whole when it fits, and otherwise scrolls, leaving what the app can do a few rows, or half when
    /// there isn't room for that. A long list of concerns never pushes the buttons off the screen, and Lamp's
    /// verdict, its first lines, is what stays in view. Below 48 points nothing could be read, so that's the floor.
    private var shared: CGFloat { max(48, budget) }
    private var considerLimit: CGFloat { min(considering ?? 0, max(shared - 120, shared / 2)) }
    /// How tall what the app can do may be: the height a long review always stopped at, or what's left.
    private var limit: CGFloat { min(460, shared - (considering == nil ? 0 : considerLimit)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                // Lamp's icons carry their own margin, so one fills a larger frame to sit like the plain icon
                // does, and rises by that margin so its top lines up with the name's.
                Image(nsImage: icon ?? NSWorkspace.shared.icon(for: .applicationBundle)).resizable()
                    .frame(width: icon == nil ? 66 : 84, height: icon == nil ? 66 : 84)
                    .frame(width: 84, height: 84)
                    .padding(.top, -8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    // The name is the sender's: shown as written, never as formatting, and on one line whose
                    // end (the closing quote and the question mark) stays in view however long it is.
                    Text(verbatim: "Open “\(name)”?").font(.title2.bold())
                        .lineLimit(1).truncationMode(.middle)
                    // The sender's words, said to be theirs.
                    if let description {
                        Text(verbatim: "Described by the person who shared it with you as: \(description)")
                            .font(.callout).foregroundStyle(.secondary).lineLimit(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fixed[.name] = $0 }

            if let review {
                // What it does and the start of what to weigh stay in view, however short the screen, so Lamp's
                // verdict is never scrolled away beside the button that opens the app.
                if !review.summary.isEmpty {
                    section("What it does") {
                        // The reviewer is asked for a sentence or two: a few lines here, the whole of it on hover.
                        Text(review.summary).lineLimit(5).fixedSize(horizontal: false, vertical: true).help(review.summary)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fixed[.summary] = $0 }
                }
                let considerations = Self.considerations(review)
                if !considerations.isEmpty {
                    ScrollView {
                        section("Things to consider") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(considerations) { consideration($0) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { considering = $0 }
                    }
                    .frame(maxHeight: considerLimit)
                    .fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    // An Android app runs on the emulator or the person's phone, never on the Mac itself.
                    section(android ? "What it can do" : "What it can do on your Mac") { capabilities(review) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: limit)
                .fixedSize(horizontal: false, vertical: true)   // no taller than its content, up to the limit
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Checking what this wish does…").foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
            }

            if let existing {
                // The buttons say what each does; this is what someone would worry about before choosing Update.
                Label {
                    Text(verbatim: "You already have this wish\(existing == name ? "" : ", as “\(existing)”"). Updating keeps your data, and you can go back if you change your mind.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fixed[.existing] = $0 }
            }

            buttons
                .cardButtons()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fixed[.buttons] = $0 }
        }
        .padding(24)
        .frame(width: 500)
    }

    private var buttons: some View {
        HStack {
            Spacer()
            // Escape always cancels. Return builds only when the review is in and vouches for the app
            // (`ImportReview.opening`); anything less takes a deliberate click.
            Button("Cancel", role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
            if existing != nil {
                // The app is already here: the file either becomes its next version or a second app.
                // Either way its code runs, so both follow the same rule as opening does. Return is
                // only ever Update: keeping both is the choice someone makes on purpose.
                switch review?.opening {
                case .byReturn:
                    Button("Keep Both", action: open)
                    Button("Update", action: update)
                        .keyboardShortcut(.defaultAction)
                case .anyway:
                    Button("Keep Both Anyway", role: .destructive, action: open)
                    Button("Update Anyway", role: .destructive, action: update)
                case .byClick, nil:
                    Button("Keep Both", action: open)
                        .disabled(review == nil)
                    Button("Update", action: update)
                        .disabled(review == nil)
                }
            } else {
                switch review?.opening {
                case .byReturn:
                    Button("Build & Open", action: open)
                        .keyboardShortcut(.defaultAction)
                case .anyway:
                    Button("Open Anyway", role: .destructive, action: open)
                case .byClick, nil:
                    Button("Build & Open", action: open)
                        .disabled(review == nil)
                }
            }
        }
    }

    /// Something to weigh before opening: red for what should stop someone, orange for what should make them think.
    struct Consideration: Identifiable, Equatable {
        enum Weight { case caution, warning }
        let text: String
        let weight: Weight
        var icon = "exclamationmark.triangle.fill"
        /// Said under it, smaller: why the check didn't run, in the provider's words.
        var detail: String?
        var id: String { text }
    }

    /// The verdict first, unless it's an all-clear (said by nothing being here), then each concern.
    static func considerations(_ review: ImportReview) -> [Consideration] {
        var list: [Consideration] = []
        switch review.verdict {
        case .risky: list.append(Consideration(text: "Looks risky. Don't open unless you trust the sender", weight: .warning, icon: "xmark.octagon.fill"))
        case .sensitive: list.append(Consideration(text: "Does sensitive things. Open only if you expected that", weight: .warning, icon: "exclamationmark.octagon.fill"))
        case .partlyChecked: list.append(Consideration(text: "Only partly checked. Open only if you trust the sender", weight: .caution))
        case .powerful: list.append(Consideration(text: "Powerful. Check it's what you expect", weight: .caution))
        case .checkedOnThisMac: list.append(Consideration(text: "Nothing worrying found, but not by a check Lamp can vouch for", weight: .caution))
        case .unchecked: list.append(Consideration(text: "Not checked by AI", weight: .warning, detail: review.note))
        case .safe: break
        }
        // What the code was seen to do can outrank the missing check in the verdict; the reader still hears,
        // in red, that no AI read it, and why.
        if review.risk == nil, review.verdict != .unchecked, review.asked || review.note != nil {
            list.append(Consideration(text: "Not checked by AI", weight: .warning, detail: review.note))
        }
        // A high rating makes each reason for it as serious as the rating.
        let weight: Consideration.Weight = review.risk == .high ? .warning : .caution
        for concern in review.concerns where !list.contains(where: { $0.text == concern }) {
            list.append(Consideration(text: concern, weight: weight))
        }
        return list
    }

    private func consideration(_ item: Consideration) -> some View {
        let color: Color = item.weight == .warning ? .red : .orange
        return Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.text).fixedSize(horizontal: false, vertical: true)
                if let detail = item.detail {
                    // A provider's own words, of any length: a few lines here, the whole of it on hover.
                    Text(verbatim: detail).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true).help(detail)
                }
            }
        } icon: {
            Image(systemName: item.icon)
        }
        .foregroundStyle(color)
    }

    /// One row per thing the app can do, like the permissions list in System Settings: what Lamp's own checks
    /// found in the code, worst first, then what the AI noticed beyond them, each an icon in a tinted square and
    /// a line in plain words.
    private func capabilities(_ review: ImportReview) -> some View {
        let found = review.detected.sorted { $0.level > $1.level }
        let rows = found.map { Row(icon: $0.icon, tint: tint(for: $0.level), text: $0.label) }
            + review.capabilities.map { Row(icon: "sparkle.magnifyingglass", tint: .purple, text: $0) }
        return VStack(spacing: 0) {
            if rows.isEmpty {
                // Says what the checks found, not what the app can't do.
                row(Row(icon: "magnifyingglass", tint: .secondary, text: "Nothing found by Lamp's checks."))
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, item in
                row(item)
                if index < rows.count - 1 { Divider().padding(.leading, 48) }
            }
        }
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private struct Row {
        let icon: String
        let tint: Color
        let text: String
    }

    private func row(_ item: Row) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(item.tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(verbatim: item.text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
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

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}


/// The Try On choices in a wish's menu on the desk: the one list the chat's bar draws too (`TryOnMenu`).
private struct TryOnChoices: View {
    @EnvironmentObject private var store: Store
    let project: LampProject

    var body: some View {
        if let menu = TryOnMenu.make(for: project, store: store) {
            ForEach(Array(menu.sections.enumerated()), id: \.offset) { index, section in
                if index > 0, !section.submenu { Divider() }
                if let title = section.title, section.submenu {
                    Menu(title) { items(section) }
                } else if let title = section.title {
                    Section(title) { items(section) }
                } else {
                    items(section)
                }
            }
            .onAppear { store.refreshDevices(); store.refreshSimulators() }
        }
    }

    @ViewBuilder private func items(_ section: TryOnMenu.Section) -> some View {
        ForEach(section.items) { item in
            Toggle(isOn: Binding(get: { item.checked }, set: { _ in store.tryOn(project, item.id) })) {
                Label(item.title, systemImage: item.symbol)
            }
            .disabled(item.disabled)
        }
    }
}

extension Store {
    /// What the app's AI has cost, under its name in the toolbar ("AI: 3 calls · $0.02"); nil before it's used any.
    func usageSummary(_ project: LampProject) -> String? {
        guard let usage = usage[project.id], usage.calls > 0 else { return nil }
        let calls = "AI: \(usage.calls) call\(usage.calls == 1 ? "" : "s")"
        return usage.cost < 0.005 ? calls : calls + String(format: " · $%.2f", usage.cost)
    }
}
