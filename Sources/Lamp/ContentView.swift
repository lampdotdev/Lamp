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
                // Nothing set up, the desk still opens and its wishes run: what's missing is asked for in the chat when a
                // change needs it, and the request waits there until it's done.
                main
                    .frame(minWidth: 760, minHeight: 480)
            }
        }
        .modifier(StoreDialogs(active: store.selection == nil))
        .background(WindowKeyWatcher(became: {
            store.selection = nil
            DeskPick.shared.deskIsKey = true
        }, resigned: { DeskPick.shared.deskIsKey = false }))
        .background(DeskWindowMarker())
        .onAppear { LampWindows.open = openWindow }
    }

    private var main: some View {
        VStack(spacing: 0) {
            // While they install, while a request waits for them, or while they need repair: games and screens are made without them.
            if store.setup.checked && !store.setup.hasBuildTools
                && (store.setup.repair != nil || store.setup.installRequested || (store.setup.hasBuilder && store.waitsForAppleTools)) { BuildToolsBanner() }
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
        // The whole wish, as Play and Stop are: each app's own menu in the toolbar is for that app alone. Open and Remix
        // are the desk's own, above it (`DeskWishMenu`).
        Button("Rebuild & Open") { store.runPrepared(project) }
            .disabled(busy)
        Button("Quit") { Task { await store.quitWish(project) } }
            .disabled(!store.isWishOpen(project))
        // A wish whose apps are all in folders has only the way to one more app here (`TryOnMenu`).
        if TryOnMenu.make(for: project, store: store) != nil {
            // Which simulator the app opens in (it's built for both), or which of the person's own phones.
            Menu("Try On") { TryOnChoices(project: project) }
                .disabled(busy)
        }
        Divider()
        Button("Rename…") { store.renaming = project }
            // Still being found: the wish it becomes names it. A device's setup is never named.
            .disabled(busy || project.makesNoApp)
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
            Button("Copy App File") { store.copyAppFile(project) }
            Button { Sharing.share(project, from: .app(project.id)) } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Button("Export…") { store.chooseExport(project) }
            Divider()
        }
        Button("Delete…", role: .destructive) { store.deleting = project }
    }
}

/// While Apple's tools install, above everything: what's happening, and that the requests that need them wait for it.
struct BuildToolsBanner: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(spacing: 10) {
            if let repair = store.setup.repair {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(repair.text).font(.callout)
            } else {
                ProgressView().controlSize(.small)
                Text("Installing Apple's app-building tools. Apps that need them start as soon as they're in.")
                    .font(.callout)
            }
            Spacer()
            Button(store.setup.repair?.button ?? (store.setup.installRequested ? "Show Installer" : "Install…"), action: store.fixBuildTools)
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
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var mixing = MixModel.shared
    let pending: Store.PendingImport

    /// The app's own icon, once drawn from the file; the plain app icon until then, and for a file without one.
    @State private var icon: NSImage?
    /// How tall the sheet may be where it hangs: from its top down to the bottom of the screen's usable area
    /// (above the Dock), and no taller than Lamp's window, which cuts off whatever of a sheet goes past it.
    /// Unlimited until the sheet is on screen.
    @State private var room = CGFloat.infinity
    @State private var sheet: NSWindow?

    var body: some View {
        ImportReviewCard(name: pending.package.name, description: pending.package.description, icon: icon,
                         review: pending.review, existing: pending.existing?.name, changedHere: pending.changedHere, room: room,
                         cancel: store.cancelImport, open: store.confirmImport, update: store.confirmUpdate,
                         android: pending.package.platform.target.recipe.language == .kotlin, prepared: pending.prepared != nil,
                         mixWaits: mixing.stage == .mixing,
                         mix: pending.mixable ? { if store.mixPendingImport() { openWindow(id: "mix") } } : nil,
                         trying: pending.trying, tryIt: store.confirmTrial, ownFolder: pending.outside != nil,
                         progress: work?.failed == false ? work?.line : nil, failure: work?.failed == true ? work?.line : nil,
                         retry: store.retryReview)
            .task { icon = await Sharing.icon(of: pending.package) }
            .background(WindowFinder { sheet = $0; fit() })
            // The window can be moved or resized with the sheet down, and the Dock can come and go.
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { _ in fit() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in fit() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in fit() }
    }

    /// This sheet's review while it's made: its stage, or why it couldn't be.
    private var work: Store.ReviewWork? {
        store.reviewWork.flatMap { $0.sheet == pending.id ? $0 : nil }
    }

    private func fit() {
        guard let window = sheet?.sheetParent, let screen = window.screen else { return }
        room = Self.room(below: window.frame.minY + window.contentLayoutRect.maxY, on: screen.visibleFrame,
                         inside: window.contentLayoutRect.height)
    }

