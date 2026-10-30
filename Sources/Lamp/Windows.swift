import SwiftUI
import AppKit

/// Lamp's window: the desk. Each wish's chat is beside whatever shows it (`ChatPanel`). `Store.selection` is the wish
/// whose chat is in front (nil for the desk), so what acts on "this wish" (the menu bar's commands, the dialogs) acts
/// on the chat being looked at. File → Duplicate… acts on the desk's pick while the desk is in front (`DeskPick`).
@MainActor
enum LampWindows {
    /// SwiftUI's way to open a window, handed over by the first window to appear. It opens any of the app's
    /// scenes, so the one kept serves after its window has closed.
    static var open: OpenWindowAction?

    /// The desk's window while it exists (`DeskWindowMarker`): gone once it's closed.
    static weak var desk: NSWindow?

    /// Whether the desk is on screen now: not closed, minimized or put away for an app's sidebar.
    static var deskShown: Bool { (desk ?? MagicPanel.mainWindow)?.isVisible == true }

    /// The desk's window, opened again if it was closed or put away for an app's sidebar.
    static func showDesk() {
        if let main = desk ?? MagicPanel.mainWindow, !main.isVisible { main.makeKeyAndOrderFront(nil) }
        open?(id: "main")
    }
}

/// The wish picked on the desk, for the menu bar's commands. An object of its own, so moving the pick doesn't redraw
/// everything that watches the store. Whether the desk is key is followed from the window rather than left to SwiftUI's
/// focused values: those didn't come back to the desk after Settings had been in front.
@MainActor
final class DeskPick: ObservableObject {
    static let shared = DeskPick()

    /// The desk's `current`: the row clicked or moved to, else the first.
    @Published var wish: LampProject.ID?
    @Published var deskIsKey = false

    /// A chat or Settings in front never acts on a row behind it.
    var target: LampProject.ID? { deskIsKey ? wish : nil }
}

/// Notes the window the desk is drawn in (`LampWindows.desk`), so what's asked of the desk asks the real window.
struct DeskWindowMarker: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { LampWindows.desk = window }
        }
    }
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {}
}

/// Runs `became` whenever the window this view is in becomes the key window, and `resigned` when it stops being it.
struct WindowKeyWatcher: NSViewRepresentable {
    let became: () -> Void
    var resigned: () -> Void = {}

    final class Probe: NSView {
        var became: (() -> Void)?
        var resigned: (() -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else {
                resigned?()
                return
            }
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.became?() }
                },
                center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.resigned?() }
                },
            ]
            if window.isKeyWindow { DispatchQueue.main.async { [weak self] in self?.became?() } }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: Probe, context: Context) {
        view.became = became
        view.resigned = resigned
    }
}

/// The questions and sheets the store raises (rename, name a version, delete, a shared wish to review, Image
/// Playground), shown in the one window in front so they're asked once. Another window coming to the front
/// moves an open one there rather than answering it.
struct StoreDialogs: ViewModifier {
    @EnvironmentObject private var store: Store
    @ObservedObject private var setupSheet = SetupSheet.shared
    let active: Bool
    @State private var newName = ""
    @State private var versionName = ""

    func body(content: Content) -> some View {
        content
        .sheet(item: Binding(get: { active ? store.pendingImport : nil }, set: { if active { store.pendingImport = $0 } })) { pending in
            ImportReviewView(pending: pending)
        }
        // Not while a chat's setup sheet is up: Image Playground opens over that (`SetupSheet`).
        .modifier(PlaygroundIconSheet(active: active && !setupSheet.isShowing))
        .alert("Rename “\(store.renaming?.name ?? "")”", isPresented: Binding(
            get: { active && store.renaming != nil }, set: { if active, !$0 { store.renaming = nil } })) {
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
            get: { active && store.naming != nil }, set: { if active, !$0 { store.naming = nil } })) {
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
        .confirmationDialog("Delete “\(store.deleting?.title ?? "")”?", isPresented: Binding(
            get: { active && store.deleting != nil }, set: { if active, !$0 { store.deleting = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let project = store.deleting { Task { await store.delete(project) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // A device app comes off the devices Lamp put it on too (`DeviceApps.removeEverywhere`), whichever app of the
            // wish it is.
            Text("The wish, its chat, its history and what it saved are moved to the Trash."
                 + (store.deleting.flatMap { wish in store.apps(of: wish).lazy.compactMap { $0.hasDevice ? DeviceApps.integration(for: $0)?.name : nil }.first }
                    .map { " It's also taken off your \($0)." } ?? ""))
        }
        .dialogIcon(store.deleting.map { Image(nsImage: store.iconImage(for: $0)) })
        .onChange(of: store.renaming) { newName = store.renaming.map { $0.untitled ? "" : $0.name } ?? "" }
    }
}

extension Store {
    /// The color a stand-in icon is drawn in: the design's, or the one chosen with the app's name before it.
    func standInColor(for project: LampProject) -> String? {
        Icons.load(project)?.background ?? iconColors[project.id]
    }

    /// The app's own icon, or its blueprint stand-in if it doesn't have one yet.
    func iconImage(for project: LampProject) -> NSImage {
        if let icon = icons[project.id] { return icon }
        let renderer = ImageRenderer(content: StandInIcon(project: project, size: 128, color: standInColor(for: project)))
        renderer.scale = 2
        return renderer.nsImage ?? NSApp.applicationIconImage
    }
}
