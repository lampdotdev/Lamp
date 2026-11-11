import Foundation
import LampSidebarKit

/// A release's GitHub half (Release Update on the Share Link card, `WishLinkCards.share`), the one way a wish goes to
/// GitHub. For a wish that's on GitHub, the wish as it is now goes up (`GitHubRepo.stage` and `upload`, with their
/// checks), its what's-new lines as the commit's message, then a release of the repository's, tagged with the release's
/// version and those lines as its notes, and the page as before. For one that isn't, ticking Also put on GitHub shows
/// what will go up and the choices GitHub takes once (`FirstPush`: public or private, the license, the README's
/// picture), and the release makes the repository and pushes the first commit the same way. The link on lamp.dev
/// always goes first: this follows it, and a failure here is said apart from it, so the link works whatever GitHub does.
enum GitHubRelease {
    /// The release as GitHub gets it. Its tag is the release's number ("v1" for its first, which is its link's first
    /// share; `WishReleases.Release.number`): simple, and never reused, since each release is numbered after the last.
    struct Version: Equatable, Sendable {
        var tag: String
        var lines: [String]

        init(tag: String, lines: [String]) {
            self.tag = tag
            self.lines = lines
        }

        /// The release just recorded in the wish, by its number, with its lines.
        init(number: Int, lines: [String]) {
            self.init(tag: "v\(max(1, number))", lines: lines)
        }

        /// The commit's message: the lines, the first as its subject; nil for a release that says nothing.
        var message: String? { lines.isEmpty ? nil : lines.joined(separator: "\n") }
        /// The release's notes on GitHub, a line each.
        var notes: String { lines.map { "- \($0)" }.joined(separator: "\n") }
    }

    /// The repository a release goes to, found as the card opens.
    struct Target: Equatable {
        var repo: String
        var gh: String
        var login: String
        /// The person's own repository the wish was opened from (`GitHubRepo.ownOrigin`), which Lamp keeps no record of
        /// putting up: the commit the wish has of it, and why it can't go up yet, when it can't.
        var openedAt: String? = nil
        var behind: String? = nil
        /// Who its commits are made as, which the card says when it shows an address (`GitHubRepo.note(for:)`): a
        /// commit that would show another is refused (`GitHubRepo.commit`).
        var authors: [GitHubRepo.Author] = []
    }

    enum Found: Equatable {
        case ready(Target)
        /// On GitHub, with changes there the wish doesn't have (`BringIn`): Bring In Changes first.
        case behind(Target)
        /// On GitHub, but not to be updated from here: what to do about it.
        case note(String)
        /// Not on GitHub yet: a release can put it there, with the person's GitHub sign-in.
        case new(gh: String, login: String)
        /// Not on GitHub yet, and GitHub's command-line tool or a sign-in to it is missing.
        case needs(GitHubNeed)
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The code went up but GitHub's release of it didn't: said as such, since the repository has the update.
    struct TagFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Whether the wish is on GitHub and can be released there: one Lamp put up (`GitHubRepo.kept`), or the person's own
    /// repository it was opened from. A wish that isn't is `new`, for a release to put there the first time.
    static func find(_ project: LampProject) async -> Found {
        let kept = GitHubRepo.isUp(project) ? GitHubRepo.kept(for: project) : nil
        let signIn = kept.map { Found.note("To update \($0.repo) on GitHub too, sign in to GitHub with gh.") }
        guard let gh = await Publish.gh() else { return signIn ?? .needs(.install) }
        guard let login = await Publish.login(gh: gh) else { return signIn ?? .needs(.signIn) }
        var target: Target
        if let kept {
            target = Target(repo: kept.repo, gh: gh, login: login)
            if await isBehind(project, kept: kept, gh: gh) { return .behind(target) }
        } else {
            guard let own = await GitHubRepo.ownOrigin(of: project, login: login, gh: gh) else { return .new(gh: gh, login: login) }
            target = Target(repo: own.repo, gh: gh, login: login, openedAt: own.commit, behind: own.behind)
        }
        do {
            target.authors = try await GitHubRepo.authors(releasingTo: target.repo, withPage: false, gh: gh, login: login)
        } catch {
            return .note(error.localizedDescription)
        }
        return .ready(target)
    }

