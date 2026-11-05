import AppKit
import Foundation

/// Bringing into a wish what changed in its own repository on GitHub since Lamp put it there: someone's pull request
/// (Send Changes Back, `Contribute`) merged by the owner, or an edit made on GitHub. A release never goes over commits
/// the wish doesn't have (`GitHubRepo.upload`), so the Share Link card offers Bring In Changes in their place
/// (`GitHubRelease.find`), and the next Release Update goes on top of them.
///
/// It's a reviewed update as any other (`Store.mergeUpdate`): Lamp fetches the repository with the person's own GitHub
/// sign-in (so a private one works), shows the review, and on Update git merges what changed there since the commit
/// the wish has of it into the wish three ways, the agent settling only what both changed. The base is always that one
/// commit (`given`): its staged tree kept from the last bring-in, else the commit itself, else, before any bring-in,
/// the wish's own version Lamp pushed in it; never a guess. The wish's own repository is never followed as a copy
/// (`Following`) and never joins its chain; only the credit for work the change uses joins the wish's credits.
///
/// What came in counts only once it's in a saved version (`accept`): its commit is kept with the repository's record
/// (`GitHubRepo.Repo.taken`) with the version that saved it (`takenIn`), and its staged tree at a ref of the wish's git
/// (`snapshot`). A release checks the wish's history still has that version (`holds`), so an Undo or a going back to an
/// earlier version since is brought in again rather than undone on GitHub.
enum BringIn {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// One bring-in: what the merge measures both sides against, and what it brings.
    struct Pull: Codable, Equatable, Sendable {
        var repo: String
        /// The commit of the repository's the wish has: the last it brought in, or Lamp's last push.
        var base: String
        /// The commit fetched now, which the review shows.
        var head: String
        /// Someone's request on the repository (`SuggestedChanges`), by number, with who sent it and the files it changes
        /// that a release can't carry: its head is brought in, not the repository's latest.
        var request: Int? = nil
        var from: String? = nil
        var leftOut: [String]? = nil
        /// `leftOut` was worked out; when it couldn't be, the request is never marked merged by a release.
        var checked: Bool? = nil
    }

    /// A bring-in left to the agent to settle (conflicts), which counts once its turn finished well.
    struct Pending: Codable, Equatable {
        var pull: Pull
        var request: String
        var cards: [String]? = nil

        func isItsTurn(_ messages: [QueuedMessage]) -> Bool {
            let cards = Set(cards ?? [])
            return messages.contains { $0.text == request || $0.card.map { cards.contains($0.uuidString) } == true }
        }
    }

    /// Where the staged latest is kept while it's merged, which the agent's note on conflicts names.
    static let incomingRef = "refs/lamp/own-incoming"
    /// A commit of the wish's own repository as the merge staged it, kept for the next bring-in's base and a release's check.
    static func snapshot(_ commit: String) -> String { "refs/lamp/own/" + commit }

    // MARK: Fetching

    /// Fetches the repository's latest into a folder of Lamp's (`RepoImport.cloneFolder`), with the person's GitHub
    /// sign-in, and the base commit into the wish's git, for the review and the merge. Answers the tree to review and
    /// the pull. The base is the last commit the wish brought in while it still has it (`holds`), else Lamp's last push.
    static func fetch(_ project: LampProject, kept: GitHubRepo.Repo, gh: String) async throws -> (folder: URL, tree: URL, pull: Pull) {
        guard let pushed = kept.commit else { throw Failure(message: "Lamp has no record of what it put on GitHub for \(project.name).") }
        let holding = await holds(project, kept: kept)
        let base = holding ? kept.expected ?? pushed : pushed
        let git = GitHubRepo.git
        let folder = RepoImport.cloneFolder()
        let name = String(kept.repo.split(separator: "/").last ?? "repository")
        let tree = folder.appendingPathComponent(name)
        var done = false
        defer { if !done { try? FileManager.default.removeItem(at: folder) } }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let signedIn = GitHubRepo.signedIn(gh: gh)
        let cloned = await Subprocess.run(git, signedIn + ["clone", "-q", "--depth", "1", "https://github.com/\(kept.repo).git", tree.path], timeout: 600)
        guard cloned.ok, let head = await GitHubRepo.head(git, in: tree) else {
            throw Failure(message: "GitHub didn't give back \(kept.repo): \(cloned.output.trimmed.suffix(200))")
        }
        await fetchBase(base, into: tree, for: project, gh: gh)
        done = true
        return (folder, tree, Pull(repo: kept.repo, base: base, head: head))
    }

