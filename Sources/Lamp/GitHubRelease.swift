import Foundation

/// A release's GitHub half (Release Update on the Share Link card, `WishLinkCards.share`): for a wish that's on GitHub,
/// the wish as it is now goes up as Put on GitHub's update does (`GitHubRepo.stage` and `upload`, with their checks), its
/// what's-new lines as the commit's message, then a release of the repository's, tagged with the release's version and
/// those lines as its notes, and the page as before. The link on lamp.dev always goes first: this follows it, and a
/// failure here is said apart from it, so the link works whatever GitHub does.
///
/// Putting a wish on GitHub the first time stays Put on GitHub's own card (`GitHubRepoCards`), which asks the choices
/// GitHub takes once; after that, a release is how the repository is updated.
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
        /// On GitHub, but not to be updated from here: what to do about it.
        case note(String)
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
    /// repository it was opened from. Nil for a wish that isn't on GitHub, which Put on GitHub… puts there first.
    static func find(_ project: LampProject) async -> Found? {
        let kept = GitHubRepo.isUp(project) ? GitHubRepo.kept(for: project) : nil
        let signIn = kept.map { Found.note("To update \($0.repo) on GitHub too, sign in to GitHub with gh.") }
        guard let gh = await Publish.gh() else { return signIn }
        guard let login = await Publish.login(gh: gh) else { return signIn }
        var target: Target
        if let kept {
            target = Target(repo: kept.repo, gh: gh, login: login)
        } else {
            guard let own = await GitHubRepo.ownOrigin(of: project, login: login, gh: gh) else { return nil }
            target = Target(repo: own.repo, gh: gh, login: login, openedAt: own.commit, behind: own.behind)
        }
        do {
            target.authors = try await GitHubRepo.authors(releasingTo: target.repo, withPage: Publish.hasPage(project), gh: gh, login: login)
        } catch {
            return .note(error.localizedDescription)
        }
        return .ready(target)
    }

    /// Releases the wish as it is now on GitHub, with `picture` for the README when the person chose to show one when
    /// they put it there. Answers whether anything there changed.
    static func release(_ project: LampProject, to target: Target, version: Version, picture: Data?,
                        pushed: @escaping @Sendable () -> Void, step: @escaping @Sendable (String) -> Void) async throws {
        let before = GitHubRepo.kept(for: project)
        // Never over commits there the wish hasn't taken: they'd be lost. A record of Lamp's own push goes by its commit.
        if before == nil, let behind = target.behind { throw Failure(message: behind) }
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
        let uploaded = try await GitHubRepo.upload(staged, of: project, to: target.repo, gh: target.gh, login: target.login, isNew: false,
                                                   expected: before?.commit ?? target.openedAt, isPrivate: !isPublic,
                                                   license: before?.license ?? false, picture: before?.picture,
                                                   authors: target.authors, release: version, pushed: pushed, step: step)
        // A newer release may have pushed while this one waited for its page (the card is free by then): its record
        // stands, and this older one's is left out.
        guard GitHubRepo.kept(for: project)?.commit == uploaded.repo.commit else { return }
        await GitHubRepo.settle(uploaded.repo, before: before, of: project, gh: target.gh)
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
