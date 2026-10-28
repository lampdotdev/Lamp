import Foundation

/// The latest of a wish from where it came from, merged into it by git. The wish's own git gets that repository as its
/// `upstream` remote and fetches the commit the wish has of it (`Credits.Remix.commit`, recorded when the wish was
/// opened from there and after each merge), one commit deep. That commit's tree is read as the import reads one and
/// staged as the import would install it (`stage`: Lamp's own files, the repository's own files and Lamp's records left
/// out, an Android app's code in this Mac's package), and so is the reviewed package; each is a tree in the wish's git,
/// the second committed on top of the first (`ref`). Git then merges the wish's files, that base and that staged tree
/// three ways (`git merge-tree`): what changed only upstream or only here is in place with no agent, and only a file
/// both sides changed in the same place keeps conflict markers, which the agent settles (`Versions.rememberConflicts`).
///
/// A wish from a shared file, with no repository, is merged the same way against the best base there is: the version
/// of this wish's own history the file says it was made from (a file that came back from someone it was sent to,
/// `Sharing.export`), else what the last update brought in (`ref`), else the version that arrived.
///
/// Every git command runs as Lamp's own git does (`Versions.git`: confined to the wish's folder, the network open), and
/// nothing of the wish's own history goes anywhere: the remote is only fetched from. The wish's history stays a line:
/// the merge is saved as one version on top of the last (`Store.mergeUpdate`), never as a merge commit.
enum Upstream {
    /// The staged upstream, kept at a ref of Lamp's so the agent can read a file as it is upstream
    /// (`git show refs/lamp/upstream:<path>`), git never prunes it, and the next merge of a wish with no repository
    /// can measure against it.
    static let ref = "refs/lamp/upstream"
    static let remote = "upstream"

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Merged {
        /// Files the merge left conflict markers in, by their paths in the wish; empty for a clean merge.
        var conflicts: [String]
        /// What the merge measured both sides against.
        var base: Base
        /// The wish's other apps the package brings that aren't here yet, to be made as an update makes them
        /// (`Store.installParts`): the merge put nothing of theirs in place.
        var newParts: [Sharing.Package.Part]
    }

    enum Base: Equatable {
        /// The repository's commit the wish had, fetched.
        case upstream(String)
        /// A version of this wish's own history: the one the file says it was made from, or the arrival.
        case own(String)
        /// What the last update brought in.
        case lastBrought
        /// Nothing: every file is new on both sides.
        case none
    }

