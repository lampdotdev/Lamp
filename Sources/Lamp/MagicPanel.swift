import SwiftUI
import AppKit
import Combine

/// An app's chat beside the app itself, opened by the 🪄 in its title bar (`LampMagic` in LampSupport.swift), so
/// the person can change the app while using it. It's Lamp's own chat for that app (`ProjectView`), in a panel
/// beside the app that doesn't bring Lamp's main window forward: what's said here is said in the main window too.
/// The app tells Lamp where its window is, and the panel keeps to its side. It's an ordinary window, covered by
/// other apps like any, and stays while the app is closed for a change to go in, so the build can be followed
/// until the app opens again; it closes when the person quits the app.
@MainActor
final class MagicPanel: NSObject, NSWindowDelegate {
    static let shared = MagicPanel()

    /// Apps show the wand while this file is there, beside the apps' folders, looked for each time a window of
    /// theirs comes to the front (`LampMagic`). Lamp writes it at launch. It was a switch in Settings while the
    /// wand was an experiment; apps built since read it still.
    static var flag: URL { Store.shared.root.appendingPathComponent(".magic") }

    /// An app's wand, when Lamp is running, says so directly rather than by a link (`LampMagic`), so this Lamp
    /// answers and not another copy macOS might pick for the link. Listened for from launch.
    static let listen: Void = {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Edition.notificationPrefix + "magicOpen"), object: nil, queue: .main) { note in
            guard let app = note.userInfo?["app"] as? String else { return }
            let frame = (note.userInfo?["frame"] as? String).map(NSRectFromString)
            MainActor.assumeIsolated { shared.show(app, beside: frame) }
        }
    }()

    /// Lamp's own window when it was put away for the panel (`keepMainWindowHidden`), to bring back from the Dock.
    static weak var mainWindow: NSWindow?

    /// Lamp was started by an app's wand: its window, which SwiftUI opens with the app, is put away as it
    /// appears, so the panel is all there is. At launch it's the one ordinary window there is, and it's looked
    /// for for a moment, since it can come after the link.
    static func keepMainWindowHidden() {
        Task { @MainActor in
            for _ in 0..<30 {
                if let main = NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible && $0.canBecomeMain }) {
                    mainWindow = main
                    main.orderOut(nil)
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// At launch: listening for the wand, and the file apps read to show it.
    static func start() {
        _ = listen
        FileManager.default.createFile(atPath: flag.path, contents: nil)
    }

    private var panel: NSPanel?
    var isOpen: Bool { panel != nil }
    private(set) var appID: String?
    /// The app's window as it last said, in screen coordinates; nil when it's out of sight.
    private var appFrame: NSRect?
    private var observers: [NSObjectProtocol] = []
    private var busyWatch: AnyCancellable?
    /// The copy of the app the person is pointing in, while the panel is put away because it was over the app.
    /// Tied to that process: a change that reopens the app ends the pointing with it, and the new copy has
    /// nothing to point with, so it never says the pointing ended.
    private var steppedAside: pid_t?
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
        steppedAside = nil
        panel.makeKeyAndOrderFront(nil)
        listen(for: project)
    }

    func close() {
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0) }
        observers = []
        busyWatch = nil
        dropCover()
        if let appID, let project = Store.shared.projects.first(where: { $0.id == appID }) { Store.shared.announceDraft(of: project) }
        panel?.orderOut(nil)
        panel = nil
        steppedAside = nil
        appID = nil
        appFrame = nil
    }

    private func makePanel(for project: LampProject) -> NSPanel {
        // Non-activating: typing here doesn't bring Lamp, and its main window, in front of the app.
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 600),
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "Editing \(project.name)"
        // A plain title bar over a solid chat: what's behind it showing through the chat made it hard to read.
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        // An ordinary window, which another app's windows cover like any other: it stays beside the app rather
        // than coming and going as apps take turns in front. Lamp brings it up when the app or Lamp comes forward.
        panel.level = .normal
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
        // Its two buttons at the right of the title bar, as a window's own buttons sit.
        let buttons = NSHostingView(rootView: MagicButtons(project: project).environmentObject(Store.shared))
        buttons.frame.size = buttons.fittingSize
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = buttons
        accessory.layoutAttribute = .trailing
        panel.addTitlebarAccessoryViewController(accessory)
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
                if !text.isEmpty { self.revealApp() }
            }
        })
        // The app or Lamp coming forward brings it up with them. Looked at again when the app's turn ends too.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateVisibility() }
        })
        busyWatch = Store.shared.$busy.map { $0.contains(id) }.removeDuplicates().dropFirst()
            .receive(on: RunLoop.main).sink { [weak self] busy in
                MainActor.assumeIsolated {
                    self?.updateVisibility()
                    // The turn is over: if no copy came back, the picture standing in for it goes.
                    if !busy { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.dropCoverIfAppGone() } }
                }
            }
        // The app quit for a change: its picture stands where its window was until the new copy is up.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                let ended = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                if let ended, ended == self?.steppedAside { self?.comeBack() }
                guard let self, let current = Store.shared.projects.first(where: { $0.id == id }),
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == current.bundleID
                        || app.bundleURL?.standardizedFileURL == current.installedURL.standardizedFileURL else { return }
                if Store.shared.busy.contains(id) { self.showCover(for: current); return }
                // The person quit the app: the panel beside it goes with it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    // Still this app's panel: another app's wand opened meanwhile has taken it over.
                    guard self.appID == id, Store.shared.macCopies(of: current).isEmpty, !Store.shared.busy.contains(id) else { return }
                    self.close()
                }
            }
        })
        // What the person pointed at in the app (`LampMagic.Picker`), for their message.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Edition.notificationPrefix + "picked"), object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let current = Store.shared.projects.first(where: { $0.id == id }),
                      note.object as? String == current.bundleID else { return }
                self.take(pointed: note.userInfo ?? [:], in: current)
                self.comeBack()
            }
        })
        // Pointing ended without a pick: Escape, or a click on nothing named.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Edition.notificationPrefix + "pickEnded"), object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let current = Store.shared.projects.first(where: { $0.id == id }),
                      note.object as? String == current.bundleID else { return }
                self.comeBack()
            }
        })
    }

    // MARK: Pointing

    /// Asks the app to let the person point at part of its window, and brings it in front for that. Where the
    /// panel had no room beside the app and lies over it, it steps aside until the pointing ends, so all of the
    /// app can be pointed at and the line saying how to stop isn't covered.
    func point() {
        guard let appID, let project = Store.shared.projects.first(where: { $0.id == appID }) else { return }
        let copy = Store.shared.macCopies(of: project).first
        if let panel, let appFrame, let copy, panel.frame.intersects(appFrame) {
            steppedAside = copy.processIdentifier
            panel.orderOut(nil)
        }
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "pick"), object: project.bundleID, userInfo: nil, deliverImmediately: true)
        copy?.activate()
    }

    private func comeBack() {
        guard steppedAside != nil else { return }
        steppedAside = nil
        updateVisibility()
    }

    /// The pointed-at thing goes into the message box as a picture named after it ("Save button.png"), so the
    /// person writes their message as they would and the agent sees what it is and what it looks like. Both
    /// come from the app, so neither is trusted further than that: only a picture the app left in its own
    /// runtime folder, as Lamp asked, is taken, and its name is made from plain words, shown before it's sent.
    private func take(pointed info: [AnyHashable: Any], in project: LampProject) {
        let store = Store.shared
        let folder = Runtime.macFolder(project).standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard let path = info["picture"] as? String else { return }
        let picture = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard picture.path.hasPrefix(folder), picture.lastPathComponent.hasPrefix("pointed-"), picture.pathExtension == "png" else { return }
        let name = Self.name(role: info["role"] as? String ?? "", label: info["label"] as? String ?? "")
        let place = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-pointed-\(UUID().uuidString)")
        let named = place.appendingPathComponent(name + ".png")
        guard (try? FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)) != nil,
              (try? FileManager.default.copyItem(at: picture, to: named)) != nil else { return }
        store.attach([named], to: project)
        panel?.makeKeyAndOrderFront(nil)
        store.chatFocusRequest += 1
    }

    /// "Save button", "Banana Bread text", "area": what it says, then what it is in everyday words, short
    /// enough for a file's name and with nothing a file's name can't hold.
    static func name(role: String, label: String) -> String {
        let everyday = ["static text": "text", "group": "area", "image": "picture", "cell": "row", "row": "row",
                        "text field": "field", "scroll area": "area", "web area": "page"]
        let kind = everyday[role.lowercased()] ?? role.lowercased()
        var words = label.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .filter { !"/:\\\0".contains($0) && !$0.isNewline }
        if words.count > 40 { words = String(words.prefix(39)) + "…" }
        let name = [words, kind].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Pointed at" : name.prefix(1).uppercased() + name.dropFirst()
    }

    // MARK: Standing in while the app reopens

    private var cover: NSWindow?
    private var coverTimeout: DispatchWorkItem?

    /// The picture the app left of its window as it quit (`LampMagic.leaveCover`), where the window was, a
    /// little dimmed with a note that it's updating, so the change looks made in place rather than the window
    /// vanishing and coming back elsewhere. Only a fresh picture: one left by an earlier quit would be wrong.
    private func showCover(for project: LampProject) {
        let folder = Runtime.macFolder(project)
        let picture = folder.appendingPathComponent("cover.png")
        guard let made = (try? picture.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              Date().timeIntervalSince(made) < 10, let image = NSImage(contentsOf: picture),
              let text = try? String(contentsOf: folder.appendingPathComponent("cover-frame.txt"), encoding: .utf8) else { return }
        let frame = NSRectFromString(text)
        guard frame.width > 0, frame.height > 0 else { return }
        dropCover()
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CoverView(image: image))
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        if let panel, panel.isVisible { panel.orderFrontRegardless() }
        cover = window
        // Never for long: a build that fails or a turn that ends without the app leaves nothing standing.
        let timeout = DispatchWorkItem { [weak self] in self?.dropCover() }
        coverTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: timeout)
    }

    /// The new copy said where its window is: the picture fades into it.
    private func revealApp() {
        guard let cover else { return }
        self.cover = nil
        coverTimeout?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                cover.animator().alphaValue = 0
            }, completionHandler: { MainActor.assumeIsolated { cover.orderOut(nil) } })
        }
    }

    private func dropCover() {
        coverTimeout?.cancel()
        cover?.orderOut(nil)
        cover = nil
    }

    private func dropCoverIfAppGone() {
        guard cover != nil, let appID, let project = Store.shared.projects.first(where: { $0.id == appID }),
              Store.shared.macCopies(of: project).isEmpty, !Store.shared.busy.contains(appID) else { return }
        dropCover()
    }

    private func updateVisibility() {
        guard let panel, let appID, let current = Store.shared.projects.first(where: { $0.id == appID }) else { return }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let copies = Store.shared.macCopies(of: current)
        let ours = front == ProcessInfo.processInfo.processIdentifier || copies.contains { $0.processIdentifier == front }
        let pointing = steppedAside.map { pid in copies.contains { $0.processIdentifier == pid } } ?? false
        // Always there, as a window beside the app is; another app in front simply covers it.
        if pointing { panel.orderOut(nil) } else if ours || !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Beside the app's window, on whichever side has room, as tall as it; over its right edge when neither has.
    private func place() {
        guard let panel, let frame = appFrame else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
        // Its own width, or wider if the person made it so.
        let width = max(panel.frame.width, Self.width)
        var x = frame.maxX + Self.gap
        if x + width > screen.maxX { x = frame.minX - Self.gap - width }
        if x < screen.minX { x = min(frame.maxX, screen.maxX) - width - Self.gap }
        let height = min(max(frame.height, panel.minSize.height), screen.height)
        let y = max(screen.minY, min(frame.minY, screen.maxY - height))
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: false)
    }
}

