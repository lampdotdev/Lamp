import XCTest
@testable import Lamp

/// A wish the agent made from someone's project on GitHub gets its updates the way a wish opened from GitHub does: the
/// same button in its Credits, the same "An update is available", with nothing the person reads naming a repository,
/// "upstream", "original" or a commit. Its credited commit moves on only when the update's turn finished well.
final class AppUpdatesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-app-updates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private let slop = Credits.Source(name: "Slop New York", author: "Mr.doob", url: "https://github.com/mrdoob/slop-newyork",
                                      commit: "dcb453fbba807d7f95d910f824a4abef849fde13", license: "MIT")
    private let font = Credits.Source(name: "Inter", author: "Rasmus Andersson", url: "https://github.com/rsms/inter",
                                      commit: "1234567890abcdef1234567890abcdef12345678", license: "OFL-1.1")

    // MARK: Which source is checked

    func testAWishMadeFromAProjectFollowsTheWorkItIsBasedOn() {
        let credits = Credits(upstream: [slop, font])
        XCTAssertEqual(AppUpdates.route(for: credits, own: nil), .adapted(slop))
    }

    func testAWishFromAnotherWishKeepsFollowingThatWish() {
        let remix = Credits.Remix(name: "New York", url: "https://github.com/someone/new-york", commit: "abcdef1")
        let credits = Credits(upstream: [slop], remixOf: [remix])
        XCTAssertEqual(AppUpdates.route(for: credits, own: nil), .wish(remix))
    }

    func testASourceWithNoCommitIsOfferedNothing() {
        var source = slop
        source.commit = nil
        XCTAssertNil(AppUpdates.route(for: Credits(upstream: [source]), own: nil))
        XCTAssertNil(AppUpdates.route(for: Credits(upstream: [Credits.Source(name: "Kenney", url: "https://kenney.nl", commit: nil)]), own: nil))
    }

    func testTheWishsOwnRepositoryIsNotWhereItCameFrom() {
        XCTAssertNil(AppUpdates.route(for: Credits(upstream: [slop]), own: "https://github.com/mrdoob/slop-newyork"))
    }

    // MARK: The cheap check

    /// `git ls-remote https://github.com/mrdoob/slop-newyork.git HEAD`, recorded 2026-10-28.
    private let lsRemote = ["13dd142b480bcfa01a6b18e36127c87e41cb4d80\tHEAD"]

    func testTheTipIsReadFromWhatGitHubAnswers() {
        XCTAssertEqual(AppUpdates.tip(fromLsRemote: lsRemote), "13dd142b480bcfa01a6b18e36127c87e41cb4d80")
        XCTAssertNil(AppUpdates.tip(fromLsRemote: []))
        XCTAssertNil(AppUpdates.tip(fromLsRemote: ["fatal: repository not found"]))
    }

    func testAvailability() {
        let route = AppUpdates.Route.adapted(slop)
        let tip = AppUpdates.tip(fromLsRemote: lsRemote)
        XCTAssertNil(AppUpdates.availability(of: route, check: nil))
        XCTAssertEqual(AppUpdates.availability(of: route, check: .init(tip: tip, at: Date())), .available)
        var current = slop
        current.commit = "13dd142"   // written short
        XCTAssertEqual(AppUpdates.availability(of: .adapted(current), check: .init(tip: tip, at: Date())), .upToDate)
        // A failed check never says up to date.
        XCTAssertEqual(AppUpdates.availability(of: .adapted(current), check: .init(tip: nil, at: Date())), .failed)
        XCTAssertEqual(AppUpdates.availability(of: route, check: .init(tip: tip, at: Date(), checking: true)), .checking)
    }

    // MARK: What the person reads

    func testCreditsOfferTheSameButtonForEveryKindOfWish() throws {
        let adapted = try XCTUnwrap(AppInfoView.creditsSection(Credits(upstream: [slop]), own: nil, update: .available))
        XCTAssertEqual(adapted.rows.first { $0.label == "Updates" }?.value, "An update is available")
        XCTAssertEqual(adapted.buttons.last?.title, "Review Update…")
        XCTAssertEqual(adapted.buttons.last?.action, AppInfoView.updateFromRepository)

        let remix = Credits.Remix(name: "New York", url: "https://github.com/someone/new-york", commit: "abcdef1")
        let wish = try XCTUnwrap(AppInfoView.creditsSection(Credits(remixOf: [remix]), own: nil, update: .upToDate))
        XCTAssertEqual(wish.rows.first { $0.label == "Updates" }?.value, "Your app is up to date")
        XCTAssertEqual(wish.buttons.last?.title, "Check for Updates…")

        // An update being prepared, or ready, is reviewed from the same button, never checked for again.
        for state in [AppUpdates.Availability.preparing, .ready] {
            let section = try XCTUnwrap(AppInfoView.creditsSection(Credits(upstream: [slop]), own: nil, update: state))
            XCTAssertEqual(section.buttons.last?.title, "Review Update…")
        }

        let unchecked = try XCTUnwrap(AppInfoView.creditsSection(Credits(upstream: [slop]), own: nil))
        XCTAssertNil(unchecked.rows.first { $0.label == "Updates" })
        XCTAssertEqual(unchecked.buttons.last?.title, "Check for Updates…")

        // Nothing to update from: no button.
        var pinned = slop
        pinned.commit = nil
        let none = try XCTUnwrap(AppInfoView.creditsSection(Credits(upstream: [pinned]), own: nil, update: nil))
        XCTAssertFalse(none.buttons.contains { $0.action == AppInfoView.updateFromRepository })
    }

    func testNothingThePersonReadsNamesWhereTheUpdateComesFrom() {
        let said = [AppUpdates.request] + [AppUpdates.Availability.checking, .upToDate, .available, .failed, .preparing, .ready].map(\.line)
        for line in said {
            for word in ["upstream", "original", "commit", "repositor", "github", "13dd142", "dcb453f"] {
                XCTAssertFalse(line.lowercased().contains(word), "“\(line)” says \(word)")
            }
        }
    }

    // MARK: Accepting

    func testOnlyAFinishedUpdateIsOfferedForReview() {
        XCTAssertEqual(AppUpdates.settle(end: .changed, errors: false, asking: false), .ready)
        XCTAssertEqual(AppUpdates.settle(end: .changed, errors: true, asking: false), .failed)
        XCTAssertEqual(AppUpdates.settle(end: .failed, errors: true, asking: false), .failed)
        XCTAssertEqual(AppUpdates.settle(end: .replied, errors: false, asking: true), .waiting)
        // Nothing in the update applied to the app: the turn changed nothing and asked nothing, and is done.
        XCTAssertEqual(AppUpdates.settle(end: .replied, errors: false, asking: false), .ready)
    }

    /// A credit written with `.git` or a slash at the end is fetched from the repository's own address, as it's checked.
    func testTheUpdateIsFetchedFromTheRepositorysOwnAddress() throws {
        for url in ["https://github.com/mrdoob/slop-newyork.git", "https://github.com/mrdoob/slop-newyork/"] {
            var source = slop
            source.url = url
            let route = try XCTUnwrap(AppUpdates.route(for: Credits(upstream: [source]), own: nil))
            XCTAssertEqual(AppUpdates.job(for: route, tip: "13dd142b480bcfa01a6b18e36127c87e41cb4d80", wish: "slop")?.url,
                           "https://github.com/mrdoob/slop-newyork")
        }
    }

    /// What the agent spent preparing an update in its copy goes on the app it was for: $0.30 isn't lost with the copy.
    func testWhatAnUpdateCostIsKeptOnTheApp() {
        let app = AppUsage(calls: 4, cost: 0.02, agentRuns: 3, agentCost: 1.10)
        let copy = AppUsage(calls: 0, cost: 0, agentRuns: 1, agentCost: 0.30)
        let total = app.adding(copy)
        XCTAssertEqual(total.agentRuns, 4)
        XCTAssertEqual(total.agentCost ?? 0, 1.40, accuracy: 0.0001)
        XCTAssertEqual(total.calls, 4)
        XCTAssertEqual(AppUsage().adding(copy).totalCost, 0.30, accuracy: 0.0001)
    }

    /// An update's review has no sender to trust: its warnings speak of the update.
    func testAnUpdatesReviewDoesNotSpeakOfASender() {
        for verdict in ["risky", "partly"] {
            let review = ImportReview(summary: "A game.", capabilities: [], concerns: [], risk: verdict == "risky" ? .high : .low,
                                      reviewer: ImportReview.Reviewer(name: "Sonnet", onThisMac: false), asked: true, detected: [],
                                      partial: verdict == "partly")
            let lines = ImportReviewCard.considerations(review, prepared: true).map(\.text)
            XCTAssertFalse(lines.isEmpty, verdict)
            XCTAssertFalse(lines.contains { $0.contains("sender") }, "\(lines)")
            XCTAssertTrue(ImportReviewCard.considerations(review).contains { $0.text.contains("sender") }, verdict)
        }
    }

    /// A wish changed after its copy was made isn't replaced by that copy: the change would be lost.
    func testAWishChangedSinceTheCopyWasMadeIsNotReplaced() {
        let job = AppUpdates.Job(url: slop.url!, base: slop.commit!, target: "13dd142b480bcfa01a6b18e36127c87e41cb4d80", wish: "slop", head: "aaaa111")
        XCTAssertFalse(AppUpdates.isStale(job, head: "aaaa111", unsaved: false))
        XCTAssertTrue(AppUpdates.isStale(job, head: "bbbb222", unsaved: false))
        XCTAssertTrue(AppUpdates.isStale(job, head: "aaaa111", unsaved: true))
    }

    /// What the copy's credits gained while the update was prepared goes into the app with its files; the copy's link
    /// to the app it was copied from doesn't.
    func testAnUpdateKeepsTheCreditsItsCopyGained() {
        let job = AppUpdates.Job(url: slop.url!, base: slop.commit!, target: "13dd142b480bcfa01a6b18e36127c87e41cb4d80", wish: "newyork")
        let kept = Credits(upstream: [slop])
        var moved = slop
        moved.commit = job.target
        let library = Credits.Source(name: "Tween", author: "Someone", url: "https://github.com/someone/tween",
                                     commit: "abcdef1234567", license: "MIT")
        let prepared = Credits(upstream: [moved, library], remixOf: [Credits.Remix(name: "New York", wish: UUID().uuidString)],
                               generated: [Credits.Generated(file: "Web/sky.png")])
        let after = AppUpdates.credits(afterUpdating: kept, with: prepared, job: job)
        XCTAssertEqual(after.upstream.map(\.name), ["Slop New York", "Tween"])
        XCTAssertEqual(after.upstream.first?.commit, job.target)
        XCTAssertEqual(after.generated.map(\.file), ["Web/sky.png"])
        XCTAssertTrue(after.remixOf.isEmpty)
    }

    func testAnAcceptedUpdateMovesBothCreditRecordsAndNothingElse() throws {
        let dir = root.appendingPathComponent("slop")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        let project = LampProject(id: "slop", name: "Slop", exe: "Slop", dir: dir)
        try Credits.arrive(Credits(upstream: [slop, font]), in: project)
        let job = AppUpdates.Job(url: "https://github.com/mrdoob/slop-newyork.git", base: slop.commit!, target: "13dd142b480bcfa01a6b18e36127c87e41cb4d80")

        let source = try XCTUnwrap(AppUpdates.accepted(job, in: Credits.load(project)).upstream.first)
        try Credits.add(Credits(upstream: [source]), to: project)

        for record in [Credits.file, Credits.arrivedPath] {
            let credits = try XCTUnwrap(Credits.read(dir.appendingPathComponent(record)))
            XCTAssertEqual(credits.upstream.map(\.commit), [job.target, font.commit], record)
            XCTAssertEqual(credits.upstream.first?.license, "MIT", record)
        }
        XCTAssertEqual(AppUpdates.route(of: project)?.commit, job.target)
    }

    // MARK: Fetching (live: GitHub)

    /// The change between two real commits, fetched as Lamp fetches it (confined git, no blobs until needed) into the
    /// wish's .lamp. Run with LAMP_LIVE_GITHUB=1.
    func testFetchingAnUpdateGivesTheAgentTheWholeChange() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LAMP_LIVE_GITHUB"] == "1", "Set LAMP_LIVE_GITHUB=1 to fetch from GitHub")
        let dir = root.appendingPathComponent("slop")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        let project = LampProject(id: "slop", name: "Slop", exe: "Slop", dir: dir)
        let job = AppUpdates.Job(url: "https://github.com/mrdoob/slop-newyork", base: "dcb453f", target: "13dd142b480bcfa01a6b18e36127c87e41cb4d80")
        try await AppUpdates.fetch(job, for: project)
        let update = dir.appendingPathComponent(AppUpdates.Job.folder)
        let files = try String(contentsOf: update.appendingPathComponent("files.txt"), encoding: .utf8)
        let log = try String(contentsOf: update.appendingPathComponent("log.txt"), encoding: .utf8)
        let diff = try String(contentsOf: update.appendingPathComponent("changes.diff"), encoding: .utf8)
        XCTAssertFalse(files.isEmpty)
        XCTAssertTrue(log.contains("PersonRig"), log)
        XCTAssertTrue(diff.hasPrefix("diff --git"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: update.appendingPathComponent("latest").path))
        XCTAssertEqual(AppUpdates.Job.load(project), job)

        // A base that isn't there gives no made-up change, and leaves nothing behind.
        let gone = AppUpdates.Job(url: job.url, base: "0000000000000000000000000000000000000001", target: job.target)
        do {
            try await AppUpdates.fetch(gone, for: project)
            XCTFail("fetched a change from a base that isn't there")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: update.appendingPathComponent("files.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: update.appendingPathComponent("latest").path))

        // Stop ends the fetch: git's process, handed to whatever holds the copy, is ended, and nothing is left fetched.
        do {
            try await AppUpdates.fetch(job, for: project, started: { Subprocess.terminateTree($0) })
            XCTFail("a stopped fetch finished")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: update.appendingPathComponent("changes.diff").path))
    }
}

