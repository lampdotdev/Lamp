import Foundation

/// A wish opened from where it lives on GitHub: the repository Put on GitHub made (`GitHubRepo`), by its address or
/// from a folder it was cloned into. The repository is fetched shallowly with Lamp's own git, confined as every git
/// command of Lamp's is (`Versions.git`: the sandbox, with the network open), into a folder of Lamp's; then the tree is
/// read as a shared file's contents are (`Sharing.open(unpacked:)`: the same review, the same checks, Lamp's own files
/// written afresh), or the shared file in it is opened when the tree holds only that. The repository's address and the
/// commit fetched go on the credits' chain, on the link for the wish opened, so a remix of a remix links each
/// repository and an update from there is merged from that commit (`Upstream`).
enum RepoImport {
    /// A repository on GitHub, with a branch, tag or commit when the address names one.
    struct Source: Equatable {
        let owner: String
        let name: String
        var ref: String? = nil
        /// Where it lives, as the credits name it: "https://github.com/owner/name".
        var url: String { "https://github.com/\(owner)/\(name)" }
    }

    /// The repository an address names: `https://github.com/owner/name`, with or without the scheme or `.git`, a
    /// branch or tag after `/tree/`, a commit after `/commit/`; or git's own way of naming it over SSH
    /// (`git@github.com:owner/name.git`, `ssh://git@github.com/owner/name.git`), which a clone's remote often is.
    /// Nil for anything else.
    static func source(from text: String) -> Source? {
        var line = text.trimmed
        guard !line.isEmpty, line.count <= 400 else { return nil }
        for ssh in ["ssh://git@github.com/", "git@github.com:"] where line.lowercased().hasPrefix(ssh) {
            line = "https://github.com/" + line.dropFirst(ssh.count)
        }
        if !line.contains("://") { line = "https://" + line }
        guard let url = URL(string: line), let host = url.host?.lowercased(), host == "github.com" || host == "www.github.com",
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        var parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts.removeFirst()
        var name = parts.removeFirst()
        if name.lowercased().hasSuffix(".git") { name.removeLast(4) }
        guard isOwner(owner), isName(name) else { return nil }
        var ref: String? = nil
        if parts.count >= 2, ["tree", "commit", "commits"].contains(parts[0]) {
            ref = parts.dropFirst().joined(separator: "/")
            guard isRef(ref!) else { return nil }
        } else if !parts.isEmpty {
            return nil
        }
        return Source(owner: owner, name: name, ref: ref)
    }

    static func source(from url: URL) -> Source? { source(from: url.absoluteString) }

