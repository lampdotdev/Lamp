import Foundation

/// The latest of a wish from where it came from, merged into it by git. The wish's own git gets that repository as its
/// `upstream` remote and fetches the commit the wish has of it (`Credits.Remix.commit`, recorded when the wish was
/// opened from there and after each merge), one commit deep. That commit's tree is read as the import reads one
/// (`filtered`: Lamp's own files, the repository's own files and Lamp's records left out) and the reviewed package is
/// staged as the import would install it (`stage`), each as a tree in the wish's git, the second committed on top of
/// the first (`ref`). Git then merges the wish's files, that base and that staged tree three ways (`git merge-tree`):
/// what changed only upstream or only here is in place with no agent, and only a file both sides changed in the same
/// place keeps conflict markers, which the agent settles (`Versions.rememberConflicts`). A wish from a shared file,
/// with no repository, is merged the same way against the version that arrived.
///
/// Every git command runs as Lamp's own git does (`Versions.git`: confined to the wish's folder, the network open), and
/// nothing of the wish's own history goes anywhere: the remote is only fetched from. The wish's history stays a line:
/// the merge is saved as one version on top of the last (`Store.mergeUpdate`), never as a merge commit.
enum Upstream {
    /// The staged upstream, kept at a ref of Lamp's so the agent can read a file as it is upstream
    /// (`git show refs/lamp/upstream:<path>`) and git never prunes it.
    static let ref = "refs/lamp/upstream"
    static let remote = "upstream"

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Files the merge left conflict markers in, by their paths in the wish; empty for a clean merge.
    struct Merged {
        var conflicts: [String]
    }

