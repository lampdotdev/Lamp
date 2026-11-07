import AppKit
import CryptoKit
import Foundation

/// A Lamp project worked on by the person's own coding agent (Claude Code, Codex) in a folder of theirs, through Lamp's
/// MCP server (`OutsideServer`). The folder is a normal repository laid out as Lamp lays a wish out on GitHub
/// (`RepoImport.open`): it stays the source of truth for the code and its git is the person's. Lamp never writes in it.
///
/// What Lamp builds and runs is a project of its own in its apps folder, the workspace: made once, when the folder is
/// opened, and kept from then on, with its live copy, the libraries a change goes in as, the baselines those are
/// compiled against and the app's runtime folder (`LiveReload`, `Runtime`). Each apply captures the folder's code and
/// files, checks that what was copied is what the folder held throughout, writes into the workspace only what differs,
/// and builds and puts that in as a look does (`Store.build`, `Store.install`). So changes go into the open app as
/// Lamp's own do, with nothing of LiveReload's told about a second folder.
///
/// Every operation on a folder runs one at a time, whichever agent or connection asks (`Store.outsideSerially`), and
/// holds the project as any of Lamp's own work does (`Store.begin`), so Lamp's chat and a build of its own never run
/// beside it.
enum OutsideWork {
    struct Payload: @unchecked Sendable {
        let values: [String: Any]
        init(_ values: [String: Any]) { self.values = values }
        func string(_ key: String) -> String? { (values[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
        func bool(_ key: String) -> Bool { values[key] as? Bool ?? false }
    }

    /// What a tool answers: its words (led by the outcome, the only part some agents read closely), the app's pictures,
    /// and the same facts as data.
    struct Answer {
        var outcome: String
        var text: String
        var pictures: [[String: String]] = []
        var isError = false
        var facts: [String: Any] = [:]

        /// The facts go in the words, as one line of JSON under the outcome, and not as structured content: an agent
        /// given both may show the agent only the structured part (Claude Code does), and the words carry what matters
        /// most (a compiler's errors, what the app printed).
        var mcp: [String: Any] {
            var structured = facts
            structured["outcome"] = outcome
            let line = (try? JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
            var content: [[String: Any]] = [["type": "text", "text": "Outcome: \(outcome).\n" + line + "\n\n" + text]]
            for picture in pictures {
                content.append(["type": "image", "data": picture["data"] ?? "", "mimeType": picture["mimeType"] ?? "image/png"])
            }
            return ["content": content, "isError": isError]
        }

        static func refused(_ text: String) -> Answer { Answer(outcome: "refused", text: text, isError: true) }
    }

    static let instructions = """
    Lamp builds and runs the Mac app in a folder you work on, and puts each change you make into the open app while it \
    runs. Call open_project once with the folder's absolute path. After editing, call apply_change: it builds what the \
    folder holds now and answers how the change reached the app (live, reopened, opened, held, unchanged, not_built or \
    crashed), with pictures of its windows. look_at_app shows the open app as it is and never applies anything. Lamp \
    never writes in your folder; its git is yours.
    """

    static var tools: [[String: Any]] {
        let path: [String: Any] = ["type": "string", "description": "The folder's absolute path."]
        return [
            ["name": "open_project",
             "description": "Has Lamp take on a Lamp-format Mac app in a folder (lamp-app.json and its code at the top), build it and open it. Lamp asks the person first. Call again if Lamp says the folder moved or is missing.",
             "inputSchema": ["type": "object", "properties": ["path": path], "required": ["path"]]],
            ["name": "apply_change",
             "description": "Builds what the folder holds now and puts it into the open app. Answers the outcome: live (went into the running app, window as it was), reopened (closed and opened again for it), opened (it wasn't open), held (waits for the person's Reload), unchanged (nothing new), not_built (compiler errors follow), crashed (the app quit; its log follows), stale (the folder changed while Lamp built it: apply again), cancelled. Retrying with the same operation_id gets the first answer.",
             "inputSchema": ["type": "object", "properties": [
                "path": path,
                "operation_id": ["type": "string", "description": "Any id of yours for this apply, to retry it safely."],
                "reopen": ["type": "boolean", "description": "Close the app and open a fresh copy, for what only a launch shows."],
             ], "required": ["path"]]],
            ["name": "look_at_app",
             "description": "Pictures of the open app's windows and what it printed. Applies nothing: it says when the folder has changes not put in yet.",
             "inputSchema": ["type": "object", "properties": ["path": path], "required": ["path"]]],
        ]
    }

    // MARK: Folders taken on

    /// A folder Lamp has taken on, and the workspace that builds it. Known by its real path and, so a folder put in its
    /// place is never taken for it, by its device and inode.
    struct Adopted: Codable, Equatable {
        var repo: String
        var device: Int64
        var inode: UInt64
        var project: String
        /// What the folder held at the last apply that went in (`Capture.fingerprint`).
        var applied: String?
    }

    static var registryURL: URL { Edition.supportFolder.appendingPathComponent("Outside/adopted.json") }

    static func loadRegistry() -> [Adopted] {
        guard let data = try? Data(contentsOf: registryURL) else { return [] }
        return (try? JSONDecoder().decode([Adopted].self, from: data)) ?? []
    }

    static func saveRegistry(_ list: [Adopted]) {
        try? FileManager.default.createDirectory(at: registryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: registryURL, options: .atomic) }
    }

    /// A folder's identity now, or why it has none: it must be a real folder (a link to one is followed once, here,
    /// to its real path, and the real path is what's kept).
    static func identity(of path: String) -> (real: String, device: Int64, inode: UInt64)? {
        let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        var info = stat()
        guard lstat(real, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
        return (real, Int64(info.st_dev), UInt64(info.st_ino))
    }

    // MARK: Capturing a folder

    /// What a folder held when Lamp read it: the package the import reads (`RepoImport.open`, held to the same limits
    /// and the same manifest), and every file's hash, so what was copied is checked against what the folder held.
    struct Capture {
        let package: Sharing.Package
        let hashes: [String: String]
        var fingerprint: String {
            var hasher = SHA256()
            for (path, hash) in hashes.sorted(by: { $0.key < $1.key }) { hasher.update(data: Data((path + "\0" + hash + "\n").utf8)) }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }

    struct CaptureProblem: Error { let text: String }

    static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Every regular file the import would take, by its path in the folder, and its hash. The same folders are left out
    /// as the import leaves out (`RepoImport.copyTree`), and links are never followed.
    static func hashes(of folder: URL) -> [String: String] {
        let skipped: Set<String> = [".git", ".build", "build", ".lamp", "node_modules"]
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        var found: [String: String] = [:]
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return [:] }
        for case let item as URL in items {
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { items.skipDescendants(); continue }
            if values?.isDirectory == true, skipped.contains(item.lastPathComponent) { items.skipDescendants(); continue }
            guard values?.isRegularFile == true, item.pathExtension != "lampapp", let data = try? Data(contentsOf: item) else { continue }
            found[Sharing.relativePath(of: item, in: folder)] = sha(data)
        }
        return found
    }

    /// Reads the folder as the import does, then checks it: every file the package took must have the bytes the folder
    /// held before the copy began, and the folder must hold the same after it. A folder still being written is read
    /// again, a few times, and then refused, never built from a mix of two moments.
    static func capture(_ repo: URL) throws -> Capture {
        var last = ""
        for _ in 0..<3 {
            let before = hashes(of: repo)
            let package: Sharing.Package
            do { package = try RepoImport.open(folder: repo) } catch {
                let failure = error as? Sharing.ImportError
                throw CaptureProblem(text: (failure?.message ?? error.localizedDescription) + (failure?.detail.map { " " + $0 } ?? ""))
            }
            var differs: [String] = []
            let taken = package.sources + package.attachments + [package.folder.appendingPathComponent("APP.md")]
            for file in taken {
                guard let data = try? Data(contentsOf: file) else { continue }
                let path = Sharing.relativePath(of: file, in: package.folder)
                if before[path] != sha(data) { differs.append(path) }
            }
            let after = hashes(of: repo)
            if differs.isEmpty, before == after { return Capture(package: package, hashes: before) }
            try? FileManager.default.removeItem(at: package.folder)
            last = (differs.isEmpty ? Set(after.keys).symmetricDifference(before.keys).union(after.keys.filter { after[$0] != before[$0] }).sorted() : differs)
                .prefix(5).joined(separator: ", ")
            Thread.sleep(forTimeInterval: 0.4)
        }
        throw CaptureProblem(text: "The folder kept changing while Lamp read it (\(last)). Apply again once your edits are written.")
    }

    /// The paths that differ between two readings of a folder.
    static func changes(from old: [String: String], to new: [String: String]) -> [String] {
        Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }.sorted()
    }

    /// Puts what was captured into the workspace, writing only what differs, so a file that didn't change keeps its
    /// date and LiveReload sees only the change. Lamp's own files in the workspace are left to Lamp
    /// (`Template.writeOwnedFiles`), whatever copy of them the folder has.
    static func sync(_ capture: Capture, into project: LampProject) throws -> [String] {
        let fm = FileManager.default
        let package = capture.package
        let codeFolders = ["Sources/", Template.widgetFolder + "/", Template.watchFolder + "/", Template.shareFolder + "/"]
        let lampsOwn: Set<String> = ["LampSupport.swift", Template.sceneSupportFile, Template.widgetSupportFile, Template.shareSupportFile]
        func ownedByLamp(_ path: String) -> Bool {
            lampsOwn.contains((path as NSString).lastPathComponent) || Template.watchSupportPaths.contains(path)
        }
        var wanted: [String: URL] = [:]
        for file in package.sources {
            let path = package.path(of: file)
            guard !path.contains(".."), codeFolders.contains(where: { path.hasPrefix($0) }), !ownedByLamp(path) else { continue }
            wanted[path] = file
        }
        for file in package.attachments {
            let path = Sharing.Assets.folder + "/" + package.assetPath(of: file)
            guard !path.contains("..") else { continue }
            wanted[path] = file
        }
        let appMd = package.folder.appendingPathComponent("APP.md")
        if fm.fileExists(atPath: appMd.path) { wanted["APP.md"] = appMd }

        var changed: [String] = []
        // What's in the workspace now under the same folders, Lamp's own files aside.
        var have: [String] = []
        for folder in codeFolders + [Sharing.Assets.folder + "/"] {
            let root = project.dir.appendingPathComponent(folder)
            for case let item as URL in fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) ?? FileManager.DirectoryEnumerator() {
                guard (try? item.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                let path = Sharing.relativePath(of: item, in: project.dir)
                if !ownedByLamp(path) { have.append(path) }
            }
        }
        for path in have where wanted[path] == nil {
            try fm.removeItem(at: project.dir.appendingPathComponent(path))
            changed.append(path)
        }
        for (path, source) in wanted {
            let data = try Data(contentsOf: source)
            let target = project.dir.appendingPathComponent(path)
            if (try? Data(contentsOf: target)) == data { continue }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            changed.append(path)
        }
        return changed.sorted()
    }
}

/// What the MCP server keeps while Lamp runs: the folders taken on, each folder's queue, the answers kept for a retry
/// (for this run of Lamp only), and which folders have been looked at since Lamp started.
@MainActor final class OutsideState {
    static let shared = OutsideState()
    var adopted: [OutsideWork.Adopted] = OutsideWork.loadRegistry()
    /// Folders taken on before Lamp last started: an apply waits for a look first, since whatever was under way when
    /// Lamp ended is unknown to the agent.
    var fromBefore: Set<String>
    var tails: [String: Task<Void, Never>] = [:]
    var answers: [String: OutsideWork.Answer] = [:]
    var ended: Set<Int> = []

    init() { fromBefore = Set(adopted.map(\.repo)) }

    func save() { OutsideWork.saveRegistry(adopted) }
}

extension Store {
    func outsideConnectionEnded(_ connection: Int) { OutsideState.shared.ended.insert(connection) }

    /// One operation at a time for each key (a folder's real path), in the order asked, across every connection.
    func outsideSerially(_ key: String, _ work: () async -> OutsideWork.Answer) async -> OutsideWork.Answer {
        let state = OutsideState.shared
        let previous = state.tails[key]
        let (ended, end) = AsyncStream<Void>.makeStream()
        let mine = Task { for await _ in ended {} }
        state.tails[key] = mine
        defer {
            end.finish()
            if state.tails[key] == mine { state.tails[key] = nil }
        }
        await previous?.value
        return await work()
    }

    func outsideCall(_ name: String, _ payload: OutsideWork.Payload, connection: Int) async -> OutsideWork.Answer {
        guard let path = payload.string("path"), path.hasPrefix("/") else { return .refused("Give the folder's absolute path as `path`.") }
        let key = OutsideWork.identity(of: path)?.real ?? path
        return await outsideSerially(key) {
            // Asked by a connection that has ended while it waited its turn: nobody is there for the answer.
            if OutsideState.shared.ended.contains(connection) { return .refused("The connection ended before this began.") }
            if Task.isCancelled { return OutsideWork.Answer(outcome: "cancelled", text: "Cancelled before it began; nothing changed.") }
            switch name {
            case "open_project": return await outsideOpen(path)
            case "apply_change":
                let id = payload.string("operation_id").map { key + "\n" + $0 }
                if let id, var kept = OutsideState.shared.answers[id] {
                    kept.text = "This operation_id was applied already; this is its first answer, and nothing ran again.\n\n" + kept.text
                    return kept
                }
                let answer = await outsideApply(path, reopen: payload.bool("reopen"))
                // Only an apply that ran is kept for a retry: one refused or cancelled before it began changed nothing,
                // so the same id tried again (after the look a refusal asked for) runs.
                if let id, !["refused", "cancelled"].contains(answer.outcome) { OutsideState.shared.answers[id] = answer }
                return answer
            case "look_at_app": return await outsideLook(path)
            default: return .refused("Lamp has no tool \(name).")
            }
        }
    }

    /// The folder a call names, as taken on, and its workspace; or why it can't be used.
    private func outsideFolder(_ path: String) -> (OutsideWork.Adopted, LampProject)? {
        guard let now = OutsideWork.identity(of: path),
              let entry = OutsideState.shared.adopted.first(where: { $0.repo == now.real }),
              entry.device == now.device, entry.inode == now.inode,
              let project = projects.first(where: { $0.id == entry.project }) else { return nil }
        return (entry, project)
    }

    private func outsideRefusal(_ path: String) -> OutsideWork.Answer {
        guard let now = OutsideWork.identity(of: path) else {
            return .refused("There's no folder at \(path) now. If it moved, call open_project with where it is.")
        }
        guard let entry = OutsideState.shared.adopted.first(where: { $0.repo == now.real }) else {
            return .refused("Lamp hasn't taken on \(now.real). Call open_project first.")
        }
        if entry.device != now.device || entry.inode != now.inode {
            return .refused("The folder at \(now.real) isn't the one Lamp took on: another was put in its place. Call open_project to take this one on.")
        }
        return .refused("Lamp's copy of this app is gone. Call open_project again.")
    }

    // MARK: open_project

    private func outsideOpen(_ path: String) async -> OutsideWork.Answer {
        guard let now = OutsideWork.identity(of: path) else { return .refused("There's no folder at \(path).") }
        let state = OutsideState.shared
        let repo = URL(fileURLWithPath: now.real)
        // Taken on already, here or (moved) elsewhere: the same workspace goes on.
        if let index = state.adopted.firstIndex(where: { ($0.repo == now.real || ($0.device == now.device && $0.inode == now.inode)) }),
           projects.contains(where: { $0.id == state.adopted[index].project }),
           state.adopted[index].device == now.device, state.adopted[index].inode == now.inode {
            let moved = state.adopted[index].repo != now.real
            state.fromBefore.remove(state.adopted[index].repo)
            state.adopted[index].repo = now.real
            state.save()
            var answer = await outsideApply(now.real, reopen: false)
            if moved { answer.text = "Lamp had this folder at another path; it's known here now.\n\n" + answer.text }
            return answer
        }
        // A folder put where one Lamp knew was: that one is let go (its workspace stays on the desk), and this one is new.
        state.adopted.removeAll { $0.repo == now.real }
        guard FileManager.default.fileExists(atPath: repo.appendingPathComponent("lamp-app.json").path) else {
            return .refused("\(now.real) isn't a Lamp-format project: it needs lamp-app.json and its code at the top, as Lamp puts a wish on GitHub.")
        }
        let capture: OutsideWork.Capture
        do { capture = try await Self.offMain { Result { try OutsideWork.capture(repo) } }.get() } catch {
            return .refused((error as? OutsideWork.CaptureProblem)?.text ?? error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: capture.package.folder) }
        let package = capture.package
        guard package.platform == .mac, package.parts.isEmpty else {
            return .refused("For now Lamp takes on only a Mac app on its own; this is \(package.platform.target.identity.name)\(package.parts.isEmpty ? "" : " with other apps").")
        }
        // The person agrees before code from a folder is built and run, as they do for any app that comes to Lamp.
        let alert = NSAlert()
        alert.messageText = "Build “\(package.name)” from a folder?"
        alert.informativeText = "Your coding agent asked \(Edition.name) to build and open the app in \(now.real). \(Edition.name) won't change anything in that folder."
        alert.addButton(withTitle: "Build It")
        alert.addButton(withTitle: "Don't Build")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return .refused("The person chose not to build it.") }
        let project: LampProject
        do {
            project = try Template.scaffold(name: uniqueName(package.name), platform: package.platform, family: package.family, in: root)
            try Sharing.install(package, into: project)
            if let identity = package.identity, !projects.contains(where: { Sharing.identity(of: $0, create: false) == identity }) {
                Sharing.setIdentity(identity, of: project)
            }
        } catch {
            return .refused("Lamp couldn't set up its copy: \(error.localizedDescription)")
        }
        reload()
        _ = await initRepo(project, message: "Taken on from \(now.real)")
        state.adopted.append(OutsideWork.Adopted(repo: now.real, device: now.device, inode: now.inode, project: project.id, applied: nil))
        state.save()
        var answer = await outsideApply(now.real, reopen: false)
        answer.text = "Lamp took on \(now.real) as “\(project.name)”.\n\n" + answer.text
        return answer
    }

    // MARK: apply_change

    private func outsideApply(_ path: String, reopen: Bool) async -> OutsideWork.Answer {
        guard let found = outsideFolder(path) else { return outsideRefusal(path) }
        var entry = found.0
        let project = found.1
        let state = OutsideState.shared
        if state.fromBefore.contains(entry.repo) {
            return .refused("Lamp started again since this folder was last applied, and what was under way then didn't finish for you. Call look_at_app to see the app as it is, then apply again.")
        }
        guard let hold = begin(project) else {
            return .refused("Lamp is busy with this app (its own chat or a build). Try again in a moment.")
        }
        defer { finish(current(project) ?? project) }
        let repo = URL(fileURLWithPath: entry.repo)
        let began = Date()

        return await withTaskCancellationHandler {
            let capture: OutsideWork.Capture
            do { capture = try await Self.offMain { Result { try OutsideWork.capture(repo) } }.get() } catch {
                return .refused((error as? OutsideWork.CaptureProblem)?.text ?? error.localizedDescription)
            }
            defer { try? FileManager.default.removeItem(at: capture.package.folder) }
            let written: [String]
            do { written = try OutsideWork.sync(capture, into: project) } catch {
                return .refused("Lamp couldn't copy the folder's files into its build: \(error.localizedDescription)")
            }
            if Task.isCancelled { return OutsideWork.Answer(outcome: "cancelled", text: "Cancelled before building. Lamp's copy has the folder's files; the app is as it was.") }

            let wasOpen = isRunning(project)
            let changed = Runtime.sourcesChanged(project)
            var answer: OutsideWork.Answer
            if !changed, wasOpen, !reopen {
                answer = OutsideWork.Answer(outcome: "unchanged", text: "Nothing changed since the app was built; it's open as it was.")
            } else if changed, let errors = await build(project, inPlace: !reopen) {
                answer = Task.isCancelled || hold.stopped
                    ? OutsideWork.Answer(outcome: "cancelled", text: "Cancelled during the build; the app is as it was.")
                    : OutsideWork.Answer(outcome: "not_built", text: "The app doesn't build. Fix these compiler errors and apply again:\n\n\(errors)", isError: true)
            } else {
                let crash = await install(project, inFront: false, fresh: reopen, reload: reopen, early: true)
                let outcome: String
                switch hold.outcomes.last {
                case .live?: outcome = "live"
                case .held?: outcome = "held"
                case .reopened?: outcome = "reopened"
                case .opened?: outcome = "opened"
                case nil: outcome = isRunning(project) ? (wasOpen ? "reopened" : "opened") : "not_opened"
                }
                // A change that went in can still bring the app down a moment later.
                if crash == nil, isRunning(project) { try? await Task.sleep(for: .milliseconds(1500)) }
                if let crash {
                    answer = OutsideWork.Answer(outcome: "crashed", text: "The app quit.\n\n\(crash)", isError: true)
                } else if !isRunning(project), outcome != "held" {
                    answer = OutsideWork.Answer(outcome: "crashed", text: "The app isn't running after the change: it quit as it went in or right after it opened.", isError: true)
                } else {
                    let words = [
                        "live": "The change went into the open app without reopening it; the window is as the person left it.",
                        "reopened": "The app couldn't take this change as it ran, so it was closed and opened again with it.",
                        "opened": "The app wasn't open, so it was opened with the change.",
                        "held": "The person kept the app open; the change waits for them to press Reload.",
                    ]
                    answer = OutsideWork.Answer(outcome: outcome, text: words[outcome] ?? "The app is built.")
                    if outcome == "live" {
                        try? await Task.sleep(for: .milliseconds(300))
                        Runtime.requestScreenshots(of: project)
                    }
                    answer.pictures = Self.pictureData(Self.agentPictures(await Runtime.screenshots(of: project, since: began), in: project), in: project)
                }
            }
            if Privacy.sharesLog, let tail = Runtime.logTail(project) { answer.text += "\n\nWhat it printed:\n\(tail)" }
            // Built from what the folder held at the capture: an edit made since isn't in it, and is said.
            let now = await Self.offMain { OutsideWork.hashes(of: repo) }
            let since = OutsideWork.changes(from: capture.hashes, to: now)
            answer.facts["stale"] = !since.isEmpty
            answer.facts["written"] = written
            if !since.isEmpty {
                answer.text = "Stale: the folder changed while Lamp built it (\(since.prefix(5).joined(separator: ", "))). What's in the app is the folder as it was before; apply again.\n\n" + answer.text
            }
            if ["live", "reopened", "opened", "held", "unchanged"].contains(answer.outcome) {
                entry.applied = capture.fingerprint
                if let index = state.adopted.firstIndex(where: { $0.repo == entry.repo }) { state.adopted[index] = entry; state.save() }
            }
            log(project, .detail, "Your coding agent applied a change: \(answer.outcome).")
            return answer
        } onCancel: {
            Task { @MainActor in _ = hold.cancel() }
        }
    }

    // MARK: look_at_app

    private func outsideLook(_ path: String) async -> OutsideWork.Answer {
        guard let (entry, project) = outsideFolder(path) else { return outsideRefusal(path) }
        OutsideState.shared.fromBefore.remove(entry.repo)
        let repo = URL(fileURLWithPath: entry.repo)
        let now = await Self.offMain { OutsideWork.hashes(of: repo) }
        var fingerprint: String {
            var hasher = SHA256()
            for (path, hash) in now.sorted(by: { $0.key < $1.key }) { hasher.update(data: Data((path + "\0" + hash + "\n").utf8)) }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        let pending = entry.applied != fingerprint
        guard isRunning(project) else {
            return OutsideWork.Answer(outcome: "not_open", text: "The app isn't open. apply_change opens it." + (pending ? " The folder has changes not put in yet." : ""),
                                      facts: ["pending": pending])
        }
        let asked = Date()
        Runtime.requestScreenshots(of: project)
        var answer = OutsideWork.Answer(outcome: "open", text: (pending ? "The folder has changes not put in yet; apply_change puts them in. " : "The app runs what the folder holds. ")
                                        + "Pictures of its windows follow, frontmost first.", facts: ["pending": pending])
        answer.pictures = Self.pictureData(Self.agentPictures(await Runtime.screenshots(of: project, since: asked, waiting: 3), in: project), in: project)
        if Privacy.sharesLog, let tail = Runtime.logTail(project) { answer.text += "\n\nWhat it printed:\n\(tail)" }
        return answer
    }
}
