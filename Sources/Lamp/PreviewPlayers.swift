import AppKit
import CryptoKit
import LampRelayKit
import Network

/// The TV preview of an app that phones play as controllers, as an app of its own (LampPreview.swift in Lamp's player):
/// a copy of the player made for that one app, which runs the app's page at the TV's size and its phones' page and
/// relay itself, so a game in the preview goes on playing, and new phones join it, with Lamp closed. Opened as any app
/// is, so it outlives Lamp; closed with its window, or by Stop. Every other preview stays a window of Lamp's own
/// (`TVPreview`), which asks Lamp for its phones.
///
/// Lamp keeps each one's folder (Previews/<app>): the copy (Preview.app, made again when the player, the app's phone
/// page or what it's told about itself changes), the versions of the app's page it was handed (Pages/<version>), which
/// one to open (`current`), and what the copy wrote for Lamp to reach it (control.json). While both are open, Lamp looks
/// at it and uses it for the agent through that channel; a Lamp that opens again finds the preview still open there,
/// rather than opening a second one.
@MainActor
enum PreviewPlayers {
    /// Previews that take players, but not an app of a wish of several: its apps reach each other through Lamp
    /// (`WishRooms`), which only Lamp's own preview answers for.
    static func takes(_ project: LampProject) -> Bool {
        GameKit.playerURL != nil && Store.takesPlayers(project) && TVs.hasPhonePage(project)
            && project.partFolders.isEmpty && !project.isPart
    }

    static func folder(for id: String) -> URL { Edition.supportFolder.appendingPathComponent("Previews").appendingPathComponent(id) }
    static func folder(for project: LampProject) -> URL { folder(for: project.id) }
    static func bundle(for project: LampProject) -> URL { folder(for: project).appendingPathComponent("Preview.app") }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Open or not

    /// What control.json says: where the open copy listens, with the key for this opening.
    struct Control: Equatable {
        let port: UInt16
        let key: String
        let pid: pid_t
        let run: String
    }

