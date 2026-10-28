import AppKit
import Foundation
import LampSidebarKit

/// Sending a wish's changes back to the repository it came from (`Credits.origin`: the chain's last link naming a
/// repository that isn't the wish's own, with the commit the wish has of it): a pull request on that repository from
/// the person's own fork, made with GitHub's command-line tool (`gh`) and their sign-in, as Put on GitHub puts a
/// repository up (`GitHubRepo`). What goes is what Put on GitHub would put (`GitHubRepo.stage`: the shared file's
/// contents with the same checks, Lamp's own files, the shared file), as one commit on top of that commit in a clone
/// of the fork, with the repository's README and license left as its owner wrote them and its credits.json taking
/// only what the wish newly uses. Nothing of the wish's own history goes, and never the chat: the pull request says
/// where the wish came from, what its versions were called and which files changed.
enum Contribute {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Where the changes would go, and the commit they're on top of. Nil for a wish that didn't come from a repository
    /// on GitHub, or came from one before Lamp recorded the commit (open it from there again to get one).
    static func origin(of project: LampProject) -> (source: RepoImport.Source, commit: String)? {
        guard let link = AppInfoView.origin(of: project), let source = link.url.flatMap(RepoImport.source(from:)),
              let commit = link.commit else { return nil }
        return (source, commit)
    }

    static func canContribute(_ project: LampProject) -> Bool { origin(of: project) != nil }

    /// The pull request opened, and the branch on the fork it came from.
    struct Request: Equatable {
        let url: String
        let branch: String
        let fork: String
    }

    /// The person's fork of `source`, when they have one: "login/name". Asked of GitHub.
    static func fork(of source: RepoImport.Source, login: String, gh: String) async -> String? {
        let candidate = "\(login)/\(source.name)"
        let looked = await Subprocess.run(gh, ["api", "repos/\(candidate)", "--jq", ".parent.full_name"], mergeErrors: false, timeout: 30)
        guard looked.ok, looked.output.trimmed.lowercased() == "\(source.owner)/\(source.name)".lowercased() else { return nil }
        return candidate
    }

