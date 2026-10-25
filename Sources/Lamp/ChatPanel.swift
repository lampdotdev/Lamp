import SwiftUI
import AppKit
import ApplicationServices
import LampSidebarKit

/// A wish's chat where no Mac app of its own shows it: the screen the extension draws beside a Mac app (`ChatScreen`),
/// drawn by Lamp in a panel of its own, beside whatever is showing the wish. Beside the iPhone or iPad simulator,
/// the Android emulator, or one of Lamp's own previews (a TV, a device's screen) it's attached to that window and
/// follows it; where nothing on this Mac shows the wish (an app on a TV, an Xbox or the person's phone, a widget, the
/// menu bar, the background, a wish not made yet or being found, an app that didn't build or crashed) it's a window
/// of its own in the middle of the screen, wider than beside a window, since the chat is then what's being looked at.
///
/// A wish's chat is in one place at a time: this panel or the extension beside its Mac app (`MagicPanel`), and moving
/// between them keeps the draft (it's the store's) and where the person was reading (`ChatLink.readingAt`).
@MainActor
final class ChatPanel: NSObject, NSWindowDelegate {
    private static var open: [String: ChatPanel] = [:]

    /// The wish's chat in front, in Lamp's panel, made when there's none. Lamp comes in front with it unless
    /// `activate` is false (a chat put up beside an app the person is using, which keeps the keyboard).
    static func show(_ id: String, activate: Bool = true) {
        let panel = open[id] ?? ChatPanel(id: id)
        open[id] = panel
        panel.place()
        if activate {
            NSApp.activate()
            panel.window.makeKeyAndOrderFront(nil)
        } else {
            panel.window.orderFront(nil)
        }
    }

    static func isOpen(_ id: String) -> Bool { open[id] != nil }
    /// The wish's panel, for a sheet of Lamp's over it (`SetupSheet`).
    static func window(for id: String) -> NSWindow? { open[id]?.window }
    static var openIDs: [String] { Array(open.keys) }

    /// The chat went somewhere else (beside the app, which has connected its own), or its wish is gone.
    static func close(_ id: String) { open[id]?.close() }

    /// A wish's folder moved (its first request named it): its panel follows it to the new id.
    static func moved(_ id: String, to new: String) {
        guard id != new, let panel = open.removeValue(forKey: id) else { return }
        open[new] = panel
        panel.id = new
        SidebarServer.shared.follow(panel.link, to: new)
    }

    /// The panel that's key, for the menus' commands (`Store.selection`).
    static var keyID: String? { open.first { $0.value.window.isKeyWindow }?.key }

    private(set) var id: String
    let link: LocalChat
    let window: Panel
    private var follower: Timer?
    /// The person dragged it away by its bar: it stays where they put it, until what it's beside changes.
    private var detached = false
    /// What it was last put beside, and that window's frame then, so it's moved only when one of those changes.
    private var besideKey: String?
    private var besideFrame: CGRect?

    /// The panel's width beside a window, kept for every wish, between the chat's narrowest and widest (as
    /// `LampSidebar.width`): narrow, since the window beside it is what's being looked at.
    private static let widthKey = "chatPanelWidth"
    private static let narrowest: CGFloat = 320
    private static let widest: CGFloat = 640
    private static var width: CGFloat {
        get { kept(widthKey, default: 380, widest: widest) }
        set { UserDefaults.standard.set(Double(newValue), forKey: widthKey) }
    }
    /// Its width on its own, kept apart: with nothing beside it the chat is what's being looked at, so it's a window of
    /// its own size rather than a strip down the side of the screen.
    private static let aloneWidthKey = "chatPanelAloneWidth"
    private static let aloneWidest: CGFloat = 900
    private static var aloneWidth: CGFloat {
        get { kept(aloneWidthKey, default: 620, widest: aloneWidest) }
        set { UserDefaults.standard.set(Double(newValue), forKey: aloneWidthKey) }
    }

    private static func kept(_ key: String, default value: CGFloat, widest: CGFloat) -> CGFloat {
        let kept = CGFloat(UserDefaults.standard.double(forKey: key))
        return kept > 0 ? min(max(kept, narrowest), widest) : value
    }