    /// Whether the repository has changes the wish doesn't: commits after the last one it has (`Repo.expected`), or
    /// ones it brought in and has since taken back (an Undo, `BringIn.holds`). Asked of GitHub without fetching
    /// anything; a repository GitHub doesn't answer for is left to the release, which checks again.
    static func isBehind(_ project: LampProject, kept: GitHubRepo.Repo, gh: String) async -> Bool {
        let head = await Subprocess.run(GitHubRepo.git, GitHubRepo.signedIn(gh: gh) + ["ls-remote", "https://github.com/\(kept.repo).git", "HEAD"],
                                        mergeErrors: false, timeout: 60)
        if head.ok, let now = head.output.split(whereSeparator: \.isWhitespace).first.map(String.init), now != kept.expected { return true }
        return await !BringIn.holds(project, kept: kept)
    }

    /// Releases the wish as it is now on GitHub, with `picture` for the README when the person chose to show one when
    /// they put it there. Answers whether anything there changed.
    static func release(_ project: LampProject, to target: Target, version: Version, picture: Data?,
                        pushed: @escaping @Sendable () -> Void, step: @escaping @Sendable (String) -> Void) async throws {
        let before = GitHubRepo.kept(for: project)
        // Never over commits there the wish hasn't taken: they'd be lost. A record of Lamp's own push goes by its commit.
        if before == nil, let behind = target.behind { throw Failure(message: behind) }
        if let before, await !BringIn.holds(project, kept: before) { throw GitHubRepo.Moved(repo: target.repo, name: project.name) }
        var broughtIn: Set<String> = []
        if let before { broughtIn = await BringIn.paths(project, kept: before) }
        step("Checking what goes to GitHub…")
        guard let isPublic = await GitHubRepo.isPublic(target.repo, gh: target.gh) else {
            throw Failure(message: "GitHub didn't answer for \(target.repo). Try again in a moment.")
        }
        // The README keeps to the choices made when it was put up: its picture, its license.
        let shown = before?.picture == true ? picture : nil
        let staged = try await Task.detached(priority: .userInitiated) {
            try GitHubRepo.stage(project, repo: target.repo, link: WishLink.kept(for: project)?.url, isPublic: isPublic, picture: shown)
        }.value
        defer { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        // Requests brought in that this release really has go with it, so GitHub marks them merged (`SuggestedChanges`).
        // Asked of GitHub afresh, so a request rewritten since it was brought in, or one opened under it, keeps it out.
        var merging: [String] = []
        if let before, SuggestedChanges.record(for: project)?.taken.isEmpty == false {
            step("Checking suggested changes…")
            if let found = await SuggestedChanges.find(project, kept: before, gh: target.gh) {
                // What it found shows on the desk, as any look at GitHub's does.
                await MainActor.run { Store.shared.publishSuggestions(project, found: found.record, gh: target.gh) }
                merging = await SuggestedChanges.parents(for: project, gh: target.gh).map(\.head)
            }
        }
        let uploaded = try await GitHubRepo.upload(staged, of: project, to: target.repo, gh: target.gh, login: target.login, isNew: false,
                                                   expected: before?.expected ?? target.openedAt,
                                                   lastPushed: before?.taken == nil ? nil : before?.commit, broughtIn: broughtIn,
                                                   keeping: before?.ownFiles ?? [], merging: merging, isPrivate: !isPublic,
                                                   license: before?.license ?? false, picture: before?.picture,
                                                   authors: target.authors, release: version, pushed: pushed, step: step)
        // A newer release may have pushed while this one waited for its page (the card is free by then): its record
        // stands, and this older one's is left out.
        guard GitHubRepo.kept(for: project)?.commit == uploaded.repo.commit else { return }
        await GitHubRepo.settle(uploaded.repo, before: before, of: project, gh: target.gh)
        // What GitHub made of the requests it went with is GitHub's to say.
        if !merging.isEmpty { await MainActor.run { Store.shared.checkSuggestions(project) } }
    }

    // MARK: The first time

    /// Putting a wish on GitHub the first time, as Release Update's card has it while Also put on GitHub is ticked: the
    /// choices GitHub takes once, and what would go up with them, staged and checked so the card shows it before
    /// anything goes. A repository made by a first try that failed before anything went up (`kept`, with no commit) is
    /// gone on with: its choices are settled, and the release finishes it.
    struct FirstPush {
        var stage: WishLinkCard.GitHubSetup.Stage = .preparing
        var gh: String
        var login: String
        var kept: GitHubRepo.Repo?
        var repo: String?
        var isPrivate = false
        var license = true
        /// The README shows the wish's picture: as chosen at a first try, else shown, as the card shows it.
        var showsPicture = true
        /// What would go up, as checked: whether anyone can read it there, who its commits are made as.
        var staged: GitHubRepo.Staged?
        var isPublic: Bool?
        var authors: [GitHubRepo.Author]?
        /// The latest check: one that a newer choice started over doesn't land.
        var checking: UUID?

        init(gh: String, login: String, kept: GitHubRepo.Repo?) {
            self.gh = gh
            self.login = login
            self.kept = kept
            license = kept.map { $0.license ?? false } ?? true
            showsPicture = kept?.picture ?? true
        }

        var settled: Bool { kept != nil }

        /// Removes what was staged to check.
        mutating func discard() {
            if let staged { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
            staged = nil
        }
    }

    /// What `check` found: what goes up and where.
    struct Checked {
        var repo: String
        var staged: GitHubRepo.Staged
        var isPublic: Bool
        var authors: [GitHubRepo.Author]
    }

    /// Stages what the first push would put up with the card's choices, checked (a license, a key in the code), with
    /// who its commits are made as, so the card shows it before anything goes. A repository made already keeps its name
    /// and is as GitHub says; a new one gets a free name on the person's account.
    static func check(_ project: LampProject, _ push: FirstPush, picture: Data?) async throws -> Checked {
        let repo: String
        let isPublic: Bool
        if let kept = push.kept {
            repo = kept.repo
            isPublic = await GitHubRepo.isPublic(kept.repo, gh: push.gh) ?? false
        } else {
            repo = await Publish.freeName(for: project, login: push.login, gh: push.gh)
            isPublic = !push.isPrivate
        }
        let shown = push.showsPicture ? picture : nil
        let staged = try await Task.detached(priority: .userInitiated) {
            try GitHubRepo.stage(project, repo: repo, link: WishLink.kept(for: project)?.url, isPublic: isPublic, picture: shown)
        }.value
        do {
            let authors = try await GitHubRepo.authors(for: staged, repo: repo, isNew: push.kept == nil, gh: push.gh, login: push.login)
            return Checked(repo: repo, staged: staged, isPublic: isPublic, authors: authors)
        } catch {
            try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent())
            throw error
        }
    }

    /// The card's view of the first push.
    static func setup(_ push: FirstPush, of project: LampProject) -> WishLinkCard.GitHubSetup {
        let credits = push.staged?.credits ?? Credits.load(project)
        var (notes, terms) = ShareCheck.cardNotes(for: credits)
        if !credits.generated.isEmpty { notes.append(Credits.generatedLine(credits.generated.count) + ", marked as such.") }
        if push.stage == .ready, let note = push.authors.flatMap(GitHubRepo.note(for:)) { notes.append(note) }
        let isPublic = push.isPublic ?? !push.isPrivate
        // What the README offers: in a public repository the repository itself on lamp.dev; in a private one the link.
        let remix = push.staged?.remix.flatMap(URL.init(string:)).flatMap { url in
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "repo" }?.value
                .map { "lamp.dev, from " + $0.replacingOccurrences(of: "https://", with: "") }
        }
        let link = WishLink.kept(for: project).map { kept in kept.url.host.map { $0 + kept.url.path } ?? kept.url.absoluteString }
        let page = (push.staged?.page?.url ?? push.staged?.site).map { $0.replacingOccurrences(of: "https://", with: "") }
        return WishLinkCard.GitHubSetup(
            stage: push.stage, repo: push.repo, settled: push.settled, page: page, plays: Publish.pageUse(project) != .use,
            privatePage: !isPublic && Publish.hasPage(project), credit: credits.basedOn,
            remix: push.staged == nil ? nil : remix ?? link ?? "This app's link",
            size: push.staged.map { "\($0.files) files · " + ByteCountFormatter.string(fromByteCount: Int64($0.bytes), countStyle: .file) },
            notes: notes, terms: terms, isPrivate: push.isPrivate, license: push.license,
            canChooseLicense: push.staged.map { GitHubRepo.canOfferLicense($0.credits) } ?? true, showsPicture: push.showsPicture)
    }

