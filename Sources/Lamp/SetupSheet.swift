import SwiftUI
import AppKit
import LampSidebarKit

/// A setup card's own sheet: what the chat shows as a card's header with Set Up… (`SidebarLine.Kind.offer`) is set up
/// here, in Lamp, where its keys, downloads and sign-ins can be typed and Image Playground opened. The chat beside a
/// Mac app can't hold them, since it's drawn inside the app's window, so both chats hand them to Lamp the same way:
/// as a sheet on Lamp's own chat panel when the chat is there, else as a panel of its own in front.
@MainActor
final class SetupSheet: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = SetupSheet()

    /// The card being set up: its wish and its line. Image Playground opens over this sheet while it's up, not over
    /// the desk (`StoreDialogs`).
    @Published private(set) var showing: (project: String, line: UUID)?
    var isShowing: Bool { showing != nil }

    private var window: NSPanel?
    /// The app in front when the sheet came up by itself (a terminal Claude Code works in): it keeps being the active
    /// app, and gets activation back if something in the sheet took it.
    private var returnTo: NSRunningApplication?

    /// `byItself`: the sheet comes up without a click, while another app is in front. It floats over that app without
    /// making Lamp the active app, so none of Lamp's other windows come forward; a click in it gives it the keyboard
    /// (a non-activating panel), and when it goes the keyboard is back where it was.
    func show(_ project: LampProject, line: LogLine, byItself: Bool = false) {
        returnTo = nil
        close()
        let front = NSWorkspace.shared.frontmostApplication
        let beside = byItself && front?.processIdentifier != ProcessInfo.processInfo.processIdentifier
        returnTo = beside ? front : nil
        showing = (project.id, line.id)
        if line.kind == .drawIcon { Store.shared.iconFromPlayground(project) }
        var style: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
        if beside { style.insert(.nonactivatingPanel) }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: style, backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: SetupSheetView(projectID: project.id, lineID: line.id) { [weak self] in self?.close() }
            .environmentObject(Store.shared))
        window = panel
        if beside {
            panel.center()
            panel.level = .floating
            // Lamp stays in the background, where a panel would otherwise hide.
            panel.hidesOnDeactivate = false
            panel.orderFrontRegardless()
            return
        }
        NSApp.activate()
        if let chat = ChatPanel.window(for: project.id) {
            chat.beginSheet(panel)
        } else {
            panel.center()
            panel.level = .floating
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        guard let window else { return }
        self.window = nil
        if let parent = window.sheetParent { parent.endSheet(window) } else { window.close() }
        showing = nil
        giveFocusBack()
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === window { window = nil; showing = nil; giveFocusBack() }
    }

    /// Only needed when something in the sheet made Lamp the active app (Image Playground, a dialog): activation is
    /// handed back to the app that had it, as macOS's cooperative activation lets an active app do.
    private func giveFocusBack() {
        guard let app = returnTo else { return }
        returnTo = nil
        guard NSApp.isActive, !app.isTerminated else { return }
        NSApp.yieldActivation(to: app)
        app.activate(from: .current, options: [])
    }
}

/// The card itself, as it was drawn in Lamp's window: the setup offer with its rows, or the app's icon to draw.
private struct SetupSheetView: View {
    @EnvironmentObject private var store: Store
    let projectID: String
    let lineID: UUID
    let done: () -> Void

    var body: some View {
        let project = store.projects.first { $0.id == projectID }
        let line = store.logs[projectID]?.first { $0.id == lineID }
        if line?.kind == .needsBuilder {
            SetupView(later: done)
                .onChange(of: store.setup.hasBuilder && store.setup.hasAgent) { _, set in if set { done() } }
        } else {
            card(project, line)
        }
    }

    private func card(_ project: LampProject?, _ line: LogLine?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let project, let line {
                switch line.kind {
                case .needsKey, .offer:
                    if let offer = line.setupOffer { SetupCard(offer: offer, reason: line.text, dir: project.dir) }
                case .drawIcon:
                    HStack(spacing: 14) {
                        AppIcon(project: project, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(DrawIconLine.text(project.name)).font(.headline)
                            Text("Image Playground makes its picture, and you pick the one you like.").foregroundStyle(.secondary)
                        }
                    }
                    Button("Draw Icon…") { store.iconFromPlayground(project) }.cardButtons()
                default:
                    EmptyView()
                }
            }
            HStack {
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction).cardButtons()
            }
        }
        .padding(20)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(PlaygroundIconSheet(active: true))
    }
}
