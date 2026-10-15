import SwiftUI
import AppKit
import Combine

/// What goes with an app's chat inside its own window (`Sidebar`), on Lamp's side: the 🪄 the app shows, starting
/// Lamp when it isn't open, pointing at part of the app for a message, and the picture standing in the app's
/// place while a change reopens it, so the window looks changed in place rather than gone and back.
@MainActor
final class MagicPanel {
    static let shared = MagicPanel()

    /// Apps show the wand while this file is there, beside the apps' folders, looked for each time a window of
    /// theirs comes to the front (`LampMagic`). Lamp writes it at launch. It was a switch in Settings while the
    /// wand was an experiment; apps built since read it still.
    static var flag: URL { Store.shared.root.appendingPathComponent(".magic") }

    /// An app's sidebar is opening (`LampSidebar` in LampSupport.swift): Lamp follows the app. Said
    /// directly when Lamp is running, so this Lamp answers and not another copy macOS might pick for a link.
    /// An app built before the sidebar asks for its chat this way too (`magicOpen`): it's shown in Lamp's
    /// window until the app is rebuilt.
    static let listen: Void = {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Edition.notificationPrefix + "sidebar"), object: nil, queue: .main) { note in
            guard let app = note.userInfo?["app"] as? String else { return }
            MainActor.assumeIsolated { shared.opening(app) }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Edition.notificationPrefix + "magicOpen"), object: nil, queue: .main) { note in
            guard let app = note.userInfo?["app"] as? String else { return }
            MainActor.assumeIsolated {
                NSApp.activate(ignoringOtherApps: true)
                Store.shared.showChat(app)
            }
        }
    }()

    /// Lamp's own window when it was put away because an app's sidebar started Lamp (`keepMainWindowHidden`), to
    /// bring back from the Dock.
    static weak var mainWindow: NSWindow?

    /// Lamp was started by an app's sidebar: its window, which SwiftUI opens with the app, is put away as it
    /// appears, since the chat is in the app. At launch it's the one ordinary window there is, and it's looked
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

    func opening(_ id: String) {
        guard let project = Store.shared.projects.first(where: { $0.id == id }) else { return }
        follow(project.id)
    }

    // MARK: Following an app

    private final class Following {
        var observers: [NSObjectProtocol] = []
        var busyWatch: AnyCancellable?
        var cover: NSWindow?
        var coverTimeout: DispatchWorkItem?
    }
    private var following: [String: Following] = [:]

    /// What the app says and does while its sidebar is in use: its window's picture when it quits for a change,
    /// its window's place once the new copy is up, and what was pointed at.
    func follow(_ id: String) {
        guard following[id] == nil else { return }
        let state = Following()
        following[id] = state
        // The new copy said where its window is: the picture standing in for it fades into it.
        state.observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Edition.notificationPrefix + "windowFrame"), object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let current = Store.shared.projects.first(where: { $0.id == id }), note.object as? String == current.bundleID,
                      let text = note.userInfo?["frame"] as? String, !text.isEmpty else { return }
                self?.revealApp(id)
            }
        })
        // The turn is over: if no copy came back, the picture standing in for it goes.
        state.busyWatch = Store.shared.$busy.map { $0.contains(id) }.removeDuplicates().dropFirst()
            .receive(on: RunLoop.main).sink { [weak self] busy in
                MainActor.assumeIsolated {
                    if !busy { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.dropCoverIfAppGone(id) } }
                }
            }
        // The app quit for a change: its picture stands where its window was until the new copy is up. Quit by
        // the person, nothing more is followed until the sidebar opens again.
        state.observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let current = Store.shared.projects.first(where: { $0.id == id }),
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == current.bundleID
                        || app.bundleURL?.standardizedFileURL == current.installedURL.standardizedFileURL else { return }
                if Store.shared.busy.contains(id) { return self.showCover(for: current) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    guard Store.shared.macCopies(of: current).isEmpty, !Store.shared.busy.contains(id) else { return }
                    self.stopFollowing(id)
                }
            }
        })
        // What the person pointed at in the app (`LampMagic.Picker`), for their message.
        state.observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Edition.notificationPrefix + "picked"), object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let current = Store.shared.projects.first(where: { $0.id == id }), note.object as? String == current.bundleID else { return }
                self?.take(pointed: note.userInfo ?? [:], in: current)
            }
        })
    }

    private func stopFollowing(_ id: String) {
        guard let state = following.removeValue(forKey: id) else { return }
        state.observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0)
        }
        state.coverTimeout?.cancel()
        state.cover?.orderOut(nil)
    }

    // MARK: Pointing

    /// The pointed-at thing goes into the message box as a pill: its picture, named after it ("Save button.png"),
    /// and what it is, so the person writes their message as they would and the agent sees what it is and what it
    /// looks like. Pointing again replaces it. Both come from the app, so neither is trusted further than that:
    /// only a picture the app left in its own runtime folder, as Lamp asked, is taken, and its name is made from
    /// plain words, shown before it's sent.
    private func take(pointed info: [AnyHashable: Any], in project: LampProject) {
        let folder = Runtime.macFolder(project).standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard let path = info["picture"] as? String else { return }
        let picture = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard picture.path.hasPrefix(folder), picture.lastPathComponent.hasPrefix("pointed-"), picture.pathExtension == "png" else { return }
        let name = Self.name(role: info["role"] as? String ?? "", label: info["label"] as? String ?? "")
        let place = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-pointed-\(UUID().uuidString)")
        let named = place.appendingPathComponent(name + ".png")
        guard (try? FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)) != nil,
              (try? FileManager.default.copyItem(at: picture, to: named)) != nil else { return }
        Store.shared.point(at: PointedAt(title: name, detail: Self.words(info["context"] as? String ?? ""), picture: named.path), in: project)
    }

    /// Points again for the message being written: the app lays its pointer over its window, in front. What's
    /// picked takes the place of what was; Escape there leaves it as it was.
    func pointAgain(in project: LampProject) {
        guard let app = Store.shared.macCopies(of: project).first else { return }
        follow(project.id)
        NSApp.yieldActivation(to: app)
        app.activate()
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "pick"), object: project.bundleID, userInfo: nil, deliverImmediately: true)
    }

    /// Words from the app, on one line and short enough for the card; nil when there are none.
    static func words(_ text: String) -> String? {
        var words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ").filter { !$0.isNewline && $0 != "\0" }
        if words.count > 60 { words = String(words.prefix(59)) + "…" }
        return words.isEmpty ? nil : words
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

    /// The picture the app left of its window as it quit (`LampMagic.leaveCover`), where the window was, a
    /// little dimmed with a note that it's updating. Only a fresh picture: one left by an earlier quit would be wrong.
    private func showCover(for project: LampProject) {
        guard let state = following[project.id] else { return }
        let folder = Runtime.macFolder(project)
        let picture = folder.appendingPathComponent("cover.png")
        guard let made = (try? picture.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              Date().timeIntervalSince(made) < 10, let image = NSImage(contentsOf: picture),
              let text = try? String(contentsOf: folder.appendingPathComponent("cover-frame.txt"), encoding: .utf8) else { return }
        let frame = NSRectFromString(text)
        guard frame.width > 0, frame.height > 0 else { return }
        dropCover(project.id)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CoverView(image: image))
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        state.cover = window
        // Never for long: a build that fails or a turn that ends without the app leaves nothing standing.
        let id = project.id
        let timeout = DispatchWorkItem { [weak self] in self?.dropCover(id) }
        state.coverTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: timeout)
    }

    private func revealApp(_ id: String) {
        guard let state = following[id], let cover = state.cover else { return }
        state.cover = nil
        state.coverTimeout?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                cover.animator().alphaValue = 0
            }, completionHandler: { MainActor.assumeIsolated { cover.orderOut(nil) } })
        }
    }

    private func dropCover(_ id: String) {
        guard let state = following[id] else { return }
        state.coverTimeout?.cancel()
        state.cover?.orderOut(nil)
        state.cover = nil
    }

    private func dropCoverIfAppGone(_ id: String) {
        guard following[id]?.cover != nil, let project = Store.shared.projects.first(where: { $0.id == id }),
              Store.shared.macCopies(of: project).isEmpty, !Store.shared.busy.contains(id) else { return }
        dropCover(id)
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

/// What the person pointed at in an app, going with a message: what it is in everyday words ("Watered button"),
/// what it's part of when the app says ("Kitchen basil"), and its picture, which is one of the message's files.
struct PointedAt: Codable, Equatable {
    var title: String
    var detail: String?
    /// The picture's path while the message is being written, and its name in the app's Attachments folder in
    /// a request already sent.
    var picture: String

    /// The picture, while the message is being written.
    var url: URL? { picture.hasPrefix("/") ? URL(fileURLWithPath: picture) : nil }

    /// Tells the agent which of the attached pictures is the part of the app the request is about, and what
    /// it's part of, which the picture alone may not show.
    static func note(for pointed: [PointedAt]) -> String {
        pointed.map { pointed in
            let part = pointed.detail.map { " (part of \"\($0)\")" } ?? ""
            return "\n\nThe user pointed at this in the app: \(pointed.title)\(part), pictured in \(Attachments.folder)/\(pointed.picture)."
        }.joined()
    }

    /// This, from a request already sent, for a message being written again.
    func waiting(in project: LampProject) -> PointedAt {
        guard url == nil else { return self }
        var waiting = self
        waiting.picture = Attachments.urls([picture], in: project)[0].path
        return waiting
    }
}

extension LogLine {
    /// A request's files as the message box holds them when it's taken back: what was pointed at on its own pill,
    /// the rest as files.
    func draftAttachments(in project: LampProject) -> (attachments: [URL], pointed: PointedAt?) {
        let names = (attachments ?? []).filter { $0 != pointed?.picture }
        return (Attachments.urls(names, in: project), pointed?.waiting(in: project))
    }
}

extension Store {
    /// The app is open on this Mac, where it can be pointed at again.
    func canPoint(in project: LampProject) -> Bool {
        switch project.platform {
        case .mac: isOpen(project)
        case .universal: openOnMac.contains(project.id)
        case .iphone: false
        }
    }
}
