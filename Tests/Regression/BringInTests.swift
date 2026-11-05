import XCTest
@testable import Lamp

/// The owner's half of sending changes back: a pull request merged on GitHub (or an edit made there) moves the wish's
/// repository past what Lamp pushed, so a release is refused until Bring In Changes has brought it in; then it goes on
/// top of it, with nothing of it lost: the app's code merged, the repository's own files (a README edited there) kept.
/// GitHub here is a bare repository on disk, reached by git's own address rewriting, and `gh` a stand-in.
final class BringInTests: XCTestCase {
    private let escape = HistoryEscapeTests()
    override func setUp() { expectNoSharingFoldersLeft() }
    override func tearDown() { escape.tearDown() }

    private struct World {
        let wish: LampProject
        let bare: URL
        let gh: URL
        let place: URL
    }

    private func sh(_ command: String, in folder: URL) throws -> String {
        let ran = try escape.loose(command, in: folder)
        XCTAssertEqual(ran.status, 0, "\(command): \(ran.output)")
        return ran.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A wish under the home folder with its first version saved, a bare repository standing in for
    /// github.com/someone/tally, and a `gh` that answers as GitHub would for a private repository.
    private func world() throws -> World {
        let app = try escape.app()
        let place = app.root
        let bare = place.appendingPathComponent("tally.git")
        _ = try sh("git init -q --bare -b main \(Sandbox.quoted(bare.path))", in: place)
        let gh = place.appendingPathComponent("gh")
        try """
        #!/bin/zsh
        [[ "$1 $2" == "repo view" ]] && echo PRIVATE
        exit 0
        """.write(to: gh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gh.path)
        let surroundings = ["GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "url.\(bare.absoluteString).insteadOf",
                            "GIT_CONFIG_VALUE_0": "https://github.com/someone/tally.git"]
        for (name, value) in surroundings { setenv(name, value, 1) }
        let keptURL = GitHubRepo.keptURL, pendingURL = BringIn.keptURL
        GitHubRepo.keptURL = place.appendingPathComponent("kept.json")
        BringIn.keptURL = place.appendingPathComponent("bring-in.json")
        addTeardownBlock {
            for name in surroundings.keys { unsetenv(name) }
            GitHubRepo.keptURL = keptURL
            BringIn.keptURL = pendingURL
        }
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: place)
        try Template.writeOwnedFiles(for: wish)
        try "let step = 1\n".write(to: wish.dir.appendingPathComponent("Sources/Counter.swift"), atomically: true, encoding: .utf8)
        _ = try sh("git init -q -b main && printf '.lamp/\\n.build/\\nbuild/\\n' > .gitignore && git add -A && git -c user.name=Lamp -c user.email=lamp@localhost commit -qm first", in: wish.dir)
        return World(wish: wish, bare: bare, gh: gh, place: place)
    }