/// The boundaries around a prepared update: what may run before review, which turns finish it, and which version of a
/// project Make App builds.
final class AppUpdateBoundaryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-update-bounds-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    /// A copy an update is prepared in isn't installed, opened or used before the person has reviewed it; once it's kept,
    /// or for any other app, it is.
    func testACopyAwaitingReviewIsNeverOpened() throws {
        let copy = LampProject(id: "newyorkupdate", name: "New York Update", exe: "NewYorkUpdate", dir: root)
        XCTAssertTrue(AppUpdates.mayOpen(copy))
        try AppUpdates.Job(url: "https://github.com/mrdoob/slop-newyork", base: "dcb453f", target: "13dd142", wish: "newyork").save(in: copy)
        XCTAssertFalse(AppUpdates.mayOpen(copy))
        AppUpdates.Job.clear(copy)
        XCTAssertTrue(AppUpdates.mayOpen(copy))
    }

    /// After a preparation that failed, a question about why isn't the update: only the update's request, or answers to
    /// the agent's questions during it, can finish it.
    func testOnlyTheUpdatesOwnTurnFinishesIt() {
        let asked = UUID()
        var job = AppUpdates.Job(url: "https://github.com/mrdoob/slop-newyork", base: "dcb453f", target: "13dd142", wish: "newyork")
        job.cards = [asked.uuidString]
        XCTAssertTrue(AppUpdates.isUpdateTurn([QueuedMessage(text: AppUpdates.request)], job: job))
        XCTAssertTrue(AppUpdates.isUpdateTurn([QueuedMessage(text: "The second one", card: asked)], job: job))
        XCTAssertFalse(AppUpdates.isUpdateTurn([QueuedMessage(text: "Why did it fail?")], job: job))
        XCTAssertFalse(AppUpdates.isUpdateTurn([], job: job))
    }

    /// After a preparation that failed, the person asks for something else and answers the agent's question about
    /// that: the answer isn't the update's, so it can't finish it.
    func testAnAnswerToAnotherQuestionIsNotTheUpdates() {
        var job = AppUpdates.Job(url: "https://github.com/mrdoob/slop-newyork", base: "dcb453f", target: "13dd142", wish: "newyork")
        job.cards = [UUID().uuidString]
        XCTAssertFalse(AppUpdates.isUpdateTurn([QueuedMessage(text: "Blue", card: UUID())], job: job))
        XCTAssertFalse(AppUpdates.isUpdateTurn([QueuedMessage(text: "Blue", card: UUID())],
                                               job: AppUpdates.Job(url: job.url, base: job.base, target: job.target, wish: job.wish)))
    }

    /// A copy waiting for its review can't be duplicated: the duplicate would be an app of its own with no review to
    /// pass, and would be built and opened at once.
    func testACopyAwaitingReviewCannotBeDuplicated() throws {
        let copy = LampProject(id: "newyorkupdate", name: "New York Update", exe: "NewYorkUpdate", dir: root)
        XCTAssertTrue(AppUpdates.mayDuplicate(copy))
        try AppUpdates.Job(url: "https://github.com/mrdoob/slop-newyork", base: "dcb453f", target: "13dd142", wish: "newyork").save(in: copy)
        XCTAssertFalse(AppUpdates.mayDuplicate(copy))
    }

    /// A message sent to a copy while Update deletes it goes to the app the copy went into, however long deleting takes.
    @MainActor
    func testAMessageToACopyBeingDeletedGoesToTheApp() throws {
        let apps = root.appendingPathComponent("Apps")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let wish = try Template.draft(name: "New York", in: apps)
        let copy = try Template.draft(name: "New York Update", in: apps)
        let store = Store(testingAt: apps)
        let (app, update) = (try XCTUnwrap(store.current(wish)), try XCTUnwrap(store.current(copy)))
        XCTAssertEqual(store.queueTarget(for: update).id, update.id)
        store.retiringCopies[update.id] = app.id
        XCTAssertEqual(store.queueTarget(for: update).id, app.id)
        store.retiringCopies[update.id] = nil
        XCTAssertEqual(store.queueTarget(for: update).id, update.id)
    }

    /// Review Update… on a copy whose agent asked the person something shows the question; only a preparation that
    /// stopped or failed is offered again.
    func testAQuestionWaitingInTheCopyIsShownNotRetried() {
        XCTAssertEqual(AppUpdates.step(ready: false, working: false, asking: true), .show)
        XCTAssertEqual(AppUpdates.step(ready: false, working: false, asking: false), .retry)
        XCTAssertEqual(AppUpdates.step(ready: false, working: true, asking: false), .show)
        XCTAssertEqual(AppUpdates.step(ready: true, working: false, asking: false), .review)
    }

    /// Make App builds the version the person opened: the branch, tag or commit in the address, at the commit fetched.
    func testMakeAppBuildsTheVersionThatWasOpened() throws {
        let source = try XCTUnwrap(RepoImport.source(from: "https://github.com/mrdoob/slop-newyork/tree/v1.2"))
        let request = AppUpdates.adaptRequest(source, commit: "13dd142b480bcfa01a6b18e36127c87e41cb4d80", change: "Make it snow")
        XCTAssertTrue(request.contains("13dd142b480bcfa01a6b18e36127c87e41cb4d80"), request)
        XCTAssertTrue(request.contains("v1.2"), request)
        XCTAssertTrue(request.hasSuffix("Make it snow"), request)
    }
}