    /// The base, when GitHub still has it, fetched into the clone at `tree` and from there into the wish's git, for the
    /// merge (`given`).
    static func fetchBase(_ base: String, into tree: URL, for project: LampProject, gh: String) async {
        let git = GitHubRepo.git
        if await Subprocess.run(git, GitHubRepo.signedIn(gh: gh) + ["fetch", "-q", "--depth", "1", "origin", base], cwd: tree, timeout: 300).ok,
           await Subprocess.run(git, ["update-ref", "refs/lamp/base", base], cwd: tree, timeout: 10).ok {
            _ = await Versions.git("git fetch -q --depth 1 \(Sandbox.quoted("file://" + tree.path)) refs/lamp/base", cwd: project.dir) { _ in }
        }
    }

    /// The base the merge measures against: `pull.base` and nothing else, from what the wish's git has of it. Its
    /// staged tree from the last bring-in comes first, being what the wish took then; the commit itself, fetched; then,
    /// for Lamp's own push, the version of the wish it pushed. Refused when none is there, rather than measured against
    /// something older, which could bring back what was taken away on GitHub.
    static func given(for pull: Pull, kept: GitHubRepo.Repo?, in project: LampProject) async throws -> Upstream.Given {
        if await has(snapshot(pull.base), in: project) { return .staged(snapshot(pull.base)) }
        if await has(pull.base, in: project) { return .commit(pull.base) }
        if let kept, kept.commit == pull.base, let version = kept.version { return .own(version) }
        throw Failure(message: "Lamp can't tell what changed on GitHub since this app last took \(pull.repo)'s changes, so it brought nothing in.")
    }

    private static func has(_ name: String, in project: LampProject) async -> Bool {
        await Upstream.run("git rev-parse --verify -q \(Sandbox.quoted(name + "^{commit}"))", in: project).status == 0
    }

    // MARK: Once it's in

    /// What came in counts, now that it's in a saved version: its staged tree is kept by its commit, and the
    /// repository's record names it, unless Lamp pushed since (a release over it measures from there).
    @MainActor static func accept(_ pull: Pull, in project: LampProject) async {
        _ = await Upstream.run("git update-ref \(snapshot(pull.head)) \(incomingRef)", in: project)
        // Someone's request is kept with the others (`SuggestedChanges`): the repository itself hasn't moved.
        if pull.request != nil { return await SuggestedChanges.accept(pull, in: project) }
        guard var kept = GitHubRepo.kept(for: project), kept.repo == pull.repo, kept.commit != nil,
              kept.commit == pull.base || kept.taken == pull.base else { return }
        kept.taken = pull.head == kept.commit ? nil : pull.head
        kept.takenIn = kept.taken == nil ? nil : await Versions.head(project)
        GitHubRepo.keep(kept, for: project)
        WishLinkCards.shared.findAgain(project)
    }

    /// Keeps the base as the merge staged it, for a bring-in whose base was read from somewhere else (the commit, the
    /// wish's version), so a later one, or a release's check, finds it even once GitHub no longer has that commit.
    static func keepBase(_ pull: Pull, mark: String?, in project: LampProject) async {
        guard let mark, await !has(snapshot(pull.base), in: project) else { return }
        _ = await Upstream.run("git update-ref \(snapshot(pull.base)) \(mark)", in: project)
    }

    /// Whether the wish still has what it brought in since Lamp's last push: the version that brought it in is in its
    /// history, and nothing since went back to before it (an Undo of it, a going back to an earlier version; the latest
    /// of these decides, so a going forward again counts). A change made after it, to what came in or anything else, is
    /// the wish's own, and holds.
    static func holds(_ project: LampProject, kept: GitHubRepo.Repo) async -> Bool {
        guard kept.taken != nil else { return true }
        return await holds(version: kept.takenIn, in: project)
    }

    /// The same for any version that brought something in (a request's, `SuggestedChanges`).
    static func holds(version: String?, in project: LampProject) async -> Bool {
        guard let version = Credits.validCommit(version) else { return false }
        return await has(version, at: "HEAD", in: project)
    }

    /// Whether the files of `commit` have what `version` brought: it descends from `version`, and the latest going back
    /// since, followed to the version it went back to (and so on, as that one may itself be a going back), has it too.
    private static func has(_ version: String, at commit: String, in project: LampProject, depth: Int = 0) async -> Bool {
        guard depth < 50, await descends(version, to: commit, in: project) else { return false }
        let log = await Upstream.run("git log --first-parent --format='%x1e%H%x1f%(trailers:key=Lamp-Undid,valueonly,separator=%x2C)%x1f%(trailers:key=Lamp-Restored,valueonly,separator=%x2C)' \(version)..\(commit)", in: project)
        guard log.status == 0 else { return false }
        for entry in log.output.split(separator: "\u{1e}") {
            let fields = entry.split(separator: "\u{1f}", omittingEmptySubsequences: false).map { String($0).trimmed }
            guard fields.count == 3 else { continue }
            var target: String? = Credits.validCommit(fields[2])
            if target == nil, let undid = Credits.validCommit(fields[1]) {
                target = Credits.validCommit((await Upstream.run("git rev-parse --verify -q \(undid)^", in: project)).output.trimmed)
                if target == nil { return false }
            }
            guard let target else { continue }
            return await has(version, at: target, in: project, depth: depth + 1)
        }
        return true
    }

    private static func descends(_ version: String, to commit: String, in project: LampProject) async -> Bool {
        await Upstream.run("git merge-base --is-ancestor \(version) \(commit)", in: project).status == 0
    }

    /// The app's files as the wish last brought them in, by their paths: a release leaves one of these the app took away
    /// again taken away, where a file GitHub alone has stays (`GitHubRepo.keptFromGitHub`).
    static func paths(_ project: LampProject, kept: GitHubRepo.Repo) async -> Set<String> {
        guard let taken = kept.taken else { return [] }
        let listed = await Upstream.run("git ls-tree -r --name-only \(snapshot(taken))", in: project)
        guard listed.status == 0 else { return [] }
        return Set(listed.output.split(separator: "\n").map(String.init))
    }

    // MARK: What Lamp keeps

    /// A test points this at a folder of its own.
    nonisolated(unsafe) static var keptURL = Edition.supportFolder.appendingPathComponent("GitHub Bring In.json")
    private static func key(_ project: LampProject) -> String { project.instance.isEmpty ? project.id : project.instance }

    static func pending(for project: LampProject) -> Pending? { read()[key(project)] }

    static func setPending(_ pending: Pending?, for project: LampProject) {
        var all = read()
        all[key(project)] = pending
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: keptURL, options: .atomic) }
    }

    private static func read() -> [String: Pending] {
        (try? Data(contentsOf: keptURL)).flatMap { try? JSONDecoder().decode([String: Pending].self, from: $0) } ?? [:]
    }
}

