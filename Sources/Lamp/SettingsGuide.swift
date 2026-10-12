import AppKit
import SwiftUI

/// Leads the person to a switch only they can turn on, in System Settings ▸ Privacy & Security: opens the
/// page and keeps a small panel at the foot of the Settings window with the app to drag into the list
/// there, so nobody has to find it with the + button (which opens on the wrong folder, and can't reach an
/// app that isn't in Applications).
///
/// Nothing here needs a permission of its own, which matters because it runs before any is given: macOS
/// tells any app where other apps' windows are (only their titles need Screen Recording), and what's
/// dragged is the app as a file, the same thing Finder would hand over. System Settings decides what a
/// drop does; if a future macOS stops taking one, the list and its + button are still right there. And
/// if the Settings window can't be found, so there's no panel, macOS's own request is made instead: it puts
/// Lamp in the list with its switch off.
/// `LampPermissionGuide` in Template.swift is the same panel for the apps Lamp builds: keep the two in step.
@MainActor
enum SettingsGuide {
    enum Permission {
        case accessibility

        /// What System Settings calls it.
        var name: String { "Accessibility" }

        fileprivate var page: URL {
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        }

        /// macOS's own request, for when the panel can't be shown: it lists Lamp, switched off.
        fileprivate func askTheSystem() {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
    }

    private static var showing: Guide?

    /// Opens the page, in front, and shows the panel until `isOn` says the switch is on (true), or the person
    /// presses its back button or quits System Settings (false). `app` is whose switch it is: Lamp, or a
    /// helper. Asking again starts over, which is how the page and the panel come back from wherever they went.
    static func ask(_ permission: Permission, for app: URL = Bundle.main.bundleURL,
                    isOn: @escaping @Sendable () async -> Bool) async -> Bool {
        showing?.end(false)   // one at a time: there is one Settings window
        return await withCheckedContinuation { continuation in
            let guide = Guide(permission: permission, app: app, isOn: isOn) { continuation.resume(returning: $0) }
            showing = guide
            guide.begin()
        }
    }

    fileprivate static func ended(_ guide: Guide) {
        if showing === guide { showing = nil }
    }

    /// The Settings window on screen now: its number, for keeping the panel just above it, where it is
    /// (screen points from the top left of the main display), and whether a sheet is up on it (macOS asking
    /// for the password after a drop), when the panel would only be in the way.
    fileprivate static func settingsWindow(of pid: pid_t) -> (id: CGWindowID, frame: CGRect, busy: Bool)? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let own = windows.compactMap { window -> (id: CGWindowID, frame: CGRect)? in
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return (id, frame)
        }
        // The main window is the big one; a sheet is a smaller window of its own inside it.
        guard let main = own.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
              main.frame.width >= 400, main.frame.height >= 300 else { return nil }
        return (main.id, main.frame, own.contains { $0.id != main.id && main.frame.contains($0.frame) })
    }
}

@MainActor
private final class Guide {
    private static let settingsID = "com.apple.systempreferences"
    private static let width: CGFloat = 530, margin: CGFloat = 14
    private static let patience: TimeInterval = 4

    private let permission: SettingsGuide.Permission
    private let app: URL
    private let isOn: @Sendable () async -> Bool
    private var finish: ((Bool) -> Void)?
    private var panel: NSPanel?
    private var tracker: Timer?
    private var checking: Task<Void, Never>?
    private let began = Date()
    private var sawSettings = false
    private var lost: Date?        // since when System Settings has been in front with no window to be found
    private var askedSystem = false

    init(permission: SettingsGuide.Permission, app: URL, isOn: @escaping @Sendable () async -> Bool,
         finish: @escaping (Bool) -> Void) {
        self.permission = permission
        self.app = app
        self.isOn = isOn
        self.finish = finish
    }