    private static func isOwner(_ text: String) -> Bool {
        (1...39).contains(text.count) && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } && !text.hasPrefix("-")
    }

    private static func isName(_ text: String) -> Bool {
        (1...100).contains(text.count) && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
            && !text.hasPrefix("-") && !text.hasPrefix(".")
    }

    /// A branch, tag or commit as git takes it after `fetch`: plain characters, never an option or a step up.
    private static func isRef(_ text: String) -> Bool {
        (1...200).contains(text.count) && !text.hasPrefix("-") && !text.contains("..")
            && text.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { step in
                !step.isEmpty && step.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
            }
    }

    // MARK: Fetching

    /// Where a repository is fetched to: a folder of its own in Lamp's work folder (`Store.fetchedPrefix`, so a request
    /// kept beside it goes with it as with a fetched file), the tree inside it under the repository's name.
    static func cloneFolder() -> URL {
        Sharing.workFolder.appendingPathComponent(Store.fetchedPrefix + UUID().uuidString)
    }

    /// Fetches the repository's tree at `ref` (its default branch without one), one commit deep, into `folder`:
    /// nothing of its history, and nothing of the person's goes with the request (git never asks for a sign-in, so a
    /// private repository is refused rather than waited on). Returns the tree.
    static func clone(_ source: Source, into folder: URL) async throws -> URL {
        let fm = FileManager.default
        let tree = folder.appendingPathComponent(source.name)
        try fm.createDirectory(at: tree, withIntermediateDirectories: true)
        let remote = Sandbox.quoted(source.url + ".git")
        let ref = Sandbox.quoted(source.ref ?? "HEAD")
        let command = "git init -q && git remote add origin \(remote) && git fetch -q --depth 1 origin \(ref) && git checkout -q --detach FETCH_HEAD"
        let said = Said()
        // Ten minutes is plenty for a wish; a repository that takes longer isn't one, and is let go: git and whatever it
        // started with it, not only the shell they run under, which would leave them holding the output open.
        let status = await Versions.git(command, cwd: tree, env: ["GIT_TERMINAL_PROMPT": "0"], started: { process in
            Task {
                try? await Task.sleep(for: .seconds(600))
                Subprocess.terminateTree(process)
            }
        }, onLine: { said.add($0) })
        guard status == 0 else {
            try? fm.removeItem(at: folder)
            let detail = said.lines.last.map { String($0.suffix(200)) }
            if status == Versions.unconfined { throw Sharing.ImportError("Lamp couldn't fetch \(source.owner)/\(source.name).", detail: "Its sandbox couldn't be set up.") }
            throw Sharing.ImportError("Lamp couldn't get \(source.owner)/\(source.name) from GitHub.",
                                      detail: detail.map { $0.contains("not found") || $0.contains("Authentication") ? "Check the address: the repository may be private, or not there." : $0 }
                                        ?? "Check the address and that you're online.")
        }
        return tree
    }

    /// What git printed, gathered off the main actor's hands.
    private final class Said: @unchecked Sendable {
        private let lock = NSLock()
        private var kept: [String] = []
        func add(_ line: String) { lock.lock(); kept.append(line); lock.unlock() }
        var lines: [String] { lock.lock(); defer { lock.unlock() }; return kept }
    }

    // MARK: Reading a tree

    /// The wish in a folder laid out as Put on GitHub lays a repository out: the shared file's contents at the top
    /// (`lamp-app.json` and the code), read as a shared file is once copied into a folder of Lamp's own, with Lamp's
    /// own files, the repository's README and license and the shared file beside them left where they are. A folder
    /// holding only a shared file opens that file. The folder itself is never changed: it may be the person's.
    static func open(folder: URL) throws -> Sharing.Package {
        let fm = FileManager.default
        let repository = repository(of: folder)
        if fm.fileExists(atPath: folder.appendingPathComponent("lamp-app.json").path) {
            let copy = Sharing.workFolder.appendingPathComponent("forge-import-\(UUID().uuidString)")
            var opened = false
            defer { if !opened { try? fm.removeItem(at: copy) } }
            try copyTree(folder, to: copy)
            var package = try Sharing.open(unpacked: copy)
            package.credits = naming(package.credits, repository: repository?.url, commit: repository?.commit, name: package.name, identity: package.identity)
            opened = true
            return package
        }
        let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey])) ?? [])
            .filter { $0.pathExtension == "lampapp" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let file = files.first else {
            throw Sharing.ImportError("This isn't a wish Lamp can open.", detail: "A wish put on GitHub has lamp-app.json and its code at the top of the repository.")
        }
        var package = try Sharing.open(file)
        package.credits = naming(package.credits, repository: repository?.url, commit: repository?.commit, name: package.name, identity: package.identity)
        return package
    }

    /// Whether a fetched tree is a wish (laid out as Put on GitHub lays one out, or holding a shared file) rather than
    /// someone's own project, which `open` can't read.
    static func holdsWish(_ folder: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.appendingPathComponent("lamp-app.json").path) { return true }
        return ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).contains { $0.hasSuffix(".lampapp") }
    }

    /// The tree as a shared file unpacks: every regular file but the repository's own records and builds, and the shared
    /// file beside the code, which would double what's counted. Held to what a shared file may hold.
    private static func copyTree(_ from: URL, to: URL) throws {
        let fm = FileManager.default
        let skipped: Set<String> = [".git", ".build", "build", ".lamp", "node_modules"]
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey]
        guard let items = fm.enumerator(at: from, includingPropertiesForKeys: Array(keys)) else { throw Sharing.ImportError("Lamp couldn't read the folder.") }
        try fm.createDirectory(at: to, withIntermediateDirectories: true)
        var files = 0, bytes = 0
        for case let item as URL in items {
            let values = try? item.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true { items.skipDescendants(); continue }
            if values?.isDirectory == true, skipped.contains(item.lastPathComponent) { items.skipDescendants(); continue }
            guard values?.isRegularFile == true, item.pathExtension != "lampapp" else { continue }
            files += 1
            bytes += values?.fileSize ?? 0
            guard files <= Sharing.maxFiles, bytes <= Sharing.maxUnpackedBytes else {
                throw Sharing.ImportError("This folder holds more than a Lamp app would (over \(Sharing.maxFiles) files or 256 MB).")
            }
            let target = to.appendingPathComponent(Sharing.relativePath(of: item, in: from))
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: item, to: target)
        }
    }

    /// The chain with the wish opened named where it lives: its last link (the wish the file was shared from) takes the
    /// address it has none for, and the commit the tree is at, which is the truth whatever the file says (the file was
    /// written before that commit was made); a file with no chain gets the wish as its one link.
    static func naming(_ credits: Credits?, repository: String?, commit: String?, name: String, identity: String?) -> Credits? {
        guard let repository else { return credits }
        var credits = credits ?? Credits()
        if credits.remixOf.isEmpty {
            credits.remixOf = [Credits.Remix(name: name, wish: identity, url: repository, commit: commit)]
        } else {
            let last = credits.remixOf.count - 1
            if credits.remixOf[last].url == nil { credits.remixOf[last].url = repository }
            if Credits.Source.plain(credits.remixOf[last].url ?? "") == Credits.Source.plain(repository) { credits.remixOf[last].commit = commit }
        }
        return credits.checked
    }

    /// Where a cloned folder came from, when its git remote is a repository on GitHub, and the commit it's at: asked of
    /// git confined to that folder, as every git command of Lamp's is. The address as it was given (the setting itself,
    /// not what git would rewrite it to for fetching). Nil for a folder with no repository, or one from elsewhere.
    static func repository(of folder: URL) -> (url: String, commit: String?)? {
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) else { return nil }
        let result = Versions.gitBlocking("git config --get remote.origin.url", cwd: folder)
        guard result.ok, let source = source(from: result.output.trimmed) else { return nil }
        let head = Versions.gitBlocking("git rev-parse HEAD", cwd: folder)
        return (source.url, head.ok ? Credits.validCommit(head.output.trimmed) : nil)
    }
}