extension Store {
    /// Bring In Changes on the Share Link card: the wish's own repository, fetched with the person's sign-in, reviewed
    /// as an update, and merged into the wish on Update (`mergeUpdate`).
    func bringInFromGitHub(_ project: LampProject) {
        guard let kept = GitHubRepo.kept(for: project), GitHubRepo.isUp(project) else { return }
        guard !busy.contains(project.id), (queued[project.id] ?? []).isEmpty else {
            let alert = NSAlert()
            alert.messageText = "“\(project.name)” is busy right now"
            alert.informativeText = "Try again when it's done."
            alert.runModal()
            return
        }
        Task {
            guard let gh = await Publish.gh(), await Publish.login(gh: gh) != nil else {
                let alert = NSAlert()
                alert.messageText = "Sign in to GitHub with gh first"
                alert.informativeText = "Lamp fetches \(kept.repo) with your own GitHub sign-in."
                alert.runModal()
                return
            }
            do {
                let fetched = try await BringIn.fetch(project, kept: kept, gh: gh)
                importApp(from: fetched.tree, updating: project.id, bringingIn: fetched.pull)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    /// After a turn: a bring-in left to the agent counts once the turn that settled it finished well, and is dropped if
    /// it didn't, so the card offers it again. A turn that answers one of its questions settles it the same way.
    func settleBringIn(_ project: LampProject, messages: [QueuedMessage], end: TurnEnd, asked: Bool) async {
        guard var pending = BringIn.pending(for: project), pending.isItsTurn(messages) else { return }
        let turnLines = (logs[project.id] ?? []).reversed().prefix { $0.kind != .user }
        let asking = asked || Talk.open(in: logs[project.id] ?? []) != nil || (queued[project.id] ?? []).contains { $0.card != nil }
        switch AppUpdates.settle(end: end, errors: turnLines.contains { $0.kind == .error }, asking: asking) {
        case .waiting:
            let cards = [Talk.open(in: logs[project.id] ?? [])?.id].compactMap { $0 } + (queued[project.id] ?? []).compactMap(\.card)
            if !cards.isEmpty {
                pending.cards = Array(Set((pending.cards ?? []) + cards.map(\.uuidString)))
                BringIn.setPending(pending, for: project)
            }
            return
        case .ready:
            await BringIn.accept(pending.pull, in: project)
        case .failed: break
        }
        BringIn.setPending(nil, for: project)
    }
}