    /// Opens the pull request: the fork made when there's none, the parent commit fetched into a folder of Lamp's, the
    /// staged tree put over it, one commit, pushed to a branch of the fork, and the request on `source`; `step` hears
    /// what it's doing.
    static func send(_ staged: GitHubRepo.Staged, of project: LampProject, to source: RepoImport.Source, parent: String, fork: String?,
                     gh: String, login: String, step: @escaping @Sendable (String) -> Void) async throws -> Request {
        let fm = FileManager.default
        let upstream = "\(source.owner)/\(source.name)"
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

        step("Reading what's there…")
        let git = GitHubRepo.git
        let signedIn = GitHubRepo.signedIn(gh: gh)
        let work = staged.folder.deletingLastPathComponent().appendingPathComponent("clone")
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let branch = "lamp/\(Publish.slug(project.name))-\(UUID().uuidString.prefix(6).lowercased())"
        for arguments in [["init", "-q"], ["remote", "add", "upstream", "https://github.com/\(upstream).git"]] {
            let ran = await Subprocess.run(git, arguments, cwd: work, timeout: 60)
            guard ran.ok else { throw Failure(message: "Couldn't prepare the pull request: \(ran.output.trimmed.suffix(200))") }
        }
        let fetched = await Subprocess.run(git, signedIn + ["fetch", "-q", "--depth", "1", "upstream", parent], cwd: work, timeout: 600)
        guard fetched.ok else {
            throw Failure(message: "GitHub didn't give back the version of \(upstream) this wish came from: \(fetched.output.trimmed.suffix(200))")
        }
        let checkedOut = await Subprocess.run(git, ["checkout", "-q", "-b", branch, "FETCH_HEAD"], cwd: work, timeout: 60)
        guard checkedOut.ok else { throw Failure(message: "Couldn't prepare the pull request: \(checkedOut.output.trimmed.suffix(200))") }

        // The wish as it is now in the parent's place, but for what's the repository's own: its README and license
        // stay its owner's (a license the wish's credits name at the root is that one), and its credits, read before
        // anything goes, keep their chain and take only what the wish newly uses.
        let theirs = Credits.read(work.appendingPathComponent(Credits.file)) ?? Credits()
        // And the identity its wish has there: a copy here may have its own (a starter's copy, or one kept beside
        // another), which a contribution must never put in its place.
        let theirApp = (try? JSONSerialization.jsonObject(with: Data(contentsOf: work.appendingPathComponent("lamp-app.json"))) as? [String: Any])?["app"] as? String
        let kept: Set<String> = [".git", "README.md", "LICENSE"]
        // A repository with no shared file beside its code (a starter's) gets none from a contribution either.
        let hadFile = ((try? fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)) ?? []).contains { $0.pathExtension == "lampapp" }
        for item in try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil) where !kept.contains(item.lastPathComponent) {
            try fm.removeItem(at: item)
        }
        for item in try fm.contentsOfDirectory(at: staged.folder, includingPropertiesForKeys: nil)
        where !["README.md", Credits.file].contains(item.lastPathComponent) && !fm.fileExists(atPath: work.appendingPathComponent(item.lastPathComponent).path)
            && (hadFile || item.pathExtension != "lampapp") {
            try fm.copyItem(at: item, to: work.appendingPathComponent(item.lastPathComponent))
        }
        try theirs.merged(with: Credits(upstream: staged.credits.upstream, generated: staged.credits.generated)).encoded()
            .write(to: work.appendingPathComponent(Credits.file), options: .atomic)
        let manifestURL = work.appendingPathComponent("lamp-app.json")
        if let theirApp, var manifest = try? JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any] {
            manifest["app"] = theirApp
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                .write(to: manifestURL, options: .atomic)
        }

        let added = await Subprocess.run(git, ["add", "-A"], cwd: work, timeout: 120)
        guard added.ok else { throw Failure(message: "Couldn't prepare the pull request: \(added.output.trimmed.suffix(200))") }
        // Nothing to send when only the export's own marks differ, as Put on GitHub tells an unchanged wish.
        if await Subprocess.run(git, ["diff", "--cached", "--quiet", "--", ".", ":(exclude)lamp-app.json", ":(exclude)*.lampapp"], cwd: work, timeout: 60).ok {
            let before = await Subprocess.run(git, ["show", "HEAD:lamp-app.json"], cwd: work, mergeErrors: false, timeout: 30)
            if before.ok, let after = try? Data(contentsOf: work.appendingPathComponent("lamp-app.json")),
               GitHubRepo.manifestsMatch(Data(before.output.utf8), after) {
                throw Failure(message: "\(upstream) already has everything this wish has: there's nothing to send.")
            }
        }
        var changed: [String] = []
        let listed = await Subprocess.run(git, ["diff", "--cached", "--name-only"], cwd: work, mergeErrors: false, timeout: 60)
        if listed.ok { changed = listed.output.split(separator: "\n").map(String.init) }
        let summary = await summary(of: project, from: source, changed: changed)
        // The summary is the commit's message and the pull request's text, from files: it's prose, never arguments.
        let message = work.deletingLastPathComponent().appendingPathComponent("message.txt")
        let body = work.deletingLastPathComponent().appendingPathComponent("body.md")
        try (summary.title + "\n\n" + summary.body).write(to: message, atomically: true, encoding: .utf8)
        try summary.body.write(to: body, atomically: true, encoding: .utf8)
        let committed = await Subprocess.run(git, GitHubRepo.identity(login: login) + ["commit", "-q", "-F", message.path], cwd: work, timeout: 120)
        guard committed.ok else { throw Failure(message: "Couldn't prepare the pull request: \(committed.output.trimmed.suffix(200))") }

        step("Uploading…")
        let pushed = await Subprocess.run(git, signedIn + ["push", "-q", "https://github.com/\(fork).git", "HEAD:refs/heads/\(branch)"], cwd: work, timeout: 600)
        guard pushed.ok else { throw Failure(message: "GitHub didn't take it: \(pushed.output.trimmed.suffix(200))") }

        step("Opening the pull request…")
        let base = await Subprocess.run(gh, ["repo", "view", upstream, "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name"], mergeErrors: false, timeout: 30)
        let baseBranch = base.ok && !base.output.trimmed.isEmpty ? base.output.trimmed : "main"
        let head = fork.split(separator: "/").first.map(String.init) ?? login
        let opened = await Subprocess.run(gh, ["pr", "create", "--repo", upstream, "--head", "\(head):\(branch)", "--base", baseBranch,
                                               "--title", summary.title, "--body-file", body.path], timeout: 120)
        guard opened.ok, let url = opened.output.split(whereSeparator: \.isWhitespace).map(String.init).last(where: { $0.hasPrefix("https://") }) else {
            throw Failure(message: "GitHub didn't open the pull request: \(opened.output.trimmed.suffix(200))")
        }
        return Request(url: url, branch: branch, fork: fork)
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
            + "this is the remix's version of it, sent back from Lamp.\n\n"
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
        body += "To try it, open the remix with Lamp (File → Open from GitHub…), or build it with `./build.sh`."
        return ("\(project.name): changes from a remix", body)
    }
}