    /// Titled for its edges and shadow, with the title bar hidden: the chat draws its own bar (`ChatBar`), with the
    /// close button and the room to drag it by.
    final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private init(id: String) {
        self.id = id
        link = SidebarServer.shared.local(for: id)
        window = Panel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 640),
                       styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        link.panel = self
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(button)?.isHidden = true }
        // Moved by its bar (`startMove`), never by the title bar it doesn't show: that would take presses meant for the
        // bar's buttons.
        window.isMovable = false
        window.isFloatingPanel = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenAuxiliary, .managed]
        window.minSize = NSSize(width: Self.narrowest, height: 360)
        window.maxSize = NSSize(width: Self.aloneWidest, height: .greatestFiniteMagnitude)
        window.title = Store.shared.projects.first { $0.id == id }?.title ?? "Wish"
        window.delegate = self
        window.contentView = NSHostingView(rootView: PanelContent(link: link).environmentObject(Store.shared))
        // Following what it's beside: Lamp's own windows tell it when they move, other apps' don't, so it looks.
        follower = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        if Store.shared.selection == id { Store.shared.selection = nil }
        follower?.invalidate()
        follower = nil
        window.parent?.removeChildWindow(window)
        if Self.open[id] === self { Self.open[id] = nil }
        SidebarServer.shared.letGo(link)
        // An empty new wish goes with its chat, as it went when the person left it.
        Store.shared.closedChat(id)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        Store.shared.selection = id
        Store.shared.markRead()
    }

    func windowDidResize(_ notification: Notification) {
        // Only a width the person chose: a panel squeezed beside a window keeps the width they want for the next. Beside
        // a window and on its own are kept apart.
        guard window.inLiveResize else { return }
        if besideKey == nil { Self.aloneWidth = window.frame.width } else { Self.width = min(window.frame.width, Self.widest) }
    }

    // MARK: Moving it

    /// The chat's bar was pressed and dragged: the panel follows the pointer until the button is let go, and stays
    /// where it's put.
    func startMove() {
        let start = NSEvent.mouseLocation
        let origin = window.frame.origin
        detached = true
        window.parent?.removeChildWindow(window)
        var monitor: Any?
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            let now = NSEvent.mouseLocation
            self.window.setFrameOrigin(NSPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y))
            if event.type == .leftMouseUp, let monitor { NSEvent.removeMonitor(monitor) }
            return event
        }
    }

    // MARK: Where it goes

    /// What the chat is beside now: one of Lamp's own windows, another app's (by its process and frame), or nothing.
    private enum Beside {
        case lamp(NSWindow)
        case other(key: String, frame: CGRect)
    }

    /// The wish's Mac app was open when last looked: one that opens since takes its chat beside it.
    private var openOnMac: Bool?

    /// Looks at which the wish was gone: one gone for good (deleted, or an empty wish discarded) takes its chat with it.
    private var missing = 0

    private func place() {
        let project = Store.shared.projects.first { $0.id == id }
        // Looked at again a moment later, so a wish between its old folder and its new one isn't taken for gone.
        missing = project == nil && Store.shared.project(following: id) == nil ? missing + 1 : 0
        if missing > 3 { return close() }
        // Its name in the Window menu and Mission Control follows the wish's.
        if let title = project?.title, window.title != title { window.title = title }
        // Its Mac app opened (Play, a reopen for a change, the person opening it): the chat goes beside it, in one place.
        let open = Store.shared.openOnMac.contains(id)
        if let project, open, openOnMac == false {
            Task {
                guard await MagicPanel.chatsInApp(project), MagicPanel.runningCopiesTakeTheChat(project) else { return }
                MagicPanel.shared.openChat(in: project)
            }
        }
        openOnMac = open
        let beside = Self.beside(for: id)
        let key: String? = switch beside {
        case .lamp(let parent): "lamp:\(parent.windowNumber)"
        case .other(let key, _): key
        case nil: nil
        }
        let frame: CGRect? = switch beside {
        case .lamp(let parent): parent.frame
        case .other(_, let frame): frame
        case nil: nil
        }
        // Something else to be beside (or nothing any more): a panel dragged away comes back to it.
        if key != besideKey { detached = false }
        guard !detached else { return }
        guard key != besideKey || frame != besideFrame || window.frame.isEmpty || !window.isVisible else { return }
        besideKey = key
        besideFrame = frame
        if case .lamp(let parent) = beside {
            if window.parent !== parent {
                window.parent?.removeChildWindow(window)
                parent.addChildWindow(window, ordered: .above)
            }
        } else if let parent = window.parent {
            parent.removeChildWindow(window)
        }
        let screen = frame.flatMap { frame in NSScreen.screens.first { $0.frame.intersects(frame) } } ?? window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var placed = frame.map { Self.frame(beside: $0, in: visible, width: Self.width) } ?? Self.floating(in: visible, width: Self.aloneWidth)
        // Two chats on their own at once: each a step down and across, as windows cascade, so none hides another.
        if frame == nil {
            while placed.minY - 28 >= visible.minY, placed.maxX + 28 <= visible.maxX,
                  Self.open.values.contains(where: { $0 !== self && $0.window.isVisible && $0.window.frame.origin == placed.origin }) {
                placed = placed.offsetBy(dx: 28, dy: -28)
            }
        }
        window.setFrame(placed, display: true, animate: false)
    }

    /// Beside a window: on the right when there's room, else on the left, else over the window's right edge; as tall
    /// as the window, but never less than a chat needs.
    nonisolated static func frame(beside window: CGRect, in visible: CGRect, width: CGFloat) -> CGRect {
        let gap: CGFloat = 8
        let height = min(max(window.height, 480), visible.height)
        let top = min(window.maxY, visible.maxY)
        let y = max(visible.minY, top - height)
        let x: CGFloat
        if visible.maxX - window.maxX >= width + gap {
            x = window.maxX + gap
        } else if window.minX - visible.minX >= width + gap {
            x = window.minX - gap - width
        } else {
            x = max(visible.minX, visible.maxX - width)
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// On its own: a window of its own size in the middle of the screen, as tall as a chat reads well, never taller
    /// than the screen allows.
    nonisolated static func floating(in visible: CGRect, width: CGFloat) -> CGRect {
        let margin: CGFloat = 12
        let width = min(width, visible.width - 2 * margin)
        let height = min(820, visible.height - 2 * margin)
        return CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height).integral
    }

    /// The window showing the wish on this Mac, if any: Lamp's preview of it, the simulator it's open in, or Lamp's
    /// Android emulator. Nil for a wish nothing on this Mac shows, whose chat floats.
    private static func beside(for id: String) -> Beside? {
        let store = Store.shared
        guard let project = store.projects.first(where: { $0.id == id }) else { return nil }
        // The wish's own app, or one of its others (the TV app beside an iPhone app) that's open now.
        for app in [project] + store.parts(of: project) {
            if let preview = TVPreview.window(app), preview.isVisible, !preview.isMiniaturized { return .lamp(preview) }
            // The simulator it was last open in, while that device's window is still up: a quit app's chat stays
            // beside the simulator, where Play opens it again.
            if let udid = store.simulatorDevice(of: app) ?? (app.onIOS && app.device == nil ? lastSimulator[app.id] : nil),
               let found = simulatorWindow(udid) {
                lastSimulator[app.id] = udid
                return found
            }
            if store.isOpenInEmulator(app), let found = emulatorWindow() { return found }
        }
        return nil
    }

    private static var titles: [String: String] = [:]
    /// The simulator each app was last open in.
    private static var lastSimulator: [String: String] = [:]

    /// The simulator's window for this device: by Accessibility, which says each window's title, when Lamp may use
    /// it; otherwise by the window list, which says only whose a window is, so the viewer's largest window.
    private static func simulatorWindow(_ udid: String) -> Beside? {
        guard let pid = Simulator.Driver.viewerProcess() else { return nil }
        if AXIsProcessTrusted() {
            if titles[udid] == nil { titles[udid] = Simulator.Driver.windowTitle(udid) ?? "" }
            let name = (titles[udid] ?? "").components(separatedBy: " – ")[0]
            let app = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
               let windows = value as? [AXUIElement] {
                let framed = windows.compactMap { window -> (title: String, frame: CGRect)? in
                    var title: CFTypeRef?, position: CFTypeRef?, size: CFTypeRef?, minimized: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
                    AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
                    guard (minimized as? Bool) != true,
                          AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
                          AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success else { return nil }
                    var origin = CGPoint.zero, extent = CGSize.zero
                    AXValueGetValue(position as! AXValue, .cgPoint, &origin)
                    AXValueGetValue(size as! AXValue, .cgSize, &extent)
                    return ((title as? String) ?? "", CGRect(origin: origin, size: extent))
                }
                let chosen = framed.first { !name.isEmpty && $0.title.hasPrefix(name + " – ") } ?? (framed.count == 1 ? framed.first : nil)
                if let chosen, chosen.frame.width > 100 { return .other(key: "sim:\(udid)", frame: flipped(chosen.frame)) }
            }
        }
        return largestWindow(of: pid).map { .other(key: "sim:\(udid)", frame: $0) }
    }

    private static func emulatorWindow() -> Beside? {
        guard let pid = Emulator.windowOwner() else { return nil }
        return largestWindow(of: pid).map { .other(key: "emulator", frame: $0) }
    }

    /// A process's largest ordinary window on screen, in AppKit's coordinates.
    private static func largestWindow(of pid: pid_t) -> CGRect? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let frames = windows.compactMap { info -> CGRect? in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid, info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 100, rect.height > 100 else { return nil }
            return rect
        }
        return frames.max { $0.width * $0.height < $1.width * $1.height }.map(flipped)
    }

    /// From the window server's coordinates (the top left of the main screen, y down) to AppKit's (its bottom left, y up).
    private static func flipped(_ rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// The panel's content: the chat, with the questions the store raises about its wish (rename, delete, a version's name)
/// while it's the chat in front.
private struct PanelContent: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var link: LocalChat

    var body: some View {
        ChatScreen()
            .environmentObject(link as ChatLink)
            .ignoresSafeArea()
            .modifier(StoreDialogs(active: store.selection == link.projectID))
    }
}
