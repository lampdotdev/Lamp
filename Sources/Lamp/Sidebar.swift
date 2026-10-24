import Foundation
import AppKit
import Combine
import Security
import LampSidebarKit

/// The chat inside a Mac app's own window. The app shows it beside its content when its 🪄 is clicked
/// (`LampSidebar` in LampSupport.swift); what's drawn there is an extension Lamp puts in every Mac app
/// (Sources/LampSidebar), running in a sandboxed process of its own, so the app's code can neither draw the chat
/// nor read it, nor send the agent anything through it. The extension shows what Lamp sends it and passes on
/// what the person does. It reaches Lamp on this Mac's own address (a socket in its own folder would be simpler,
/// but macOS keeps other apps, Lamp included, out of an app's folder); Lamp listens only after finding which
/// process is on the other end and checking that it runs the very extension Lamp signed for that app.
enum Sidebar {
    static func bundleID(for project: LampProject) -> String { project.bundleID + ".sidebar" }
    /// The extension point the app declares, which only its own extension takes: bundled in the app, macOS
    /// lets the app show it without asking the person.
    static func pointID(for project: LampProject) -> String { project.bundleID + ".lamp-sidebar" }
    static let sceneID = "chat"

    static func extensionURL(in app: URL) -> URL { app.appendingPathComponent("Contents/Extensions/LampSidebar.appex") }
    private static func pointURL(in app: URL) -> URL { app.appendingPathComponent("Contents/Extensions/LampSidebar.appextensionpoint") }

    /// The program, built with Lamp.
    private static var program: URL? { Bundle.main.url(forResource: "LampSidebar", withExtension: nil) }

    /// Whether this app gets the chat: a Mac app with windows (one that is only its widget has none).
    static func applies(to project: LampProject) -> Bool {
        project.platform.hasMac && !project.onIOS && !Template.isWidgetOnly(project)
    }

