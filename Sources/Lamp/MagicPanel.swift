import SwiftUI
import AppKit
import Combine
import LampSidebarKit

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
        // The app's Reload button (`LampMagic.ReloadButton`): only a change Lamp holds for that app goes in.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Edition.notificationPrefix + "reloadNow"), object: nil, queue: .main) { note in
            guard let app = note.userInfo?["app"] as? String else { return }
            MainActor.assumeIsolated { Store.shared.reloadWaiting(app) }
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

    // MARK: Handing the chat to the app

    /// Whether this wish's chat is shown beside its app rather than in Lamp's window: a Mac app with windows (not one
    /// in the menu bar, a widget or the background), built with the sidebar in it. For a wish whose apps are all in
    /// folders, its one Mac app's (`Store.chatApp`).
    static func chatsInApp(_ wish: LampProject) async -> Bool {
        let project = Store.shared.chatApp(of: wish)
        guard Sidebar.applies(to: project),
              FileManager.default.fileExists(atPath: Sidebar.extensionURL(in: project.installedURL).path) else { return false }
        return await Task.detached { WishPlace.of(project) }.value == .window
    }

    /// Whether the copies of the app running now can take Lamp's request for their chat (`openChat`): one built by a
    /// Lamp from before it would only come forward, with the chat nowhere. Read off each running copy's own program,
    /// which may be older than the one installed since. The request's name alone, without Lamp's prefix: an app reads
    /// the prefix from its Info.plist (`LampInstall.note`), so its program holds only the name.
    static func runningCopiesTakeTheChat(_ wish: LampProject) -> Bool {
        let project = Store.shared.chatApp(of: wish)
        // An app of Lamp's own around a page is built from this Lamp's files whenever they change, and in release: Swift
        // keeps a string this short inside the code there, so the name isn't in the program to find.
        if project.platform.target.hostedByLamp { return true }
        return Store.shared.macCopies(of: project).allSatisfy { app in
            guard let program = app.executableURL, let data = try? Data(contentsOf: program, options: .alwaysMapped) else { return false }
            return data.range(of: Data("openSidebar".utf8)) != nil
        }
    }

    private static func handedOff(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/sidebar-handed-off") }

    /// At the agent's first look that opens a new app (`Store.present`), or after the turn that first builds and opens
    /// it when there was none: its chat window closes and the app opens the chat beside its content, so the rest of the
    /// making happens in the app itself. Once for each app: a chat the
    /// person opened in Lamp's window afterwards stays there.
    /// Given the wish or its app: the chat is the wish's, the window its app's (`Store.chatApp`).
    func handOff(_ project: LampProject) async {
        let wish = Store.shared.wish(of: project), app = Store.shared.chatApp(of: wish)
        guard !FileManager.default.fileExists(atPath: Self.handedOff(app).path),
              await Self.chatsInApp(wish), !Store.shared.macCopies(of: app).isEmpty,
              Self.runningCopiesTakeTheChat(wish) else { return }
        FileManager.default.createFile(atPath: Self.handedOff(app).path, contents: nil)
        openChat(in: app)
        // Lamp's window closes once the chat is up in the app, and not before: with no window of its own and no chat
        // connected, Lamp would quit, and an app that couldn't show the chat would leave it nowhere.
        for _ in 0..<50 {
            if SidebarServer.shared.isConnected(wish.id) { return ChatPanel.close(wish.id) }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// A new app's chat moves beside it early in its first turn (`Store.present`), and every pass that reopens the app
    /// takes it down with the old copy. When no chat comes back beside the app (the reopen failed, the app crashed, or a
    /// pass made it a menu bar app or a widget, with no window for it), the chat goes back to Lamp's window rather than
    /// nowhere, with the turn's progress, its errors and Stop. A chat the person closed beside the app keeps its
    /// connection, so it isn't brought back against their wish.
    func keepChatInSight(_ project: LampProject) async {
        let wish = Store.shared.wish(of: project)
        guard FileManager.default.fileExists(atPath: Self.handedOff(Store.shared.chatApp(of: wish)).path) else { return }
        if await Self.chatsInApp(wish) {
            // A copy that opened brings its chat back as its window comes up: give it the time that takes.
            for _ in 0..<40 {
                if SidebarServer.shared.isConnected(wish.id) || ChatPanel.isOpen(wish.id) { return }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        guard !SidebarServer.shared.isConnected(wish.id), !ChatPanel.isOpen(wish.id) else { return }
        // Beside whatever shows it now, without taking the keyboard from what the person is in.
        ChatPanel.show(wish.id, activate: NSApp.isActive)
    }

    /// An app's chat is in one place at a time: when it opens beside the app, Lamp's panel for it closes.
    func chatOpenedInApp(_ project: LampProject) {
        // Only once the chat Lamp checked is there (`SidebarServer.accepted`): the app's word that it's opening is a
        // notification anything could send, and a panel closed with no chat to take its place would leave it nowhere.
        let wish = Store.shared.wish(of: project)
        guard SidebarServer.shared.isConnected(wish.id) else { return }
        ChatPanel.close(wish.id)
    }

    /// The app was opened to show its chat beside it: if no chat has come by the time it should have (the app
    /// couldn't start, or quit as it opened), the chat is shown in Lamp's panel, so it's never nowhere. A rebuild
    /// first (an app built by an older Lamp) is waited for, since its progress is in that chat.
    func showChatIfAppNeverComes(_ project: LampProject) {
        let id = project.id
        Task {
            var waited = 0
            while Store.shared.busy.contains(id), waited < 1200 {
                try? await Task.sleep(for: .milliseconds(500))
                waited += 1
            }
            for _ in 0..<30 {
                if SidebarServer.shared.isConnected(id) { return }
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard let current = Store.shared.projects.first(where: { $0.id == id }), !SidebarServer.shared.isConnected(id),
                  Store.shared.macCopies(of: Store.shared.chatApp(of: current)).isEmpty else { return }
            ChatPanel.show(id)
        }
    }

    /// The app quit while its chat was beside it, and not for a change that reopens it: it crashed, or quit while a
    /// turn was going on. The chat comes up in Lamp's panel, on its own, without taking the keyboard, once no chat
    /// has come back beside a copy of the app.
    func showChatAfterQuit(_ project: LampProject) {
        let id = project.id
        Task {
            // A change that reopens the app leaves a moment with no copy running: only three seconds with none, and no
            // chat back beside one, is the app gone.
            var gone = 0
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(250))
                guard let current = Store.shared.projects.first(where: { $0.id == id }), !SidebarServer.shared.isConnected(id),
                      !ChatPanel.isOpen(id) else { return }
                gone = Store.shared.macCopies(of: Store.shared.chatApp(of: current)).isEmpty ? gone + 1 : 0
                if gone >= 12 { return ChatPanel.show(id, activate: NSApp.isActive) }
            }
        }
    }

    /// A wish Lamp came with opens with its chat beside it the first time it's opened, ready to be changed, as a new
    /// app does after its first build (`handOff`), and once only: a chat the person closes stays closed.
    /// True when it did: otherwise the chat is opened as for any other app (`openChat`).
    @discardableResult
    func startWithChat(_ project: LampProject) -> Bool {
        guard project.platform == .mac, Starters.isStarter(project),
              !FileManager.default.fileExists(atPath: Self.handedOff(project).path) else { return false }
        FileManager.default.createFile(atPath: Self.handedOff(project).path, contents: nil)
        let folder = Runtime.macFolder(project)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The app is seen on its own for a moment first: someone who's never seen it looks at it before the chat comes.
        FileManager.default.createFile(atPath: folder.appendingPathComponent("open-sidebar").path, contents: Data("1.2".utf8))
        follow(project.id)
        return true
    }

    /// The chat opened in the app's window: by a file in its runtime folder for a copy that's still starting
    /// (`LampSidebar.restore`), and by a word to one that's already running (`LampSidebar.openForLamp`).
    func openChat(in wish: LampProject) {
        let project = Store.shared.chatApp(of: wish)
        let folder = Runtime.macFolder(project)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("open-sidebar").path, contents: nil)
        follow(project.id)
        Store.shared.macCopies(of: project).first?.activate()
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "openSidebar"), object: project.bundleID, userInfo: nil, deliverImmediately: true)
    }

    func opening(_ id: String) {
        guard let project = Store.shared.projects.first(where: { $0.id == id }) else { return }
        follow(project.id)
        // A chat closed beside the app keeps its connection, so opening it again is told only this way.
        chatOpenedInApp(project)
    }

    // MARK: Following an app

    private final class Following {
        var observers: [NSObjectProtocol] = []
    }
    private var following: [String: Following] = [:]

    /// What the app says and does while its sidebar is in use: that it quit, and what was pointed at.
    func follow(_ id: String) {
        guard following[id] == nil else { return }
        let state = Following()
        following[id] = state
        // The app quit for a change: it's followed on into the new copy. Quit by the person, nothing more is
        // followed until the sidebar opens again.
        state.observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let current = Store.shared.projects.first(where: { $0.id == id }),
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == current.bundleID
                        || app.bundleURL?.standardizedFileURL == current.installedURL.standardizedFileURL else { return }
                if Store.shared.busy.contains(id) { return }
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
                self?.pointingEnded(id)
            }
        })
        state.observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Edition.notificationPrefix + "pickEnded"), object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let current = Store.shared.projects.first(where: { $0.id == id }), note.object as? String == current.bundleID else { return }
                self?.pointingEnded(id)
            }
        })
    }

    private func stopFollowing(_ id: String) {
        guard let state = following.removeValue(forKey: id) else { return }
        state.observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0)
        }
    }

    // MARK: Pointing

    /// Asked for from Lamp's own window: Lamp comes back in front once the person has pointed, or given up.
    private var pointingFromLamp: Set<String> = []

    /// The person chose to point at part of the app (the + menu by the message box): the app lays its outline
    /// over its window (`LampMagic.Picker`), and what's picked comes back as an attachment (`take`).
    func point(in wish: LampProject, fromLamp: Bool) {
        let project = Store.shared.chatApp(of: wish)
        guard let app = Store.shared.macCopies(of: project).first else { return }
        follow(project.id)
        if fromLamp { pointingFromLamp.insert(project.id) } else { pointingFromLamp.remove(project.id) }
        NSApp.yieldActivation(to: app)
        app.activate()
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "pick"), object: project.bundleID, userInfo: nil, deliverImmediately: true)
    }

    private func pointingEnded(_ id: String) {
        guard pointingFromLamp.remove(id) != nil else { return }
        NSApp.activate()
        ChatPanel.show(Store.shared.projects.first { $0.id == id }.map { Store.shared.wish(of: $0).id } ?? id)
    }

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
        Store.shared.point(at: PointedAt(title: name, detail: Self.words(info["context"] as? String ?? ""), picture: named.path),
                           in: Store.shared.wish(of: project))
    }

    /// Points again for the message being written: the app lays its pointer over its window, in front. What's
    /// picked takes the place of what was; Escape there leaves it as it was.
    func pointAgain(in project: LampProject) { point(in: project, fromLamp: false) }

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
    func canPoint(in wish: LampProject) -> Bool {
        let project = chatApp(of: wish)
        // Only a Mac copy: an app for both may be open elsewhere too.
        guard project.hasMac else { return false }
        return project.hasIOS ? openOnMac.contains(project.id) : isOpen(project)
    }
}
