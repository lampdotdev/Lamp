import SwiftUI
import AppKit
import Combine

/// An app's chat beside the app itself, opened by the 🪄 in its title bar (`LampMagic` in LampSupport.swift), so
/// the person can change the app while using it. It's Lamp's own chat for that app (`ProjectView`), in a panel
/// that floats over the app without bringing Lamp's main window forward: what's said here is said in the main
/// window too. The app tells Lamp where its window is, and the panel keeps to its side. It shows while the app,
/// or Lamp, is in front, and stays while the app is closed for a change to go in, so the build can be followed
/// until the app opens again.
@MainActor
final class MagicPanel: NSObject, NSWindowDelegate {
    static let shared = MagicPanel()

    private var panel: NSPanel?
    private(set) var appID: String?
    /// The app's window as it last said, in screen coordinates; nil when it's out of sight.
    private var appFrame: NSRect?
    private var observers: [NSObjectProtocol] = []
    private var busyWatch: AnyCancellable?
    static let width: CGFloat = 400
    private static let gap: CGFloat = 8

    func show(_ id: String, beside frame: NSRect? = nil) {
        guard let project = Store.shared.projects.first(where: { $0.id == id }) else { return }
        if appID != project.id { close() }
        appID = project.id
        if let frame, frame.width > 0, frame.height > 0 { appFrame = frame }
        let panel = self.panel ?? makePanel(for: project)
        self.panel = panel
        if appFrame != nil { place() } else { panel.center() }
        panel.makeKeyAndOrderFront(nil)
        listen(for: project)
    }

    func close() {
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0) }
        observers = []
        busyWatch = nil
        if let appID, let project = Store.shared.projects.first(where: { $0.id == appID }) { Store.shared.announceDraft(of: project) }
        panel?.orderOut(nil)
        panel = nil
        appID = nil
        appFrame = nil
    }

    private func makePanel(for project: LampProject) -> NSPanel {
        // Non-activating: typing here doesn't bring Lamp, and its main window, in front of the app.
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 600),
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = project.name
        // A plain title bar over a solid chat: the panel floats over other windows, and what's behind it showing
        // through the chat made it hard to read.
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 320, height: 360)
        panel.delegate = self
        let host = NSHostingController(rootView: MagicChat(project: project).environmentObject(Store.shared))
        // The chat's toolbar is for Lamp's window: kept out of this panel's title bar, where it overlapped the chat.
        host.sceneBridgingOptions = []
        panel.contentViewController = host
        return panel
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { close() }
    }

    // The panel and Lamp's window are two editors of one message box: each takes up what was typed in the
    // other as typing moves between them.
    nonisolated func windowDidBecomeKey(_ notification: Notification) {
        MainActor.assumeIsolated { announceDraft() }
    }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated { announceDraft() }
    }

    private func announceDraft() {
        guard let appID, let project = Store.shared.projects.first(where: { $0.id == appID }) else { return }
        Store.shared.announceDraft(of: project)
    }

    private func listen(for project: LampProject) {
        guard observers.isEmpty else { return }
        let id = project.id
        // Where the app's window is. Only the position of something Lamp draws depends on it.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Edition.notificationPrefix + "windowFrame"), object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let current = Store.shared.projects.first(where: { $0.id == id }), note.object as? String == current.bundleID else { return }
                let text = note.userInfo?["frame"] as? String ?? ""
                self.appFrame = text.isEmpty ? nil : NSRectFromString(text)
                self.place()
            }
        })
        // Over the app and Lamp only: another app in front puts it away until one of them comes back. Looked at
        // again when the app's turn ends too, which ends the exception for a change going in.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateVisibility() }
        })
        busyWatch = Store.shared.$busy.map { $0.contains(id) }.removeDuplicates().dropFirst()
            .receive(on: RunLoop.main).sink { [weak self] _ in MainActor.assumeIsolated { self?.updateVisibility() } }
    }

    private func updateVisibility() {
        guard let panel, let appID, let current = Store.shared.projects.first(where: { $0.id == appID }) else { return }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let copies = Store.shared.macCopies(of: current)
        let ours = front == ProcessInfo.processInfo.processIdentifier || copies.contains { $0.processIdentifier == front }
        // While the app is closed for a change, the chat is where the change is followed.
        let updating = copies.isEmpty && Store.shared.busy.contains(appID)
        if ours || updating { panel.orderFront(nil) } else { panel.orderOut(nil) }
    }

    /// Beside the app's window, on whichever side has room, as tall as it; over its right edge when neither has.
    private func place() {
        guard let panel, let frame = appFrame else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
        let width = max(panel.frame.width, panel.minSize.width)
        var x = frame.maxX + Self.gap
        if x + width > screen.maxX { x = frame.minX - Self.gap - width }
        if x < screen.minX { x = min(frame.maxX, screen.maxX) - width - Self.gap }
        let height = min(max(frame.height, panel.minSize.height), screen.height)
        let y = max(screen.minY, min(frame.minY, screen.maxY - height))
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: false)
    }
}

/// The chat in the panel: the app's chat as in Lamp's window, and a way back to that window for the rest.
private struct MagicChat: View {
    @EnvironmentObject private var store: Store
    let project: LampProject

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Open in Lamp") {
                    store.showChat(project.id)
                    MagicPanel.shared.close()
                }
                .buttonStyle(.link)
                .font(.callout)
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            Divider()
            ProjectView(project: store.current(project) ?? project)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 320, minHeight: 360)
    }
}
