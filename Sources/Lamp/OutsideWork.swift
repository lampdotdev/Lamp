import AppKit
import CryptoKit
import Foundation

/// A Lamp project worked on by the person's own coding agent (Claude Code, Codex) in a folder of theirs, through Lamp's
/// MCP server (`OutsideServer`). The folder is a normal repository laid out as Lamp lays a wish out on GitHub
/// (`RepoImport.open`): it stays the source of truth for the code and its git is the person's. Lamp writes in it only
/// what it takes to read it as a Lamp app, once, after the person's Build & Open (`Conversion`: a site's manifest), and
/// makes a copy instead when that would be disruptive.
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
    Lamp builds and runs the app in a folder you work on, on this Mac, puts each change you make into the open app \
    while it runs, and shares what you made. Call open_project once with the folder's absolute path: the person reviews \
    the app in Lamp first, and the answer says how Lamp reads the folder and lists Lamp's skills for this kind of app. \
    Read the ones that fit with read_skill before changing what they cover; they say which of Lamp's building blocks to \
    use and how. Lamp's own files (Sources/LampSupport.swift, build.sh, Package.swift, lamp.js) are rewritten at every \
    build: read them, never edit them. After \
    editing, call apply_change: it builds what the folder holds now and answers how the change reached the app, with \
    pictures of its windows. look_at_app shows the open app as it is and never applies anything; you can't click or \
    type in the app, so ask the person to try what needs a hand. export_app makes the app's shared file and \
    publish_link opens Lamp's Share Link card for the person; both share only what's built from the folder as it is. \
    Lamp writes in your folder only what it needs to read it as an app (a site gets Lamp's manifest), once, and says \
    so; its git is yours. When that would be disruptive, Lamp works in a copy instead and the answer says where: pass \
    on to the person exactly what it says to do.
    """

    static var tools: [[String: Any]] {
        let path: [String: Any] = ["type": "string", "description": "The folder's absolute path."]
        return [
            ["name": "open_project",
             "description": "Has Lamp take on the app in a folder, build it and open it on this Mac. Lamp reads the folder as it reads anything brought to it: an app in Lamp's format (lamp-app.json and its code at the top), or a plain site (index.html at the top, no build step), which it runs as a web app. The folder stays where edits are made: once the person approves, Lamp adds only what it needs to read it (a site gets Lamp's manifest), or, when that would replace or reorganize the folder's own files, works in a copy and answers its path and what the person must do to work there. Lamp shows the person its review of the code first, and builds it only if they choose Build & Open. A folder Lamp can't read as an app is answered not_importable, with what it lacks. Call again if Lamp says the folder moved or is missing.",
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
            ["name": "export_app",
             "description": "Makes the app's shared file (.lampapp), which anyone with Lamp can open: its code and files, never its data or anything of yours. Only once the app is built from the folder as it is (apply first). Lamp checks the credits, licenses and secrets first, and asks the person when something in it came with no license. Answers the file's path, in Lamp's own folder: copy it where it's wanted.",
             "inputSchema": ["type": "object", "properties": ["path": path], "required": ["path"]]],
            ["name": "publish_link",
             "description": "Opens Lamp's Share Link card for the app, where the person shares it on lamp.dev, or releases what's new on a link it has, and waits for them. Only once the app is built from the folder as it is (apply first); nothing is applied until the card is done. Answers the link, or that the person closed the card, or what failed: a link can exist while its app file didn't finish going up, and the answer says so. Changing or taking a link down stays on the card.",
             "inputSchema": ["type": "object", "properties": ["path": path], "required": ["path"]]],
        ] + Store.mcpTools.filter { $0["name"] as? String == "read_skill" }
    }

    /// What open_project tells the agent about working on this kind of app: the skills Lamp offers it (the same index
    /// and words as Lamp's own engines get, `Skills.index`), those its code already shows it uses, and whose files
    /// are Lamp's. The skills are the one place that says which building blocks to use and how.
    /// A site (`RepoImport.Layout.site`) is laid out as the folder has it: the skills' Web/ is the folder's top.
    @MainActor static func guidance(for project: LampProject, layout: RepoImport.Layout) -> String {
        let named = Skills.named(project.platform)
        var text: String
        if case .site(let laidOut) = layout {
            text = "Working on it: Lamp runs this site as a web app, its page shown in an app of Lamp's. Edit the site's files where they are in the folder: what Lamp's skills call Web/ is this folder's top\(laidOut ? ", and the rest of the app is in \(StaticSite.folder)/" : ""). Lamp writes its own files around the page at every build, so lamp.js, Sources/LampSupport.swift, build.sh and Package.swift are never taken from the folder.\n"
        } else {
            text = "Working on it: Sources/LampSupport.swift, build.sh and Package.swift are Lamp's and rewritten at every build, so edits to them never go in; read LampSupport.swift for what Lamp gives the app.\n"
        }
        if !named.isEmpty { text += "Read these with read_skill before changing the app, and keep to them: \(named.joined(separator: ", ")).\n" }
        let applying = Skills.applying(to: project)
        if !applying.isEmpty { text += "Its code already uses: " + applying.map { "\($0.name) (\($0.because))" }.joined(separator: "; ") + ".\n" }
        return text + Skills.index(offeredOutside(project.platform))
    }

    /// The kind's skills an agent outside Lamp can use: those whose description names one of Lamp's tools it doesn't
    /// have are left out, since they're about that tool (`make_app_for`, `make_art`, `device_integration`, `lampify`, the
    /// `assets` index). A tool is taken as named when it's written as code, or as a whole word that isn't an ordinary
    /// one (it has an underscore, or the spell checker doesn't know it: "lampify"), so a skill that only uses the word
    /// ("progress", "plan") stays. The skills themselves, and what Lamp's own engines are offered, don't change.
    @MainActor static func offeredOutside(_ platform: Platform) -> [String] {
        let own = Set(tools.compactMap { $0["name"] as? String })
        let missing = Store.mcpTools.compactMap { $0["name"] as? String }.filter { !own.contains($0) }
        return Skills.offered(platform).filter { name in
            guard let description = Skills.all[name]?.description else { return false }
            return !missing.contains { tool in
                if description.contains("`\(tool)`") { return true }
                guard description.range(of: "\\b\(tool)\\b", options: .regularExpression) != nil else { return false }
                return tool.contains("_") || NSSpellChecker.shared.checkSpelling(of: tool, startingAt: 0).location != NSNotFound
            }
        }
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
        /// The workspace holds files the open app may not run yet: written by an apply that hadn't put them in when it
        /// ended (cancelled once built, or Lamp quitting midway). Kept on disk, so the next apply puts them in even
        /// after Lamp starts again, though nothing is left to build. Nil in records from before it was kept.
        var owed: Bool?
        /// The folder's own metadata as last put in (`metadataDigest`): an apply puts it in again only when the folder's
        /// changed. Lamp works on the icon of its copy by itself (designing one, painting its artwork), and writing the
        /// folder's over that at every apply changed the icon each time, which reopens the app for every change.
        var metadata: String?
        /// What the workspace holds of the folder's (`Mapping.record`): each path there and the folder's path it came
        /// from, so a file taken out of the folder is taken out where the import had put it. Nil in records from before
        /// it was kept.
        var files: [String: String]?
        /// For a copy Lamp made to work in (`Conversion.disruptive`): the original folder's real path, whose own calls are
        /// answered from this copy rather than taking the original on a second time.
        var copiedFrom: String? = nil
        /// Why it was copied, said again whenever the original is named.
        var copiedBecause: [String]? = nil
    }

    /// What the agent passes on when Lamp works in a copy: its exact path, why it was made, that the folder the agent
    /// gave is unchanged, and how the person lets their agent edit the copy (`switchSteps`).
    static func copyNotice(copy: String, original: String, because: [String], withoutGit: Bool = false) -> String {
        "Lamp works on this app in a copy, at \(copy), because \(because.joined(separator: "; ")). The folder you gave, \(original), is unchanged."
            + (withoutGit ? " That folder is a git worktree, so the copy has no git of its own: commit from it with `git init`, or bring changes back by hand." : "")
            + "\nTell the person, in these words:\n\(switchSteps(copy))\n"
            + "From now on, edit only the copy and call every tool with path \(copy)."
    }

    /// How the person points their coding app at the copy. The desktop apps are the main clients, so their steps lead and
    /// the command line gets one short line; this is the one place the wording lives.
    static func switchSteps(_ copy: String) -> String {
        """
        - Claude Code desktop app: click + → Add folder and pick \(copy), or choose New → Local → Open folder… and pick \(copy).
        - ChatGPT desktop app: Edit project → Add folder and pick \(copy), or make \(copy) the project's primary folder and start a new chat.
        - Command line: start the agent again with `--add-dir \(copy)`.
        """
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
    /// and the same manifest), every file's hash, and where each of the package's files goes in the workspace and which
    /// file of the folder it came from (`Mapping`), so what was copied is checked against what the folder held and an
    /// edit to the folder lands where the import put that file.
    struct Capture {
        let package: Sharing.Package
        let layout: RepoImport.Layout
        let hashes: [String: String]
        let mapping: Mapping
        var fingerprint: String { OutsideWork.fingerprint(hashes) }
    }

    /// The one way between the folder and the workspace, for every apply and the first build alike: each file the
    /// import puts in the app, by its path in the workspace, with the package's copy of it and its path in the folder.
    /// The two differ for a site, whose page the import moves into Web/ (`StaticSite.unpack`); a file the import writes
    /// itself (a plain site's lamp-app.json and APP.md) has no path in the folder.
    struct Mapping {
        struct File { let copy: URL; let source: String? }
        let files: [String: File]
        /// What's kept between applies: each workspace path and the folder's path it came from ("" for none).
        var record: [String: String] { files.mapValues { $0.source ?? "" } }
        /// The folder's paths that become the app's code and files; every other file of the folder is the app's metadata.
        var sources: Set<String> { Set(files.values.compactMap(\.source)) }
    }

    /// One digest of a folder's reading, to tell whether what's in the app is what the folder holds.
    static func fingerprint(_ hashes: [String: String]) -> String {
        var hasher = SHA256()
        for (path, hash) in hashes.sorted(by: { $0.key < $1.key }) { hasher.update(data: Data((path + "\0" + hash + "\n").utf8)) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    struct CaptureProblem: Error { let text: String }

    static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// The folders the import leaves out of a folder of this layout (`RepoImport.copyTree`): a site keeps every folder
    /// but git's, since a `build/` or `node_modules/` it checked in is what its page loads.
    static func skipped(_ layout: RepoImport.Layout) -> Set<String> {
        if case .site = layout { return [".git"] }
        return [".git", ".build", "build", ".lamp", "node_modules"]
    }

    /// Every regular file the import would take, by its path in the folder, and its hash. The same folders are left out
    /// as the import leaves out, and links are never followed.
    static func hashes(of folder: URL, layout: RepoImport.Layout? = nil) -> [String: String] {
        let skipped = skipped(layout ?? RepoImport.layout(of: folder))
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        var found: [String: String] = [:]
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return [:] }
        for case let item as URL in items {
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { items.skipDescendants(); continue }
            if values?.isDirectory == true, skipped.contains(item.lastPathComponent) { items.skipDescendants(); continue }
            // A worktree's .git is a file: git's, never the app's.
            if item.lastPathComponent == ".git" { continue }
            guard values?.isRegularFile == true, item.pathExtension != "lampapp", let data = try? Data(contentsOf: item) else { continue }
            found[Sharing.relativePath(of: item, in: folder)] = sha(data)
        }
        return found
    }

    /// Where a file of the package came from in the folder, as the import laid it out: nil for one the import wrote.
    static func source(ofPackagePath path: String, layout: RepoImport.Layout) -> String? {
        let web = TVTemplate.webFolder + "/"
        switch layout {
        case .wish: return path
        case .site(laidOut: false): return path.hasPrefix(web) ? String(path.dropFirst(web.count)) : nil
        case .site(laidOut: true): return path.hasPrefix(web) ? String(path.dropFirst(web.count)) : StaticSite.folder + "/" + path
        case .sharedFile, .unknown: return nil
        }
    }

    /// The package's files the install puts in the app, by their path there, as `Sharing.install` puts them for this kind
    /// (its code, the page and its data for an app around a page, the app's own files in Assets/, APP.md), Lamp's own
    /// files left out. Nil for a kind whose files Lamp doesn't keep in step with a folder yet.
    static func mapping(of package: Sharing.Package, layout: RepoImport.Layout) -> Mapping? {
        var files: [String: Mapping.File] = [:]
        func add(_ path: String, _ copy: URL, from packagePath: String) {
            guard !path.contains("..") else { return }
            files[path] = Mapping.File(copy: copy, source: source(ofPackagePath: packagePath, layout: layout))
        }
        let language = package.platform.target.recipe.language
        if ScreenKit.isWebApp(package.platform) {
            for file in package.sources + package.webData {
                let path = package.path(of: file)
                guard !ScreenFiles.isLamps(path),
                      path.hasPrefix(TVTemplate.webFolder + "/") || (path.hasPrefix("Sources/") && path.hasSuffix(".swift")) else { continue }
                add(path, file, from: path)
            }
        } else if language == .swift {
            let codeFolders = ["Sources/", Template.widgetFolder + "/", Template.watchFolder + "/", Template.shareFolder + "/"]
            let lampsOwn: Set<String> = ["LampSupport.swift", Template.sceneSupportFile, Template.widgetSupportFile, Template.shareSupportFile]
            for file in package.sources where !lampsOwn.contains(file.lastPathComponent) {
                let path = package.path(of: file)
                guard codeFolders.contains(where: { path.hasPrefix($0) }), !Template.watchSupportPaths.contains(path) else { continue }
                add(path, file, from: path)
            }
        } else {
            return nil
        }
        for file in package.attachments {
            add(Sharing.Assets.folder + "/" + package.assetPath(of: file), file, from: package.path(of: file))
        }
        let appMd = package.folder.appendingPathComponent("APP.md")
        if FileManager.default.fileExists(atPath: appMd.path) { add("APP.md", appMd, from: "APP.md") }
        return Mapping(files: files)
    }

    /// Reads the folder as the import does, then checks it: every file the package took from the folder must have the
    /// bytes the folder held before the copy began, and the folder must hold the same after it. A folder still being
    /// written is read again, a few times, and then refused, never built from a mix of two moments.
    static func capture(_ repo: URL) throws -> Capture {
        var last = ""
        for _ in 0..<3 {
            let layout = RepoImport.layout(of: repo)
            if case .unknown(let why) = layout { throw CaptureProblem(text: why) }
            let before = hashes(of: repo, layout: layout)
            let package: Sharing.Package
            do { package = try RepoImport.open(folder: repo) } catch {
                let failure = error as? Sharing.ImportError
                throw CaptureProblem(text: (failure?.message ?? error.localizedDescription) + (failure?.detail.map { " " + $0 } ?? ""))
            }
            guard let mapping = mapping(of: package, layout: layout) else {
                try? FileManager.default.removeItem(at: package.folder)
                throw CaptureProblem(text: "Lamp can't yet keep \(package.platform.target.identity.name) in step with a folder.")
            }
            var differs: [String] = []
            for file in mapping.files.values {
                guard let source = file.source, let data = try? Data(contentsOf: file.copy) else { continue }
                if before[source] != sha(data) { differs.append(source) }
            }
            let after = hashes(of: repo, layout: layout)
            if differs.isEmpty, before == after, RepoImport.layout(of: repo) == layout {
                return Capture(package: package, layout: layout, hashes: before, mapping: mapping)
            }
            try? FileManager.default.removeItem(at: package.folder)
            last = (differs.isEmpty ? changes(from: before, to: after) : differs.sorted()).prefix(5).joined(separator: ", ")
            Thread.sleep(forTimeInterval: 0.4)
        }
        throw CaptureProblem(text: "The folder kept changing while Lamp read it (\(last)). Apply again once your edits are written.")
    }

    /// The paths that differ between two readings of a folder.
    static func changes(from old: [String: String], to new: [String: String]) -> [String] {
        Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }.sorted()
    }

    /// The folder's files that are the app's metadata rather than its code or its own files (what `syncMetadata`
    /// reads): every file of the folder the mapping doesn't put in the app.
    static func metadataDigest(_ capture: Capture) -> String {
        let code = capture.mapping.sources
        return fingerprint(capture.hashes.filter { !code.contains($0.key) })
    }

    /// Puts what was captured into the workspace, writing only what differs, so a file that didn't change keeps its
    /// date and LiveReload sees only the change, and taking out what an earlier apply put in that the folder no longer
    /// holds (`previous`: the mapping's record then; nil in records from before it was kept, for which the code folders
    /// and Assets/ are looked through instead). Lamp's own files in the workspace are left to Lamp
    /// (`Template.writeOwnedFiles`), whatever copy of them the folder has. Answers the folder's paths written or taken
    /// out (the workspace's, for a file with none), and the record to keep.
    /// `metadata`: put the app's metadata in too (`syncMetadata`), which is only when the folder's changed.
    static func sync(_ capture: Capture, into project: LampProject, previous: [String: String]?, metadata: Bool) throws -> [String] {
        let fm = FileManager.default
        let wanted = capture.mapping.files
        let had = previous ?? legacyFiles(in: project)
        var changed: [String] = []
        for (path, source) in had where wanted[path] == nil {
            let target = project.dir.appendingPathComponent(path)
            guard !path.contains(".."), fm.fileExists(atPath: target.path) else { continue }
            try fm.removeItem(at: target)
            changed.append(source.isEmpty ? path : source)
        }
        for (path, file) in wanted {
            let data = try Data(contentsOf: file.copy)
            let target = project.dir.appendingPathComponent(path)
            if (try? Data(contentsOf: target)) == data { continue }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            changed.append(file.source ?? path)
        }
        return (changed + (metadata ? try syncMetadata(capture.package, into: project) : [])).sorted()
    }

    /// What a workspace taken on before the mapping was kept holds of the folder's: its code folders and Assets/, Lamp's
    /// own files aside (only Mac apps in Lamp's format were taken on then).
    private static func legacyFiles(in project: LampProject) -> [String: String] {
        let fm = FileManager.default
        let lampsOwn: Set<String> = ["LampSupport.swift", Template.sceneSupportFile, Template.widgetSupportFile, Template.shareSupportFile]
        var have: [String: String] = [:]
        for folder in ["Sources/", Template.widgetFolder + "/", Template.watchFolder + "/", Template.shareFolder + "/", Sharing.Assets.folder + "/"] {
            let root = project.dir.appendingPathComponent(folder)
            for case let item as URL in fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) ?? FileManager.DirectoryEnumerator() {
                guard (try? item.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                let path = Sharing.relativePath(of: item, in: project.dir)
                if !lampsOwn.contains(item.lastPathComponent), !Template.watchSupportPaths.contains(path) { have[path] = path }
            }
        }
        return have
    }

    // MARK: Converting a folder

    /// What it takes for a folder to read as a Lamp app in place, and whether that can be done there. A Lamp app needs
    /// nothing; a plain site needs Lamp's manifest beside its page, as Lamp lays a site out on GitHub
    /// (`StaticSite.folder`: lamp-app.json and APP.md, the very ones the review read), which turns it into a laid-out site.
    ///
    /// The folder is edited in place, as the person's source control expects; a copy is made only when the conversion
    /// would be disruptive: replace or remove meaningful existing files, substantially reorganize the project, replace
    /// its build or dependency setup, drop targets or features, break its own way of working, or overwrite uncommitted
    /// work. Adding a manifest or a few support files stays in place. `disruptive` says why, when it is; every check of
    /// that kind belongs here, so the one decision is made in one place.
    struct Conversion: Equatable {
        /// Files added, by their path in the folder.
        var added: [String: Data] = [:]
        /// Why the conversion can't be done in the folder itself; empty when it can.
        var disruptive: [String] = []
        /// Of `added`, those the mapping puts in the app (a laid-out site's APP.md), so they aren't counted as metadata.
        var appFiles: Set<String> = []

        /// What the review says Build & Open will change in the folder, before it's chosen; nil when nothing.
        var reviewLine: String? {
            if !disruptive.isEmpty { return Self.copyLine }
            return added.isEmpty ? nil : Self.inPlaceLine
        }
        static let inPlaceLine = "Building adds Lamp's manifest to this folder. Nothing else in it changes."
        static let copyLine = "Building works in a copy beside this folder, which stays as it is."
    }

    static func conversion(for capture: Capture, in repo: URL) -> Conversion {
        guard capture.layout == .site(laidOut: false) else { return Conversion() }
        var conversion = Conversion()
        for name in ["lamp-app.json", "APP.md"] {
            guard let data = try? Data(contentsOf: capture.package.folder.appendingPathComponent(name)) else { continue }
            conversion.added[StaticSite.folder + "/" + name] = data
        }
        conversion.appFiles = [StaticSite.folder + "/APP.md"]
        let fm = FileManager.default
        var isFolder: ObjCBool = false
        if fm.fileExists(atPath: repo.appendingPathComponent(StaticSite.folder).path, isDirectory: &isFolder), !isFolder.boolValue {
            conversion.disruptive.append("the folder has a file named \(StaticSite.folder), where Lamp keeps a site's manifest, and adding it would replace that file")
        }
        for path in conversion.added.keys.sorted() where fm.fileExists(atPath: repo.appendingPathComponent(path).path) {
            conversion.disruptive.append("adding Lamp's manifest would replace the folder's own \(path)")
        }
        if !fm.isWritableFile(atPath: repo.path) { conversion.disruptive.append("Lamp can't write in the folder") }
        return conversion
    }

    /// A git worktree or submodule checkout: its .git is a file, not the repository itself.
    static func isLinkedCheckout(_ folder: URL) -> Bool {
        let values = try? folder.appendingPathComponent(".git").resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true
    }

    /// Carries a conversion out: in the folder, never over a file that's there, or, when it's disruptive, in a copy of
    /// the whole folder (its git with it) beside the original, which is left as it was. Answers the folder to work in.
    static func convert(_ conversion: Conversion, in repo: URL) throws -> URL {
        let fm = FileManager.default
        var folder = repo
        if !conversion.disruptive.isEmpty {
            let parent = repo.deletingLastPathComponent()
            var name = repo.lastPathComponent + "-lamp"
            var n = 2
            while fm.fileExists(atPath: parent.appendingPathComponent(name).path) { name = repo.lastPathComponent + "-lamp-\(n)"; n += 1 }
            folder = parent.appendingPathComponent(name)
            try fm.copyItem(at: repo, to: folder)
            // A worktree's (or submodule's) .git is a file naming the main repository's record of this checkout: the copy
            // would claim that same checkout, so it goes without it.
            if isLinkedCheckout(repo) { try fm.removeItem(at: folder.appendingPathComponent(".git")) }
            // In the copy only, a file in the way of what's added is kept beside it under another name.
            for path in conversion.added.keys.sorted() {
                var walked = ""
                for step in path.split(separator: "/").map(String.init) {
                    walked += (walked.isEmpty ? "" : "/") + step
                    let item = folder.appendingPathComponent(walked)
                    var isFolder: ObjCBool = false
                    guard fm.fileExists(atPath: item.path, isDirectory: &isFolder) else { break }
                    if !isFolder.boolValue || walked == path {
                        try fm.moveItem(at: item, to: folder.appendingPathComponent(walked + "-before-lamp"))
                        break
                    }
                }
            }
        }
        for (path, data) in conversion.added.sorted(by: { $0.key < $1.key }) {
            let target = folder.appendingPathComponent(path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .withoutOverwriting)
        }
        return folder
    }

    /// The app's own metadata, put in as the import puts it in (`Sharing.install`), from the same checked package: its
    /// capabilities (a file that declares none takes them away), description, credits and the license files they name,
    /// and its icon's design and artwork. Each is written by the import's own writer; what's answered as written is
    /// only what came out different, so a folder whose metadata didn't change still answers unchanged.
    static func syncMetadata(_ package: Sharing.Package, into project: LampProject) throws -> [String] {
        let fm = FileManager.default
        let licences = package.licences.map { Sharing.relativePath(of: $0, in: package.folder) }.filter { !$0.contains("..") }
        let watched = [Template.Capabilities.file, AppDescription.file, Credits.file, Credits.arrivedPath] + licences
        func read() -> [String: Data] {
            Dictionary(uniqueKeysWithValues: watched.compactMap { path in
                (try? Data(contentsOf: project.dir.appendingPathComponent(path))).map { (path, $0) }
            })
        }
        let before = read()
        let iconBefore = (try? Data(contentsOf: Icons.specURL(project)))
        try package.capabilities.save(for: project)
        try AppDescription.write(package.description, for: project)
        try Credits.arrive(package.credits, in: project)
        for (file, path) in zip(package.licences.filter { !Sharing.relativePath(of: $0, in: package.folder).contains("..") }, licences) {
            let target = project.dir.appendingPathComponent(path)
            if (try? Data(contentsOf: target)) == (try? Data(contentsOf: file)) { continue }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: target)
            try fm.copyItem(at: file, to: target)
        }
        let newArt = try Sharing.installIcon(package, into: project)
        let after = read()
        var changed = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
        if newArt || (try? Data(contentsOf: Icons.specURL(project))) != iconBefore { changed.insert("icon.json") }
        return Array(changed)
    }
}

/// A folder waiting on Lamp's import review for `open_project` (`Store.importApp`): told once, with the app made or
/// why there's none, whichever way the review ends.
/// The review is of the very package open_project captured and checked (`snapshot`), never the folder read again, so
/// what the person approves is what's built first.
@MainActor final class OutsideImport {
    let repo: String
    /// The folder as captured: what the review reads and the install puts in. Kept until the review ends.
    let snapshot: Sharing.Package
    /// What taking it on will change in the folder, as worked out before the review, which says so.
    let conversion: OutsideWork.Conversion
    /// Build & Open was chosen: the review closing after that isn't a no.
    var confirmed = false
    private var done: ((LampProject?, String?) -> Void)?
    /// Told already: a review opened again for it (its Try Again) makes no app, which nobody would be told of and a
    /// second open_project would make again.
    var isFinished: Bool { done == nil }

    init(repo: String, snapshot: Sharing.Package, conversion: OutsideWork.Conversion, done: @escaping (LampProject?, String?) -> Void) {
        self.repo = repo
        self.snapshot = snapshot
        self.conversion = conversion
        self.done = done
    }

    /// A copy of the snapshot for one review to unpack into and take apart, as a file opened is copied for each.
    nonisolated static func copy(of snapshot: Sharing.Package) throws -> Sharing.Package {
        let copy = Sharing.workFolder.appendingPathComponent("forge-import-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: snapshot.folder, to: copy)
        do {
            var package = try Sharing.open(unpacked: copy)
            // Where it came from, which the import adds to the chain it read (`RepoImport.naming`).
            package.credits = snapshot.credits
            return package
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw error
        }
    }

    func finish(_ project: LampProject?, _ why: String?) {
        let done = self.done
        self.done = nil
        done?(project, why)
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
    /// Records whether a folder's workspace holds files the open app may not run yet (`Adopted.owed`).
    func setOwed(_ owed: Bool, repo: String) {
        guard let index = adopted.firstIndex(where: { $0.repo == repo }), (adopted[index].owed ?? false) != owed else { return }
        adopted[index].owed = owed
        save()
    }

    init() { fromBefore = Set(adopted.map(\.repo)) }

    func save() { OutsideWork.saveRegistry(adopted) }

    /// A workspace the person's own agent works on: Lamp's own agent never starts on it by itself.
    func isOutside(_ projectID: String) -> Bool { adopted.contains { $0.project == projectID } }
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
        // The same skills, by the same means, as Lamp's own engines read them.
        if name == "read_skill" {
            let (status, answer) = Skills.read(payload.values)
            return status == 200 ? OutsideWork.Answer(outcome: "skill", text: answer["text"] as? String ?? "")
                : .refused(answer["error"] as? String ?? "No such skill.")
        }
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
            case "export_app": return await outsideExport(path)
            case "publish_link": return await outsidePublish(path)
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
        // Taken on already, here or (moved) elsewhere: the same workspace goes on. A retry of an open_project that took
        // the folder on lands here, so it never makes a second app.
        if let index = state.adopted.firstIndex(where: { ($0.repo == now.real || ($0.device == now.device && $0.inode == now.inode)) }),
           projects.contains(where: { $0.id == state.adopted[index].project }),
           state.adopted[index].device == now.device, state.adopted[index].inode == now.inode {
            let moved = state.adopted[index].repo != now.real
            state.fromBefore.remove(state.adopted[index].repo)
            state.adopted[index].repo = now.real
            state.save()
            var answer = await outsideApply(now.real, reopen: false)
            if moved { answer.text = "Lamp had this folder at another path; it's known here now.\n\n" + answer.text }
            if let project = projects.first(where: { $0.id == state.adopted[index].project }) {
                answer.text += "\n\n" + OutsideWork.guidance(for: project, layout: RepoImport.layout(of: repo))
            }
            return answer
        }
        // A folder Lamp works on in a copy: answered from the copy, never taken on a second time.
        if let copy = state.adopted.first(where: { $0.copiedFrom == now.real }), projects.contains(where: { $0.id == copy.project }),
           OutsideWork.identity(of: copy.repo) != nil {
            var answer = await outsideApply(copy.repo, reopen: false)
            answer.text = OutsideWork.copyNotice(copy: copy.repo, original: now.real, because: copy.copiedBecause ?? ["taking it on in place would have been disruptive"]) + "\n\n" + answer.text
            answer.facts["copied_to"] = copy.repo
            answer.facts["original_unchanged"] = true
            return answer
        }
        // A folder put where one Lamp knew was: that one is let go (its workspace stays on the desk), and this one is new.
        state.adopted.removeAll { $0.repo == now.real }
        state.save()
        // What the folder is, as the import reads it (`RepoImport.layout`): a Lamp app, a site, or what's missing for
        // either. One Lamp can't read is answered with what it lacks.
        switch RepoImport.layout(of: repo) {
        case .unknown(let why):
            return OutsideWork.Answer(outcome: "not_importable", text: "Lamp can't open \(now.real) as it is. \(why) Nothing was changed.", isError: true)
        case .sharedFile(let file):
            return OutsideWork.Answer(outcome: "not_importable",
                                      text: "\(now.real) holds only a packed Lamp app (\(file.lastPathComponent)), not its code, so there's nothing in the folder to edit. Lamp works on a folder holding the app's code: lamp-app.json and its code at the top, or a site's index.html at the top. Nothing was changed.",
                                      isError: true)
        case .wish, .site: break
        }
        let capture: OutsideWork.Capture
        do { capture = try await Self.offMain { Result { try OutsideWork.capture(repo) } }.get() } catch {
            return .refused((error as? OutsideWork.CaptureProblem)?.text ?? error.localizedDescription)
        }
        let package = capture.package
        let target = package.platform.target
        guard (target.startsAt ?? target.places).contains(.mac), package.parts.isEmpty else {
            try? FileManager.default.removeItem(at: package.folder)
            return OutsideWork.Answer(outcome: "not_importable",
                                      text: "For now Lamp takes on only an app that opens on this Mac, on its own; this is \(target.identity.name)\(package.parts.isEmpty ? "" : " with other apps"). Nothing was changed.",
                                      isError: true)
        }
        // The same review as any app that comes to Lamp: its fixed checks, the AI's check when AI is set up, and the
        // person's Build & Open, of exactly what was captured, which is what's then installed. The agent's call waits
        // for that answer.
        // What taking it on will change in the folder is worked out now, so the review says it before Build & Open.
        let planned = OutsideWork.conversion(for: capture, in: repo)
        let made: (LampProject?, String?) = await withCheckedContinuation { answered in
            importApp(from: repo, outside: OutsideImport(repo: now.real, snapshot: package, conversion: planned) { answered.resume(returning: ($0, $1)) })
        }
        guard let project = made.0 else {
            try? FileManager.default.removeItem(at: package.folder)
            return .refused(made.1 ?? "Lamp didn't take the folder on.")
        }
        // Approved: what it takes for the folder to read as a Lamp app goes in now, in place, or in a copy when that
        // would be disruptive (`OutsideWork.Conversion`). Never before Build & Open, so a no leaves the folder as it was.
        // Worked out again, since the folder may have changed while the review was up; a plan that became disruptive
        // (a file now in the way) is a copy rather than anything written over, and the answer says which happened.
        var conversion = OutsideWork.conversion(for: capture, in: repo)
        if conversion.disruptive.isEmpty, !planned.disruptive.isEmpty { conversion.disruptive = planned.disruptive }
        try? FileManager.default.removeItem(at: package.folder)
        let folder: URL
        do { folder = try await Self.offMain { Result { try OutsideWork.convert(conversion, in: repo) } }.get() } catch {
            // The app made for it goes too: kept, it would be one no call knows of, and the next open_project would make another.
            await delete(current(project) ?? project)
            return .refused("Lamp couldn't \(conversion.disruptive.isEmpty ? "add its manifest to the folder" : "make a copy of the folder to work in"): \(error.localizedDescription) Nothing was kept; the folder is as it was.")
        }
        guard let worked = OutsideWork.identity(of: folder.path) else { return .refused("Lamp lost the folder it was to work in.") }
        var reviewed = capture.hashes
        for (path, data) in conversion.added { reviewed[path] = OutsideWork.sha(data) }
        let code = capture.mapping.sources.union(conversion.appFiles)
        state.adopted.append(OutsideWork.Adopted(repo: worked.real, device: worked.device, inode: worked.inode, project: project.id, applied: nil,
                                                 metadata: OutsideWork.fingerprint(reviewed.filter { !code.contains($0.key) }),
                                                 files: capture.mapping.record,
                                                 copiedFrom: conversion.disruptive.isEmpty ? nil : now.real,
                                                 copiedBecause: conversion.disruptive.isEmpty ? nil : conversion.disruptive))
        state.save()
        // An app that came with no icon gets its design now, before its first build, as a new app's is designed while its
        // first request builds: designed after it, the icon is a change the open app can't take, and the next change of
        // any kind reopens the app for it.
        if Icons.load(project) == nil, let made = current(project) {
            Icons.save(await Icons.design(for: made), for: made)
        }
        // Its first build is what the review read and installed, never the folder read again: an edit made while the
        // review was up would otherwise go in unreviewed. Such an edit is pending, for the next apply.
        var answer = await outsideApply(worked.real, reopen: false, reviewed: reviewed)
        var lead = "Lamp took on \(worked.real) as “\(project.name)”."
        let added = conversion.added.keys.sorted()
        if !conversion.disruptive.isEmpty {
            // The agent must pass this on: its own session can't edit outside the folder it was started in.
            lead = OutsideWork.copyNotice(copy: worked.real, original: now.real, because: conversion.disruptive,
                                          withoutGit: OutsideWork.isLinkedCheckout(repo))
                + "\nLamp took the copy on as “\(project.name)”" + (added.isEmpty ? "." : ", with \(added.joined(separator: " and ")) added to it.")
            answer.facts["copied_to"] = worked.real
            answer.facts["copied_because"] = conversion.disruptive
            answer.facts["original_unchanged"] = true
        } else if !added.isEmpty {
            lead += " To read it as a Lamp app, Lamp added \(added.joined(separator: " and ")) to the folder; nothing else in it was changed. They're Lamp's manifest for a site: keep them with the site in its git."
        }
        if !added.isEmpty { answer.facts["added"] = added }
        answer.facts["path"] = worked.real
        answer.text = lead + "\n\n" + answer.text + "\n\n" + OutsideWork.guidance(for: current(project) ?? project, layout: RepoImport.layout(of: folder))
        return answer
    }

    // MARK: apply_change

    /// `reviewed`: the app's first build after its review, from what the review installed; the folder as read just before
    /// the review began, so what went in is known to be the folder's only when the folder still reads the same.
    private func outsideApply(_ path: String, reopen: Bool, reviewed: [String: String]? = nil) async -> OutsideWork.Answer {
        guard let found = outsideFolder(path) else { return outsideRefusal(path) }
        let entry = found.0
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
            let read: [String: String]
            var written: [String] = []
            if let reviewed {
                read = reviewed
            } else {
                let capture: OutsideWork.Capture
                do { capture = try await Self.offMain { Result { try OutsideWork.capture(repo) } }.get() } catch {
                    return .refused((error as? OutsideWork.CaptureProblem)?.text ?? error.localizedDescription)
                }
                defer { try? FileManager.default.removeItem(at: capture.package.folder) }
                let metadata = OutsideWork.metadataDigest(capture)
                let kept = state.adopted.first(where: { $0.repo == entry.repo })
                let metadataChanged = kept?.metadata != metadata
                do { written = try OutsideWork.sync(capture, into: project, previous: kept?.files, metadata: metadataChanged) } catch {
                    return .refused("Lamp couldn't copy the folder's files into its build: \(error.localizedDescription)")
                }
                // The record of what the workspace holds of the folder's goes with what was just written, whatever the
                // apply comes to: a file taken out of the folder now is out of the workspace too.
                if let index = state.adopted.firstIndex(where: { $0.repo == entry.repo }) {
                    if metadataChanged { state.adopted[index].metadata = metadata }
                    state.adopted[index].files = capture.mapping.record
                    state.save()
                }
                read = capture.hashes
            }
            // Owed from here until the change goes in, on disk before anything is built.
            if !written.isEmpty { state.setOwed(true, repo: entry.repo) }
            if Task.isCancelled { return OutsideWork.Answer(outcome: "cancelled", text: "Cancelled before building. Lamp's copy has the folder's files; the app is as it was.") }

            let wasOpen = isRunning(project)
            let changed = Runtime.sourcesChanged(project)
            var answer: OutsideWork.Answer
            let owed = state.adopted.first(where: { $0.repo == entry.repo })?.owed ?? false
            if !changed, wasOpen, !reopen, !owed {
                answer = OutsideWork.Answer(outcome: "unchanged", text: "Nothing changed since the app was built; it's open as it was.")
            } else if changed, let errors = await build(project, inPlace: !reopen) {
                answer = Task.isCancelled || hold.stopped
                    ? OutsideWork.Answer(outcome: "cancelled", text: "Cancelled during the build; the app is as it was.")
                    : OutsideWork.Answer(outcome: "not_built", text: "The app doesn't build. Fix these compiler errors and apply again:\n\n\(errors)", isError: true)
            } else if Task.isCancelled || hold.stopped {
                // Cancelled once built: nothing goes into the app, which stays as it was until the next apply.
                answer = OutsideWork.Answer(outcome: "cancelled", text: "Cancelled after the build; nothing went into the app, which is as it was.")
            } else {
                let crash = await install(project, inFront: false, fresh: reopen, reload: reopen, early: true)
                state.setOwed(false, repo: entry.repo)
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
                    let drawn = await outsidePictures(of: project, since: began)
                    answer.pictures = drawn.pictures
                    if let note = drawn.note { answer.text += " " + note }
                }
            }
            if Privacy.sharesLog, let tail = Runtime.logTail(project) { answer.text += "\n\nWhat it printed:\n\(tail)" }
            // Built from what the folder held at the capture: an edit made since isn't in it, and is said.
            let now = await Self.offMain { OutsideWork.hashes(of: repo) }
            let since = OutsideWork.changes(from: read, to: now)
            answer.facts["stale"] = !since.isEmpty
            answer.facts["written"] = written
            if !since.isEmpty {
                answer.text = "Stale: the folder changed \(reviewed == nil ? "while Lamp built it" : "since Lamp's review read it") (\(since.prefix(5).joined(separator: ", "))). What's in the app is the folder as it was before; apply again.\n\n" + answer.text
            }
            if ["live", "reopened", "opened", "held", "unchanged"].contains(answer.outcome) {
                // Only what was applied: the record's other fields (`owed`) were kept up to date as the apply went.
                if let index = state.adopted.firstIndex(where: { $0.repo == entry.repo }) {
                    state.adopted[index].applied = OutsideWork.fingerprint(read)
                    state.save()
                }
            }
            log(project, .detail, "Your coding agent applied a change: \(answer.outcome).")
            return answer
        } onCancel: {
            // Nothing is ended under way: a build or a change going in that's stopped midway leaves the app waiting for
            // Reload, and Lamp would carry the change on by itself. The apply stops at its next step instead (before
            // the build, or once built, before the change goes in).
        }
    }

    /// The app's pictures once its window has drawn. A window that has just opened is pictured before its page (or
    /// anything the system draws in it) has painted, which comes out one even color (`GameKit.isBlank`): it's pictured
    /// again until it shows something, for a while, and a window still blank then is said rather than shown.
    private func outsidePictures(of project: LampProject, since: Date, waiting: Double = 6) async -> (pictures: [[String: String]], note: String?) {
        var shots = await Runtime.screenshots(of: project, since: since, waiting: waiting)
        let deadline = Date().addingTimeInterval(15)
        while let first = shots.first, GameKit.isBlank(first), Date() < deadline, isRunning(project), !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(700))
            let asked = Date()
            Runtime.requestScreenshots(of: project)
            shots = await Runtime.screenshots(of: project, since: asked, waiting: 3)
        }
        if let first = shots.first, GameKit.isBlank(first) {
            return ([], "Its window stayed one even color, so no picture follows: it may not have drawn yet, or be covered. Call look_at_app in a moment.")
        }
        return (Self.pictureData(Self.agentPictures(shots, in: project), in: project), nil)
    }

    // MARK: look_at_app

    private func outsideLook(_ path: String) async -> OutsideWork.Answer {
        guard let (entry, project) = outsideFolder(path) else { return outsideRefusal(path) }
        OutsideState.shared.fromBefore.remove(entry.repo)
        let repo = URL(fileURLWithPath: entry.repo)
        let now = await Self.offMain { OutsideWork.hashes(of: repo) }
        let pending = entry.applied != OutsideWork.fingerprint(now)
        guard isRunning(project) else {
            return OutsideWork.Answer(outcome: "not_open", text: "The app isn't open. apply_change opens it." + (pending ? " The folder has changes not put in yet." : ""),
                                      facts: ["pending": pending])
        }
        let asked = Date()
        Runtime.requestScreenshots(of: project)
        var answer = OutsideWork.Answer(outcome: "open", text: (pending ? "The folder has changes not put in yet; apply_change puts them in. " : "The app runs what the folder holds. ")
                                        + "Pictures of its windows follow, frontmost first.", facts: ["pending": pending])
        let drawn = await outsidePictures(of: project, since: asked, waiting: 3)
        answer.pictures = drawn.pictures
        if let note = drawn.note { answer.text += " " + note }
        if Privacy.sharesLog, let tail = Runtime.logTail(project) { answer.text += "\n\nWhat it printed:\n\(tail)" }
        return answer
    }

    // MARK: Sharing

    /// The folder's app, when what's built is the folder as it is now: sharing goes out only from a known snapshot,
    /// never from a workspace a step behind (or ahead of) the folder the agent sees.
    private func outsideSnapshot(_ path: String) async -> (OutsideWork.Adopted, LampProject, String)? {
        // Nothing owed either: a later apply that wrote the workspace without going in (it didn't build, or was
        // cancelled) leaves files there that the folder may no longer hold, which sharing would pack.
        guard let (entry, project) = outsideFolder(path), let applied = entry.applied, entry.owed != true else { return nil }
        let now = await Self.offMain { OutsideWork.hashes(of: URL(fileURLWithPath: entry.repo)) }
        // The last apply that went in wrote the workspace from this very reading. The whole build that follows a live
        // change may still be running; sharing packs the files, not the build, so it doesn't wait for it.
        guard OutsideWork.fingerprint(now) == applied else { return nil }
        return (entry, project, applied)
    }

    private func notSnapshot(_ path: String) -> OutsideWork.Answer {
        guard outsideFolder(path) != nil else { return outsideRefusal(path) }
        return .refused("What's built isn't the folder as it is now. Call apply_change, and share once it answers live, reopened, opened or unchanged.")
    }

    private func outsideExport(_ path: String) async -> OutsideWork.Answer {
        guard let (_, project, snapshot) = await outsideSnapshot(path) else { return notSnapshot(path) }
        guard begin(project) != nil else { return .refused("Lamp is busy with this app. Try again in a moment.") }
        defer { finish(current(project) ?? project) }
        // Work that came with no license is the person's to pass on or not: asked as Share… asks.
        guard Sharing.askToShare(project) else { return .refused("The person chose not to share it: some of its work came with no license.") }
        do {
            let file = try await Self.offMain { Result { try Store.sharedFile(of: project) } }.get()
            return OutsideWork.Answer(outcome: "exported", text: "Lamp made \(project.name)'s shared file at \(file.path). It holds the app's code and files, never its data or anything of the person's. Copy it where it's wanted; Lamp makes it again at the next export.",
                                      facts: ["file": file.path, "snapshot": snapshot])
        } catch {
            let failure = error as? Sharing.ImportError
            return .refused((failure?.message ?? error.localizedDescription) + (failure?.detail.map { " " + $0 } ?? ""))
        }
    }

    /// The Share Link card, for the person: the agent's call waits while it's open, holding the app so nothing is
    /// applied under it. Lamp keeps the link's secret, as for any link, so changing it or taking it down stays there.
    private func outsidePublish(_ path: String) async -> OutsideWork.Answer {
        guard let (_, project, snapshot) = await outsideSnapshot(path) else { return notSnapshot(path) }
        guard begin(project) != nil else { return .refused("Lamp is busy with this app. Try again in a moment.") }
        defer { finish(current(project) ?? project) }
        let cards = WishLinkCards.shared
        cards.open(project)
        NSApp.activate()
        var sent = false
        let began = Date()
        while Date().timeIntervalSince(began) < 30 * 60 {
            if Task.isCancelled { return OutsideWork.Answer(outcome: "cancelled", text: "Stopped waiting; the card is still open for the person.") }
            guard let card = cards.card(for: project) else {
                return sent ? OutsideWork.Answer(outcome: "closed", text: "The person closed the card after trying to share; nothing more is known of it.")
                    : OutsideWork.Answer(outcome: "closed", text: "The person closed the card without sharing.")
            }
            if card.stage == .sending { sent = true }
            if sent, card.stage != .sending {
                let link = card.shared?.url.absoluteString
                var facts: [String: Any] = ["snapshot": snapshot]
                if let link { facts["link"] = link }
                if case .failed(let why) = card.stage {
                    // A link is made before the app's file goes up: a failure after that leaves a link that exists without
                    // this release, which is said as it is.
                    if card.released, let link {
                        return OutsideWork.Answer(outcome: "published_with_problem", text: "\(link) is shared, but: \(why)", facts: facts)
                    }
                    if let link {
                        return OutsideWork.Answer(outcome: "partial", text: "The link \(link) exists, but this release didn't finish: \(why) It may show the earlier version or no app file. The person can try again on the card.", isError: true, facts: facts)
                    }
                    return OutsideWork.Answer(outcome: "failed", text: "Nothing was shared: \(why)", isError: true, facts: facts)
                }
                if card.released, let link {
                    return OutsideWork.Answer(outcome: "published", text: "Shared at \(link). Lamp copied the link for the person.", facts: facts)
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return OutsideWork.Answer(outcome: "timed_out", text: "The card was open for 30 minutes without being shared; it's still open for the person.")
    }
}
