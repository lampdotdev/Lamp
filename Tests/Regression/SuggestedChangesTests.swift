import XCTest
@testable import Lamp

/// The owner's half of a request sent to their app on GitHub, brought in from Lamp rather than merged there: the
/// request's head merged into the wish, then gone with the next release as one more parent of its commit, which is what
/// GitHub reads to mark the request merged. GitHub here is a bare repository on disk, a request a ref under
/// refs/pull/<n>/head in it, and `gh` a stand-in answering from files the test writes.
final class SuggestedChangesTests: XCTestCase {
    private let escape = HistoryEscapeTests()
    override func setUp() { expectNoSharingFoldersLeft() }
    override func tearDown() { escape.tearDown() }

    private struct World {
        let wish: LampProject
        let bare: URL
        let gh: URL
        let place: URL
        /// What the stand-in `gh` answers: the open requests, and the commit a compare names as their merge base.
        let pulls: URL
        let mergeBase: URL
    }

    private func sh(_ command: String, in folder: URL) throws -> String {
        let ran = try escape.loose(command, in: folder)
        XCTAssertEqual(ran.status, 0, "\(command): \(ran.output)")
        return ran.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func world() throws -> World {
        let app = try escape.app()
        let place = app.root
        let bare = place.appendingPathComponent("tally.git")
        _ = try sh("git init -q --bare -b main \(Sandbox.quoted(bare.path))", in: place)
        let pulls = place.appendingPathComponent("pulls.json"), mergeBase = place.appendingPathComponent("merge-base")
        try "[]".write(to: pulls, atomically: true, encoding: .utf8)
        let gh = place.appendingPathComponent("gh")
        try """
        #!/bin/zsh
        [[ "$1 $2" == "repo view" ]] && { echo PRIVATE; exit 0 }
        [[ "$1" == api && "$2" == --paginate && "$3" == repos/someone/tally/pulls\\?* ]] && { /usr/bin/python3 -c 'import json,sys; [print(json.dumps(i)) for i in json.load(open(sys.argv[1]))]' \(Sandbox.quoted(pulls.path)); exit 0 }
        [[ "$1" == api && "$2" == repos/someone/tally/pulls/* ]] && { f=\(Sandbox.quoted(place.path))/state-${2##*/}; [[ -f $f ]] && cat $f || printf 'open\\tfalse\\n'; exit 0 }
        [[ "$1" == api && "$2" == repos/someone/tally/compare/* && "$4" == .merge_base_commit.sha ]] && { cat \(Sandbox.quoted(mergeBase.path)); exit 0 }
        exit 0
        """.write(to: gh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gh.path)
        let surroundings = ["GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "url.\(bare.absoluteString).insteadOf",
                            "GIT_CONFIG_VALUE_0": "https://github.com/someone/tally.git"]
        for (name, value) in surroundings { setenv(name, value, 1) }
        let keptURL = GitHubRepo.keptURL, pendingURL = BringIn.keptURL, suggestedURL = SuggestedChanges.keptURL
        GitHubRepo.keptURL = place.appendingPathComponent("kept.json")
        BringIn.keptURL = place.appendingPathComponent("bring-in.json")
        SuggestedChanges.keptURL = place.appendingPathComponent("suggested.json")
        addTeardownBlock {
            for name in surroundings.keys { unsetenv(name) }
            GitHubRepo.keptURL = keptURL
            BringIn.keptURL = pendingURL
            SuggestedChanges.keptURL = suggestedURL
        }
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: place)
        try Template.writeOwnedFiles(for: wish)
        try "let step = 1\n".write(to: wish.dir.appendingPathComponent("Sources/Counter.swift"), atomically: true, encoding: .utf8)
        _ = try sh("git init -q -b main && printf '.lamp/\\n.build/\\nbuild/\\n' > .gitignore && git add -A && git -c user.name=Lamp -c user.email=lamp@localhost commit -qm first", in: wish.dir)
        return World(wish: wish, bare: bare, gh: gh, place: place, pulls: pulls, mergeBase: mergeBase)
    }