/// The chat in the panel: the app's chat as in Lamp's window.
private struct MagicChat: View {
    @EnvironmentObject private var store: Store
    let project: LampProject

    var body: some View {
        ProjectView(project: store.current(project) ?? project)
            .background(Color(nsColor: .windowBackgroundColor))
            .frame(minWidth: 320, minHeight: 360)
    }
}

/// Pointing at part of the app, and taking the chat to Lamp's window: the panel's title bar buttons.
private struct MagicButtons: View {
    @EnvironmentObject private var store: Store
    let project: LampProject

    var body: some View {
        HStack(spacing: 14) {
            Button {
                MagicPanel.shared.point()
            } label: {
                Image(systemName: "scope")
            }
            .help("Point at what you want to change")
            .accessibilityLabel("Point at Something")
            Button {
                store.showChat(project.id)
                MagicPanel.shared.close()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Open this chat in Lamp")
            .accessibilityLabel("Open in Lamp")
        }
        // Plain, in the text's own color like the rest of the chat's controls: a borderless button takes the
        // accent color.
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .contentShape(Rectangle())
        .padding(.horizontal, 12)
        .frame(height: 28)
    }
}

/// The app's last picture of itself, standing in its window's place while a change goes in.
private struct CoverView: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .overlay(Color.black.opacity(0.12))
            .overlay(alignment: .bottom) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Updating…").font(.callout.weight(.medium))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