    /// Puts the extension into a built app, before it's signed. Its program is the same for every app; what
    /// tells them apart is the Info.plist, which names the app's own extension point.
    static func install(into app: URL, for project: LampProject, entitlementsIn folder: URL) throws {
        let fm = FileManager.default
        let appex = extensionURL(in: app)
        try? fm.removeItem(at: appex)
        try? fm.removeItem(at: pointURL(in: app))
        guard applies(to: project), let program else { return }
        try fm.createDirectory(at: appex.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try fm.copyItem(at: program, to: appex.appendingPathComponent("Contents/MacOS/LampSidebar"))
        let info: [String: Any] = [
            "CFBundleExecutable": "LampSidebar",
            "CFBundleIdentifier": bundleID(for: project),
            "CFBundleName": "Lamp",
            "CFBundleDisplayName": "Lamp",
            "CFBundlePackageType": "XPC!",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "14.0",
            "EXAppExtensionAttributes": ["EXExtensionPointIdentifier": pointID(for: project)],
            // How it starts Lamp when Lamp isn't open.
            "LampScheme": Edition.urlScheme,
            "LampApp": project.id,
            // Where Lamp listens for it.
            "LampPort": Int(Edition.sidebarPort),
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: appex.appendingPathComponent("Contents/Info.plist"))
        let point: [String: Any] = [pointID(for: project): ["EXPresentsUserInterface": true]]
        try PropertyListSerialization.data(fromPropertyList: point, format: .xml, options: 0).write(to: pointURL(in: app))
        try entitlements.write(to: entitlementsURL(in: folder), atomically: true, encoding: .utf8)
    }

    /// Sandboxed, which macOS asks of every extension it loads, with the ways out it needs: to reach Lamp, and to
    /// read the files the person attaches.
    private static let entitlements = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/>
        <key>com.apple.security.network.client</key><true/>
        <key>com.apple.security.files.user-selected.read-only</key><true/></dict></plist>

        """

    static func entitlementsURL(in folder: URL) -> URL { folder.appendingPathComponent("sidebar-entitlements.plist") }

    /// The signing step, before the app's: with the hardened runtime, so nothing can be loaded into it that
    /// would make it act otherwise than its code.
    static func signingStep(_ sign: String) -> String {
        "{ [ ! -d \"$LAMP_SIDEBAR\" ] || \(sign) --options runtime --entitlements \"$LAMP_SIDEBAR_ENTITLEMENTS\" \"$LAMP_SIDEBAR\" 2>&1; }"
    }

    static func signingEnvironment(in app: URL, entitlementsIn folder: URL) -> [String: String] {
        ["LAMP_SIDEBAR": extensionURL(in: app).path, "LAMP_SIDEBAR_ENTITLEMENTS": entitlementsURL(in: folder).path]
    }

    // MARK: Which extension is the real one

    /// The code hashes of the extensions Lamp signed for each app, newest last: the extension in a running copy
    /// may be from the build before. Kept in Lamp's own folder, never the app's, which the app could change.
    private static var hashesURL: URL { Edition.supportFolder.appendingPathComponent("sidebar-hashes.json") }
    private static var hashes: [String: [String]] = {
        (try? JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: hashesURL))) ?? [:]
    }()

    /// After signing: the hash of what was signed, the one thing a process can't fake about what it runs.
    static func remember(_ project: LampProject, signed app: URL) {
        let appex = extensionURL(in: app)
        var code: SecStaticCode?
        var info: CFDictionary?
        guard FileManager.default.fileExists(atPath: appex.path),
              SecStaticCodeCreateWithPath(appex as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
              let hash = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else { return }
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        var list = (hashes[project.id] ?? []).filter { $0 != hex }
        list.append(hex)
        hashes[project.id] = Array(list.suffix(4))
        try? JSONEncoder().encode(hashes).write(to: hashesURL)
    }

    /// The app whose extension, as Lamp signed it, is on the other end of a connection; nil for anything else.
    /// The process is found by the connection's port among the processes running a sidebar, then its code is
    /// checked against what Lamp signed, by hash.
    @MainActor static func app(on socket: Int32) -> LampProject? {
        var peer = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard withUnsafeMutablePointer(to: &peer, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getpeername(socket, $0, &length) } }) == 0,
              peer.sin_addr.s_addr == inet_addr("127.0.0.1"),
              let pid = PeerProcess.find(connectedFrom: UInt16(bigEndian: peer.sin_port), to: Edition.sidebarPort,
                                         path: { $0.hasSuffix("/LampSidebar.appex/Contents/MacOS/LampSidebar") }) else { return nil }
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &code) == errSecSuccess, let code else { return nil }
        return Store.shared.projects.first { project in
            (hashes[project.id] ?? []).contains { hex in
                var requirement: SecRequirement?
                return SecRequirementCreateWithString("cdhash H\"\(hex)\"" as CFString, [], &requirement) == errSecSuccess
                    && SecCodeCheckValidity(code, [], requirement) == errSecSuccess
            }
        }
    }
}

/// Lamp's end of every sidebar: a socket in each app's extension folder, and what's said over it.
@MainActor
final class SidebarServer {
    static let shared = SidebarServer()

    private var listener: Listener?
    private var connections: [ObjectIdentifier: Connection] = [:]
    private var watching: AnyCancellable?
    private var pending = false

    /// Some app's chat is showing beside it: Lamp keeps running when its own window closes.
    var isInUse: Bool { !connections.isEmpty }

    /// This app's chat is showing beside it.
    func isConnected(_ projectID: String) -> Bool { connections.values.contains { $0.projectID == projectID } }

    /// At launch: an app whose sidebar is open finds Lamp again.
    func start() {
        listener = Listener(server: self)
        // The chat, and how far an open card has been answered in Lamp's window, which isn't the Store's.
        watching = Store.shared.objectWillChange.merge(with: AskProgresses.shared.objectWillChange)
            .merge(with: WishLinkCards.shared.objectWillChange).sink { [weak self] _ in
            DispatchQueue.main.async { self?.scheduleUpdate() }
        }
        // A key, a model chosen in Settings or for the app, or Not Now changes what an offer's card says.
        for name in [KeyStore.changed, AppModels.changed, UserDefaults.didChangeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleUpdate() }
            }
        }
    }

    fileprivate func accepted(_ socket: Int32) {
        guard let project = Sidebar.app(on: socket) else {
            print("Sidebar: a connection that wasn't from an extension Lamp signed; closed")
            close(socket)
            return
        }
        let connection = Connection(socket: socket, projectID: project.id, server: self)
        connections[ObjectIdentifier(connection)] = connection
        MagicPanel.shared.follow(project.id)
        MagicPanel.shared.chatOpenedInApp(project)
        Store.shared.refreshUndoOffer(project)
        connection.push(force: true)
    }

    fileprivate func closed(_ connection: Connection) {
        connections[ObjectIdentifier(connection)] = nil
        // With no sidebar left for it, nothing shows the microphone or can stop it: dictation ends with the last.
        let id = connection.projectID
        if !connections.values.contains(where: { $0.projectID == id }) {
            dictations.removeValue(forKey: id)?.cancel()
            listening[id] = nil
        }
    }

    private func scheduleUpdate() {
        guard !pending, !connections.isEmpty else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            pending = false
            connections.values.forEach { $0.push(force: false) }
        }
    }

    /// The sidebar empties its box as Return is pressed, before Lamp has the words: when they weren't sent after all,
    /// Lamp's draft (which still holds them) goes back to the box, as a draft changed here would.
    private func giveBack(_ project: LampProject) {
        draftVersions[project.id, default: 0] += 1
        pushNow()
    }

    private func pushNow() {
        connections.values.forEach { $0.push(force: false) }
    }

    // MARK: What the sidebar shows

    /// Bumped when the draft is changed anywhere but the sidebar itself, which then takes it up.
    private var draftVersions: [String: Int] = [:]
    private var draftsFromSidebar: [String: String] = [:]
    /// How many times the sidebar's words were taken to be sent (`submit`), by app.
    private var sends: [String: Int] = [:]
    private var shownDrafts: [String: String] = [:]

    fileprivate func state(for project: LampProject) -> SidebarState {
        let store = Store.shared
        let draft = store.draft(for: project)
        if shownDrafts[project.id] != draft.text {
            if draftsFromSidebar[project.id] != draft.text { draftVersions[project.id, default: 0] += 1 }
            shownDrafts[project.id] = draft.text
        }
        let log = store.logs[project.id] ?? []
        let busy = store.busy.contains(project.id)
        let details = Self.details
        // The progress line, as Lamp's window shows it: not under the agent's questions.
        let progress = busy && Talk.open(in: log) == nil ? store.progress[project.id] : nil
        var state = SidebarState(app: project.name, lines: Self.lines(log, project: project, busy: busy, progressShown: progress != nil,
                                                                                         reach: reach[project.id] ?? LogLine.recentCount,
                                                                                         canSendAgain: !busy && !store.pendingSubmissions.contains(project.id),
                                                                                         details: details),
                                 working: progress?.activity, workingSince: progress?.started, empty: log.isEmpty, busy: busy,
                                 draft: draft.text, draftVersion: draftVersions[project.id] ?? 0,
                                 attachments: draft.attachments.map { Self.attachment($0) })
        state.workingActivitySince = progress?.activitySince
        state.workingSteps = progress == nil ? nil : Self.liveSteps(log, project: project, details: details, doing: progress?.activity,
                                                                                 looking: progress?.looking == true)
        state.pointed = draft.pointed.map { Self.pointed($0, canChooseAgain: store.canPoint(in: project)) }
        let canSendNow = store.canSendNow(in: project)
        let lastWaiting = store.waitingToSend(in: project).last?.id
        // Not Lamp's own request waiting for Reload (`Store.pause`): the Reload line stands for it.
        state.queued = (store.queued[project.id] ?? []).filter { !$0.afterReload }.map { message in
            var queued = SidebarQueued(id: message.id, text: message.text,
                                       attachments: message.attachments.map { Self.attachment($0) })
            queued.pointed = message.pointed.map { Self.pointed($0) }
            queued.sendingNow = message.sendNow ? true : nil
            // Send Now is the group's: offered once, under the latest waiting message.
            queued.canSendNow = canSendNow && message.id == lastWaiting ? true : nil
            return queued
        }
        let waiting = store.queued[project.id] ?? []
        for index in state.lines.indices where state.lines[index].kind == .ask {
            guard let line = log.first(where: { $0.id == state.lines[index].id }),
                  let message = Talk.waiting(on: line, in: waiting) else { continue }
            state.lines[index].takeBack = message.id
            state.lines[index].waitingForSetup = store.setup.ready ? nil : true
        }
        state.waitingForSetup = !store.setup.ready
        state.waitingForReload = store.queueWaitsForReload(in: project) ? true : nil
        state.approval = store.approvals[project.id].map {
            SidebarApproval(id: $0.id, title: $0.title, command: $0.command, explanation: $0.explanation?.look, request: $0.request,
                            whyAsked: $0.whyAsked)
        }
        state.notResponding = store.notResponding[project.id] != nil ? ErrorMessages.notResponding(project.name) : nil
        state.replacing = draft.replacing != nil
        state.hasEarlier = LogLine.recentStart(in: LogLine.visible(log, details: details), atLeast: reach[project.id] ?? LogLine.recentCount) > 0
        state.suggestion = suggestion(for: project, log: log, busy: busy)
        state.listening = dictations[project.id]?.isListening ?? false
        state.canDictate = Dictation.hasMicrophone
        state.dictationProblem = dictations[project.id]?.problem.map {
            SidebarProblem(title: $0.title, message: $0.message, settingsButton: $0.settingsURL == nil ? nil : $0.settingsButton)
        }
        state.submitting = store.pendingSubmissions.contains(project.id)
        state.sends = sends[project.id, default: 0]
        // As Lamp's window offers it: not while anything waits to go after the change.
        state.undoChange = busy || !(store.queued[project.id] ?? []).isEmpty ? nil : store.undoOffers[project.id]
        let history = history(for: project, busy: busy, lines: log.count)
        state.toolbar = SidebarToolbar(canUndo: !busy && (history?.undoable ?? false), canShare: store.canShare(project) && (history?.made ?? false),
                                       hasVersions: history?.saved ?? false, details: details, usage: store.usageSummary(project))
        state.panel = panels[project.id]
        switch state.panel {
        case .versions:
            let versions = versions(for: project, busy: busy)
            state.versions = versions.list
            state.hasEarlierVersions = versions.more
        case .info: state.info = AppInfoView.sections(for: project, models: AppModels.load(project), store: store)
        case nil: break
        }
        state.sharing = sharing.removeValue(forKey: project.id)
        if let card = WishLinkCards.shared.card(for: project), card.inSidebar { state.wishLink = wishLink(card, of: project) }
        return state
    }

    /// The Share Link card as the chat beside the app draws it, its picture made small once for each picture.
    private func wishLink(_ card: WishLinkCards.Card, of project: LampProject) -> SidebarWishLink {
        if wishLinkPictures[project.id]?.digest != card.pictureDigest {
            wishLinkPictures[project.id] = (card.pictureDigest, card.picture.flatMap(Self.smallPicture))
        }
        let shown = card.shared?.shown
        return SidebarWishLink(
            name: card.values.name, line: card.values.line, words: card.values.words, includePicture: card.values.includePicture,
            revision: card.revision, picture: wishLinkPictures[project.id]?.data, icon: card.icon,
            link: card.shared?.url.absoluteString,
            shown: shown.map { SidebarWishLinkValues(name: $0.name, line: $0.line, words: $0.words, includePicture: $0.picture != nil) },
            newPicture: shown?.picture != nil && shown?.picture != card.pictureDigest,
            sending: card.stage == .sending, problem: { if case .failed(let message) = card.stage { message } else { nil } }(),
            copied: card.copied, canRetake: WishLinkCards.shared.canRetake(project), retaking: card.retaking,
            limits: [WishLink.Limit.name, WishLink.Limit.line, WishLink.Limit.words])
    }

    private var wishLinkPictures: [String: (digest: String?, data: Data?)] = [:]

    /// Agent Details, one setting for both chats as in Lamp's window.
    private static var details: Bool { UserDefaults.standard.bool(forKey: "showDetails") }

    // MARK: The toolbar's

    /// The panel each app's sidebar shows in place of the chat.
    private var panels: [String: SidebarPanel] = [:]
    /// The wish's file after Share…, until it's been sent.
    private var sharing: [String: SidebarSharing] = [:]

    /// What the toolbar knows of each app's history, read again as Lamp's window reads it: when a turn starts or ends
    /// and when the chat changes.
    private var histories: [String: (key: String, value: ProjectView.History?)] = [:]

    private func history(for project: LampProject, busy: Bool, lines: Int) -> ProjectView.History? {
        let key = "\(busy) \(lines)"
        if histories[project.id]?.key != key {
            let known = histories[project.id]?.value
            histories[project.id] = (key, known)
            Task { [weak self] in
                let read = await ProjectView.History.read(project)
                guard let self, self.histories[project.id]?.key == key else { return }
                self.histories[project.id] = (key, read)
                self.scheduleUpdate()
            }
        }
        return histories[project.id]?.value
    }

    /// The Versions panel's list, read again as Lamp's window reads it: when a turn starts or ends and when a version
    /// changes (a picture, a title, a name). The newest first, with a small picture each.
    private var versionLists: [String: (key: String, value: [SidebarVersion]?)] = [:]

    /// How many of each app's versions the panel shows, newest first, grown when it asks for earlier ones.
    private var versionReach: [String: Int] = [:]
    private static let versionPage = 60

    private func versions(for project: LampProject, busy: Bool) -> (list: [SidebarVersion]?, more: Bool) {
        let store = Store.shared
        let reach = versionReach[project.id] ?? Self.versionPage
        let key = "\(busy)-\(store.versionsRevision)-\(reach)"
        if versionLists[project.id]?.key != key {
            let known = versionLists[project.id]?.value
            versionLists[project.id] = (key, known)
            Task { [weak self] in
                let list = await Versions.list(project)
                if let current = list.first { await store.fillCurrentPicture(project, current: current) }
                store.titleVersions(project)
                // A page at a time, so what's sent with each change stays small; the rest is a click away.
                let shown = await Task.detached {
                    list.prefix(reach).enumerated().map { index, version in
                        SidebarVersion(id: version.id, label: version.label, named: version.name != nil, date: version.date,
                                       current: index == 0, picture: Self.versionPicture(Versions.pictureURL(in: project, for: version.id)))
                    }
                }.value
                guard let self, self.versionLists[project.id]?.key == key else { return }
                self.versionLists[project.id] = (key, shown)
                self.versionsTotal[project.id] = list.count
                self.scheduleUpdate()
            }
        }
        let list = versionLists[project.id]?.value
        return (list, (versionsTotal[project.id] ?? 0) > (list?.count ?? 0))
    }

    private var versionsTotal: [String: Int] = [:]

    /// A version's picture, small enough to send with the list every time the chat changes.
    private nonisolated static func versionPicture(_ url: URL) -> Data? {
        NSImage(contentsOf: url).flatMap(smallPicture)
    }

    private nonisolated static func smallPicture(_ data: Data) -> Data? { NSImage(data: data).flatMap(smallPicture) }

    private nonisolated static func smallPicture(_ image: NSImage) -> Data? {
        let width: CGFloat = 360
        let scale = min(width / max(image.size.width, 1), 1)
        let size = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let small = NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
        guard let tiff = small.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }

    /// Share…: the file is made here, where the wish is, and handed to the sidebar, which shows the share menu.
    private func share(_ project: LampProject) {
        Task { [weak self] in
            do {
                let file = try await Task.detached(priority: .userInitiated) { () -> SidebarFile in
                    let url = try Sharing.export(project)
                    defer { try? FileManager.default.removeItem(at: url) }
                    return SidebarFile(name: url.lastPathComponent, data: try Data(contentsOf: url))
                }.value
                self?.sharing[project.id] = SidebarSharing(id: UUID(), file: file)
                self?.scheduleUpdate()
            } catch {
                Store.shared.log(project, .error, error.localizedDescription)
            }
        }
    }

    /// The agent's progress line: a message like any other while its turn goes on, and once it's among a finished
    /// turn's steps (as the messages it wrote on the way are) a status line with the progress line's mark, which a sidebar from before progress lines draws
    /// as a status line rather than failing to read the chat.
    static func progress(_ line: LogLine, gap: Double, folded: Bool = false) -> SidebarLine {
        guard folded else { return SidebarLine(id: line.id, kind: .agent, text: line.text, gap: gap) }
        var out = SidebarLine(id: line.id, kind: .status, text: line.text, gap: gap)
        out.symbol = ChatLook.progressSymbol
        return out
    }

    /// The chat as Lamp's window shows it without Agent Details (`Transcript`): the same lines, gathered and
    /// spaced the same way. Cards and notes Lamp's window has and this doesn't yet are left out.
    static func tools(_ run: [LogLine], gap: Double, running: Bool) -> SidebarLine {
        let calls = run.map { ToolCall($0.text) }
        var line = SidebarLine(id: run[0].id, kind: .tools, text: ToolGroup.summary(calls), gap: gap, running: running)
        line.symbol = ToolGroup.icon(calls)
        line.calls = calls.map { SidebarToolCall(symbol: $0.icon, verb: $0.verb, argument: $0.argument) }
        return line
    }

    /// A turn's steps as its one line opens to them, in "Worked for…" and in the live line, as Lamp's window shows them.
    static func stepLines(_ steps: [LogLine]) -> [SidebarLine] {
        ChatItem.items(steps).flatMap { step -> [SidebarLine] in
            switch step {
            case .tools(let run): [tools(run, gap: 4, running: false)]
            case .statuses(let run): run.map { line in
                var status = SidebarLine(id: line.id, kind: .status, text: line.text, gap: 4)
                status.said = line.said
                return status
            }
            default: []
            }
        }
    }

    /// The steps of the turn still going, for the line that says what it's doing, as Lamp's window shows them.
    static func liveSteps(_ log: [LogLine], project: LampProject, details: Bool, doing: String? = nil, looking: Bool = false) -> [SidebarLine]? {
        guard !details else { return nil }
        let steps = ChatItem.live(LogLine.visible(log, details: false), dir: project.dir, doing: doing, looking: looking).steps
        return steps.isEmpty ? nil : stepLines(steps)
    }

    static func lines(_ log: [LogLine], project: LampProject, busy: Bool, progressShown: Bool,
                      reach: Int = LogLine.recentCount, canSendAgain: Bool = false, details: Bool = false) -> [SidebarLine] {
        let dir = project.dir
        // Offers with nothing left to offer (an icon drawn, a widget gone) are left out, as in Lamp's window.
        let lines = Transcript.withoutSpentOffers(LogLine.visible(log, details: details), dir: dir)
        let finalAnswers = Transcript.finalAnswers(in: lines, busy: busy)
        let openAsk = Talk.open(in: lines)?.id
        // Only the end of a long chat, as Lamp's window opens on it; the rest is a click away in Lamp.
        let start = LogLine.recentStart(in: lines, atLeast: reach)
        let latestRequest = lines.last { $0.kind == .user }?.id
        let shown = Array(lines[start...])
        // While the turn goes on, its steps since it last said something are in the line that says what it's doing (`liveSteps`).
        let items = ChatItem.items(progressShown ? (details ? Transcript.withoutStepInProgress(shown) : ChatItem.live(shown, dir: dir).shown) : shown,
                                   gather: !details)
        var out: [SidebarLine] = []
        for (index, item) in items.enumerated() {
            let isLast = index == items.count - 1
            let gap = Double(ChatItem.gap(after: index > 0 ? items[index - 1] : nil, before: item, isFinalAnswer: finalAnswers.contains(item.id)))
            switch item {
            case .statuses(let run):
                for (position, line) in run.enumerated() {
                    let running = isLast && busy && !progressShown && line.id == run.last?.id && line.text.hasSuffix("…")
                    var status = SidebarLine(id: line.id, kind: .status, text: line.text, gap: position == 0 ? gap : 4, running: running)
                    status.said = line.said
                    out.append(status)
                }
            case .tools(let run):
                // Only with Agent Details on: the steps, summed up, each one under it.
                out.append(tools(run, gap: gap, running: isLast && busy && !progressShown))
            case .work(let id, let title, let steps):
                var line = SidebarLine(id: id, kind: .work, text: title, gap: gap)
                line.steps = Self.stepLines(steps)
                out.append(line)
            case .line(let line):
                switch line.kind {
                case .user:
                    let (files, pointed) = line.draftAttachments(in: project)
                    var request = SidebarLine(id: line.id, kind: .user, text: line.text, gap: gap,
                                              attachments: files.isEmpty ? nil : files.map { attachment($0) })
                    request.pointed = pointed.map { Self.pointed($0) }
                    request.canGoBack = line.version != nil
                    request.canSendAgain = canSendAgain && line.canSendAgain
                    request.isLatest = line.id == latestRequest
                    out.append(request)
                case .agent:
                    out.append(SidebarLine(id: line.id, kind: .agent, text: line.text, gap: gap, growing: busy))
                case .progress:
                    out.append(Self.progress(line, gap: gap))
                case .summary:
                    out.append(SidebarLine(id: line.id, kind: .summary, text: line.text, gap: gap))
                case .error:
                    out.append(SidebarLine(id: line.id, kind: .error, text: line.text, gap: gap))
                case .ask:
                    guard let ask = line.ask else { continue }
                    let open = line.id == openAsk
                    // What a sidebar from before the shared card reads: the questions while they wait, else what
                    // was chosen, folded.
                    var card = SidebarLine(id: line.id, kind: .ask, text: open ? ask.text : (ask.folded ?? ask.text), gap: gap,
                                           questions: open ? ask.questions.map {
                                               SidebarQuestion(question: $0.question, options: $0.options.map { $0.title },
                                                               symbols: $0.options.map { $0.symbol })
                                           } : nil)
                    card.ask = ask
                    card.askOpen = open
                    let progress = AskProgresses.shared.progress(for: line.id)
                    card.progress = progress
                    card.progressVersion = progressVersion(for: line.id, progress)
                    out.append(card)
                case .result:
                    continue
                case .needsKey, .offer:
                    // The card's header: setting it up (a key, a download, a sign-in) happens in Lamp's window.
                    guard let offer = line.setupOffer else { continue }
                    let header = SetupCard.header(offer, reason: line.text, project: project)
                    var card = SidebarLine(id: line.id, kind: .offer, text: header.title, gap: gap)
                    card.symbol = SetupCard.symbol(offer)
                    card.status = header.status
                    card.done = header.done
                    card.button = header.done || offer.declined(in: project) ? nil : "Set Up in Lamp…"
                    out.append(card)
                case .widget:
                    let placed = Store.shared.placedWidgets.contains(project.id)
                    var card = SidebarLine(id: line.id, kind: .offer, text: WidgetCard.title(project.name), gap: gap)
                    card.symbol = "widget.small"
                    card.status = project.platform.hasIOS ? WidgetCard.phoneStatus(project.name) : WidgetCard.status(project.name, placed: placed)
                    card.done = placed
                    out.append(card)
                case .reload:
                    let queued = Store.shared.reloadWhenFree.contains(project.id)
                    var card = SidebarLine(id: line.id, kind: .action,
                                           text: queued ? ReloadLine.queued(project.name) : ReloadLine.text(project.name), gap: gap)
                    card.symbol = "arrow.clockwise"
                    card.button = "Reload"
                    card.prominent = true
                    card.disabled = queued
                    out.append(card)
                case .drawIcon:
                    var card = SidebarLine(id: line.id, kind: .action, text: DrawIconLine.text(project.name), gap: gap)
                    card.symbol = "paintbrush.pointed"
                    card.button = "Draw Icon…"
                    out.append(card)
                case .iphoneSetup:
                    let (kind, part) = IPhoneSetupLine.wanted(from: line.text)
                    var card = SidebarLine(id: line.id, kind: .action, text: IPhoneSetupLine.text(project.name, wanted: kind, part: part), gap: gap)
                    card.symbol = IPhoneSetupLine.setup(for: kind).symbol
                    card.button = "See What's Needed…"
                    card.disabled = IPhoneSetupLine.isOff(for: project, wanted: kind, part: part)
                    out.append(card)
                case .deviceOffer:
                    // A device app's chat is in Lamp's window, never beside an app.
                    continue
                case .deviceStep:
                    // The step's card has a field and a sign-in, which happen in Lamp's window.
                    let step = DeviceStepLine.text(line.text)
                    var card = SidebarLine(id: line.id, kind: .offer, text: step.text, gap: gap)
                    card.symbol = "dot.radiowaves.left.and.right"
                    card.done = step.done
                    card.button = step.done ? nil : "Set Up in Lamp…"
                    out.append(card)
                case .noted:
                    guard let receipt = line.noted else { continue }
                    var card = SidebarLine(id: line.id, kind: .note, text: NoteCard.title(receipt, app: project.name), gap: gap)
                    card.added = receipt.added
                    card.removed = receipt.removed
                    card.undone = receipt.undone == true
                    card.problem = noteProblems[line.id]
                    out.append(card)
                default:
                    continue
                }
            }
        }
        return out
    }

    /// An attachment as the sidebar shows it: its name, and a picture of it or its icon, as Lamp's window has it.
    fileprivate static func attachment(_ url: URL) -> SidebarAttachment {
        SidebarAttachment(name: url.lastPathComponent, thumbnail: thumbnail(url), isImage: Attachments.isImage(url))
    }

    /// How much of each chat the sidebar shows, from its end, grown when it scrolls to the top (`earlier`).
    private var reach: [String: Int] = [:]

    /// The message box's suggestion, as Lamp's window offers it: one per finished turn, made once for both
    /// (`NextStep` keeps them), and not again once dismissed.
    private var suggestions: [String: (turn: UUID, text: String?)] = [:]
    private var dismissedSuggestions: [String: UUID] = [:]

    private func suggestion(for project: LampProject, log: [LogLine], busy: Bool) -> String? {
        guard !busy, let turn = NextStep.turn(in: log), dismissedSuggestions[project.id] != turn,
              Store.shared.draft(for: project).text.isEmpty else { return nil }
        if let known = suggestions[project.id], known.turn == turn { return known.text }
        suggestions[project.id] = (turn, nil)
        Task { [weak self] in
            let text = await NextStep.suggest(for: project, lines: log)
            guard let self, self.suggestions[project.id]?.turn == turn else { return }
            self.suggestions[project.id] = (turn, text)
            self.scheduleUpdate()
        }
        return nil
    }

    /// Dictation into the sidebar's message box runs in Lamp, which has the microphone, and writes into the
    /// draft the sidebar shows.
    private var dictations: [String: Dictation] = [:]
    private var listening: [String: AnyCancellable] = [:]

    private func dictate(_ on: Bool, in project: LampProject) {
        let dictation = dictations[project.id] ?? Dictation()
        if dictations[project.id] == nil {
            dictations[project.id] = dictation
            // Listening starts and stops on its own too (a long pause): the sidebar's microphone follows.
            listening[project.id] = dictation.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { self?.scheduleUpdate() }
            }
        }
        if !on { return dictation.stop() }
        guard !dictation.isListening else { return }
        let store = Store.shared
        let typed = store.draft(for: project).text
        let separator = typed.isEmpty || typed.last!.isWhitespace ? "" : " "
        Task {
            await dictation.start { heard, _ in
                guard let current = store.current(project) else { return }
                var draft = store.draft(for: current)
                draft.text = typed + separator + heard
                store.updateDraft(draft, for: current)
            }
            self.scheduleUpdate()
        }
        scheduleUpdate()
    }

    /// Sends what's in the message box the way Lamp's window does (`ProjectView.send`): held while setup is
    /// needed, sent again in place of a request taken back, and the box left with whatever came after.
    private func submit(_ project: LampProject) {
        let store = Store.shared
        let submitted = store.draft(for: project)
        guard !submitted.isEmpty else { return }
        let replaced = submitted.replacing.flatMap { id in store.logs[project.id]?.first { $0.id == id } }
        guard replaced == nil || !store.busy.contains(project.id), let token = store.beginSubmission(project) else {
            return giveBack(project)
        }
        // The box's words are taken: a Send the sidebar made before it heard so isn't sent again.
        sends[project.id, default: 0] += 1
        dictations[project.id]?.cancel()
        store.endArrival(for: project.id)
        func finish(sent: Bool) {
            if let current = store.current(project) {
                store.updateDraft(store.draft(for: current).afterSubmission(submitted, sent: sent), for: current)
            }
            store.endSubmission(token)
            if !sent { giveBack(project) }
            // At once, not after the usual pause: the person is waiting to see their message go.
            pushNow()
        }
        PhoneSetup.shared.perform(for: project, in: store, cancelled: { finish(sent: false) }) { current in
            let text = submitted.text.trimmed
            guard let replaced else {
                store.send(text, attachments: submitted.attachments, pointed: submitted.pointed, to: current)
                return finish(sent: true)
            }
            Task { finish(sent: await store.sendAgain(replaced, as: text, attachments: submitted.attachments, pointed: submitted.pointed, in: current)) }
        }
    }

    /// How far each open card has been answered, as last sent and as the sidebar last said, and the number that
    /// goes up only when it changed in Lamp's window (`SidebarLine.progressVersion`), as the draft's does.
    fileprivate static var shownProgress: [UUID: AskProgress] = [:]
    fileprivate static var progressFromSidebar: [UUID: AskProgress] = [:]
    fileprivate static var progressVersions: [UUID: Int] = [:]

    private static func progressVersion(for line: UUID, _ progress: AskProgress?) -> Int {
        let value = progress ?? AskProgress()
        if shownProgress[line] != value {
            if progressFromSidebar[line] != value { progressVersions[line, default: 0] += 1 }
            shownProgress[line] = value
        }
        return progressVersions[line] ?? 0
    }

    /// What went wrong taking back a save of the notes from the sidebar, by its receipt, as Lamp's window shows it
    /// under the receipt.
    fileprivate static var noteProblems: [UUID: String] = [:]

    /// What was pointed at, as the sidebar shows it.
    fileprivate static func pointed(_ pointed: PointedAt, canChooseAgain: Bool? = nil) -> SidebarPointed {
        SidebarPointed(title: pointed.title, detail: pointed.detail, canChooseAgain: canChooseAgain)
    }

    private static var thumbnails: [URL: Data] = [:]
    fileprivate static func thumbnail(_ url: URL) -> Data? {
        if let data = thumbnails[url] { return data }
        let image = Attachments.isImage(url) ? NSImage(contentsOf: url) : NSWorkspace.shared.icon(forFile: url.path)
        guard let image else { return nil }
        let side: CGFloat = 64
        let scale = min(side / max(image.size.width, 1), side / max(image.size.height, 1), 1)
        let size = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let small = NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
        guard let tiff = small.tiffRepresentation, let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        thumbnails[url] = data
        return data
    }

    // MARK: What the person did

    fileprivate func handle(_ command: SidebarCommand, from projectID: String) {
        let store = Store.shared
        guard let project = store.projects.first(where: { $0.id == projectID }) else { return }
        switch command {
        case .send(let text, let seen):
            // Sent already: the box still showed these words when Return was pressed again.
            if let seen, seen < sends[project.id, default: 0] { return }
            // The words as the sidebar has them, in case its last edit is still on its way.
            var draft = store.draft(for: project)
            if draft.text != text {
                draft.text = text
                store.updateDraft(draft, for: project)
            }
            submit(project)
        case .goBack(let id, let before):
            guard let line = store.logs[project.id]?.first(where: { $0.id == id }), !store.busy.contains(project.id) else { return }
            Task { await store.restore(project, toVersionOf: line, before: before) }
        case .takeBack(let id):
            // As Lamp's window does (`ProjectView.takeBack`): what was in the box is set aside, and comes back on Escape.
            guard let line = store.logs[project.id]?.first(where: { $0.id == id }), line.canSendAgain,
                  !store.busy.contains(project.id), !store.pendingSubmissions.contains(project.id) else { return }
            var draft = store.draft(for: project)
            if draft.replacing == nil {
                draft.setAsideText = draft.text
                draft.setAsideAttachments = draft.attachments
                draft.setAsidePointed = draft.pointed
            }
            dictations[project.id]?.cancel()
            // Lamp's change, not the sidebar's, even when the box held these words before: the sidebar takes it up.
            draftsFromSidebar[project.id] = nil
            draft.text = line.text
            (draft.attachments, draft.pointed) = line.draftAttachments(in: project)
            draft.replacing = line.id
            store.updateDraft(draft, for: project)
        case .putBack:
            var draft = store.draft(for: project)
            guard draft.replacing != nil, !store.pendingSubmissions.contains(project.id) else { return }
            draft = Store.Draft(text: draft.setAsideText, attachments: draft.setAsideAttachments, pointed: draft.setAsidePointed)
            draftsFromSidebar[project.id] = nil
            store.updateDraft(draft, for: project)
        case .preview(let id, let index):
            // What was pointed at comes after the other files, as the sidebar counts them.
            let (others, pointed) = id.flatMap { id in store.logs[project.id]?.first(where: { $0.id == id }) }
                .map { $0.draftAttachments(in: project) } ?? { let draft = store.draft(for: project); return (draft.attachments, draft.pointed) }()
            let files = others + (pointed?.url.map { [$0] } ?? [])
            guard files.indices.contains(index) else { return }
            // Quick Look's own window, over the app, without bringing Lamp forward.
            let preview = Process()
            preview.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
            preview.arguments = ["-p", files[index].path]
            preview.standardOutput = FileHandle.nullDevice
            preview.standardError = FileHandle.nullDevice
            try? preview.run()
        case .earlier:
            reach[project.id] = (reach[project.id] ?? LogLine.recentCount) + LogLine.recentCount
            scheduleUpdate()
        case .dismissSuggestion:
            if let turn = NextStep.turn(in: store.logs[project.id] ?? []) { dismissedSuggestions[project.id] = turn }
            scheduleUpdate()
        case .dictate(let on):
            dictate(on, in: project)
        case .dictationProblem(let openSettings):
            guard let dictation = dictations[project.id] else { return }
            if openSettings, let url = dictation.problem?.settingsURL { NSWorkspace.shared.open(url) }
            dictation.problem = nil
        case .answer(let id, let answers):
            guard let line = store.logs[project.id]?.first(where: { $0.id == id }) else { return }
            store.answer(line, with: answers, in: project)
        case .draft(let text):
            var draft = store.draft(for: project)
            guard draft.text != text else { return }
            draft.text = text
            draftsFromSidebar[project.id] = text
            store.updateDraft(draft, for: project)
        case .attach(let files):
            // Written where Lamp keeps pasted files, each in a folder of its own so two of one name both stay.
            let urls = files.compactMap { file -> URL? in
                let name = (file.name as NSString).lastPathComponent.filter { !"/:\\\0".contains($0) }
                guard !name.isEmpty, !name.hasPrefix(".") else { return nil }
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-sidebar-\(UUID().uuidString)")
                let url = folder.appendingPathComponent(name)
                guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
                      (try? file.data.write(to: url)) != nil else { return nil }
                return url
            }
            store.attach(urls, to: project)
        case .offer(let id):
            guard let line = store.logs[project.id]?.first(where: { $0.id == id }) else { return }
            // Reload is done where the person is, beside the app: nothing to show in Lamp's window.
            if line.kind == .reload { return store.reloadWaiting(project.id) }
            // A device's setup has a window of its own.
            if line.kind == .deviceStep, let device = store.devices.first(where: { $0.id == line.text && $0.integration != nil }) {
                return DeviceSetupWindow.show(device)
            }
            // In Lamp's window: where the card's keys, downloads and sign-ins are, and what Image Playground
            // opens over, which Lamp may have put away for the sidebar.
            NSApp.activate(ignoringOtherApps: true)
            store.showChat(project.id)
            if line.kind == .drawIcon { store.iconFromPlayground(project) }
        case .undoNote(let id):
            Self.noteProblems[id] = store.undoNote(id, in: project)
            scheduleUpdate()
        case .undoChange(let version):
            Task { await store.undo(project, change: version) }
        case .askProgress(let id, let progress):
            Self.progressFromSidebar[id] = progress
            AskProgresses.shared.set(progress, for: id)
        case .removeAttachment(let index):
            var draft = store.draft(for: project)
            if index == draft.attachments.count, draft.pointed != nil {
                draft.pointed = nil
            } else {
                guard draft.attachments.indices.contains(index) else { return }
                draft.attachments.remove(at: index)
            }
            store.updateDraft(draft, for: project)
        case .pointAgain:
            MagicPanel.shared.pointAgain(in: project)
        case .point:
            MagicPanel.shared.point(in: project, fromLamp: false)
        case .stop:
            store.stop(project)
        case .unqueue(let id):
            guard let message = store.queued[project.id]?.first(where: { $0.id == id }) else { return }
            store.unqueue(message, from: project)
        case .sendNow(let latest):
            store.sendNow(in: project, latest: latest)
        case .approve(let id, let allow, let allowAll):
            // Only the approval still waiting: a click that arrives after it was answered in Lamp does nothing.
            guard store.approvals[project.id]?.id == id else { return }
            store.answerApproval(for: project, allow: allow, allowAll: allowAll)
        case .forceQuit:
            guard store.notResponding[project.id] != nil else { return }
            store.forceQuit(project)
        case .showLamp:
            // Asked for from another app's window, so Lamp has to take the front for itself.
            NSApp.activate(ignoringOtherApps: true)
            store.showDesk()
        case .undo:
            Task { await store.undo(project) }
        case .delete:
            Task { await store.delete(project) }
        case .copyWishFile:
            store.copyAppFile(project)
        case .share:
            share(project)
        case .export:
            // Lamp's own save panel, in front of the app.
            NSApp.activate(ignoringOtherApps: true)
            store.chooseExport(project)
        case .details(let on):
            UserDefaults.standard.set(on, forKey: "showDetails")
        case .panel(let panel):
            panels[project.id] = panel
            scheduleUpdate()
        case .earlierVersions:
            versionReach[project.id] = (versionReach[project.id] ?? Self.versionPage) + Self.versionPage
            scheduleUpdate()
        case .goBackToVersion(let id):
            guard !store.busy.contains(project.id) else { return }
            Task {
                guard let version = await Versions.list(project).first(where: { $0.id == id }) else { return }
                await store.restore(project, to: version)
            }
        case .nameVersion(let id, let name):
            Task {
                guard let version = await Versions.list(project).first(where: { $0.id == id }) else { return }
                await store.name(version, of: project, as: name.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        case .wishLink(let command):
            let cards = WishLinkCards.shared
            switch command {
            case .open: cards.open(project, inSidebar: true)
            case .share(let values):
                cards.update(project, values: WishLinkCard.Values(name: values.name, line: values.line, words: values.words,
                                                                  includePicture: values.includePicture))
                cards.share(project)
            case .copy: cards.copy(project)
            case .stop: cards.stop(project)
            case .retake: cards.retake(project)
            case .close: cards.close(project)
            }
        case .infoAction(let action):
            AppInfoView.perform(action, for: project) { tab in
                UserDefaults.standard.set(tab, forKey: "settingsTab")
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            scheduleUpdate()
        case .hello:
            break   // answered by the connection
        }
    }

    // MARK: Sockets

    /// Lamp's port on this Mac's own address, which only programs on this Mac can reach.
    fileprivate final class Listener {
        let fd: Int32
        let source: DispatchSourceRead

        init?(server: SidebarServer) {
            let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard socket >= 0 else { return nil }
            var on: Int32 = 1
            setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = Edition.sidebarPort.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            guard bound == 0, Darwin.listen(socket, 8) == 0 else {
                print("Sidebar: couldn't listen: \(String(cString: strerror(errno)))")
                close(socket)
                return nil
            }
            fd = socket
            source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: .main)
            source.setEventHandler { [weak server] in
                let client = accept(socket, nil, nil)
                guard client >= 0 else { return }
                MainActor.assumeIsolated { server?.accepted(client) }
            }
            source.resume()
        }
    }

    fileprivate final class Connection {
        let fd: Int32
        let projectID: String
        weak var server: SidebarServer?
        private var source: DispatchSourceRead?
        private var buffer = Data()
        private var last: Data?
        /// The draft as last sent, and its version. The sidebar takes the draft only when its version changes, so a
        /// draft that changed only by the person typing in the sidebar is sent as it last was: otherwise each pause in
        /// typing sent the whole chat back, to be read and drawn again.
        private var sentDraft = ""
        private var sentDraftVersion = -1
        private let outbox: SidebarOutbox
        /// A state that came while the last one was still going out: only the latest is sent once it has.
        private var waiting = false
        /// Which shape of the chat the sidebar reads (`SidebarCommand.hello`); 1 until it says.
        fileprivate var version = 1

        init(socket: Int32, projectID: String, server: SidebarServer) {
            fd = socket
            self.projectID = projectID
            self.server = server
            // A sidebar that went away mid-write mustn't end Lamp.
            var on: Int32 = 1
            setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            outbox = SidebarOutbox(fd: socket)
            let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.read() } }
            source.resume()
            self.source = source
            outbox.onDrain = { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.waiting else { return }
                    self.waiting = false
                    self.push(force: false)
                }
            }
        }

        @MainActor private func read() {
            var chunk = [UInt8](repeating: 0, count: 65536)
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count < 0, errno == EAGAIN || errno == EINTR { return }
            guard count > 0 else { return end() }
            buffer.append(contentsOf: chunk[0..<count])
            // A long line (files attached) comes in many pieces: the buffer is looked through only once one ends a line.
            guard chunk[0..<count].contains(0x0A) else { return }
            for line in SidebarWire.lines(from: &buffer) {
                guard let command = try? JSONDecoder().decode(SidebarCommand.self, from: line) else { continue }
                if case .hello(let version) = command {
                    self.version = version
                    push(force: true)
                    // A starter's first chat: what it offers to change arrives once the chat is there to see.
                    Store.shared.offerStarterChanges(projectID, after: 0.9)
                } else {
                    server?.handle(command, from: projectID)
                }
            }
        }

        @MainActor func push(force: Bool) {
            guard !outbox.isHolding else { waiting = true; return }
            guard let server, let project = Store.shared.projects.first(where: { $0.id == projectID }) else { return }
            var state = server.state(for: project)
            // A sidebar from before a turn's steps were folded can't read the fold, and would drop the whole chat: it
            // gets the steps as lines, as it showed them.
            if version < 7 {
                state.lines = state.lines.flatMap { line -> [SidebarLine] in
                    guard line.kind == .work else { return [line] }
                    var steps = line.steps ?? []
                    if !steps.isEmpty { steps[0].gap = line.gap }
                    return steps
                }
            }
            // A sidebar from before the summary line can't read one, and would drop the whole chat.
            if version < 2 { state.lines.removeAll { $0.kind == .summary } }
            // Nor one from before the notes receipt a receipt.
            if version < 3 { state.lines.removeAll { $0.kind == .note } }
            if version < 4 { state.lines.removeAll { $0.kind == .offer || $0.kind == .action } }
            if version < 6 { state.lines.removeAll { $0.kind == .tools } }
            // What was pointed at, as the file it was before it had a pill of its own.
            if version < 5 {
                func asFile(_ pointed: SidebarPointed?) -> [SidebarAttachment] {
                    pointed.map { [SidebarAttachment(name: $0.title + ".png", thumbnail: nil)] } ?? []
                }
                state.attachments += asFile(state.pointed)
                for index in state.lines.indices where state.lines[index].pointed != nil {
                    state.lines[index].attachments = (state.lines[index].attachments ?? []) + asFile(state.lines[index].pointed)
                }
                state.queued = state.queued?.map { message in
                    var message = message
                    message.attachments += asFile(message.pointed)
                    return message
                }
            }
            // Answers clicked on a card and waiting in line are drawn as the folded card; a sidebar from before that
            // takes them back only from the waiting message.
            if version >= 8 {
                let onCards = Set(state.lines.compactMap(\.takeBack))
                state.queued = state.queued?.filter { !onCards.contains($0.id) }
            }
            // A sidebar from before keeps no words of its own when its box is drawn again (a panel closed), and reads
            // Lamp's: it gets the draft as it is.
            if version >= 9, state.draftVersion == sentDraftVersion {
                state.draft = sentDraft
            } else {
                sentDraft = state.draft
                sentDraftVersion = state.draftVersion
            }
            guard let data = SidebarWire.encode(state), force || data != last else { return }
            last = data
            outbox.send(data)
        }

        @MainActor private func end() {
            outbox.close()
            source?.cancel()
            source = nil
            close(fd)
            server?.closed(self)
        }
    }
}