    /// A Release Update's push, short of its tag and page, with the requests it goes with.
    private func release(_ world: World, isNew: Bool, merging: [String] = []) async throws -> GitHubRepo.Repo {
        let before = GitHubRepo.kept(for: world.wish)
        let staged = try GitHubRepo.stage(world.wish, repo: "someone/tally", link: nil, isPublic: false)
        defer { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        let up = try await GitHubRepo.upload(staged, of: world.wish, to: "someone/tally", gh: world.gh.path, login: "someone", isNew: isNew,
                                             expected: before?.expected, merging: merging, isPrivate: true, license: false) { _ in }
        GitHubRepo.keep(up.repo, for: world.wish)
        return up.repo
    }

    /// Someone's request: `files` changed on top of main, pushed where GitHub keeps request `number`, and listed open.
    private func openRequest(_ world: World, number: Int, _ files: [String: String], on base: String? = nil) throws -> String {
        let work = world.place.appendingPathComponent("contributor-\(UUID().uuidString)")
        _ = try sh("git clone -q \(Sandbox.quoted(world.bare.path)) \(Sandbox.quoted(work.path))", in: world.place)
        if let base { _ = try sh("git fetch -q origin \(base) && git reset -q --hard \(base)", in: work) }
        for (path, text) in files {
            let url = work.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let head = try sh("git add -A && git -c user.name=Remixer -c user.email=remixer@example.com commit -qm 'changes from a remix' && git push -q origin HEAD:refs/pull/\(number)/head && git rev-parse HEAD", in: work)
        try FileManager.default.removeItem(at: work)
        var listed = (try JSONSerialization.jsonObject(with: Data(contentsOf: world.pulls))) as? [[String: Any]] ?? []
        listed.removeAll { $0["number"] as? Int == number }
        listed.append(["number": number, "title": "Tally: changes from a remix", "html_url": "https://github.com/someone/tally/pull/\(number)",
                       "user": ["login": "remixer"], "head": ["sha": head],
                       "base": ["ref": "main", "repo": ["default_branch": "main"]]])
        try JSONSerialization.data(withJSONObject: listed).write(to: world.pulls)
        return head
    }

    /// Bring In… as Update on its review does it: fetched, merged against the request's base, saved, and counted.
    @MainActor
    private func bringIn(_ world: World, number: Int) async throws -> BringIn.Pull {
        let kept = try XCTUnwrap(GitHubRepo.kept(for: world.wish))
        let request = try XCTUnwrap(SuggestedChanges.record(for: world.wish)?.request(number))
        let fetched = try await SuggestedChanges.fetch(world.wish, kept: kept, request: request, gh: world.gh.path)
        defer { try? FileManager.default.removeItem(at: fetched.folder) }
        let package = try RepoImport.open(folder: fetched.tree)
        defer { try? FileManager.default.removeItem(at: package.folder) }
        let given = try await BringIn.given(for: fetched.pull, kept: kept, in: world.wish)
        let merged = try await Upstream.merge(package, into: world.wish, from: nil, commit: nil, arrival: nil, ref: BringIn.incomingRef, given: given)
        await BringIn.keepBase(fetched.pull, mark: merged.baseMark, in: world.wish)
        XCTAssertEqual(merged.conflicts, [])
        if await Versions.hasUnsavedChanges(world.wish) {
            let saved = await Versions.save(world.wish, message: "Pulled in @remixer's suggested changes")
            XCTAssertTrue(saved)
        }
        await BringIn.accept(fetched.pull, in: world.wish)
        return fetched.pull
    }

    private func parents(_ world: World, of rev: String = "main") throws -> [String] {
        try sh("git --git-dir \(Sandbox.quoted(world.bare.path)) log -1 --format=%P \(rev)", in: world.place).split(separator: " ").map(String.init)
    }

    // MARK: The cases

    /// A request brought in, then released: the release's commit has the request's head as its second parent (what makes
    /// GitHub mark it merged), the app's own change goes with it, and the record says which release it went with. The
    /// repository itself never moved, so nothing counts as taken from it.
    @MainActor
    func testABroughtInRequestGoesWithTheNextReleaseAsAParent() async throws {
        let world = try world()
        let first = try await release(world, isNew: true)
        let pushed = try XCTUnwrap(first.commit)
        try pushed.write(to: world.mergeBase, atomically: true, encoding: .utf8)
        let head = try openRequest(world, number: 7, ["Sources/Counter.swift": "let step = 2\n"])

        let finding = await SuggestedChanges.find(world.wish, kept: first, gh: world.gh.path)
        let found = try XCTUnwrap(finding)
        XCTAssertEqual(found.new, [7])
        XCTAssertEqual(found.record.unseen, [7])

        let pull = try await bringIn(world, number: 7)
        XCTAssertEqual(pull.base, pushed, "measured from where the request branched")
        XCTAssertEqual(pull.head, head)
        XCTAssertEqual(try String(contentsOf: world.wish.dir.appendingPathComponent("Sources/Counter.swift"), encoding: .utf8), "let step = 2\n")
        let taken = try XCTUnwrap(SuggestedChanges.record(for: world.wish)?.taken(7))
        XCTAssertEqual(taken.head, head, "pinned at the head reviewed")
        XCTAssertNil(GitHubRepo.kept(for: world.wish)?.taken, "the repository didn't move")
        XCTAssertEqual(SuggestedChanges.record(for: world.wish)?.unseen, [])

        let going = await SuggestedChanges.parents(for: world.wish, gh: world.gh.path)
        XCTAssertEqual(going.map(\.head), [head])
        let released = try await release(world, isNew: false, merging: going.map(\.head))
        XCTAssertEqual(try parents(world), [pushed, head])
        XCTAssertEqual(SuggestedChanges.record(for: world.wish)?.taken(7)?.released, released.commit)
        let again = await SuggestedChanges.parents(for: world.wish, gh: world.gh.path)
        XCTAssertEqual(again, [], "a request goes with one release only")
    }

    /// A release with nothing else to change (the request's change went up before, without it) still makes
    /// a commit when a request goes with it, since the parent is what marks the request merged.
    @MainActor
    func testARequestGoesEvenWhenTheFilesAreUnchanged() async throws {
        let world = try world()
        let first = try await release(world, isNew: true)
        try XCTUnwrap(first.commit).write(to: world.mergeBase, atomically: true, encoding: .utf8)
        let head = try openRequest(world, number: 3, ["Sources/Counter.swift": "let step = 5\n"])
        _ = await SuggestedChanges.find(world.wish, kept: first, gh: world.gh.path)
        _ = try await bringIn(world, number: 3)
        let plain = try await release(world, isNew: false)
        let tip = try XCTUnwrap(plain.commit)

        _ = try await release(world, isNew: false, merging: [head])
        XCTAssertEqual(try parents(world), [tip, head])
        XCTAssertEqual(try sh("git --git-dir \(Sandbox.quoted(world.bare.path)) diff --stat \(tip) main -- . ':!lamp-app.json' ':!credits.json'", in: world.place), "",
                       "the same files, but for the release's own bookkeeping")
    }

    /// What a release may go with, by GitHub's ancestry: a request rewritten since it was brought in, one whose files a
    /// release leaves out, one the wish no longer has, and one with an open request it doesn't have under it, stay out.
    func testOnlyRequestsTheReleaseReallyHasGoAsParents() async {
        func taken(_ number: Int, _ head: String, leftOut: [String]? = nil) -> SuggestedChanges.Taken {
            SuggestedChanges.Taken(number: number, head: head, base: "base", takenIn: "v\(number)", leftOut: leftOut, checked: true)
        }
        func open(_ number: Int, _ head: String) -> SuggestedChanges.Request {
            SuggestedChanges.Request(number: number, login: "remixer", title: "t", head: head, url: "u")
        }
        var record = SuggestedChanges.Record(repo: "someone/tally")
        record.open = [open(1, "h1"), open(2, "h2-rewritten"), open(3, "h3"), open(4, "h4"), open(5, "h5"), open(6, "h6-lower"), open(7, "h7")]
        record.taken = [taken(1, "h1"), taken(2, "h2"), taken(3, "h3", leftOut: [".github/workflows/x.yml"]), taken(4, "h4"), taken(5, "h5"), taken(7, "h7")]
        // 5 sits on 6, which wasn't brought in; 7 sits on 1, which goes too.
        let under: Set<[String]> = [["h6-lower", "h5"], ["h1", "h7"]]
        let going = await SuggestedChanges.parents(record, holds: { $0.number != 4 }, isAncestor: { under.contains([$0, $1]) })
        XCTAssertEqual(going.map(\.number), [1, 7])
    }


    /// A file the import doesn't take (a Mac app's README, which a release writes afresh) keeps the request from going as
    /// a parent: GitHub would mark it merged without that change.
    @MainActor
    func testARequestChangingAFileTheImportDropsDoesNotGoAsAParent() async throws {
        let world = try world()
        let first = try await release(world, isNew: true)
        try XCTUnwrap(first.commit).write(to: world.mergeBase, atomically: true, encoding: .utf8)
        _ = try openRequest(world, number: 4, ["Sources/Counter.swift": "let step = 3\n", "README.md": "Better words.\n"])
        _ = await SuggestedChanges.find(world.wish, kept: first, gh: world.gh.path)
        let pull = try await bringIn(world, number: 4)
        XCTAssertEqual(pull.checked, true)
        XCTAssertEqual(pull.leftOut, ["README.md"])
        let going = await SuggestedChanges.parents(for: world.wish, gh: world.gh.path)
        XCTAssertEqual(going, [])
    }

    /// Brought in again after its sender added to it, a request still remembers what of it a release can't carry: the
    /// check covers the whole request, not only what came in the second time.
    @MainActor
    func testWhatARequestLeftOutStaysLeftOutAfterItsBroughtInAgain() async throws {
        let world = try world()
        let first = try await release(world, isNew: true)
        let pushed = try XCTUnwrap(first.commit)
        try pushed.write(to: world.mergeBase, atomically: true, encoding: .utf8)
        let one = try openRequest(world, number: 5, ["Sources/Counter.swift": "let step = 3\n", ".github/workflows/x.yml": "on: push\n"])
        _ = await SuggestedChanges.find(world.wish, kept: first, gh: world.gh.path)
        _ = try await bringIn(world, number: 5)
        let two = try openRequest(world, number: 5, ["Sources/Counter.swift": "let step = 4\n"], on: one)
        _ = await SuggestedChanges.find(world.wish, kept: first, gh: world.gh.path)
        let again = try await bringIn(world, number: 5)
        XCTAssertEqual(again.base, one, "only what's new is merged")
        XCTAssertEqual(again.head, two)
        XCTAssertEqual(SuggestedChanges.record(for: world.wish)?.taken(5)?.leftOut, [".github/workflows/x.yml"])
        let going = await SuggestedChanges.parents(for: world.wish, gh: world.gh.path)
        XCTAssertEqual(going, [])
    }

    /// Every page of open requests is read; one GitHub still calls open is never taken for closed; one closed and opened
    /// again is open, with its card shown again.
    @MainActor
    func testOpenAndClosedAreWhatGitHubSays() async throws {
        let world = try world()
        let first = try await release(world, isNew: true)
        try XCTUnwrap(first.commit).write(to: world.mergeBase, atomically: true, encoding: .utf8)
        _ = try openRequest(world, number: 1, ["Sources/One.swift": "let one = 1\n"])
        _ = try openRequest(world, number: 2, ["Sources/Two.swift": "let two = 2\n"])
        var found = await SuggestedChanges.find(world.wish, kept: first, gh: world.gh.path)
        XCTAssertEqual(found?.record.open.map(\.number), [1, 2])

        // Missing from the list but open by its own answer: still open.
        let listed = try Data(contentsOf: world.pulls)
        try JSONSerialization.data(withJSONObject: [((try JSONSerialization.jsonObject(with: listed)) as? [[String: Any]] ?? [])[1]]).write(to: world.pulls)
        found = await SuggestedChanges.find(world.wish, kept: first, gh: world.gh.path)
        XCTAssertEqual(found?.record.open.map(\.number).sorted(), [1, 2])
        XCTAssertNil(found?.record.ended["1"])

        // Closed by GitHub's own answer, then opened again.
        try "closed\tfalse\n".write(to: world.place.appendingPathComponent("state-1"), atomically: true, encoding: .utf8)
        found = await SuggestedChanges.find(world.wish, kept: first, gh: world.gh.path)
        XCTAssertEqual(found?.record.ended["1"], .closed)
        try JSONSerialization.data(withJSONObject: (try JSONSerialization.jsonObject(with: listed))).write(to: world.pulls)
        found = await SuggestedChanges.find(world.wish, kept: first, gh: world.gh.path)
        XCTAssertNil(found?.record.ended["1"])
        XCTAssertEqual(found?.new, [1], "its card comes back")
    }

    /// A request that wasn't brought in at the same head as one that was would be marked merged with it; dropping one
    /// for that uncovers the next.
    func testARequestAtTheSameHeadThatWasntBroughtInHoldsItBack() async {
        func taken(_ number: Int, _ head: String, checked: Bool = true) -> SuggestedChanges.Taken {
            SuggestedChanges.Taken(number: number, head: head, base: "base", takenIn: "v\(number)", checked: checked)
        }
        func open(_ number: Int, _ head: String) -> SuggestedChanges.Request {
            SuggestedChanges.Request(number: number, login: "remixer", title: "t", head: head, url: "u")
        }
        var record = SuggestedChanges.Record(repo: "someone/tally")
        record.open = [open(1, "h1"), open(2, "h1"), open(3, "h3"), open(4, "h4")]
        record.taken = [taken(1, "h1"), taken(3, "h3"), taken(4, "h4", checked: false)]
        // 1 sits under 3.
        let going = await SuggestedChanges.parents(record, holds: { _ in true }, isAncestor: { $0 == "h1" && $1 == "h3" })
        XCTAssertEqual(going.map(\.number), [], "2 holds 1 back, 1 then holds 3 back, and 4 was never checked")
        record.taken.append(taken(2, "h1"))
        let all = await SuggestedChanges.parents(record, holds: { _ in true }, isAncestor: { $0 == "h1" && $1 == "h3" })
        XCTAssertEqual(all.map(\.number), [1, 3, 2])
    }
}