    /// Merges `package` (the review's, from `source` when the wish came from a repository) into the wish's files and
    /// index, unsaved. `commit` is the commit of the repository the wish has; `arrival` the version that arrived. The
    /// wish's files are expected saved: a merge that fails leaves them as they were.
    static func merge(_ package: Sharing.Package, into project: LampProject, from source: RepoImport.Source?, commit: String?,
                      arrival: String?) async throws -> Merged {
        let fm = FileManager.default
        // The merge's own indexes, in Lamp's folder in the wish, so the wish's index is never touched before the result
        // goes in; cleared with the staged folders when it's done, whichever way it went.
        let indexes = project.dir.appendingPathComponent(".lamp/merge")
        let work = Sharing.workFolder.appendingPathComponent("lamp-upstream-\(UUID().uuidString)")
        try? fm.removeItem(at: indexes)
        try fm.createDirectory(at: indexes, withIntermediateDirectories: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer {
            if fm.fileExists(atPath: work.path) { try? fm.removeItem(at: work) }
            if fm.fileExists(atPath: indexes.path) { try? fm.removeItem(at: indexes) }
        }
        let signed = "git -c user.name=Lamp -c user.email=lamp@localhost"
        let lastBrought = Credits.validCommit((await run("git rev-parse --verify -q \(ref)", in: project)).output)

        // The base: the repository's commit, fetched from it as a remote (fetched from, never pushed to); else the
        // version of this wish's own history the file was made from; else what the last update brought in; else the
        // version that arrived.
        var base = Base.none
        var baseMark: String? = nil
        if let source {
            let url = Sandbox.quoted(source.url + ".git")
            _ = await run("git remote set-url \(remote) \(url) 2>/dev/null || git remote add \(remote) \(url)", in: project)
            if let commit = Credits.validCommit(commit), await fetch(commit, in: project),
               let tree = try await stagedTree(of: commit, for: project, in: work, indexes: indexes) {
                let made = await run("\(signed) commit-tree \(tree) -p \(commit) -m 'Upstream as Lamp read it'", in: project)
                guard made.status == 0, let mark = Credits.validCommit(made.output) else { throw Failure(message: "Lamp couldn't prepare the merge.") }
                base = .upstream(commit)
                baseMark = mark
            }
        }
        // The version the file was made from, unless the last update brought in was made from that same version (a
        // file that comes back again names the version it was first given): what it brought is the base then, so a
        // change it took back isn't kept by mistake.
        if baseMark == nil, let own = await ownVersion(named: package.credits, in: project) {
            var repeated = false
            if let lastBrought { repeated = await ownBase(of: lastBrought, in: project) == own }
            if !repeated {
                baseMark = try await ownMark(own, in: project, indexes: indexes)
                base = .own(own)
            }
        }
        if baseMark == nil, let lastBrought {
            base = .lastBrought
            baseMark = lastBrought
        }
        if baseMark == nil, let own = await ownVersion(arrival, in: project) {
            baseMark = try await ownMark(own, in: project, indexes: indexes)
            base = .own(own)
        }
        if baseMark == nil {
            let tree = try await filteredTree(of: nil, in: project, indexes: indexes)
            let made = await run("\(signed) commit-tree \(tree) -m 'Nothing known'", in: project)
            guard made.status == 0, let mark = Credits.validCommit(made.output) else { throw Failure(message: "Lamp couldn't prepare the merge.") }
            baseMark = mark
        }
        guard let baseMark else { throw Failure(message: "Lamp couldn't prepare the merge.") }

        // The reviewed package, staged as the import installs it: never the raw tree. A part not here yet is made as
        // an update makes one, and left out of what's merged; it's in the tree kept as the next base all the same, so
        // a change to it here later isn't new on both sides.
        let (_, localParts) = Sharing.layout(of: project)
        let newParts = package.parts.filter { part in !localParts.contains { $0.dir.lastPathComponent == part.folder } }
        let staged = work.appendingPathComponent("theirs")
        try stage(package, for: project, into: staged, newParts: false)
        let theirsTree = try await tree(of: staged, in: project, indexes: indexes)
        // The commit says which version of this wish it was measured against, when it was one, for the next merge; one
        // measured against the last brought-in carries that one's forward, so a third file from the same copy still
        // measures against the last brought-in.
        var note = "The latest upstream as Lamp read it"
        var ownBase: String? = nil
        switch base {
        case .own(let own): ownBase = own
        case .lastBrought: if let lastBrought { ownBase = await self.ownBase(of: lastBrought, in: project) }
        default: break
        }
        if let ownBase { note += "\n\nLamp-Own-Base: \(ownBase)" }
        let madeTheirs = await run("\(signed) commit-tree \(theirsTree) -p \(baseMark) -m \(Sandbox.quoted(note))", in: project)
        guard madeTheirs.status == 0, let theirsMark = Credits.validCommit(madeTheirs.output) else { throw Failure(message: "Lamp couldn't prepare the merge.") }
        var keptMark = theirsMark
        if !newParts.isEmpty {
            let whole = work.appendingPathComponent("whole")
            try stage(package, for: project, into: whole, newParts: true)
            let wholeTree = try await tree(of: whole, in: project, indexes: indexes)
            let madeWhole = await run("\(signed) commit-tree \(wholeTree) -p \(baseMark) -m \(Sandbox.quoted(note))", in: project)
            if madeWhole.status == 0, let mark = Credits.validCommit(madeWhole.output) { keptMark = mark }
        }
        // The ref names the merge's other side for its markers; a merge that fails gives it back what it had.
        guard await run("git update-ref \(ref) \(theirsMark)", in: project).status == 0 else { throw Failure(message: "Lamp couldn't prepare the merge.") }
        func putBackRef() async {
            if let lastBrought { _ = await run("git update-ref \(ref) \(lastBrought)", in: project) } else { _ = await run("git update-ref -d \(ref)", in: project) }
        }

        // The merge itself: a tree, clean or with markers in the files both sides changed, then that tree into the
        // index and the files. Read with NULs between its parts: the tree, the conflicted files, an empty part, then
        // git's own messages.
        let merged = await run("git merge-tree --write-tree --name-only -z --merge-base=\(baseMark) HEAD \(ref)", in: project)
        guard [0, 1].contains(merged.status) else {
            await putBackRef()
            throw Failure(message: "Git couldn't merge it: \(merged.output.trimmed.suffix(200))")
        }
        let parts = merged.output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        guard let tree = parts.first.flatMap(Credits.validCommit) else {
            await putBackRef()
            throw Failure(message: "Git couldn't merge it.")
        }
        var conflicts: [String] = []
        if merged.status == 1 {
            for part in parts.dropFirst() {
                if part.isEmpty { break }
                if !conflicts.contains(part) { conflicts.append(part) }
            }
        }
        guard await run("git read-tree --reset -u \(tree)", in: project).status == 0 else {
            _ = await run("git read-tree --reset -u HEAD", in: project)
            await putBackRef()
            throw Failure(message: "Lamp couldn't put the merged files in place.")
        }
        if keptMark != theirsMark { _ = await run("git update-ref \(ref) \(keptMark)", in: project) }
        // The icon's pictures live outside the versions: the package's go in when its icon changed upstream, for the
        // design as git merged it (icon.json is in the files), never in place of a design changed here. The
        // description the same way, from the shared file's manifest.
        let baseIcon = await run("git show \(baseMark):icon.json", in: project)
        let newIcon = try? Data(contentsOf: package.folder.appendingPathComponent("icon.json"))
        if let newIcon, !(baseIcon.status == 0 && Data(baseIcon.output.utf8) == newIcon), !conflicts.contains("icon.json") {
            _ = try? Sharing.installArtwork(package, into: project)
        }
        if let description = package.description, description != AppDescription.description(of: project) {
            var before: String? = nil
            if case .upstream(let commit) = base {
                let manifest = await run("git show \(commit):lamp-app.json", in: project)
                if manifest.status == 0, let json = (try? JSONSerialization.jsonObject(with: Data(manifest.output.utf8))) as? [String: Any] {
                    before = (json["description"] as? String).flatMap(AppDescription.valid)
                }
            }
            // Changed upstream and not here: the new words. Changed here, the person's stay.
            if AppDescription.description(of: project) == nil || before == AppDescription.description(of: project) {
                try? AppDescription.write(description, for: project)
            }
        }
        return Merged(conflicts: conflicts, base: base, newParts: newParts)
    }

    /// Fetches one commit of the upstream remote, one deep, with nothing of the person's (git never asks for a
    /// sign-in). False when the repository won't give it (private now, offline, or a commit it no longer has).
    private static func fetch(_ commit: String, in project: LampProject) async -> Bool {
        let status = await Versions.git("git fetch -q --depth 1 \(remote) \(commit)", cwd: project.dir, env: ["GIT_TERMINAL_PROMPT": "0"], started: { process in
            Task {
                try? await Task.sleep(for: .seconds(600))
                Subprocess.terminateTree(process)
            }
        }, onLine: { _ in })
        return status == 0
    }

    /// The version of this wish's own history a shared file says it was made from, when it's one: the file's chain
    /// names this wish (a copy keeps the identity, `Sharing.identity`) with the commit the share was made at
    /// (`Sharing.export`), which is a version here when the file came back from someone this wish was sent to.
    static func ownVersion(named credits: Credits?, in project: LampProject) async -> String? {
        guard let identity = Sharing.identity(of: project, create: false), let credits else { return nil }
        let mine = Credits.Remix(name: project.name, wish: identity)
        guard let commit = credits.remixOf.last(where: { $0.sameWish(as: mine) })?.commit else { return nil }
        return await ownVersion(commit, in: project)
    }

    /// The version of this wish's own history a kept upstream was measured against, when it was one.
    private static func ownBase(of commit: String, in project: LampProject) async -> String? {
        let said = await run("git log -1 --format=%(trailers:key=Lamp-Own-Base,valueonly) \(commit)", in: project)
        return said.status == 0 ? Credits.validCommit(said.output.trimmed) : nil
    }

    /// `commit` when it's a version of this wish's own history.
    private static func ownVersion(_ commit: String?, in project: LampProject) async -> String? {
        guard let commit = Credits.validCommit(commit) else { return nil }
        return await run("git merge-base --is-ancestor \(commit) HEAD", in: project).status == 0 ? commit : nil
    }

    /// A version of this wish's own history as a merge base: its tree as a shared file carries it, committed on its own.
    private static func ownMark(_ version: String, in project: LampProject, indexes: URL) async throws -> String {
        let tree = try await filteredTree(of: version, in: project, indexes: indexes)
        let made = await run("git -c user.name=Lamp -c user.email=lamp@localhost commit-tree \(tree) -m 'This wish as it was shared'", in: project)
        guard made.status == 0, let mark = Credits.validCommit(made.output) else { throw Failure(message: "Lamp couldn't prepare the merge.") }
        return mark
    }

    /// The repository's commit as the import would install it: its tree read as a repository is (`RepoImport.open`)
    /// and staged (`stage`), so the base and the new code are laid out alike, whatever the kind of app does on the
    /// way in. Nil for a tree Lamp can't read as a wish (one put up before lamp-app.json), which the arrival stands
    /// in for.
    private static func stagedTree(of commit: String, for project: LampProject, in work: URL, indexes: URL) async throws -> String? {
        let fm = FileManager.default
        let unpacked = work.appendingPathComponent("base-tree")
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let out = Sandbox.quoted(unpacked.path)
        guard await run("git archive --format=tar \(commit) | /usr/bin/tar -x -C \(out)", in: project).status == 0 else { return nil }
        guard let package = try? RepoImport.open(folder: unpacked) else { return nil }
        defer { try? fm.removeItem(at: package.folder) }
        let staged = work.appendingPathComponent("base")
        try stage(package, for: project, into: staged)
        return try await tree(of: staged, in: project, indexes: indexes)
    }

    /// The tree of a version of this wish's own history as a shared file carries it: without Lamp's own files, the
    /// repository's own, credits.json (Lamp's to merge), the chat's attachments or Lamp's records. Nil for no
    /// version gives the empty tree. Made in an index of its own, so the wish's isn't touched.
    static func filteredTree(of commit: String?, in project: LampProject, indexes: URL) async throws -> String {
        let index = Sandbox.quoted(indexes.appendingPathComponent("own").path)
        guard let commit else {
            let empty = await run("git hash-object -t tree /dev/null", in: project)
            guard empty.status == 0, let tree = Credits.validCommit(empty.output) else { throw Failure(message: "Lamp couldn't prepare the merge.") }
            return tree
        }
        let listed = await run("rm -f \(index) && GIT_INDEX_FILE=\(index) git read-tree \(commit) && GIT_INDEX_FILE=\(index) git ls-files", in: project)
        guard listed.status == 0 else { throw Failure(message: "Lamp couldn't read what came from there last.") }
        let dropped = listed.output.split(separator: "\n").map(String.init).filter { isLeftOut($0, in: project) }
        var command = ""
        if !dropped.isEmpty {
            command = "GIT_INDEX_FILE=\(index) git update-index --force-remove -- " + dropped.map(Sandbox.quoted).joined(separator: " ") + " && "
        }
        let written = await run(command + "GIT_INDEX_FILE=\(index) git write-tree", in: project)
        guard written.status == 0, let tree = Credits.validCommit(written.output) else { throw Failure(message: "Lamp couldn't read what came from there last.") }
        return tree
    }

    /// A staged folder as a tree in the wish's git, every file in it (the person's Mac-wide ignores don't apply to
    /// what the import accepted).
    static func tree(of folder: URL, in project: LampProject, indexes: URL) async throws -> String {
        let index = Sandbox.quoted(indexes.appendingPathComponent(folder.lastPathComponent).path)
        let gitDir = Sandbox.quoted(project.dir.appendingPathComponent(".git").path)
        let added = await run("rm -f \(index) && GIT_INDEX_FILE=\(index) git -C \(Sandbox.quoted(folder.path)) --git-dir=\(gitDir) --work-tree=. add -f -A . "
                              + "&& GIT_INDEX_FILE=\(index) git write-tree", in: project)
        guard added.status == 0, let tree = Credits.validCommit(added.output.split(separator: "\n").last.map(String.init)) else {
            throw Failure(message: "Lamp couldn't stage the new code.")
        }
        return tree
    }

    /// Whether a path in a version's tree is left out of the merge's base: what a shared file never carries. Lamp's
    /// own files are the ones for the app at that path (a part's, in its folder).
    static func isLeftOut(_ path: String, in project: LampProject) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        guard let first = parts.first else { return true }
        if [".lamp", ".build", "build", Attachments.folder, ".git"].contains(first) { return true }
        if parts.count == 1, [Credits.file, ".gitignore", "lamp-app.json", "README.md", "icon-art.png", Sharing.glassEntry].contains(first) || first.hasSuffix(".lampapp") {
            return true
        }
        let (root, others) = Sharing.layout(of: project)
        if let part = others.first(where: { $0.dir.lastPathComponent == first }), parts.count > 1 {
            let inside = parts.dropFirst().joined(separator: "/")
            return GitHubRepo.isOwned(inside, in: part) || inside == Credits.file || inside == ".gitignore"
        }
        return GitHubRepo.isOwned(path, in: root)
    }