    /// The wish's first push, as a first Release Update with Also put on GitHub makes it.
    private func release(_ world: World, isNew: Bool) async throws -> GitHubRepo.Repo {
        let staged = try GitHubRepo.stage(world.wish, repo: "someone/tally", link: nil, isPublic: false)
        defer { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        let up = try await GitHubRepo.upload(staged, of: world.wish, to: "someone/tally", gh: world.gh.path, login: "someone", isNew: isNew,
                                             isPrivate: true, license: false) { _ in }
        GitHubRepo.keep(up.repo, for: world.wish)
        return up.repo
    }

    /// A later Release Update as the card's makes one (`GitHubRelease.release`), short of its tag, page and passing
    /// on: refused while the wish lacks what it brought in, then over the last commit it has, with what it brought in.
    private func releaseOverBroughtIn(_ world: World) async throws -> GitHubRepo.Repo {
        let before = try XCTUnwrap(GitHubRepo.kept(for: world.wish))
        guard await BringIn.holds(world.wish, kept: before) else { throw GitHubRepo.Moved(repo: before.repo, name: world.wish.name) }
        let broughtIn = await BringIn.paths(world.wish, kept: before)
        let staged = try GitHubRepo.stage(world.wish, repo: "someone/tally", link: nil, isPublic: false)
        defer { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        let up = try await GitHubRepo.upload(staged, of: world.wish, to: "someone/tally", gh: world.gh.path, login: "someone", isNew: false,
                                             expected: before.expected, lastPushed: before.taken == nil ? nil : before.commit,
                                             broughtIn: broughtIn, isPrivate: true, license: false) { _ in }
        GitHubRepo.keep(up.repo, for: world.wish)
        return up.repo
    }

    /// Someone's pull request, merged on GitHub: `files` changed (nil takes one away) on the repository's main.
    @discardableResult
    private func mergeOnGitHub(_ world: World, _ files: [String: String?], force: Bool = false, from: String? = nil) throws -> String {
        let work = world.place.appendingPathComponent("contributor-\(UUID().uuidString)")
        _ = try sh("git clone -q \(Sandbox.quoted(world.bare.path)) \(Sandbox.quoted(work.path))", in: world.place)
        if let from { _ = try sh("git fetch -q origin \(from) && git reset -q --hard \(from)", in: work) }
        for (path, text) in files {
            let url = work.appendingPathComponent(path)
            if let text {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
            } else {
                try FileManager.default.removeItem(at: url)
            }
        }
        let head = try sh("git add -A && git -c user.name=Remixer -c user.email=remixer@example.com commit -qm 'changes from a remix' && git push -q \(force ? "-f " : "")origin HEAD:main && git rev-parse HEAD", in: work)
        try FileManager.default.removeItem(at: work)
        return head
    }

    /// Bring In Changes as Update on its review does it (`Store.mergeUpdate`): fetched with the sign-in, merged against
    /// the one base the pull names, saved, and counted. The conflicts the merge left, if any (then nothing counts).
    @MainActor
    private func bringIn(_ world: World) async throws -> (conflicts: [String], given: Upstream.Given, pull: BringIn.Pull) {
        let kept = try XCTUnwrap(GitHubRepo.kept(for: world.wish))
        let fetched = try await BringIn.fetch(world.wish, kept: kept, gh: world.gh.path)
        defer { try? FileManager.default.removeItem(at: fetched.folder) }
        let package = try RepoImport.open(folder: fetched.tree)
        defer { try? FileManager.default.removeItem(at: package.folder) }
        let given = try await BringIn.given(for: fetched.pull, kept: kept, in: world.wish)
        let merged = try await Upstream.merge(package, into: world.wish, from: nil, commit: nil, arrival: nil, ref: BringIn.incomingRef, given: given)
        await BringIn.keepBase(fetched.pull, mark: merged.baseMark, in: world.wish)
        guard merged.conflicts.isEmpty else { return (merged.conflicts, given, fetched.pull) }
        if await Versions.hasUnsavedChanges(world.wish) {
            let saved = await Versions.save(world.wish, message: "Pulled in someone/tally on GitHub")
            XCTAssertTrue(saved)
        }
        await BringIn.accept(fetched.pull, in: world.wish)
        return ([], given, fetched.pull)
    }

    private func onGitHub(_ world: World, _ path: String) throws -> String? {
        let shown = try escape.loose("git --git-dir \(Sandbox.quoted(world.bare.path)) show main:\(Sandbox.quoted(path))", in: world.place)
        return shown.status == 0 ? shown.output : nil
    }

    private func code(_ world: World, _ path: String) -> String? {
        try? String(contentsOf: world.wish.dir.appendingPathComponent(path), encoding: .utf8)
    }

    private func change(_ world: World, _ path: String, _ text: String, _ message: String) async throws {
        try text.write(to: world.wish.dir.appendingPathComponent(path), atomically: true, encoding: .utf8)
        let saved = await Versions.save(world.wish, message: message)
        XCTAssertTrue(saved)
    }

    // MARK: The cases

    /// The report: a remix's pull request merged on GitHub, then Release Update. Refused while the app doesn't have it,
    /// never as a dead end: once brought in, the release goes on top of the merge, with both sides' changes in it.
    @MainActor
    func testAReleaseGoesOnTopOfAMergedPullRequestOnceItsBroughtIn() async throws {
        let world = try world()
        let first = try await release(world, isNew: true)
        let merged = try mergeOnGitHub(world, ["Sources/Counter.swift": "let step = 2\n", "Sources/Twos.swift": "let twos = true\n"])
        try await change(world, "APP.md", "Counts things.\n", "Say what it does")

        do {
            _ = try await releaseOverBroughtIn(world)
            XCTFail("a release over the merged pull request was to be refused")
        } catch let moved as GitHubRepo.Moved {
            XCTAssertEqual(moved.repo, "someone/tally")
        }
        XCTAssertEqual(try sh("git --git-dir \(Sandbox.quoted(world.bare.path)) rev-parse main", in: world.place), merged, "nothing went up")

        let brought = try await bringIn(world)
        XCTAssertEqual(brought.conflicts, [])
        XCTAssertEqual(brought.given, .commit(first.commit ?? ""), "measured against Lamp's last push, fetched with the sign-in")
        XCTAssertEqual(code(world, "Sources/Counter.swift"), "let step = 2\n")
        XCTAssertEqual(code(world, "Sources/Twos.swift"), "let twos = true\n")
        XCTAssertEqual(code(world, "APP.md"), "Counts things.\n", "the owner's own change stays")
        XCTAssertEqual(GitHubRepo.kept(for: world.wish)?.taken, merged)

        let released = try await releaseOverBroughtIn(world)
        XCTAssertNil(released.taken, "the push is the commit the wish is at now")
        XCTAssertEqual(try sh("git --git-dir \(Sandbox.quoted(world.bare.path)) rev-parse main^", in: world.place), merged, "on top of the merge")
        XCTAssertEqual(try onGitHub(world, "Sources/Counter.swift"), "let step = 2\n")
        XCTAssertEqual(try onGitHub(world, "Sources/Twos.swift"), "let twos = true\n")
        XCTAssertEqual(try onGitHub(world, "APP.md"), "Counts things.\n")
    }

    /// The pull request's change was already put into the app by hand: bringing it in finds nothing new, counts it,
    /// and the release goes.
    @MainActor
    func testChangesAlreadyInTheAppByHandAreCountedAndTheReleaseGoes() async throws {
        let world = try world()
        _ = try await release(world, isNew: true)
        let merged = try mergeOnGitHub(world, ["Sources/Counter.swift": "let step = 2\n"])
        try await change(world, "Sources/Counter.swift", "let step = 2\n", "Took the remix's step by hand")
        let before = await Versions.head(world.wish)

        let brought = try await bringIn(world)
        XCTAssertEqual(brought.conflicts, [])
        let after = await Versions.head(world.wish)
        XCTAssertEqual(after, before, "nothing new to save")
        XCTAssertEqual(GitHubRepo.kept(for: world.wish)?.taken, merged)

        // GitHub has the app as it is already: nothing new goes up, and the record names the merge as Lamp's.
        let released = try await releaseOverBroughtIn(world)
        XCTAssertEqual(released.commit, merged)
        XCTAssertNil(released.taken)
        XCTAssertEqual(try sh("git --git-dir \(Sandbox.quoted(world.bare.path)) rev-parse main", in: world.place), merged)
        XCTAssertEqual(try onGitHub(world, "Sources/Counter.swift"), "let step = 2\n")
    }

    /// The repository's own files edited on GitHub (its README, a file the app never had) stay as GitHub has them; a
    /// file of the app's taken away in the app after it was brought in stays taken away.
    @MainActor
    func testAReadmeEditedOnGitHubSurvivesTheRelease() async throws {
        let world = try world()
        _ = try await release(world, isNew: true)
        let readme = "# Tally\n\nEdited on GitHub by its owner.\n"
        try mergeOnGitHub(world, ["README.md": readme, "docs/notes.md": "Notes kept on GitHub\n", "Sources/Twos.swift": "let twos = true\n"])
        _ = try await bringIn(world)
        XCTAssertNil(code(world, "docs/notes.md"), "not the app's: it stays on GitHub alone")
        try FileManager.default.removeItem(at: world.wish.dir.appendingPathComponent("Sources/Twos.swift"))
        let saved = await Versions.save(world.wish, message: "No twos after all")
        XCTAssertTrue(saved)

        _ = try await releaseOverBroughtIn(world)
        XCTAssertEqual(try onGitHub(world, "README.md"), readme)
        XCTAssertEqual(try onGitHub(world, "docs/notes.md"), "Notes kept on GitHub\n")
        XCTAssertNil(try onGitHub(world, "Sources/Twos.swift"), "taken away in the app after it came in")
    }

    /// GitHub force-pushed after a bring-in that wasn't released yet: the next bring-in measures against what the last
    /// one took in (its kept tree), never the older push, so what the force push took away goes from the app too.
    /// And an Undo of a bring-in is found before a release could undo it on GitHub.
    @MainActor
    func testAForcePushIsMeasuredFromWhatWasLastBroughtIn() async throws {
        let world = try world()
        let first = try await release(world, isNew: true)
        let pushed = try XCTUnwrap(first.commit)
        let b = try mergeOnGitHub(world, ["Sources/Extra.swift": "let extra = 1\n"])
        _ = try await bringIn(world)
        XCTAssertEqual(code(world, "Sources/Extra.swift"), "let extra = 1\n")
        XCTAssertEqual(GitHubRepo.kept(for: world.wish)?.taken, b)

        // GitHub's main replaced: B gone (and its objects with it), C on top of Lamp's push in its place.
        let c = try mergeOnGitHub(world, ["Sources/Other.swift": "let other = 1\n"], force: true, from: pushed)
        _ = try sh("git --git-dir \(Sandbox.quoted(world.bare.path)) reflog expire --expire=now --all && git --git-dir \(Sandbox.quoted(world.bare.path)) gc -q --prune=now", in: world.place)
        XCTAssertNotEqual(try escape.loose("git --git-dir \(Sandbox.quoted(world.bare.path)) cat-file -e \(b)", in: world.place).status, 0, "B is gone from GitHub")

        let again = try await bringIn(world)
        XCTAssertEqual(again.pull.base, b)
        XCTAssertEqual(again.given, .staged(BringIn.snapshot(b)))
        XCTAssertNil(code(world, "Sources/Extra.swift"), "the force push took it away")
        XCTAssertEqual(code(world, "Sources/Other.swift"), "let other = 1\n")
        XCTAssertEqual(GitHubRepo.kept(for: world.wish)?.taken, c)

        // Back to before the bring-in: the wish no longer has it, so a release is refused rather than undoing C.
        let versions = await Versions.list(world.wish)
        XCTAssertEqual(versions.first?.message, "Pulled in someone/tally on GitHub")
        let beforeBringIn = versions[1]
        let wentBack = await Versions.restore(world.wish, to: beforeBringIn, message: Versions.restoredMessage(to: beforeBringIn),
                                              trailer: Versions.restoredTrailer(beforeBringIn))
        XCTAssertTrue(wentBack)
        let kept = try XCTUnwrap(GitHubRepo.kept(for: world.wish))
        let holds = await BringIn.holds(world.wish, kept: kept)
        XCTAssertFalse(holds)
        do {
            _ = try await releaseOverBroughtIn(world)
            XCTFail("a release over changes the wish took back was to be refused")
        } catch is GitHubRepo.Moved {}
        XCTAssertEqual(try sh("git --git-dir \(Sandbox.quoted(world.bare.path)) rev-parse main", in: world.place), c)
    }
}