/// The Send Changes Back card of each wish while it's open, in the chat's place. Preparing it finds `gh` and the
/// person's sign-in, looks for their fork and stages what would go with its checks, so the card shows exactly what will
/// go before the person confirms.
@MainActor final class ContributeCards: ObservableObject {
    static let shared = ContributeCards()

    struct Card {
        var stage: ContributeCard.Stage = .preparing
        var source: RepoImport.Source?
        var parent: String?
        var fork: String?
        var login: String?
        var gh: String?
        var staged: GitHubRepo.Staged?
        var request: Contribute.Request?
        var copied = false
        var icon: Data?

        /// Ready, or failed with the tree still staged, so Send Changes Back tries again.
        var canSend: Bool {
            switch stage {
            case .ready: true
            case .failed: staged != nil
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

    /// Finds gh, the sign-in and the fork, and stages what will go.
    func prepare(_ project: LampProject) {
        guard cards[project.id] != nil else { return }
        cards[project.id]?.stage = .preparing
        if let old = cards[project.id]?.staged { try? FileManager.default.removeItem(at: old.folder.deletingLastPathComponent()) }
        cards[project.id]?.staged = nil
        Task {
            guard let origin = Contribute.origin(of: project) else { return set(project, .refused("This wish didn't come from a repository on GitHub.")) }
            guard let gh = await Publish.gh() else { return set(project, .needsGitHub(.install)) }
            guard let login = await Publish.login(gh: gh) else { return set(project, .needsGitHub(.signIn)) }
            guard login.lowercased() != origin.source.owner.lowercased() else {
                return set(project, .refused("github.com/\(origin.source.owner)/\(origin.source.name) is your own repository: Put on GitHub updates it."))
            }
            let fork = await Contribute.fork(of: origin.source, login: login, gh: gh)
            do {
                let staged = try await Task.detached(priority: .userInitiated) {
                    try GitHubRepo.stage(project, repo: "\(origin.source.owner)/\(origin.source.name)", link: nil)
                }.value
                guard cards[project.id] != nil else {
                    try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent())
                    return
                }
                cards[project.id]?.gh = gh
                cards[project.id]?.login = login
                cards[project.id]?.source = origin.source
                cards[project.id]?.parent = origin.commit
                cards[project.id]?.fork = fork
                cards[project.id]?.staged = staged
                cards[project.id]?.stage = .ready
            } catch {
                set(project, .refused(((error as? LocalizedError)?.recoverySuggestion).map { "\(error.localizedDescription) \($0)" } ?? error.localizedDescription))
            }
        }
    }

    private func set(_ project: LampProject, _ stage: ContributeCard.Stage) { cards[project.id]?.stage = stage }

    func send(_ project: LampProject) {
        guard let card = cards[project.id], card.canSend, let staged = card.staged, let source = card.source, let parent = card.parent,
              let gh = card.gh, let login = card.login else { return }
        set(project, .working("Starting…"))
        Task {
            do {
                let id = project.id
                let request = try await Contribute.send(staged, of: project, to: source, parent: parent, fork: card.fork, gh: gh, login: login) { step in
                    Task { @MainActor in ContributeCards.shared.cards[id]?.stage = .working(step) }
                }
                try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent())
                cards[project.id]?.staged = nil
                cards[project.id]?.fork = request.fork
                cards[project.id]?.request = request
                set(project, .done(request.url))
            } catch {
                // The tree stays staged, so Send Changes Back can try again.
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
        if let staged = cards[project.id]?.staged { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        cards[project.id] = nil
    }

    /// The card as the chat draws it.
    func wire(_ card: Card, of project: LampProject) -> SidebarContribute {
        let credits = card.staged?.credits ?? Credits.load(project)
        var notes = ShareCheck.notes(for: credits)
        if !credits.generated.isEmpty { notes.append(Credits.generatedLine(credits.generated.count) + ", marked as such.") }
        if card.stage == .ready, card.fork == nil, let login = card.login, let source = card.source {
            notes.append("You have no fork of \(source.owner)/\(source.name) yet: Lamp makes one on your account (\(login)/\(source.name)) first.")
        }
        let size = card.staged.map { "\($0.files) files · " + ByteCountFormatter.string(fromByteCount: Int64($0.bytes), countStyle: .file) }
        return SidebarContribute(name: project.name, icon: card.icon, stage: card.stage,
                                 upstream: card.source.map { "\($0.owner)/\($0.name)" }, fork: card.fork ?? card.request?.fork,
                                 credit: credits.basedOn, notes: notes, size: size, copied: card.copied, canSend: card.canSend)
    }
}
