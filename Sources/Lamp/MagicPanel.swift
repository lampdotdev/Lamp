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

    /// Settings → Experimental. Apps show the wand only while it's on: they look for `flag`, beside the apps'
    /// folders, each time a window of theirs comes to the front, so turning it off takes the wand away too.
    static let switchKey = "experimentMagic"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: switchKey) }
    static var flag: URL { Store.shared.root.appendingPathComponent(".magic") }

    /// The flag apps read, made to agree with the switch: when it changes, and at launch.
    static func syncSwitch() {
        if isOn {
            FileManager.default.createFile(atPath: flag.path, contents: nil)
        } else {
            try? FileManager.default.removeItem(at: flag)
            shared.close()
        }
    }

    private var panel: NSPanel?
    private(set) var appID: String?
    /// The app's window as it last said, in screen coordinates; nil when it's out of sight.
    private var appFrame: NSRect?
    private var observers: [NSObjectProtocol] = []
    private var busyWatch: AnyCancellable?
    static let width: CGFloat = 400
    private static let gap: CGFloat = 8

    func show(_ id: String, beside frame: NSRect? = nil) {
        guard Self.isOn, let project = Store.shared.projects.first(where: { $0.id == id }) else { return }
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
        dropCover()
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
                if !text.isEmpty { self.revealApp() }
            }
        })
        // Over the app and Lamp only: another app in front puts it away until one of them comes back. Looked at
        // again when the app's turn ends too, which ends the exception for a change going in.
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
                guard let self, let current = Store.shared.projects.first(where: { $0.id == id }), Store.shared.busy.contains(id),
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == current.bundleID
                        || app.bundleURL?.standardizedFileURL == current.installedURL.standardizedFileURL else { return }
                self.showCover(for: current)
            }
        })
        // What the person pointed at in the app (`LampMagic.Picker`), for their message.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Edition.notificationPrefix + "picked"), object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let current = Store.shared.projects.first(where: { $0.id == id }),
                      note.object as? String == current.bundleID else { return }
                self.take(pointed: note.userInfo ?? [:], in: current)
            }
        })
    }

    // MARK: Pointing

    /// Asks the app to let the person point at part of its window, and brings it in front for that.
    func point() {
        guard let appID, let project = Store.shared.projects.first(where: { $0.id == appID }) else { return }
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "pick"), object: project.bundleID, userInfo: nil, deliverImmediately: true)
        Store.shared.macCopies(of: project).first?.activate()
    }

    /// The pointed-at thing goes into the message box: its words at the front, its picture as an attachment.
    /// Both come from the app, so neither is trusted further than that: the words are shown before anything
    /// is sent, and only a picture the app left in its own runtime folder, as Lamp asked, is taken.
    private func take(pointed info: [AnyHashable: Any], in project: LampProject) {
        let store = Store.shared
        var draft = store.draft(for: project)
        if let what = (info["what"] as? String)?.replacingOccurrences(of: "\n", with: " ").prefix(160), !what.isEmpty {
            let mention = "The \(what): "
            draft.text = draft.text.trimmed.isEmpty ? mention : draft.text + "\n" + mention
        }
        store.updateDraft(draft, for: project)
        let folder = Runtime.macFolder(project).standardizedFileURL.resolvingSymlinksInPath().path + "/"
        if let path = info["picture"] as? String {
            let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            if url.path.hasPrefix(folder), url.lastPathComponent.hasPrefix("pointed-"), url.pathExtension == "png" {
                store.attach([url], to: project)
            }
        }
        panel?.makeKeyAndOrderFront(nil)
        store.chatFocusRequest += 1
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
                Button {
                    MagicPanel.shared.point()
                } label: {
                    Image(systemName: "scope")
                }
                .help("Point at part of the app to ask about it")
                .accessibilityLabel("Point at Something")
                Spacer()
                Button {
                    store.showChat(project.id)
                    MagicPanel.shared.close()
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .help("Open this chat in Lamp")
                .accessibilityLabel("Open in Lamp")
            }
            // Plain, in the text's own color like the rest of the chat's controls: a borderless button takes the
            // accent color.
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
            .padding(.horizontal, 14).padding(.vertical, 6)
            Divider()
            ProjectView(project: store.current(project) ?? project)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 320, minHeight: 360)
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