    /// The new code as the import would install it into `project`: what the review read and accepted, laid out as the
    /// wish is, and nothing else from the tree. Each app's code from the one list the review read (`Package.sources`),
    /// an Android app's moved into this Mac's package as the install moves it (`AndroidFiles`), its own files, its
    /// notes, what it declares as Lamp writes it and the licenses the credits name; the wish's other apps the same way
    /// in their folders: those here already, and with `newParts` the others too (as the apps they'll be, by their
    /// folders), for the tree kept as the next base. Lamp's own files are never among them, nor the icon's pictures,
    /// which live outside the versions (`Sharing.installArtwork`), nor credits.json, which Lamp merges itself.
    static func stage(_ package: Sharing.Package, for project: LampProject, into folder: URL, newParts: Bool = false) throws {
        let fm = FileManager.default
        let lampsOwn: Set<String> = ["LampSupport.swift", Template.sceneSupportFile, Template.widgetSupportFile, Template.shareSupportFile]
        // A file may be listed twice (a license the credits name inside a part is in the wish's list and the part's; one
        // beside the app's own files is among them too): the later copy replaces the earlier, as the install's does.
        func put(_ file: URL, at relative: String, in to: URL, text: String? = nil) throws {
            guard !relative.split(separator: "/").contains(where: { $0 == ".." }) else { return }
            let target = to.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: target)
            if let text { try text.write(to: target, atomically: true, encoding: .utf8) } else { try fm.copyItem(at: file, to: target) }
        }
        func stage(_ app: Sharing.Package, for appProject: LampProject, into to: URL) throws {
            try fm.createDirectory(at: to, withIntermediateDirectories: true)
            if app.platform.target.recipe.language == .kotlin {
                let theirs = AndroidFiles.senderPackage(in: app)
                let ours = Template.androidPackage(for: appProject)
                for file in app.sources {
                    var relative = app.path(of: file)
                    guard relative.hasPrefix(Template.androidAppFolder + "/"), let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                    if let theirs { relative = AndroidFiles.movedPath(relative, from: theirs, to: ours) }
                    var renamed = theirs.map { AndroidFiles.renamePackage(in: text, from: $0, to: ours) } ?? text
                    if relative == Template.androidAppFolder + "/build.gradle.kts" { renamed = AndroidFiles.settingApplicationID(in: renamed, to: ours) }
                    try put(file, at: relative, in: to, text: renamed)
                }
            } else {
                for file in app.sources where !lampsOwn.contains(file.lastPathComponent) {
                    let relative = app.path(of: file)
                    guard !Template.watchSupportPaths.contains(relative) else { continue }
                    try put(file, at: relative, in: to)
                }
            }
            for file in app.attachments { try put(file, at: Sharing.Assets.folder + "/" + app.assetPath(of: file), in: to) }
            for file in app.androidData + app.webData { try put(file, at: Sharing.relativePath(of: file, in: app.folder), in: to) }
            for file in app.licences { try put(file, at: Sharing.relativePath(of: file, in: app.folder), in: to) }
            for name in ["APP.md", "icon.json"] {
                let file = app.folder.appendingPathComponent(name)
                if fm.fileExists(atPath: file.path) { try put(file, at: name, in: to) }
            }
            if !app.capabilities.isEmpty {
                let plain = JSONEncoder()
                plain.outputFormatting = [.prettyPrinted, .sortedKeys]
                try plain.encode(app.capabilities).write(to: to.appendingPathComponent(Template.Capabilities.file))
            }
        }
        let (root, parts) = Sharing.layout(of: project)
        try stage(package, for: root, into: folder)
        for part in package.parts {
            if let local = parts.first(where: { $0.dir.lastPathComponent == part.folder }) {
                try stage(part.package, for: local, into: folder.appendingPathComponent(part.folder))
            } else if newParts {
                // As the app it will be: its id is the one the update gives it (`Store.addPart`), which an Android
                // app's package comes from.
                let coming = LampProject(id: Parts.id(wish: project.id, folder: part.folder), name: project.name, exe: project.exe,
                                         dir: project.dir.appendingPathComponent(part.folder))
                try stage(part.package, for: coming, into: folder.appendingPathComponent(part.folder))
            }
        }
    }

    /// A git command in the wish's folder, as Lamp's git runs (`Versions.git`), with what it printed.
    private static func run(_ command: String, in project: LampProject) async -> (status: Int32, output: String) {
        let said = Said()
        let status = await Versions.git(command, cwd: project.dir) { said.add($0) }
        return (status, said.lines.joined(separator: "\n"))
    }

    private final class Said: @unchecked Sendable {
        private let lock = NSLock()
        private var kept: [String] = []
        func add(_ line: String) { lock.lock(); kept.append(line); lock.unlock() }
        var lines: [String] { lock.lock(); defer { lock.unlock() }; return kept }
    }
}