    /// Merges `package` (the review's, from `source` when the wish came from a repository) into the wish's files and
    /// index, unsaved. `base` is the commit of the repository the wish has, fetched as the merge's base; without one
    /// (a wish from a file, or opened before Lamp recorded commits) the version that `arrival` names stands in, and
    /// without that, nothing: every file is then new on both sides, and the agent is left the ones that differ. The
    /// wish's files are expected saved: a merge that fails leaves them as they were.
    static func merge(_ package: Sharing.Package, into project: LampProject, from source: RepoImport.Source?, base: String?,
                      arrival: String?) async throws -> Merged {
        let fm = FileManager.default
        // The merge's own indexes, in Lamp's folder in the wish, so the wish's index is never touched before the result
        // goes in; cleared with the staged folder when it's done, whichever way it went.
        let indexes = project.dir.appendingPathComponent(".lamp/merge")
        let work = Sharing.workFolder.appendingPathComponent("lamp-upstream-\(UUID().uuidString)")
        try? fm.removeItem(at: indexes)
        try fm.createDirectory(at: indexes, withIntermediateDirectories: true)
        defer {
            if fm.fileExists(atPath: work.path) { try? fm.removeItem(at: work) }
            if fm.fileExists(atPath: indexes.path) { try? fm.removeItem(at: indexes) }
        }
        // The repository as a remote, fetched from and never pushed to; the commit the wish has of it is what both
        // sides are measured against.
        var baseCommit: String? = nil
        if let source {
            let url = Sandbox.quoted(source.url + ".git")
            _ = await run("git remote set-url \(remote) \(url) 2>/dev/null || git remote add \(remote) \(url)", in: project)
            if let base = Credits.validCommit(base) {
                let fetched = await fetch(base, in: project)
                if fetched { baseCommit = base }
            }
        }
        let fallback = baseCommit == nil ? Credits.validCommit(arrival) : nil
        let baseTree = try await filteredTree(of: baseCommit ?? fallback, in: project, indexes: indexes)

        // The reviewed package, staged as the import installs it: never the raw tree.
        let staged = work.appendingPathComponent("tree")
        try stage(package, into: staged)
        let theirsTree = try await tree(of: staged, in: project, indexes: indexes)

        let signed = "git -c user.name=Lamp -c user.email=lamp@localhost"
        let baseParent = baseCommit.map { " -p \($0)" } ?? ""
        let madeBase = await run("\(signed) commit-tree \(baseTree)\(baseParent) -m 'Upstream as Lamp read it'", in: project)
        guard madeBase.status == 0, let baseMark = Credits.validCommit(madeBase.output) else { throw Failure(message: "Lamp couldn't prepare the merge.") }
        let madeTheirs = await run("\(signed) commit-tree \(theirsTree) -p \(baseMark) -m 'The latest upstream as Lamp read it'", in: project)
        guard madeTheirs.status == 0, let theirsMark = Credits.validCommit(madeTheirs.output) else { throw Failure(message: "Lamp couldn't prepare the merge.") }
        guard await run("git update-ref \(ref) \(theirsMark)", in: project).status == 0 else { throw Failure(message: "Lamp couldn't prepare the merge.") }

        // The merge itself: a tree, clean or with markers in the files both sides changed, then that tree into the
        // index and the files. Conflict markers name the sides as the command names them: HEAD, and the ref.
        // Read with NULs between its parts: the tree, the conflicted files, an empty part, then git's own messages.
        let merged = await run("git merge-tree --write-tree --name-only -z --merge-base=\(baseMark) HEAD \(ref)", in: project)
        guard [0, 1].contains(merged.status) else { throw Failure(message: "Git couldn't merge it: \(merged.output.trimmed.suffix(200))") }
        let parts = merged.output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        guard let tree = parts.first.flatMap(Credits.validCommit) else { throw Failure(message: "Git couldn't merge it.") }
        var conflicts: [String] = []
        if merged.status == 1 {
            for part in parts.dropFirst() {
                if part.isEmpty { break }
                if !conflicts.contains(part) { conflicts.append(part) }
            }
        }
        guard await run("git read-tree --reset -u \(tree)", in: project).status == 0 else {
            _ = await run("git read-tree --reset -u HEAD", in: project)
            throw Failure(message: "Lamp couldn't put the merged files in place.")
        }
        // The icon lives outside the versions: the package's goes in when it changed upstream, else the wish keeps its
        // own. The description the same way, from the shared file's manifest.
        let baseIcon = await run("git show \(baseMark):icon.json", in: project)
        let newIcon = try? Data(contentsOf: package.folder.appendingPathComponent("icon.json"))
        if let newIcon, !(baseIcon.status == 0 && Data(baseIcon.output.utf8) == newIcon) {
            _ = try? Sharing.installIcon(package, into: project)
        }
        if let description = package.description, description != AppDescription.description(of: project) {
            var before: String? = nil
            if let baseCommit {
                let manifest = await run("git show \(baseCommit):lamp-app.json", in: project)
                if manifest.status == 0, let json = (try? JSONSerialization.jsonObject(with: Data(manifest.output.utf8))) as? [String: Any] {
                    before = (json["description"] as? String).flatMap(AppDescription.valid)
                }
            }
            // Changed upstream and not here: the new words. Changed here, the person's stay.
            if AppDescription.description(of: project) == nil || before == AppDescription.description(of: project) {
                try? AppDescription.write(description, for: project)
            }
        }
        return Merged(conflicts: conflicts)
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

    /// The tree of `commit` as the import reads a repository: without Lamp's own files, the repository's own (README,
    /// license, the shared file, lamp-app.json, .gitignore), credits.json (Lamp's to merge), the chat's attachments or
    /// Lamp's records. Nil for no commit gives the empty tree. Made in an index of its own, so the wish's isn't touched.
    static func filteredTree(of commit: String?, in project: LampProject, indexes: URL) async throws -> String {
        let index = Sandbox.quoted(indexes.appendingPathComponent("base").path)
        guard let commit else {
            let empty = await run("git hash-object -t tree /dev/null", in: project)
            guard empty.status == 0, let tree = Credits.validCommit(empty.output) else { throw Failure(message: "Lamp couldn't prepare the merge.") }
            return tree
        }
        let listed = await run("GIT_INDEX_FILE=\(index) git read-tree \(commit) && GIT_INDEX_FILE=\(index) git ls-files", in: project)
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
        let index = Sandbox.quoted(indexes.appendingPathComponent("theirs").path)
        let gitDir = Sandbox.quoted(project.dir.appendingPathComponent(".git").path)
        let added = await run("GIT_INDEX_FILE=\(index) git -C \(Sandbox.quoted(folder.path)) --git-dir=\(gitDir) --work-tree=. add -f -A . "
                              + "&& GIT_INDEX_FILE=\(index) git write-tree", in: project)
        guard added.status == 0, let tree = Credits.validCommit(added.output.split(separator: "\n").last.map(String.init)) else {
            throw Failure(message: "Lamp couldn't stage the new code.")
        }
        return tree
    }

    /// Whether a path in a repository's tree is left out of the merge's base: what the import never installs. Lamp's
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

    /// The new code as the import would install it: what the review read and accepted, laid out as the wish is, and
    /// nothing else from the tree. Each app's code from the one list the review read (`Package.sources`), its own
    /// files, its notes, what it declares as Lamp writes it and the licenses the credits name; the wish's other apps
    /// the same way in their folders. Lamp's own files are never among them, nor the icon's pictures, which live
    /// outside the versions (`Sharing.installIcon`), nor credits.json, which Lamp merges itself.
    static func stage(_ package: Sharing.Package, into folder: URL) throws {
        let fm = FileManager.default
        let lampsOwn: Set<String> = ["LampSupport.swift", Template.sceneSupportFile, Template.widgetSupportFile, Template.shareSupportFile]
        // A file may be listed twice (a license the credits name inside a part is in the wish's list and the part's; one
        // beside the app's own files is among them too): the later copy replaces the earlier, as the install's does.
        func put(_ file: URL, at relative: String, in to: URL) throws {
            guard !relative.split(separator: "/").contains(where: { $0 == ".." }) else { return }
            let target = to.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: target)
            try fm.copyItem(at: file, to: target)
        }
        func stage(_ app: Sharing.Package, into to: URL) throws {
            try fm.createDirectory(at: to, withIntermediateDirectories: true)
            for file in app.sources where !lampsOwn.contains(file.lastPathComponent) {
                let relative = app.path(of: file)
                guard !Template.watchSupportPaths.contains(relative) else { continue }
                try put(file, at: relative, in: to)
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
            if let browser = app.browser {
                try BrowserCompanions.Declaration.encoded(browser).write(to: to.appendingPathComponent(BrowserCompanions.Declaration.file))
            }
        }
        try stage(package, into: folder)
        for part in package.parts { try stage(part.package, into: folder.appendingPathComponent(part.folder)) }
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
