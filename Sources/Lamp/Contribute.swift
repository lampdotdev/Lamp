import AppKit
import Foundation
import LampFileLook
import LampSidebarKit

/// Sending a wish's changes back to the repository it came from (`AppUpdates.origin`: the chain's last link naming a
/// repository that isn't the wish's own): a pull request on that repository from the person's own fork, made with
/// GitHub's command-line tool (`gh`) and their sign-in, as Put on GitHub puts a repository up (`GitHubRepo`).
///
/// What goes is only what the wish changed, on top of where the repository is now. The change is measured in the wish's
/// own history (`change`): from what it last took in from there (`base`: the snapshot of its last update, else the
/// version it arrived as) to the version the card was made from, each side as a shared file carries it, so Lamp's own
/// files, written afresh by each Lamp, are never part of it (`Upstream.filteredTree`). Git then replays that change on
/// the repository's latest commit three ways (`replay`): a file the wish didn't touch stays as its owner has it, and a
/// file both changed in the same place stops the request, which Check for Updates… settles first. The manifest keeps
/// the repository's identity and dates and takes only what the change says (`manifest`), credits.json keeps its chain
/// and takes only work the change newly uses, and a shared file beside the code is made again from the tree with the
/// change in it (`remakeSharedFile`). Everything is worked out before the card offers to send, as one commit in a
/// clone of Lamp's, and that commit is what goes: nothing of the wish's own history, and never the chat.
enum Contribute {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Where the changes would go. Nil for a wish that didn't come from a repository on GitHub. The commit its credits
    /// name says only what the wish is on top of: a shared file names the commit before the one it went up in, so it's
    /// never what the change is measured against.
    static func origin(of project: LampProject) -> RepoImport.Source? {
        AppUpdates.origin(of: project)?.url.flatMap(RepoImport.source(from:))
    }

    static func canContribute(_ project: LampProject) -> Bool { origin(of: project) != nil }

    /// The pull request opened, and the branch on the fork it came from.
    struct Request: Equatable {
        let url: String
        let branch: String
        let fork: String
    }

    /// What will go, worked out before the person confirms: one commit on the repository's latest, in a clone in a
    /// folder of Lamp's (`folder`, removed with the card).
    struct Prepared {
        let folder: URL
        let clone: URL
        /// The wish's version it was made from: one that's changed since isn't what the card showed.
        let version: String
        /// The repository's commit it goes on top of, and its branch.
        let tip: String
        let baseBranch: String
        let commit: String
        /// The files it changes, by their paths in the repository.
        let changed: [String]
        let title: String
        let body: String
    }

    /// The person's fork of `source`, when they have one: "login/name". Asked of GitHub.
    static func fork(of source: RepoImport.Source, login: String, gh: String) async -> String? {
        let candidate = "\(login)/\(source.name)"
        let looked = await Subprocess.run(gh, ["api", "repos/\(candidate)", "--jq", ".parent.full_name"], mergeErrors: false, timeout: 30)
        guard looked.ok, looked.output.trimmed.lowercased() == "\(source.owner)/\(source.name)".lowercased() else { return nil }
        return candidate
    }

    /// Works out what would go: the wish's change since it last took anything in, replayed on the repository's latest
    /// commit (fetched with the person's sign-in, so a private repository they can read works too), committed in their
    /// name. Throws, saying why, when nothing would go or it can't go as it is.
    static func prepare(_ project: LampProject, from source: RepoImport.Source, gh: String, login: String) async throws -> Prepared {
        let upstream = "\(source.owner)/\(source.name)"
        let base = await Subprocess.run(gh, ["repo", "view", upstream, "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name"], mergeErrors: false, timeout: 30)
        let baseBranch = base.ok && !base.output.trimmed.isEmpty ? base.output.trimmed : "main"
        return try await prepare(project, remote: "https://github.com/\(upstream).git", baseBranch: baseBranch, source: source,
                                 git: GitHubRepo.git, access: GitHubRepo.signedIn(gh: gh), login: login)
    }

