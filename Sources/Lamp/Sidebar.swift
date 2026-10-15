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
    static func install(into app: URL, for project: LampProject) throws {
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
        try entitlements.write(to: entitlementsURL(for: project), atomically: true, encoding: .utf8)
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

    static func entitlementsURL(for project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/sidebar-entitlements.plist") }

    /// The signing step, before the app's: with the hardened runtime, so nothing can be loaded into it that
    /// would make it act otherwise than its code.
    static func signingStep(_ sign: String) -> String {
        "{ [ ! -d \"$LAMP_SIDEBAR\" ] || \(sign) --options runtime --entitlements \"$LAMP_SIDEBAR_ENTITLEMENTS\" \"$LAMP_SIDEBAR\" 2>&1; }"
    }

    static func signingEnvironment(for project: LampProject) -> [String: String] {
        ["LAMP_SIDEBAR": extensionURL(in: project.builtURL).path, "LAMP_SIDEBAR_ENTITLEMENTS": entitlementsURL(for: project).path]
    }

    // MARK: Which extension is the real one

    /// The code hashes of the extensions Lamp signed for each app, newest last: the extension in a running copy
    /// may be from the build before. Kept in Lamp's own folder, never the app's, which the app could change.
    private static var hashesURL: URL { Edition.supportFolder.appendingPathComponent("sidebar-hashes.json") }
    private static var hashes: [String: [String]] = {
        (try? JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: hashesURL))) ?? [:]
    }()

    /// After signing: the hash of what was signed, the one thing a process can't fake about what it runs.
    static func remember(_ project: LampProject) {
        let appex = extensionURL(in: project.builtURL)
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
              peer.sin_addr.s_addr == inet_addr("127.0.0.1"), let pid = process(connectedFrom: peer.sin_port) else { return nil }
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

    /// The sidebar process whose connection to Lamp's port goes out from `port` (both in network order).
    private static func process(connectedFrom port: in_port_t) -> pid_t? {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let found = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        for pid in pids.prefix(Int(max(found, 0))) where pid > 0 {
            var path = [CChar](repeating: 0, count: 4096)
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
                  String(cString: path).hasSuffix("/LampSidebar.appex/Contents/MacOS/LampSidebar") else { continue }
            let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard size > 0 else { continue }
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.size)
            let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, size)
            for fd in fds.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.size) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
                var info = socket_fdinfo()
                guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size)) > 0,
                      info.psi.soi_kind == SOCKINFO_TCP else { continue }
                let tcp = info.psi.soi_proto.pri_tcp.tcpsi_ini
                if in_port_t(truncatingIfNeeded: tcp.insi_lport) == port, in_port_t(truncatingIfNeeded: tcp.insi_fport) == Edition.sidebarPort.bigEndian {
                    return pid
                }
            }
        }
        return nil
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

    /// At launch: an app whose sidebar is open finds Lamp again.
    func start() {
        listener = Listener(server: self)
        watching = Store.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.scheduleUpdate() }
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
        connection.push(force: true)
    }

    fileprivate func closed(_ connection: Connection) {
        connections[ObjectIdentifier(connection)] = nil
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

    // MARK: What the sidebar shows

    /// Bumped when the draft is changed anywhere but the sidebar itself, which then takes it up.
    private var draftVersions: [String: Int] = [:]
    private var draftsFromSidebar: [String: String] = [:]
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
        // The progress line, as Lamp's window shows it: not under the agent's questions.
        let progress = busy && Talk.open(in: log) == nil ? store.progress[project.id] : nil
        return SidebarState(app: project.name, lines: Self.lines(log, dir: project.dir, busy: busy, progressShown: progress != nil),
                            working: progress?.activity, workingSince: progress?.started, empty: log.isEmpty, busy: busy,
                            draft: draft.text, draftVersion: draftVersions[project.id] ?? 0,
                            attachments: draft.attachments.map { SidebarAttachment(name: $0.lastPathComponent, thumbnail: Self.thumbnail($0)) })
    }

    /// The chat as Lamp's window shows it without Agent Details (`Transcript`): the same lines, gathered and
    /// spaced the same way. Cards and notes Lamp's window has and this doesn't yet are left out.
    static func lines(_ log: [LogLine], dir: URL, busy: Bool, progressShown: Bool) -> [SidebarLine] {
        let lines = LogLine.visible(log, details: false)
        let finalAnswers = Transcript.finalAnswers(in: lines, busy: busy)
        let openAsk = Talk.open(in: lines)?.id
        let currentResult = Talk.current(in: lines)?.id
        // Only the end of a long chat, as Lamp's window opens on it; the rest is a click away in Lamp.
        let start = LogLine.recentStart(in: lines, atLeast: LogLine.recentCount)
        let shown = lines[start...].filter { $0.fromCard != true }
        let items = ChatItem.items(progressShown ? Transcript.withoutStepInProgress(shown) : shown)
        var out: [SidebarLine] = []
        for (index, item) in items.enumerated() {
            let isLast = index == items.count - 1
            let gap = Double(ChatItem.gap(after: index > 0 ? items[index - 1] : nil, before: item, isFinalAnswer: finalAnswers.contains(item.id)))
            switch item {
            case .statuses(let run):
                for (position, line) in run.enumerated() {
                    let running = isLast && busy && !progressShown && line.id == run.last?.id && line.text.hasSuffix("…")
                    out.append(SidebarLine(id: line.id, kind: .status, text: line.text, gap: position == 0 ? gap : 4, running: running))
                }
            case .tools:
                continue
            case .line(let line):
                switch line.kind {
                case .user:
                    let files = (line.attachments ?? []).map { dir.appendingPathComponent(Attachments.folder).appendingPathComponent($0) }
                    out.append(SidebarLine(id: line.id, kind: .user, text: line.text, gap: gap,
                                           attachments: files.isEmpty ? nil : files.map { SidebarAttachment(name: $0.lastPathComponent, thumbnail: thumbnail($0)) }))
                case .agent:
                    out.append(SidebarLine(id: line.id, kind: .agent, text: line.text, gap: gap, growing: busy))
                case .summary:
                    out.append(SidebarLine(id: line.id, kind: .summary, text: line.text, gap: gap))
                case .error:
                    out.append(SidebarLine(id: line.id, kind: .error, text: line.text, gap: gap))
                case .ask:
                    guard let ask = line.ask else { continue }
                    if line.id == openAsk {
                        out.append(SidebarLine(id: line.id, kind: .ask, text: ask.text, gap: gap, questions: ask.questions.map {
                            SidebarQuestion(question: $0.question, options: $0.options.map { $0.title }, symbols: $0.options.map { $0.symbol })
                        }))
                    } else if let folded = ask.folded {
                        out.append(SidebarLine(id: line.id, kind: .ask, text: folded, gap: gap))
                    }
                case .result:
                    guard let result = line.result else { continue }
                    let current = line.id == currentResult && !busy
                    out.append(SidebarLine(id: line.id, kind: .result, text: result.summary, gap: gap, untried: current ? result.untried : nil))
                default:
                    continue
                }
            }
        }
        return out
    }

    private static var thumbnails: [URL: Data] = [:]
    fileprivate static func thumbnail(_ url: URL) -> Data? {
        if let data = thumbnails[url] { return data }
        guard let image = NSImage(contentsOf: url) else { return nil }
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
        case .send(let text):
            let draft = store.draft(for: project)
            let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty || !draft.attachments.isEmpty else { return }
            store.send(words, attachments: draft.attachments, to: project)
            draftsFromSidebar[project.id] = ""
            store.updateDraft(Store.Draft(), for: project)
        case .answer(let id, let answers):
            guard let line = store.logs[project.id]?.first(where: { $0.id == id }) else { return }
            store.answer(line, with: answers, in: project)
        case .tryIt(let id):
            guard let untried = store.logs[project.id]?.first(where: { $0.id == id })?.result?.untried else { return }
            store.send(Talk.tryRequest(untried), to: project)
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
        case .removeAttachment(let index):
            var draft = store.draft(for: project)
            guard draft.attachments.indices.contains(index) else { return }
            draft.attachments.remove(at: index)
            store.updateDraft(draft, for: project)
        case .stop:
            store.stop(project)
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
            for line in SidebarWire.lines(from: &buffer) {
                guard let command = try? JSONDecoder().decode(SidebarCommand.self, from: line) else { continue }
                if case .hello(let version) = command {
                    self.version = version
                    push(force: true)
                } else {
                    server?.handle(command, from: projectID)
                }
            }
        }

        @MainActor func push(force: Bool) {
            guard !outbox.isHolding else { waiting = true; return }
            guard let server, let project = Store.shared.projects.first(where: { $0.id == projectID }) else { return }
            var state = server.state(for: project)
            // A sidebar from before the summary line can't read one, and would drop the whole chat.
            if version < 2 { state.lines.removeAll { $0.kind == .summary } }
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