    func begin() {
        NSWorkspace.shared.open(permission.page)
        // Already open on that page, it may stay where it was, behind other windows.
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.settingsID).first?.activate()
        let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
        let view = GuideView(app: app, name: name, permission: permission.name) { [weak self] in
            self?.end(false)
            NSApp.activate(ignoringOtherApps: true)
        }
        let host = FirstClickHost(rootView: view)
        let panel = NonKeyPanel(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: host.fittingSize.height),
                                styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.setAccessibilityRole(.window)
        panel.setAccessibilityLabel("Drag \(name) to the list in System Settings")
        self.panel = panel
        // Often enough that the panel rides along when the Settings window is moved.
        let tracker = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        RunLoop.main.add(tracker, forMode: .common)   // also while the tile is being dragged
        self.tracker = tracker
        checking = Task { [weak self, isOn] in
            while !Task.isCancelled {
                if await isOn() {
                    self?.end(true)
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Keeps the panel at the foot of the Settings window and just above it in the stack, so whatever
    /// covers that window covers the panel too. Hidden while the window isn't on screen (minimized, on
    /// another desktop) or has a sheet up; over when System Settings has quit, which closing its window does.
    private func follow() {
        guard let panel else { return }
        guard let settings = NSRunningApplication.runningApplications(withBundleIdentifier: Self.settingsID).first else {
            if sawSettings || Date().timeIntervalSince(began) > 15 { end(false) }
            return
        }
        sawSettings = true
        guard let window = SettingsGuide.settingsWindow(of: settings.processIdentifier) else {
            panel.orderOut(nil)
            // In front for a while and still no window Lamp can find: there will be no panel to drag from.
            guard settings.isActive else { return lost = nil }
            if lost == nil { lost = Date() }
            if let lost, Date().timeIntervalSince(lost) > Self.patience, !askedSystem, app == Bundle.main.bundleURL {
                askedSystem = true
                permission.askTheSystem()
            }
            return
        }
        lost = nil
        guard !window.busy else { return panel.orderOut(nil) }
        let width = min(Self.width, window.frame.width - Self.margin * 2), height = panel.frame.height
        let spot = ComputerOverlay.cocoa(CGRect(x: window.frame.maxX - Self.margin - width,
                                                y: window.frame.maxY - Self.margin - height, width: width, height: height))
        if panel.frame != spot { panel.setFrame(spot, display: true) }
        panel.order(.above, relativeTo: Int(window.id))
    }

    func end(_ granted: Bool) {
        guard let finish else { return }
        self.finish = nil
        tracker?.invalidate()
        checking?.cancel()
        panel?.orderOut(nil)
        panel?.contentView = nil   // lets go of the view, and with it this guide
        panel = nil
        SettingsGuide.ended(self)
        finish(granted)
    }
}

private struct GuideView: View {
    let app: URL
    let name: String
    let permission: String
    let back: () -> Void
    @State private var nudge = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrowshape.up.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.accentColor)
                    .offset(y: nudge ? -3 : 2)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text("Drag **\(name)** to the list above to allow **\(permission)**")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: 8) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(.quaternary, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Back to \(Edition.name)")
                .accessibilityLabel("Back to \(Edition.name)")
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                    Text(name).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                .overlay(AppToDrag(app: app, name: name))
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator))
        .onAppear {
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { nudge = true }
        }
    }
}

/// The tile's drag: the app as a file, handed over by AppKit itself so it starts on the first press in a
/// panel that never becomes the active window.
private struct AppToDrag: NSViewRepresentable {
    let app: URL
    let name: String

    func makeNSView(context: Context) -> Source { Source(app: app, name: name) }
    func updateNSView(_ view: Source, context: Context) {}

    final class Source: NSView, NSDraggingSource {
        private let app: URL
        private let name: String
        private var pressed: NSEvent?

        init(app: URL, name: String) {
            self.app = app
            self.name = name
            super.init(frame: .zero)
            setAccessibilityElement(true)
            setAccessibilityRole(.image)
            setAccessibilityLabel("\(name), to drag into System Settings")
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func mouseDown(with event: NSEvent) { pressed = event }
        override func mouseUp(with event: NSEvent) { pressed = nil }

        override func mouseDragged(with event: NSEvent) {
            guard let pressed else { return }
            self.pressed = nil
            let item = NSDraggingItem(pasteboardWriter: app as NSURL)
            // What follows the pointer: the icon and the name, as in the tile.
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            let label = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                                                                      .foregroundColor: NSColor.labelColor])
            let size = CGSize(width: 32 + 8 + ceil(label.size().width), height: 32)
            let picture = NSImage(size: size, flipped: false) { _ in
                icon.draw(in: CGRect(x: 0, y: 0, width: 32, height: 32))
                label.draw(at: CGPoint(x: 40, y: (32 - label.size().height) / 2))
                return true
            }
            item.setDraggingFrame(CGRect(origin: CGPoint(x: 6, y: (bounds.height - 32) / 2), size: size), contents: picture)
            beginDraggingSession(with: [item], event: pressed, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .link, .generic] : []
        }
    }
}