    /// The height a sheet can take when its top edge sits at `top` (screen coordinates, y up) on a screen
    /// whose usable area is `visible`, hanging in a window whose content is `inside` tall: down to the bottom of
    /// that area or of the window, whichever comes first, less a margin.
    nonisolated static func room(below top: CGFloat, on visible: CGRect, inside window: CGFloat = .infinity) -> CGFloat {
        (min(top - visible.minY, window) - 12).rounded(.down)
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
    /// That wish was changed here since it arrived: Update merges the new code into those changes, keeping them.
    var changedHere = false
    var room = CGFloat.infinity
    let cancel: () -> Void
    let open: () -> Void
    let update: () -> Void
    /// An Android app's reach is the phone's, not the Mac's.
    var android = false
    /// An update Lamp prepared in a copy of `existing` (`AppUpdates`): nobody shared it, and Update puts that copy in place.
    var prepared = false
    /// With mixing on (`Mix`), a file that can be mixed into `existing`: Mix… opens the mix window on it, in place of
    /// Update. The window checks their code itself, so it waits for nothing here.
    /// Another mix is being saved, which the window finishes first: Mix… waits for it.
    var mixWaits = false
    var mix: (() -> Void)? = nil
    /// Someone's suggested change, to try in a copy of `existing` (`SuggestionTrial`): Try It is the one choice, held to
    /// the same checks as opening.
    var trying = false
    var tryIt: () -> Void = {}
    /// A folder of the person's own that their coding agent asked Lamp to build: nobody shared it with them.
    var ownFolder = false
    /// While the review is made: the stage it's at (`Store.ReviewWork`).
    var progress: String? = nil
    /// The review couldn't be made (it ran out of time, or Lamp couldn't read the code through): said in place of it,
    /// with Try Again. Nothing is checked, so nothing opens or updates.
    var failure: String? = nil
    var retry: () -> Void = {}

    /// The heights of what stays put, measured as laid out: the app's name and description at the top, the
    /// review's summary, the line about the copy already here when there is one, and the buttons.
    @State private var fixed: [Part: CGFloat] = [:]
    private enum Part { case name, summary, existing, buttons }
    /// The height of Things to consider as laid out in full; nil when there's nothing to consider.
    @State private var considering: CGFloat?
    /// The height of the features under What it does as laid out in full; nil when the reviewer named none.
    @State private var featuring: CGFloat?
    private var heights: Heights {
        Self.heights(room: room, fixed: fixed.filter { $0.key != .buttons }.map(\.value), buttons: fixed[.buttons] ?? 0,
                     considering: considering, featuring: featuring)
    }

    /// How tall each part that scrolls may be.
    struct Heights: Equatable {
        var considering: CGFloat
        var featuring: CGFloat
        var capabilities: CGFloat
        /// The window is too short for each list to scroll on its own: everything above the buttons scrolls as
        /// one, up to `whole`, and the buttons stay under it.
        var compact = false
        var whole = CGFloat.infinity
    }

    /// What the scrolling parts share: the room under the sheet's top less the fixed parts, the sheet's padding (48)
    /// and a 16-point gap after each part but the last (8 above the features, which go on from the summary). They
    /// never take more between them, whatever the screen: Things to consider is shown whole when it fits, and
    /// otherwise scrolls, leaving the rest a few rows, or half when there isn't room for that; the features then
    /// take what they need of that the same way, and what the app can do the rest. A long list of concerns or
    /// features never pushes the buttons off the screen, and Lamp's verdict, its first lines, is what stays in view.
    /// Below 48 points nothing could be read, so that's the floor. In a window too short to leave the lists a few
    /// rows between them (120 points), the fixed parts and the lists scroll together instead, and only the buttons
    /// (`buttons` tall) stay put.
    static func heights(room: CGFloat, fixed: [CGFloat], buttons: CGFloat, considering: CGFloat?, featuring: CGFloat?) -> Heights {
        let scrolling = 1 + (considering == nil ? 0 : 1) + (featuring == nil ? 0 : 1)
        let budget = room - fixed.reduce(0, +) - buttons - 48 - 16 * CGFloat(fixed.count + scrolling) + (featuring == nil ? 0 : 8)
        if budget < 120 {
            return Heights(considering: 0, featuring: 0, capabilities: 0, compact: true, whole: max(48, room - buttons - 48 - 16))
        }
        let shared = budget
        func part(_ height: CGFloat?, of room: CGFloat) -> CGFloat { min(height ?? 0, max(room - 120, room / 2)) }
        let consider = part(considering, of: shared)
        let feature = part(featuring, of: shared - consider)
        // What the app can do: the height a long review always stopped at, or what's left.
        return Heights(considering: consider, featuring: feature, capabilities: min(460, shared - consider - feature))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if heights.compact {
                ScrollView { parts.frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: heights.whole)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                parts
            }
            buttons
                .cardButtons()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fixed[.buttons] = $0 }
        }
        .padding(24)
        .frame(width: 500)
    }

    /// A list that scrolls on its own up to `limit`, or, in a compact sheet, laid out whole in the one scroll.
    @ViewBuilder private func list<Content: View>(_ limit: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        if heights.compact {
            content()
        } else {
            ScrollView { content() }
                .frame(maxHeight: limit)
                .fixedSize(horizontal: false, vertical: true)   // no taller than its content, up to the limit
        }
    }

    /// Everything above the buttons.
    private var parts: some View {
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
                    Text(verbatim: title).font(.title2.bold())
                        .lineLimit(1).truncationMode(.middle)
                    // What Update This App does to the app already here, before what the review found.
                    if let lead {
                        Text(verbatim: lead).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // The sender's words, said to be theirs.
                    if let description, !prepared, !trying {
                        Text(verbatim: ownFolder ? "Its description: \(description)" : "Described by the person who shared it with you as: \(description)")
                            .font(.callout).foregroundStyle(.secondary).lineLimit(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fixed[.name] = $0 }

            if let review {
                // What it does and the start of what to weigh stay in view on any screen with room for a few rows
                // of the lists, so Lamp's verdict is never scrolled away beside the button that opens the app.
                // A window shorter than that scrolls it all together (`Heights.compact`), but keeps the buttons.
                if !review.summary.isEmpty {
                    section("What it does") {
                        // The reviewer is asked for a sentence or two: a few lines here, the whole of it on hover.
                        Text(review.summary).lineLimit(5).fixedSize(horizontal: false, vertical: true).help(review.summary)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fixed[.summary] = $0 }
                }
                if !review.capabilities.isEmpty {
                    // What the reviewer saw it do for the person: features, said with what the app is, not as
                    // permissions beside what Lamp's own checks found in the code. Up to eight, so they scroll.
                    list(heights.featuring) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(review.capabilities, id: \.self) { feature in
                                Label {
                                    Text(verbatim: feature).lineLimit(2).fixedSize(horizontal: false, vertical: true).help(feature)
                                } icon: {
                                    // A plain mark: what's listed is what the app does, not something Lamp approved.
                                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.secondary)
                                }
                                .font(.callout)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { featuring = $0 }
                    }
                    .padding(.top, review.summary.isEmpty ? 0 : -8)
                }
                let considerations = Self.considerations(review, prepared: prepared)
                if !considerations.isEmpty {
                    list(heights.considering) {
                        section("Things to consider") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(considerations) { consideration($0) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { considering = $0 }
                    }
                }
                list(heights.capabilities) {
                    // An Android app runs on the emulator or the person's phone, never on the Mac itself.
                    section(android ? "What it can do" : "What it can do on your Mac") { capabilities(review) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let failure {
                Label {
                    Text(verbatim: failure).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .padding(.vertical, 20)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(verbatim: progress ?? "Checking what this app does…").foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
            }

            if let existing, trying {
                Label {
                    Text(verbatim: "Lamp opens a copy of “\(existing)” with these changes and none of your data. Your app stays as it is, and the copy goes when you quit it.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "square.on.square").foregroundStyle(.secondary)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fixed[.existing] = $0 }
            } else if let existing, mix != nil || !prepared {
                // What the other choice does: the update's own lead is under the title. A prepared update says both there.
                Label {
                    Text(verbatim: mix != nil
                         ? "You already have this app\(existing == name ? "" : ", as “\(existing)”"). Mix lets you pick which of its changes to bring into yours. \(Self.separateLine)"
                         : Self.separateLine)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: mix != nil ? "arrow.triangle.merge" : "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fixed[.existing] = $0 }
            }
        }
    }

    /// The sheet's title: an update of the app already here says so, and one prepared in a copy says it's ready.
    private var title: String {
        if prepared { return "Your update to “\(existing ?? name)” is ready" }
        if trying { return "Try these changes to “\(name)”?" }
        if let existing, mix == nil { return "Update “\(existing)”?" }
        return "Open “\(name)”?"
    }

    /// What updating does to the app already here, under the title.
    private var lead: String? {
        guard existing != nil, mix == nil, !trying else { return nil }
        if prepared {
            return "This copy includes the update and your changes. Update This App replaces your current app's code and keeps its saved data. "
                + "Keep as Separate App keeps the prepared copy alongside your current app."
        }
        return changedHere
            ? "Bring in the update and keep your changes. Lamp will ask you about conflicts it can't resolve. Your saved data stays, and you can undo the update."
            : "Replace this app's code with the update. Your saved data stays, and you can undo the update."
    }

    static let separateLine = "Keep as Separate App adds the incoming version to your library and leaves your current app unchanged."

    private var buttons: some View {
        HStack {
            Spacer()
            // Escape always cancels. Return builds only when the review is in and vouches for the app
            // (`ImportReview.opening`); anything less takes a deliberate click.
            Button("Cancel", role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
            if failure != nil {
                // Nothing was checked: the one thing to do is check again.
                Button("Try Again", action: retry)
                    .keyboardShortcut(.defaultAction)
            } else if trying {
                // The copy's code runs as an opened app's does, so it follows the same rule.
                switch review?.opening {
                case .byReturn:
                    Button("Try It", action: tryIt)
                        .keyboardShortcut(.defaultAction)
                case .anyway:
                    Button("Try It Anyway", role: .destructive, action: tryIt)
                case .byClick, nil:
                    Button("Try It", action: tryIt)
                        .disabled(review == nil)
                }
            } else if existing != nil, let mix {
                switch review?.opening {
                case .anyway: Button("Keep Separate App Anyway", role: .destructive, action: open)
                case .byReturn, .byClick, nil: Button("Keep as Separate App", action: open).disabled(review == nil)
                }
                Button("Mix…", action: mix)
                    .keyboardShortcut(.defaultAction)
                    .disabled(mixWaits)
            } else if existing != nil {
                // The app is already here: the file either becomes its next version or a second app.
                // Either way its code runs, so both follow the same rule as opening does. Return is
                // only ever Update This App: a separate app is the choice someone makes on purpose.
                switch review?.opening {
                case .byReturn:
                    Button("Keep as Separate App", action: open)
                    Button("Update This App", action: update)
                        .keyboardShortcut(.defaultAction)
                case .anyway:
                    Button("Keep Separate App Anyway", role: .destructive, action: open)
                    Button("Update Anyway", role: .destructive, action: update)
                case .byClick, nil:
                    Button("Keep as Separate App", action: open)
                        .disabled(review == nil)
                    Button("Update This App", action: update)
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

    static let partlyChecked = "AI didn't check all of its code. Open only if you trust the sender"

    /// The verdict first, unless it's an all-clear (said by nothing being here), then each concern.
    /// `prepared` is an update Lamp prepared for an app here: there's no sender to trust, only the update to look at.
    static func considerations(_ review: ImportReview, prepared: Bool = false) -> [Consideration] {
        var list: [Consideration] = []
        switch review.verdict {
        case .risky where prepared:
            list.append(Consideration(text: "Looks risky. Don't update unless you expected this", weight: .warning, icon: "xmark.octagon.fill"))
        case .partlyChecked where prepared:
            list.append(Consideration(text: "AI didn't check all of its code. Update only if you trust where the app came from", weight: .caution))
        case .risky: list.append(Consideration(text: "Looks risky. Don't open unless you trust the sender", weight: .warning, icon: "xmark.octagon.fill"))
        case .sensitive: list.append(Consideration(text: "Does sensitive things. Open only if you expected that", weight: .warning, icon: "exclamationmark.octagon.fill"))
        case .partlyChecked: list.append(Consideration(text: Self.partlyChecked, weight: .caution))
        case .powerful: list.append(Consideration(text: "Powerful. Check it's what you expect", weight: .caution))
        case .checkedInParts:
            list.append(Consideration(text: prepared ? "AI checked its code in parts. Update only if you trust where the app came from"
                                                     : "AI checked its code in parts. Open only if you trust the sender", weight: .caution))
        case .checkedOnThisMac: list.append(Consideration(text: "Nothing worrying found, but not by a check Lamp can vouch for", weight: .caution))
        case .unchecked: list.append(Consideration(text: "Not checked by AI", weight: .warning, detail: review.note))
        case .safe: break
        }
        // What the code was seen to do can outrank the missing check in the verdict; the reader still hears,
        // in red, that no AI read it, and why.
        if review.risk == nil, review.verdict != .unchecked, review.asked || review.note != nil {
            list.append(Consideration(text: "Not checked by AI", weight: .warning, detail: review.note))
        }
        // A worse verdict leads, and unread code is still said, once.
        if review.partial, review.risk != nil, review.verdict != .partlyChecked {
            list.append(Consideration(text: "AI didn't check all of its code", weight: .caution))
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
    /// found in the code, worst first, each an icon in a tinted square and a line in plain words. What the AI saw it
    /// do for the person is under What it does.
    private func capabilities(_ review: ImportReview) -> some View {
        let found = review.detected.sorted { $0.level > $1.level }
        let rows = found.map { Row(icon: $0.icon, tint: tint(for: $0.level), text: $0.label) }
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