    /// The copy open now for `id`, read from its folder: only while its process is alive and is that folder's copy, so a
    /// file left by one that crashed, or a process that has since taken its number, is never taken for it.
    static func control(for id: String) -> Control? {
        let folder = folder(for: id)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("control.json")),
              let said = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = (said["port"] as? Int).flatMap(UInt16.init(exactly:)), let key = said["key"] as? String,
              let pid = (said["pid"] as? Int).map(pid_t.init), let run = said["run"] as? String,
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.bundleURL?.standardizedFileURL.path == folder.appendingPathComponent("Preview.app").standardizedFileURL.path else { return nil }
        return Control(port: port, key: key, pid: pid, run: run)
    }

    static func isOpen(_ project: LampProject) -> Bool { control(for: project.id).map { closing[project.id] != $0.pid } ?? false }

    /// A preview's bundle id, by the store its page keeps its saves in, which outlasts renames: beside this Lamp's apps'
    /// ("dev.lamp.preview.…" for "dev.lamp.app.…"), never among them, so it's never taken for one of the apps.
    static func bundleID(_ store: UUID) -> String {
        String(Edition.appBundlePrefix.dropLast("app.".count)) + "preview." + store.uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }

    /// Every app with its preview open as an app of its own now, whether this Lamp opened it or an earlier one did.
    static var openIDs: [String] {
        watchClosing()
        let root = Edition.supportFolder.appendingPathComponent("Previews")
        return ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter { control(for: $0) != nil }
    }

    /// The process of an open copy, by any app's id.
    static func process(for project: LampProject) -> NSRunningApplication? {
        control(for: project.id).flatMap { NSRunningApplication(processIdentifier: $0.pid) }
    }

    // MARK: Opening

    /// The size each open preview's page is laid out at, as last told: a TV's until a screen is looked at in another.
    private static var shapes: [String: CGSize] = [:]
    static func shape(of project: LampProject) -> CGSize { shapes[project.id] ?? CGSize(width: 1920, height: 1080) }

    /// The shape an open preview says it has: one an earlier Lamp reshaped is found as it is.
    static func learnShape(_ project: LampProject) async {
        guard shapes[project.id] == nil, let open = control(for: project.id), let answer = try? await ask(open, ["op": "hello"]),
              let sides = answer["shape"] as? [NSNumber], sides.count == 2 else { return }
        shapes[project.id] = CGSize(width: sides[0].doubleValue, height: sides[1].doubleValue)
    }

    /// Opens the staged app (again, from its start) in its preview, which is opened if it isn't: nil once it has loaded.
    static func show(_ project: LampProject, staged: URL, inFront: Bool, title: String, isTV: Bool) async -> String? {
        do {
            let folder = folder(for: project)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let version = try keep(staged, in: folder)
            Runtime.startLog(project)
            readLog(project, from: nil)
            // One being closed (Stop just now) is let go entirely first, rather than handed the app as it closes.
            if let closing = closing[project.id] { await waitGone(closing); self.closing[project.id] = nil }
            try await makeCopy(of: project, title: title, isTV: isTV) {
                // A new copy for an open preview (the phone page changed, or Lamp's player): the old one goes first,
                // so it never serves the new copy's files to its own phones.
                guard let open = control(for: project.id) else { return }
                _ = try? await ask(open, ["op": "close"])
                await waitGone(open.pid)
            }
            try Data(version.utf8).write(to: folder.appendingPathComponent("current"))
            if let open = control(for: project.id) {
                _ = try await ask(open, ["op": "title", "title": title])
                let answer = try await ask(open, ["op": "load", "version": version, "front": inFront])
                if let problem = answer["error"] as? String { return problem }
                return nil
            }
            try await carrySaved(of: project)
            shapes[project.id] = nil
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = inFront
            configuration.addsToRecentItems = false
            _ = try await NSWorkspace.shared.openApplication(at: bundle(for: project), configuration: configuration)
            // Open once it says where Lamp reaches it, which it does once the page has loaded.
            let clock = ContinuousClock(), start = clock.now
            while control(for: project.id) == nil, clock.now - start < .seconds(20) { try? await Task.sleep(for: .milliseconds(200)) }
            guard control(for: project.id) != nil else { return "The TV preview didn't open." }
            watchClosing()
            try? await Task.sleep(for: .milliseconds(600))
            return nil
        } catch {
            return "The TV preview didn't open: \(error.localizedDescription)"
        }
    }

    /// Keeps the staged copy as a version of its own in the preview's folder, named by its contents (the same files are
    /// the same version), never changed after: what an open preview serves can't change under it. The two newest stay.
    private static func keep(_ staged: URL, in folder: URL) throws -> String {
        let fm = FileManager.default
        var hash = SHA256()
        let root = staged.standardizedFileURL.path
        let walk = fm.enumerator(at: staged, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])?.compactMap { $0 as? URL } ?? []
        for file in walk.sorted(by: { $0.path < $1.path }) {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { throw Failure(message: "The app's files hold a shortcut to another file.") }
            guard values.isRegularFile == true else { continue }
            hash.update(data: Data(String(file.standardizedFileURL.path.dropFirst(root.count)).utf8))
            hash.update(data: Data([0]))
            hash.update(data: try Data(contentsOf: file, options: .alwaysMapped))
        }
        let version = String(Data(hash.finalize()).map { String(format: "%02x", $0) }.joined().prefix(32))
        let pages = folder.appendingPathComponent("Pages")
        try fm.createDirectory(at: pages, withIntermediateDirectories: true)
        let target = pages.appendingPathComponent(version)
        if !fm.fileExists(atPath: target.path) {
            let partial = pages.appendingPathComponent(".partial-" + UUID().uuidString)
            try fm.copyItem(at: staged, to: partial)
            try fm.moveItem(at: partial, to: target)
        }
        // Touched, so the newest are the ones kept.
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
        let kept = ((try? fm.contentsOfDirectory(at: pages, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for old in kept.dropFirst(2) { try? fm.removeItem(at: old) }
        return version
    }

    /// Makes the preview's copy of Lamp's player when it has none, or when what it's made of changed: the player, the
    /// app's phone page, what it's told about itself. True when a new copy was made.
    private static func makeCopy(of project: LampProject, title: String, isTV: Bool, replacing: () async -> Void) async throws {
        guard let player = GameKit.playerURL else { throw Failure(message: "This copy of Lamp is missing its player.") }
        guard let store = TVPreview.store(for: project.instance) else { throw Failure(message: "The app has no store for what it saves yet.") }
        let fm = FileManager.default
        let folder = folder(for: project), target = bundle(for: project)
        let phone = try GamePhones.snapshot(of: project)
        let install = Template.installValues(for: project)
        let info: [String: Any] = [
            "CFBundleExecutable": GameKit.playerExe,
            "CFBundleIdentifier": bundleID(store),
            "CFBundleName": title, "CFBundleDisplayName": title,
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0",
            "LSMinimumSystemVersion": "14.0", "NSPrincipalClass": "NSApplication", "NSHighResolutionCapable": true,
            "LampPlayer": ["kind": "preview", "scheme": "lamp-tv", "canvas": "1920x1080", "store": store.uuidString, "tv": isTV, "title": title],
            "LampInstall": install,
            "LampPlayerVersion": GameKit.playerVersion ?? "",
        ]
        let stamp = [GameKit.playerVersion ?? "", phone.digest, (try? JSONSerialization.data(withJSONObject: install, options: .sortedKeys))
            .map { Data(SHA256.hash(data: $0)).base64EncodedString() } ?? "", isTV ? "tv" : "device"].joined(separator: "\n")
        let stampFile = folder.appendingPathComponent("copy.stamp")
        if fm.fileExists(atPath: target.appendingPathComponent("Contents/MacOS/\(GameKit.playerExe)").path),
           (try? String(contentsOf: stampFile, encoding: .utf8)) == stamp { return }
        let partial = folder.appendingPathComponent(".partial-" + UUID().uuidString + ".app")
        defer { try? fm.removeItem(at: partial) }
        try fm.copyItem(at: player, to: partial)
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: partial.appendingPathComponent("Contents/Info.plist"))
        let resources = partial.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try phone.write(to: resources.appendingPathComponent("Phone"))
        // Signed as a whole, ad hoc, as a copy of the player for a game is before Lamp signs it: nothing outside
        // the copy is trusted by it.
        let signed = await Subprocess.run("/usr/bin/codesign", ["--force", "--sign", "-", partial.path], mergeErrors: true, timeout: 60)
        guard signed.ok else { throw Failure(message: "The preview couldn't be signed: \(signed.output)") }
        await replacing()
        try? fm.removeItem(at: target)
        try fm.moveItem(at: partial, to: target)
        try stamp.write(to: stampFile, atomically: true, encoding: .utf8)
    }

    /// What the app's page saved while its preview was a window of Lamp's own (`TVPreview`, in Lamp's store for it),
    /// written once, before the first opening of its own preview, for that to take in (carry.json, versioned, kept as
    /// the copy it was). Done is the preview's to say (carry.done), once it has read the values back from its own store.
    /// Lamp's store is left as it was.
    private static func carrySaved(of project: LampProject) async throws {
        let folder = folder(for: project)
        let file = folder.appendingPathComponent("carry.json")
        guard !FileManager.default.fileExists(atPath: file.path), !FileManager.default.fileExists(atPath: folder.appendingPathComponent("carry.done").path),
              let saved = await TVPreview.savedInLamp(project), !saved.isEmpty else { return }
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "saved": saved, "from": "Lamp's TV preview"], options: .sortedKeys)
        guard FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw Failure(message: "What the app saved couldn't be kept for its preview.")
        }
    }

    private static func waitGone(_ pid: pid_t) async {
        let clock = ContinuousClock(), start = clock.now
        while NSRunningApplication(processIdentifier: pid).map({ !$0.isTerminated }) == true, clock.now - start < .seconds(5) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated { app.forceTerminate() }
    }

    /// Lamp's lists of what's open hear of a preview closing, by its window or by Stop.
    private static var watching = false
    static func watchClosing() {
        guard !watching else { return }
        watching = true
        let root = Edition.supportFolder.appendingPathComponent("Previews").standardizedFileURL.path + "/"
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleURL?.standardizedFileURL.path.hasPrefix(root) == true else { return }
            MainActor.assumeIsolated {
                Store.shared.refreshOpenApps()
            }
        }
    }

    // MARK: Using it

    /// Previews asked to close, by app, until they're gone: never taken for open meanwhile.
    private static var closing: [String: pid_t] = [:]

    static func close(_ project: LampProject) {
        guard let open = control(for: project.id) else { return }
        closing[project.id] = open.pid
        Task { _ = try? await ask(open, ["op": "close"]) }
    }

    /// Closes it and forgets everything of it: its folder, and what WebKit kept for it (its saves, its caches).
    static func forget(_ project: LampProject) {
        let folder = folder(for: project)
        if let open = control(for: project.id), let app = NSRunningApplication(processIdentifier: open.pid) { app.forceTerminate() }
        try? FileManager.default.removeItem(at: folder)
        if let store = TVPreview.store(for: project.instance) {
            let id = bundleID(store)
            let home = FileManager.default.homeDirectoryForCurrentUser
            for place in ["Library/WebKit", "Library/Caches", "Library/HTTPStorages"] {
                try? FileManager.default.removeItem(at: home.appendingPathComponent(place).appendingPathComponent(id))
            }
        }
    }

    static func title(_ project: LampProject, _ title: String) {
        guard let open = control(for: project.id) else { return }
        Task { _ = try? await ask(open, ["op": "title", "title": title]) }
    }

    static func bringForward(_ project: LampProject) {
        guard let open = control(for: project.id) else { return }
        Task { _ = try? await ask(open, ["op": "front"]) }
        NSRunningApplication(processIdentifier: open.pid)?.activate()
    }

    static func reshape(_ project: LampProject, to size: CGSize) async {
        guard let open = control(for: project.id), size.width >= 200, size.height >= 200 else { return }
        if let answer = try? await ask(open, ["op": "shape", "width": size.width, "height": size.height]),
           let sides = answer["shape"] as? [NSNumber], sides.count == 2 {
            shapes[project.id] = CGSize(width: sides[0].doubleValue, height: sides[1].doubleValue)
        }
    }

    /// The preview's window, by the system's number for it: where the glow and the pill go while the agent uses it.
    static func windowID(_ project: LampProject) async -> CGWindowID? {
        guard let open = control(for: project.id), let answer = try? await ask(open, ["op": "hello"]),
              let number = answer["window"] as? Int, number > 0 else { return nil }
        return CGWindowID(number)
    }

    static func picture(_ project: LampProject, width: CGFloat) async -> (png: Data, moving: Bool)? {
        guard let open = control(for: project.id), let answer = try? await ask(open, ["op": "picture", "width": width]),
              let png = (answer["png"] as? String).flatMap({ Data(base64Encoded: $0) }) else { return nil }
        readLog(project, from: open)
        return (png, answer["moving"] as? Bool ?? false)
    }

    /// Runs script in the app's page, as the in-Lamp preview does: what reads the screen and presses the remote's keys.
    static func script(_ project: LampProject, _ source: String) async -> String? {
        guard let open = control(for: project.id), let answer = try? await ask(open, ["op": "script", "source": source]) else { return nil }
        readLog(project, from: open)
        return answer["value"] as? String
    }

    // MARK: The log

    /// How far into each preview's console.log Lamp has read, by its run.
    private static var logRead: [String: (run: String, offset: UInt64)] = [:]

    /// What the preview printed since Lamp last read it, added to the app's log, where the agent reads it. Nil `open`
    /// starts afresh: the preview is opened again, and its log with it.
    static func readLog(_ project: LampProject, from open: Control?) {
        let file = folder(for: project).appendingPathComponent("console.log")
        guard let open else {
            // Emptied in place: an open preview goes on writing to the same file.
            logRead[project.id] = nil
            truncate(file.path, 0)
            return
        }
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        var offset = logRead[project.id].flatMap { $0.run == open.run ? $0.offset : nil } ?? 0
        if offset > size { offset = 0 }
        try? handle.seek(toOffset: offset)
        let data = (try? handle.read(upToCount: 256 << 10)) ?? Data()
        logRead[project.id] = (open.run, offset + UInt64(data.count))
        guard !data.isEmpty, let log = try? AppFolder.appendHandle(Runtime.logURL(project), in: project.dir) else { return }
        log.write(data)
        try? log.close()
    }

    // MARK: The channel

    /// One request and its answer, on a connection of its own to the open copy, with this opening's key.
    static func ask(_ open: Control, _ request: [String: Any]) async throws -> [String: Any] {
        var body = request
        body["key"] = open.key
        var written = try JSONSerialization.data(withJSONObject: body)
        written.append(0x0A)
        let line = written
        let connection = NWConnection(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: open.port)!, using: .tcp)
        let answer = Answer()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
                answer.continuation = continuation
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.send(content: line, completion: .contentProcessed { _ in })
                        receive(connection, answer: answer, buffer: Data())
                    case .failed(let error), .waiting(let error):
                        answer.finish(.failure(error))
                        connection.cancel()
                    default: break
                    }
                }
                connection.start(queue: .global())
                DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                    answer.finish(.failure(Failure(message: "The preview didn't answer.")))
                    connection.cancel()
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    private nonisolated static func receive(_ connection: NWConnection, answer: Answer, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, done, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.firstIndex(of: 0x0A) {
                let said = (try? JSONSerialization.jsonObject(with: buffer[..<end])) as? [String: Any]
                answer.finish(said.map { .success($0) } ?? .failure(Failure(message: "The preview's answer was damaged.")))
                connection.cancel()
            } else if done || error != nil || buffer.count > 64 << 20 {
                answer.finish(.failure(Failure(message: "The preview closed before answering.")))
                connection.cancel()
            } else {
                receive(connection, answer: answer, buffer: buffer)
            }
        }
    }

    /// An answer given once, whichever comes first: the preview's, its connection failing, or the wait running out.
    private final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        var continuation: CheckedContinuation<[String: Any], Error>?
        func finish(_ result: Result<[String: Any], Error>) {
            lock.lock()
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(with: result)
        }
    }
}
