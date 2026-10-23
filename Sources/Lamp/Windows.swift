import SwiftUI
import AppKit

/// Lamp's windows, as a document app has them: the desk, and one window for each wish's chat, listed in the
/// Window menu. `Store.selection` is the wish whose window is in front (nil for the desk), so what acts on
/// "this wish" (the menu bar's commands, the dialogs) acts on the window being looked at.
@MainActor
enum LampWindows {
    /// SwiftUI's way to open a window, handed over by the first window to appear. It opens any of the app's
    /// scenes, so the one kept serves after its window has closed.
    static var open: OpenWindowAction?

    /// A wish's chat in its own window, or that window brought to the front when it's open already.
    static func showChat(_ id: String) {
        open?(id: "wish", value: id)
    }

    /// The desk's window, opened again if it was closed or put away for an app's sidebar.
    static func showDesk() {
        if let main = MagicPanel.mainWindow, !main.isVisible { main.makeKeyAndOrderFront(nil) }
        open?(id: "main")
    }
}

/// One wish's chat, alone in its window. It follows the wish when its first request moves it to a new folder,
/// and closes when the wish is deleted.
struct WishWindow: View {
    @EnvironmentObject private var store: Store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Binding var id: String?

    private var project: LampProject? { id.flatMap(store.project(following:)) }

    var body: some View {
        Group {
            if let project {
                VStack(spacing: 0) {
                    if store.setup.checked && !store.setup.hasBuildTools { BuildToolsBanner() }
                    ProjectView(project: project).id(project.id)
                }
                .modifier(StoreDialogs(active: store.selection == project.id))
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(WindowKeyWatcher { if let project { store.selection = project.id } })
        .onAppear { LampWindows.open = LampWindows.open ?? openWindow }
        .onChange(of: project?.id, initial: true) { old, now in
            if let old { store.chatWindows.remove(old) }
            if let now { store.chatWindows.insert(now) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.markRead()
        }
        // Rescaffolded under a new id: the window's value follows, so it's still the one brought forward.
        .onChange(of: project?.id) { _, now in
            if let now, now != id { id = now }
        }
        // Its chat moved into the app's own window (`MagicPanel.handOff`).
        .onChange(of: store.chatsHandedOff) { _, handed in
            guard let id = project?.id, handed.contains(id) else { return }
            store.chatsHandedOff.remove(id)
            dismiss()
        }
        // Gone (deleted, or an empty wish discarded): the window goes too. Looked at again a moment later, so a
        // wish caught between its old folder and its new one isn't taken for gone.
        .task(id: project == nil) {
            guard project == nil else { return }
            try? await Task.sleep(for: .milliseconds(300))
            if project == nil { dismiss() }
        }
        .onDisappear {
            if let project { store.chatWindows.remove(project.id) }
            guard let id else { return }
            if store.selection == id { store.selection = nil }
            // An empty new wish goes with its window, as it went when the person left its chat.
            store.closedChat(id)
        }
    }
}

/// Runs `became` whenever the window this view is in becomes the key window.
struct WindowKeyWatcher: NSViewRepresentable {
    let became: () -> Void

    final class Probe: NSView {
        var became: (() -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                              queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.became?() }
            }
            if window.isKeyWindow { DispatchQueue.main.async { [weak self] in self?.became?() } }
        }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.became = became
        return view
    }

    func updateNSView(_ view: Probe, context: Context) { view.became = became }
}

/// The questions and sheets the store raises (rename, name a version, delete, a shared wish to review, Image
/// Playground), shown in the one window in front so they're asked once. Another window coming to the front
/// moves an open one there rather than answering it.
struct StoreDialogs: ViewModifier {
    @EnvironmentObject private var store: Store
    let active: Bool
    @State private var newName = ""
    @State private var versionName = ""

    func body(content: Content) -> some View {
        content
        .sheet(item: Binding(get: { active ? store.pendingImport : nil }, set: { if active { store.pendingImport = $0 } })) { pending in
            ImportReviewView(pending: pending)
        }
        .modifier(PlaygroundIconSheet(active: active))
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
            // A device app comes off the devices Lamp put it on too (`DeviceApps.removeEverywhere`).
            Text("The wish, its chat, its history and what it saved are moved to the Trash."
                 + (store.deleting.flatMap { $0.platform.hasDevice ? DeviceApps.integration(for: $0)?.name : nil }.map { " It's also taken off your \($0)." } ?? ""))
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