    /// The same from any remote, with `access` the options git fetches it with: what tests give a repository on disk.
    static func prepare(_ project: LampProject, remote: String, baseBranch: String, source: RepoImport.Source, git: String,
                        access: [String], login: String) async throws -> Prepared {
        let fm = FileManager.default
        // What's sent is a version of the wish: files changed since its last version are no version at all.
        guard let version = await Task.detached(operation: { Versions.savedVersion(of: project.dir) }).value else {
            throw Failure(message: "\(project.name) has changes that aren't saved yet. Try again once Lamp has saved them.")
        }
        let folder = Sharing.workFolder.appendingPathComponent("lamp-contribute-\(UUID().uuidString)")
        var done = false
        defer { if !done { try? fm.removeItem(at: folder) } }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        // The wish as a shared file, with the same checks (licenses, keys): only what that carries can go.
        let exported = folder.appendingPathComponent("export")
        let file = try await Task.detached { try Sharing.export(project) }.value
        defer { try? fm.removeItem(at: file.deletingLastPathComponent()) }
        guard Subprocess.runBlocking("/usr/bin/ditto", ["-x", "-k", file.path, exported.path], timeout: 120).ok else {
            throw Failure(message: "Couldn't read \(project.name)'s files.")
        }
        guard await Task.detached(operation: { Versions.savedVersion(of: project.dir) }).value == version else {
            throw Failure(message: "\(project.name) changed while Lamp was looking. Try again.")
        }
        let clone = folder.appendingPathComponent("clone")
        try fm.createDirectory(at: clone, withIntermediateDirectories: true)
        func run(_ arguments: [String], in cwd: URL = clone, env: [String: String]? = nil, input: Data? = nil, timeout: TimeInterval = 120) async -> Subprocess.Result {
            await Subprocess.run(git, ["-c", "core.hooksPath=/dev/null"] + arguments, cwd: cwd, env: env, mergeErrors: false, timeout: timeout, input: input)
        }
        func must(_ result: Subprocess.Result) throws -> String {
            guard result.ok else { throw Failure(message: "Couldn't prepare the pull request: \((result.errors + result.output).trimmed.suffix(200))") }
            return result.output.trimmed
        }
        _ = try must(await run(["init", "-q"]))
        _ = try must(await run(["remote", "add", "upstream", remote]))
        let fetched = await run(access + ["fetch", "-q", "--depth", "1", "upstream", "refs/heads/\(baseBranch)"], timeout: 600)
        guard fetched.ok else {
            throw Failure(message: "GitHub didn't give back \(source.owner)/\(source.name): \((fetched.errors + fetched.output).trimmed.suffix(200))")
        }
        let tip = try must(await run(["rev-parse", "FETCH_HEAD"]))
        let branch = "lamp/\(Publish.slug(project.name))-\(UUID().uuidString.prefix(6).lowercased())"
        _ = try must(await run(["checkout", "-q", "-b", branch, tip]))

        var change = try await self.change(of: project, at: version, exported: exported, repository: clone, in: folder)
        // A wish that arrived before Lamp kept the manifest it came with is measured against the repository's at the
        // commit its credits name, else at its latest (only what differs from that goes).
        if change.manifest == nil {
            var said: Data? = nil
            if let commit = change.namedCommit, await run(access + ["fetch", "-q", "--depth", "1", "upstream", commit], timeout: 120).ok {
                let shown = await run(["show", "\(commit):\(change.meta)lamp-app.json"])
                if shown.ok { said = Data(shown.output.utf8) }
            }
            said = said ?? (try? Data(contentsOf: clone.appendingPathComponent(change.meta + "lamp-app.json")))
            change.manifest = said.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        }
        let ours = manifestOf(exported)
        guard !change.paths.isEmpty || !manifestChanges(ours: ours, base: change.manifest ?? [:]).isEmpty else {
            throw Failure(message: "\(project.name) has no changes of its own to send since it last took anything from \(source.owner)/\(source.name).")
        }

        func stopped(_ files: [String]) -> Failure {
            let named = files.prefix(3).joined(separator: ", ") + (files.count > 3 ? " and \(files.count - 3) more" : "")
            return Failure(message: "\(source.owner)/\(source.name) changed the same parts of \(named) since \(project.name) last took anything from it. "
                           + "Check for Updates… to bring their changes in, then send yours.")
        }
        let replayed = try await replay(change, in: clone, tip: tip, git: git)
        guard replayed.conflicts.isEmpty else { throw stopped(replayed.conflicts) }
        _ = try must(await run(["read-tree", "--reset", "-u", replayed.tree]))
        var touched = Set(change.paths)
        guard let finished = try finish(change, in: clone, exported: exported) else { throw stopped([change.meta + "lamp-app.json"]) }
        touched.formUnion(finished)

        // Nothing to send when the repository's files are all as they were: the shared file is made again only for a
        // change, since remaking one zipped another way changes its bytes and nothing else.
        _ = try must(await run(["add", "-A"]))
        guard !(try must(await run(["diff", "--cached", "--no-renames", "--name-only", "-z", tip]))).isEmpty else {
            throw Failure(message: "\(source.owner)/\(source.name) already has everything this app changed: there's nothing to send.")
        }
        // And nothing that goes holds a key: the files as they'll be pushed, checked as the export checks its own.
        let (root, parts) = Sharing.layout(of: project)
        let outgoing = folder.appendingPathComponent("outgoing")
        for path in touched where fm.fileExists(atPath: clone.appendingPathComponent(path).path) {
            let to = outgoing.appendingPathComponent(path)
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: clone.appendingPathComponent(path), to: to)
        }
        let leaks = ShareCheck.secrets(in: outgoing, known: Array(Set(([project, root] + parts).flatMap { Sharing.knownSecrets($0) })))
        try? fm.removeItem(at: outgoing)
        if let first = leaks.first {
            throw Failure(message: "\(project.name)'s changes can't go: \(first) holds a key or a password. Ask Lamp to take it out and keep it out of the code.")
        }
        try remakeSharedFile(in: clone, touched: touched, meta: change.meta, work: folder)
        _ = try must(await run(["add", "-A"]))
        let changed = try must(await run(["diff", "--cached", "--no-renames", "--name-only", "-z", tip])).split(separator: "\0").map(String.init)
        let summary = await summary(of: project, from: source, changed: changed)
        // The summary is the commit's message and the pull request's text, from files: it's prose, never arguments.
        let message = folder.appendingPathComponent("message.txt")
        try (summary.title + "\n\n" + summary.body).write(to: message, atomically: true, encoding: .utf8)
        _ = try must(await run(GitHubRepo.identity(login: login) + ["commit", "-q", "-F", message.path]))
        let commit = try must(await run(["rev-parse", "HEAD"]))
        done = true
        return Prepared(folder: folder, clone: clone, version: version, tip: tip, baseBranch: baseBranch, commit: commit, changed: changed,
                        title: summary.title, body: summary.body)
    }

    /// Opens the pull request with what `prepare` made: the fork made when there's none, the commit pushed to a branch
    /// of it, and the request on `source`; `step` hears what it's doing.
    static func send(_ prepared: Prepared, of project: LampProject, to source: RepoImport.Source, fork: String?,
                     gh: String, login: String, step: @escaping @Sendable (String) -> Void) async throws -> Request {
        let upstream = "\(source.owner)/\(source.name)"
        guard await Task.detached(operation: { Versions.savedVersion(of: project.dir) }).value == prepared.version else {
            throw Failure(message: "\(project.name) changed since Lamp looked. Close this and send the changes again.")
        }
        var fork = fork
        if fork == nil {
            step("Forking \(upstream) to your account…")
            let forked = await Subprocess.run(gh, ["repo", "fork", upstream, "--clone=false", "--default-branch-only"], timeout: 120)
            guard forked.ok else { throw Failure(message: "GitHub didn't fork \(upstream): \(forked.output.trimmed.suffix(200))") }
            // A fork takes a moment to exist; one the person already had, under another name, is what gh names.
            let named = forked.output.split(whereSeparator: \.isWhitespace).map(String.init)
                .first { $0.lowercased().hasPrefix(login.lowercased() + "/") }
            fork = named ?? "\(login)/\(source.name)"
            var found = false
            for _ in 0..<20 where !found {
                try? await Task.sleep(for: .seconds(3))
                found = await Subprocess.run(gh, ["api", "repos/\(fork!)", "--jq", ".full_name"], mergeErrors: false, timeout: 30).ok
            }
            guard found else { throw Failure(message: "The fork of \(upstream) isn't ready yet. Try again in a moment.") }
        }
        guard let fork else { throw Failure(message: "Lamp couldn't find your fork of \(upstream).") }

        step("Uploading…")
        let branch = "lamp/\(Publish.slug(project.name))-\(UUID().uuidString.prefix(6).lowercased())"
        let pushed = await Subprocess.run(GitHubRepo.git, ["-c", "core.hooksPath=/dev/null"] + GitHubRepo.signedIn(gh: gh)
                                          + ["push", "-q", "https://github.com/\(fork).git", "\(prepared.commit):refs/heads/\(branch)"],
                                          cwd: prepared.clone, timeout: 600)
        guard pushed.ok else { throw Failure(message: "GitHub didn't take it: \(pushed.output.trimmed.suffix(200))") }

        step("Opening the pull request…")
        let body = prepared.folder.appendingPathComponent("body.md")
        try prepared.body.write(to: body, atomically: true, encoding: .utf8)
        let head = fork.split(separator: "/").first.map(String.init) ?? login
        let opened = await Subprocess.run(gh, ["pr", "create", "--repo", upstream, "--head", "\(head):\(branch)", "--base", prepared.baseBranch,
                                               "--title", prepared.title, "--body-file", body.path], timeout: 120)
        guard opened.ok, let url = opened.output.split(whereSeparator: \.isWhitespace).map(String.init).last(where: { $0.hasPrefix("https://") }) else {
            throw Failure(message: "GitHub didn't open the pull request: \(opened.output.trimmed.suffix(200))")
        }
        return Request(url: url, branch: branch, fork: fork)
    }

    // MARK: The wish's own change

    /// The version of the wish's own history its change is measured from, given the version being sent: the snapshot of
    /// the update whose commit that version's credits name (`Upstream.snapshot`), so an update taken back with Undo
    /// isn't counted; else the version it last arrived as (opened, or updated by replacing its files). A wish whose
    /// updates were all brought in before snapshots were kept measures from what the last one brought
    /// (`Upstream.ref`) when its credits moved on since it arrived. Nil when nothing says what it arrived as.
    static func base(of project: LampProject, at version: String) async -> String? {
        func run(_ command: String) async -> (status: Int32, output: String) { await Upstream.run(command, in: project) }
        func commit(at version: String) async -> String? {
            let file = await run("git show \(version):\(Credits.file)")
            guard file.status == 0 else { return nil }
            return Credits.decoded(Data(file.output.utf8))?.origin(own: GitHubRepo.kept(for: project)?.url)?.commit
        }
        let named = await commit(at: version)
        if let named = Credits.validCommit(named) {
            let snapshot = await run("git rev-parse --verify -q \(Upstream.snapshot(named))^{commit}")
            if snapshot.status == 0, let found = Credits.validCommit(snapshot.output) { return found }
        }
        let arrival = await Versions.list(project).first { Store.arrivalMessages.contains($0.message) }?.id
        let snapshots = await run("git for-each-ref --count=1 --format=%(refname) refs/lamp/snapshot/")
        let last = await run("git rev-parse --verify -q \(Upstream.ref)^{commit}")
        if snapshots.status == 0, snapshots.output.trimmed.isEmpty, last.status == 0, let last = Credits.validCommit(last.output) {
            guard let arrival else { return last }
            let dates = await run("git log --no-walk=unsorted -2 --format=%ct \(last) \(arrival)").output.split(separator: "\n").compactMap { Int(String($0).trimmed) }
            let moved = await commit(at: arrival) != named
            if dates.count == 2, dates[0] > dates[1], moved { return last }
        }
        return arrival
    }

    /// The wish's change since `base`, for the version being sent: two folders laid out as its repository is
    /// (`Sharing.layout`, as the export lays it out), each holding the files the change touches as they were then
    /// (`base`) and as they are now (`ours`), with a file the change adds or takes out missing from one. Only what a
    /// shared file carries counts (`exported`, the export of this version): never Lamp's own files, the chat's
    /// attachments or anything the wish keeps for itself; and a file of Lamp's settings written in another layout
    /// (`icon.json`, `capabilities.json`) is changed only when what it says changed.
    struct Change {
        var base: URL
        var ours: URL
        /// The paths it touches in the repository, in order.
        var paths: [String]
        /// The manifest the change is measured from (`baseManifest`); nil when Lamp didn't keep it, and the
        /// repository's stands in.
        var manifest: [String: Any]?
        /// The commit of the repository the version's credits name, for the repository's manifest to stand in.
        var namedCommit: String?
        /// Where the repository keeps Lamp's files (the manifest, credits, icon, shared file): its root, or a site's
        /// folder of Lamp's (`StaticSite.folder`).
        var meta = ""
        /// Credits for work the change newly uses, as the repository will name it.
        var credits = Credits()
    }

    static func change(of project: LampProject, at version: String, exported: URL, repository: URL, in folder: URL) async throws -> Change {
        let fm = FileManager.default
        let indexes = project.dir.appendingPathComponent(".lamp/contribute")
        try? fm.removeItem(at: indexes)
        try fm.createDirectory(at: indexes, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: indexes) }
        guard let base = await base(of: project, at: version) else {
            throw Failure(message: "Lamp can't tell which changes in \(project.name) are yours. Open it from GitHub again to send changes back.")
        }
        let baseTree = try await Upstream.filteredTree(of: base, in: project, indexes: indexes)
        let oursTree = try await Upstream.filteredTree(of: version, in: project, indexes: indexes)
        let listed = await Upstream.run("git diff-tree -r -z --no-renames --name-status \(baseTree) \(oursTree)", in: project)
        guard listed.status == 0 else { throw Failure(message: "Lamp couldn't read what changed in \(project.name).") }
        let fields = listed.output.split(separator: "\0").map { String($0).trimmingCharacters(in: .newlines) }
        var statuses: [(status: Character, path: String)] = []
        var index = 0
        while index + 1 < fields.count {
            if let status = fields[index].first { statuses.append((status, fields[index + 1])) }
            index += 2
        }
        let raw = folder.appendingPathComponent("trees")
        for (name, tree) in [("base", baseTree), ("ours", oursTree)] {
            let out = raw.appendingPathComponent(name)
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            guard await Upstream.run("git archive --format=tar \(tree) | /usr/bin/tar -x -C \(Sandbox.quoted(out.path))", in: project).status == 0 else {
                throw Failure(message: "Lamp couldn't read what changed in \(project.name).")
            }
        }
        defer { try? fm.removeItem(at: raw) }

        // The wish's paths as the repository has them: the app at the file's root loses its folder (`Sharing.export`).
        let (root, parts) = Sharing.layout(of: project)
        let moved = root.dir.standardizedFileURL == project.dir.standardizedFileURL ? nil : root.dir.lastPathComponent + "/"
        func inRepository(_ path: String) -> String { moved.map { path.hasPrefix($0) ? String(path.dropFirst($0.count)) : path } ?? path }
        let carried = Set(regularFiles(in: exported))
        // A plain site's repository has the page at its root and the rest in Lamp's folder (`StaticSite.layOut`).
        let site = parts.isEmpty && ScreenKit.isSite(root)
        func laidOut(_ path: String) -> String {
            guard site else { return path }
            let web = TVTemplate.webFolder + "/"
            return path.hasPrefix(web) ? String(path.dropFirst(web.count)) : path == "LICENSE" ? path : StaticSite.folder + "/" + path
        }

        // An Android app's code here is in this Mac's package for it (`AndroidFiles.install`), and the repository's in
        // the one its build file names: each touched file goes back to that one, its path and the package in it, with
        // the id Lamp set for this Mac taken out of the build file.
        var androids: [(prefix: String, ours: String, theirs: String)] = []
        for app in [root] + parts where app.platform.target.recipe.language == .kotlin {
            let prefix = app.id == root.id ? "" : app.dir.lastPathComponent + "/"
            let build = repository.appendingPathComponent(prefix + Template.androidAppFolder + "/build.gradle.kts")
            guard let text = try? String(contentsOf: build, encoding: .utf8), let theirs = AndroidFiles.namespace(in: text) else { continue }
            androids.append((prefix, Template.androidPackage(for: app), theirs))
        }
        func toRepository(_ target: String, _ file: URL?) throws -> (path: String, text: String?) {
            guard let android = androids.first(where: { target.hasPrefix($0.prefix + Template.androidAppFolder + "/") }),
                  AndroidFiles.codeExtensions.contains((target as NSString).pathExtension.lowercased()) else { return (laidOut(target), nil) }
            let inApp = String(target.dropFirst(android.prefix.count))
            let path = android.prefix + AndroidFiles.movedPath(inApp, from: android.ours, to: android.theirs)
            guard let file, let text = try? String(contentsOf: file, encoding: .utf8) else { return (path, nil) }
            var renamed = text
            if inApp == Template.androidAppFolder + "/build.gradle.kts" {
                renamed = renamed.replacingOccurrences(of: AndroidFiles.applicationIDBlock(android.ours), with: "")
            }
            return (path, AndroidFiles.renamePackage(in: renamed, from: android.ours, to: android.theirs))
        }

        var change = Change(base: folder.appendingPathComponent("base"), ours: folder.appendingPathComponent("ours"), paths: [],
                            meta: site ? StaticSite.folder + "/" : "")
        var added: Set<String> = []
        for (status, path) in statuses {
            // The line travels in the manifest, which the export of this version says (`manifest`).
            if path == AppDescription.file { continue }
            let target = inRepository(path)
            let removed = status == "D"
            guard removed || carried.contains(target) else { continue }
            // What goes is the export's file, never the version's own bytes: the export is what passed the checks for
            // keys, and what it rewrites (capabilities.json, written from what passed its checks) goes as written.
            let from = raw.appendingPathComponent("base/" + path), to = removed ? raw.appendingPathComponent("ours/" + path) : exported.appendingPathComponent(target)
            if status == "M", let before = try? Data(contentsOf: from), let after = try? Data(contentsOf: to) {
                if before == after { continue }
                if ["icon.json", Template.Capabilities.file].contains((path as NSString).lastPathComponent),
                   let one = try? JSONSerialization.jsonObject(with: before) as? NSObject,
                   let other = try? JSONSerialization.jsonObject(with: after) as? NSObject, one.isEqual(other) {
                    continue
                }
            }
            if !removed { added.insert(target) }
            var mapped = target
            for (side, file) in [(change.base, from), (change.ours, to)] {
                let present = (try? file.checkResourceIsReachable()) == true || (try? fm.destinationOfSymbolicLink(atPath: file.path)) != nil
                let back = try toRepository(target, present ? file : nil)
                mapped = back.path
                guard present else { continue }
                let place = side.appendingPathComponent(back.path)
                try fm.createDirectory(at: place.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: place)
                if let text = back.text { try text.write(to: place, atomically: false, encoding: .utf8) } else { try fm.copyItem(at: file, to: place) }
            }
            change.paths.append(mapped)
        }
        change.paths = Array(Set(change.paths)).sorted()

        // Credits for work the change newly uses: what the export names that the base didn't, as the export names it in
        // the repository's layout. The base's are what it had then (the credits.json of the version it arrived as, or
        // the one kept with the update's snapshot), never Lamp's running record, which takes in work added here too.
        let based = await Upstream.run("git show \(base):\(Credits.file)", in: project)
        let theirs = based.status == 0 ? Credits.decoded(Data(based.output.utf8)) ?? Credits() : Credits()
        let ours = Credits.read(exported.appendingPathComponent(Credits.file)) ?? Credits()
        change.credits = Credits(upstream: ours.upstream.filter { source in !theirs.upstream.contains { $0.sameWork(as: source) } },
                                 generated: ours.generated.filter { added.contains($0.file) })
        change.manifest = await baseManifest(of: project, base: base)
        let named = await Upstream.run("git show \(version):\(Credits.file)", in: project)
        change.namedCommit = Credits.validCommit(Credits.decoded(Data(named.output.utf8))?.origin(own: GitHubRepo.kept(for: project)?.url)?.commit)
        return change
    }

    /// The manifest the wish's change is measured from: the one its last update came with (kept beside the update's
    /// snapshot, `Upstream.snapshot`), or the one it last arrived with (`Sharing.arrivedManifest`) when it's measured
    /// from its arrival. Nil when Lamp kept neither.
    static func baseManifest(of project: LampProject, base: String) async -> [String: Any]? {
        let kept = await Upstream.run("git show \(base):lamp-app.json", in: project)
        if kept.status == 0, let manifest = try? JSONSerialization.jsonObject(with: Data(kept.output.utf8)) as? [String: Any] { return manifest }
        let arrival = await Versions.list(project).first { Store.arrivalMessages.contains($0.message) }?.id
        guard base == arrival, let data = try? Data(contentsOf: project.dir.appendingPathComponent(Sharing.arrivedManifest)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// What a manifest says of the app that a change can change: its line, its kind, the device it opens on first, its
    /// other apps and whether it's a plain site. Its identity, name, format and date are the file's own.
    static let manifestKeys = ["description", "platform", "family", "parts", "site"]

    static func manifestOf(_ folder: URL) -> [String: Any] {
        (try? Data(contentsOf: folder.appendingPathComponent("lamp-app.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    private static func same(_ one: Any?, _ other: Any?) -> Bool {
        switch (one, other) {
        case (nil, nil): true
        case let (one?, other?): (one as AnyObject).isEqual(other)
        default: false
        }
    }

    /// The keys the wish changed since `base`.
    static func manifestChanges(ours: [String: Any], base: [String: Any]) -> [String] {
        manifestKeys.filter { !same(ours[$0], base[$0]) }
    }

    /// Every regular file in a folder, by its path in it.
    static func regularFiles(in folder: URL) -> [String] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return [] }
        var paths: [String] = []
        for case let file as URL in items {
            let values = try? file.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true || values?.isSymbolicLink == true { paths.append(Sharing.relativePath(of: file, in: folder)) }
        }
        return paths.sorted()
    }

    // MARK: Replaying it on the repository

    /// The change replayed on `tip` in a clone: the tip's tree with the touched files as they were (the base side) and
    /// as they are now (ours), merged three ways by git against the first (`git merge-tree`), so only what the wish
    /// changed moves, and a file the repository changed elsewhere since keeps that. The merged tree, or the files both
    /// changed in the same place.
    static func replay(_ change: Change, in clone: URL, tip: String, git: String) async throws -> (tree: String, conflicts: [String]) {
        let gitDir = clone.appendingPathComponent(".git")
        func run(_ arguments: [String], in cwd: URL = clone, index: String? = nil, input: Data? = nil) async throws -> String {
            let env = index.map { ["GIT_INDEX_FILE": gitDir.appendingPathComponent($0).path] }
            let ran = await Subprocess.run(git, ["--git-dir=\(gitDir.path)", "--work-tree=."] + arguments, cwd: cwd, env: env, mergeErrors: false,
                                           timeout: 300, input: input)
            guard ran.ok else { throw Failure(message: "Couldn't prepare the pull request: \((ran.errors + ran.output).trimmed.suffix(200))") }
            return ran.output.trimmed
        }
        let paths = Data(change.paths.map { $0 + "\0" }.joined().utf8)
        var sides: [String] = []
        for (name, folder) in [("lamp-base", change.base), ("lamp-ours", change.ours)] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            _ = try await run(["read-tree", tip], index: name)
            _ = try await run(["update-index", "--add", "--remove", "--replace", "-z", "--stdin"], in: folder, index: name, input: paths)
            sides.append(try await run(["write-tree"], index: name))
            try? FileManager.default.removeItem(at: gitDir.appendingPathComponent(name))
        }
        // Each side as a commit of its own, as the upstream merge passes them (`Upstream.merge`): a git from before
        // merge-tree took trees takes only commits. Lamp's own, never pushed, so they're never signed.
        let lamp = ["-c", "user.name=Lamp", "-c", "user.email=lamp@localhost", "-c", "commit.gpgSign=false"]
        let baseMark = try await run(lamp + ["commit-tree", sides[0], "-m", "As the change began"])
        let oursMark = try await run(lamp + ["commit-tree", sides[1], "-p", baseMark, "-m", "As the change is"])
        let merged = await Subprocess.run(git, ["--git-dir=\(gitDir.path)", "merge-tree", "--write-tree", "--name-only", "-z", "--merge-base=\(baseMark)", tip, oursMark],
                                          cwd: clone, mergeErrors: false, timeout: 300)
        guard [0, 1].contains(merged.status) else { throw Failure(message: "Git couldn't put the changes on the latest: \(merged.errors.trimmed.suffix(200))") }
        let parts = merged.output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        guard let tree = parts.first.flatMap({ Credits.validCommit($0.trimmed) }) else { throw Failure(message: "Git couldn't put the changes on the latest.") }
        var conflicts: [String] = []
        if merged.status == 1 {
            for part in parts.dropFirst() {
                if part.isEmpty { break }
                if !conflicts.contains(part) { conflicts.append(part) }
            }
        }
        return (tree, conflicts)
    }

    /// What the change says beyond its files, written into the clone's tree: the manifest's line, format and apps; the
    /// credits for work it newly uses; and the icon's pictures when its design changed. Each file is left as the
    /// repository has it unless something in it changes. The paths written.
    /// Nil when the repository changed something in the manifest the wish changed too, to something else.
    static func finish(_ change: Change, in clone: URL, exported: URL) throws -> Set<String>? {
        let fm = FileManager.default
        var written: Set<String> = []
        let meta = clone.appendingPathComponent(change.meta)
        // A site opened as it is may have no folder of Lamp's in its repository yet (`StaticSite.unpack`): the credits
        // or the icon's pictures the change brings make it.
        try fm.createDirectory(at: meta, withIntermediateDirectories: true)
        let manifestURL = meta.appendingPathComponent("lamp-app.json")
        if let data = try? Data(contentsOf: manifestURL), let theirs = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            guard let updated = manifest(theirs, ours: manifestOf(exported), change: change) else { return nil }
            if !(updated as NSDictionary).isEqual(to: theirs) {
                try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                    .write(to: manifestURL, options: .atomic)
                written.insert(change.meta + "lamp-app.json")
            }
        }
        let creditsURL = meta.appendingPathComponent(Credits.file)
        let theirs = Credits.read(creditsURL) ?? Credits()
        let new = Credits(upstream: change.credits.upstream.filter { source in !theirs.upstream.contains { $0.sameWork(as: source) } },
                          generated: change.credits.generated.filter { !theirs.generated.contains($0) })
        if !new.isEmpty {
            var credits = theirs
            credits.upstream += new.upstream
            credits.generated += new.generated
            try credits.checked.encoded().write(to: creditsURL, options: .atomic)
            written.insert(change.meta + Credits.file)
        }
        // The icon's pictures live outside the versions; they go with a design the change made.
        if change.paths.contains(change.meta + "icon.json") {
            for name in [LampFile.iconEntry, "icon-art.png", Sharing.glassEntry] {
                let from = exported.appendingPathComponent(name), to = meta.appendingPathComponent(name)
                let had = fm.fileExists(atPath: to.path)
                guard had || fm.fileExists(atPath: from.path) else { continue }
                try? fm.removeItem(at: to)
                if fm.fileExists(atPath: from.path) { try fm.copyItem(at: from, to: to) }
                written.insert(change.meta + name)
            }
        }
        return written
    }

    /// The repository's manifest with what the wish changed in it since the change's base (`manifestKeys`: its line,
    /// kind, device, apps), each taken as the wish has it, and the format the code now needs. Its identity, name and
    /// date stay the repository's. Nil when the repository changed one of those keys since, to something other than
    /// the wish did.
    static func manifest(_ theirs: [String: Any], ours: [String: Any], change: Change) -> [String: Any]? {
        let base = change.manifest ?? theirs
        var updated = theirs
        let changed = manifestChanges(ours: ours, base: base)
        for key in changed {
            guard same(theirs[key], base[key]) || same(theirs[key], ours[key]) else { return nil }
            if let value = ours[key] { updated[key] = value } else { updated.removeValue(forKey: key) }
        }
        if !change.paths.isEmpty || !changed.isEmpty, let format = ours["format"] as? Int, format > (theirs["format"] as? Int ?? 0) {
            updated["format"] = format
        }
        return updated
    }

    /// The shared file beside the repository's code, when it has one, made again with the change in it: each file the
    /// change touched as the tree now has it (taken out where the tree no longer has it), everything else as it was,
    /// zipped as Lamp zips one (`Sharing.zip`). A repository with no shared file gets none.
    /// A site's is in Lamp's folder (`meta`), holding the page in Web/ as any shared file does.
    static func remakeSharedFile(in clone: URL, touched: Set<String>, meta: String = "", work: URL) throws {
        let fm = FileManager.default
        func inFile(_ path: String) -> String {
            guard !meta.isEmpty else { return path }
            return path.hasPrefix(meta) ? String(path.dropFirst(meta.count)) : path == "LICENSE" ? path : TVTemplate.webFolder + "/" + path
        }
        guard let file = ((try? fm.contentsOfDirectory(at: clone.appendingPathComponent(meta), includingPropertiesForKeys: nil)) ?? [])
            .filter({ $0.pathExtension == "lampapp" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first else { return }
        let unpacked = work.appendingPathComponent("shared-file")
        try? fm.removeItem(at: unpacked)
        defer { try? fm.removeItem(at: unpacked) }
        guard Subprocess.runBlocking("/usr/bin/ditto", ["-x", "-k", file.path, unpacked.path], timeout: 120).ok else {
            throw Failure(message: "Couldn't read the repository's \(file.lastPathComponent).")
        }
        for path in touched.sorted() {
            let from = clone.appendingPathComponent(path), to = unpacked.appendingPathComponent(inFile(path))
            try? fm.removeItem(at: to)
            guard fm.fileExists(atPath: from.path) else { continue }
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: from, to: to)
        }
        let made = work.appendingPathComponent("remade.lampapp")
        try? fm.removeItem(at: made)
        try Sharing.zip(unpacked, to: made)
        try? fm.removeItem(at: file)
        try fm.moveItem(at: made, to: file)
    }

    /// What the pull request says: where the wish came from and what changed, in plain words, from the wish's chain,
    /// the names of its versions since it arrived (what people and Lamp called them, never the requests themselves)
    /// and the files changed. Never the chat.
    static func summary(of project: LampProject, from source: RepoImport.Source, changed: [String]) async -> (title: String, body: String) {
        let credits = Credits.load(project)
        var names: [String] = []
        for remix in credits.remixOf {
            let name = remix.name + (remix.starter != nil ? " (a Lamp starter)" : "")
            if names.last != name { names.append(name) }
        }
        var body = "\(project.name) was remixed with [Lamp](https://lamp.dev) from \(source.owner)/\(source.name) and changed there; "
            + "these are the remix's own changes, on top of the latest here, sent back from Lamp.\n\n"
        if let line = AppDescription.description(of: project) { body += line + "\n\n" }
        if !names.isEmpty { body += "Line: " + names.joined(separator: " → ") + ".\n\n" }
        let versions = await Versions.list(project)
        var titles: [String] = []
        for version in versions {
            if Store.arrivalMessages.contains(version.message) { break }
            guard let title = version.name ?? version.title, !version.isLampNote else { continue }
            if !titles.contains(title) { titles.append(title) }
        }
        if !titles.isEmpty {
            body += "What changed, by version:\n" + titles.reversed().prefix(30).map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if !changed.isEmpty {
            body += "Files changed: " + changed.prefix(40).map { "`\($0)`" }.joined(separator: ", ") + (changed.count > 40 ? ", and \(changed.count - 40) more" : "") + ".\n\n"
        }
        body += "To try it, open this repository with Lamp (File → Open from GitHub…) once it has the changes, or build it with `./build.sh`."
        return ("\(project.name): changes from a remix", body)
    }
}

/// The Send Changes Back card of each wish while it's open, in the chat's place. Preparing it finds `gh` and the
/// person's sign-in, looks for their fork and works out what would go with its checks (`Contribute.prepare`), so the
/// card shows exactly what will go before the person confirms.
@MainActor final class ContributeCards: ObservableObject {
    static let shared = ContributeCards()

    struct Card {
        var stage: ContributeCard.Stage = .preparing
        var source: RepoImport.Source?
        var fork: String?
        var login: String?
        var gh: String?
        var prepared: Contribute.Prepared?
        var request: Contribute.Request?
        var copied = false
        var icon: Data?

        /// Ready, or failed with what would go still prepared, so Send Changes Back tries again.
        var canSend: Bool {
            switch stage {
            case .ready: true
            case .failed: prepared != nil
            default: false
            }
        }
    }

    @Published private(set) var cards: [String: Card] = [:]

    func card(for project: LampProject) -> Card? { cards[project.id] }

    func open(_ project: LampProject) {
        guard cards[project.id] == nil else { return }
        cards[project.id] = Card()
        Task { cards[project.id]?.icon = await Sharing.sharedIcon(of: project) }
        prepare(project)
    }

    /// Finds gh, the sign-in and the fork, and works out what will go.
    func prepare(_ project: LampProject) {
        guard cards[project.id] != nil else { return }
        cards[project.id]?.stage = .preparing
        if let old = cards[project.id]?.prepared { try? FileManager.default.removeItem(at: old.folder) }
        cards[project.id]?.prepared = nil
        Task {
            guard let source = Contribute.origin(of: project) else { return set(project, .refused("This app didn't come from a repository on GitHub.")) }
            guard let gh = await Publish.gh() else { return set(project, .needsGitHub(.install)) }
            guard let login = await Publish.login(gh: gh) else { return set(project, .needsGitHub(.signIn)) }
            guard login.lowercased() != source.owner.lowercased() else {
                return set(project, .refused("github.com/\(source.owner)/\(source.name) is your own repository: Put on GitHub updates it."))
            }
            let fork = await Contribute.fork(of: source, login: login, gh: gh)
            do {
                let prepared = try await Contribute.prepare(project, from: source, gh: gh, login: login)
                guard cards[project.id] != nil else {
                    try? FileManager.default.removeItem(at: prepared.folder)
                    return
                }
                cards[project.id]?.gh = gh
                cards[project.id]?.login = login
                cards[project.id]?.source = source
                cards[project.id]?.fork = fork
                cards[project.id]?.prepared = prepared
                cards[project.id]?.stage = .ready
            } catch {
                set(project, .refused(((error as? LocalizedError)?.recoverySuggestion).map { "\(error.localizedDescription) \($0)" } ?? error.localizedDescription))
            }
        }
    }

    private func set(_ project: LampProject, _ stage: ContributeCard.Stage) { cards[project.id]?.stage = stage }

    func send(_ project: LampProject) {
        guard let card = cards[project.id], card.canSend, let prepared = card.prepared, let source = card.source,
              let gh = card.gh, let login = card.login else { return }
        set(project, .working("Starting…"))
        Task {
            do {
                let id = project.id
                let request = try await Contribute.send(prepared, of: project, to: source, fork: card.fork, gh: gh, login: login) { step in
                    Task { @MainActor in ContributeCards.shared.cards[id]?.stage = .working(step) }
                }
                try? FileManager.default.removeItem(at: prepared.folder)
                cards[project.id]?.prepared = nil
                cards[project.id]?.fork = request.fork
                cards[project.id]?.request = request
                set(project, .done(request.url))
            } catch {
                // What would go stays prepared, so Send Changes Back can try again.
                set(project, .failed(error.localizedDescription))
            }
        }
    }

    func fix(_ project: LampProject) {
        guard case .needsGitHub(let need) = cards[project.id]?.stage else { return }
        Publish.obtain(need, stillNeeded: { [weak self] in
            if case .needsGitHub = self?.cards[project.id]?.stage { return true } else { return false }
        }, signedIn: { [weak self] in self?.prepare(project) })
    }

    func openRequest(_ project: LampProject) {
        if let url = (cards[project.id]?.request?.url).flatMap({ URL(string: $0) }) { NSWorkspace.shared.open(url) }
    }

    func copy(_ project: LampProject) {
        guard let url = cards[project.id]?.request?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        cards[project.id]?.copied = true
    }

    func close(_ project: LampProject) {
        if let prepared = cards[project.id]?.prepared { try? FileManager.default.removeItem(at: prepared.folder) }
        cards[project.id] = nil
    }

    /// The card as the chat draws it.
    func wire(_ card: Card, of project: LampProject) -> SidebarContribute {
        let credits = Credits.load(project)
        var notes = ShareCheck.notes(for: credits)
        if !credits.generated.isEmpty { notes.append(Credits.generatedLine(credits.generated.count) + ", marked as such.") }
        if let line = ShareCheck.warningLine(credits) { notes.append(line) }
        if card.stage == .ready, card.fork == nil, let login = card.login, let source = card.source {
            notes.append("You have no fork of \(source.owner)/\(source.name) yet: Lamp makes one on your account (\(login)/\(source.name)) first.")
        }
        let size = card.prepared.map { $0.changed.count == 1 ? "1 file changed" : "\($0.changed.count) files changed" }
        return SidebarContribute(name: project.name, icon: card.icon, stage: card.stage,
                                 upstream: card.source.map { "\($0.owner)/\($0.name)" }, fork: card.fork ?? card.request?.fork,
                                 credit: credits.basedOn, notes: notes, size: size, copied: card.copied, canSend: card.canSend)
    }
}