    /// Puts the wish on GitHub the first time, after its link went up, with the choices on the card: staged afresh, so the
    /// README offers the link just made, and pushed as `version`'s commit, tagged as its release, with its page. Answers
    /// the repository. A try after one that made the repository and failed goes on with it, over only what Lamp pushed.
    static func putUp(_ project: LampProject, _ push: FirstPush, version: Version, picture: Data?,
                      pushed: @escaping @Sendable () -> Void, step: @escaping @Sendable (String) -> Void) async throws -> String {
        guard let repo = push.repo, let isPublic = push.isPublic else { throw Failure(message: "Lamp hadn't checked what goes to GitHub yet.") }
        let before = GitHubRepo.kept(for: project)
        step("Checking what goes to GitHub…")
        let shown = push.showsPicture ? picture : nil
        let link = WishLink.kept(for: project)?.url
        let staged = try await Task.detached(priority: .userInitiated) {
            try GitHubRepo.stage(project, repo: repo, link: link, isPublic: isPublic, picture: shown)
        }.value
        defer { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        let isNew = before?.repo != repo
        let uploaded = try await GitHubRepo.upload(staged, of: project, to: repo, gh: push.gh, login: push.login, isNew: isNew,
                                                   expected: isNew ? nil : before?.commit, isPrivate: !isPublic,
                                                   license: isNew ? push.license : before?.license ?? false,
                                                   picture: picture == nil ? before?.picture : push.showsPicture,
                                                   authors: push.authors, release: version, pushed: pushed, step: step)
        // As a later release's: one that pushed while this waited for its page keeps its record.
        if GitHubRepo.kept(for: project)?.commit == uploaded.repo.commit {
            await GitHubRepo.settle(uploaded.repo, before: before, of: project, gh: push.gh)
        }
        return repo
    }

    /// Makes the release on GitHub at `commit`, tagged with its version, unless it's there already from a try that
    /// failed after it: a tag of the same name on another commit is someone else's, and is said so rather than taken.
    static func tag(_ version: Version, of repo: String, at commit: String, gh: String) async throws {
        let tagRef = "refs/tags/\(version.tag)"
        let existing = await Subprocess.run(GitHubRepo.git, GitHubRepo.signedIn(gh: gh) + ["ls-remote", "https://github.com/\(repo).git", tagRef, tagRef + "^{}"],
                                            mergeErrors: false, timeout: 60)
        // An annotated tag names a tag object; the line for its peeled ref names the commit it's on.
        let refs = existing.output.split(whereSeparator: \.isNewline).compactMap { line -> (String, String)? in
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            return parts.count == 2 ? (parts[1], parts[0]) : nil
        }
        let at = refs.first { $0.0 == tagRef + "^{}" }?.1 ?? refs.first { $0.0 == tagRef }?.1
        if existing.ok, let at {
            guard at == commit else {
                throw TagFailure(message: "\(repo) already has a tag \(version.tag) on another commit, so no release was made.")
            }
            return
        }
        let made = await Subprocess.run(gh, ["release", "create", version.tag, "--repo", repo, "--target", commit,
                                             "--title", version.tag, "--notes", version.notes], timeout: 60)
        guard made.ok else {
            throw TagFailure(message: "GitHub didn't make release \(version.tag): \(made.output.trimmed.suffix(200))")
        }
    }
}
