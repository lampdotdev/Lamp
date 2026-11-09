import XCTest
@testable import Lamp

/// Mixing two copies of one wish: a copy's versions travel in its shared file, line up with the other copy's own by
/// date, and what's picked is played back with the later change winning, saved as one version per change taken.
final class MixTests: XCTestCase {
    private let escape = HistoryEscapeTests()
    override func tearDown() { escape.tearDown() }

    private let identity = UUID().uuidString
    private let start = "a\nb\nc\nd\ne\n"

    private func text(_ app: HistoryEscapeTests.App, _ file: String = "Sources/App.swift") -> String? {
        try? String(contentsOf: app.project.dir.appendingPathComponent(file), encoding: .utf8)
    }

    /// Writes files and saves them as a version made at `seconds`.
    private func commit(_ app: HistoryEscapeTests.App, _ message: String, at seconds: Int, _ files: [String: String]) throws {
        for (path, content) in files {
            let url = app.project.dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        let made = try escape.loose("git add -A && GIT_COMMITTER_DATE='@\(seconds) +0000' GIT_AUTHOR_DATE='@\(seconds) +0000' "
                                    + "git -c user.name=Lamp -c user.email=lamp@localhost commit -qm \(Sandbox.quoted(message))", in: app.project.dir)
        XCTAssertEqual(made.status, 0, made.output)
    }

    /// Mixes a pick as the window does once any check of it is in: these tests are about what a mix saves, so a pick
    /// holding code no review read gets a stand-in for that check.
    @discardableResult
    private func apply(_ picked: Set<String>, in lineup: Mix.Lineup) async throws -> Int {
        let prepared = try await Mix.prepare(picked, in: lineup)
        let stand = ImportReview(summary: "checked", capabilities: [], concerns: [], detected: [])
        return try await Mix.apply(prepared, in: lineup, checked: prepared.needsCheck ? stand : nil)
    }

    private func head(_ app: HistoryEscapeTests.App) throws -> String {
        try XCTUnwrap(Credits.validCommit(try escape.loose("git rev-parse HEAD", in: app.project.dir).output))
    }

    /// Yours, where the copies met; theirs, a copy of it with its own changes; and the file it shares.
    private func copies() async throws -> (yours: HistoryEscapeTests.App, theirs: HistoryEscapeTests.App, package: Sharing.Package, history: MixHistory) {
        let yours = try escape.app(), theirs = try escape.app()
        for app in [yours, theirs] {
            try FileManager.default.removeItem(atPath: app.tool)
            try FileManager.default.createDirectory(at: app.project.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        }
        try commit(yours, "Start", at: 100, ["Sources/App.swift": start, ".gitignore": ".lamp/\n"])
        Sharing.setIdentity(identity, of: yours.project)
        let met = try head(yours)
        // Their copy arrived as that version, its chain naming it.
        var credits = Credits()
        credits.remixOf = [Credits.Remix(name: "Coin Flip", wish: identity, commit: met)]
        try credits.encoded().write(to: theirs.project.dir.appendingPathComponent(Credits.file))
        try commit(theirs, "Imported from a shared file", at: 100, ["Sources/App.swift": start, ".gitignore": ".lamp/\n"])
        Sharing.setIdentity(identity, of: theirs.project)

        try commit(theirs, "Shout the first line", at: 200, ["Sources/App.swift": "A-them\nb\nc\nd\ne\n"])
        try commit(yours, "Whisper the first line", at: 300, ["Sources/App.swift": "A-you\nb\nc\nd\ne\n", "Notes.txt": "x\n"])
        try commit(theirs, "Shout the last line", at: 400, ["Sources/App.swift": "A-them\nb\nc\nd\nE-them\n"])

        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-mix-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: stage) }
        MixHistory.write(for: theirs.project, credits: Credits.load(theirs.project), identity: identity, into: stage)
        let history = try XCTUnwrap(MixHistory.read(in: stage))
        XCTAssertEqual(history.base, met)
        XCTAssertEqual(history.versions.map(\.title), ["Shout the first line", "Shout the last line"])
        let package = Sharing.Package(name: "Coin Flip", identity: identity, folder: stage, sources: [], attachments: [], fileCount: 0)
        return (yours, theirs, package, history)
    }

    func testBothSidesLineUpByDateAndTheLaterChangeWins() async throws {
        let (yours, _, package, history) = try await copies()
        let lineup = try await Mix.lineUp(package, history: history, with: yours.project)
        XCTAssertEqual(lineup.changes.map(\.title), ["Shout the first line", "Whisper the first line", "Shout the last line"])
        XCTAssertEqual(lineup.changes.map(\.side), [.them, .you, .them])
        XCTAssertEqual(lineup.changes.map(\.here), [false, true, false])

        let all = Set(lineup.changes.map(\.id))
        let preview = await Mix.preview(lineup.changes, in: lineup)
        XCTAssertEqual(preview.replaced, [lineup.changes[0].id: "Whisper the first line"])

        let saved = try await apply(all, in: lineup)
        XCTAssertEqual(saved, 2)
        XCTAssertEqual(text(yours), "A-you\nb\nc\nd\nE-them\n")
        XCTAssertEqual(text(yours, "Notes.txt"), "x\n")
        let log = try escape.loose("git log --format='%s|%(trailers:key=Lamp-Mixed,valueonly,separator=%x2C)' -3", in: yours.project.dir).output
        XCTAssertEqual(log.split(separator: "\n"), ["Shout the last line|\(lineup.changes[2].id)", "Shout the first line|\(lineup.changes[0].id)", "Whisper the first line|"])
        let unsaved = await Versions.hasUnsavedChanges(yours.project)
        XCTAssertFalse(unsaved)

        // Mixed once, their changes are on their side, already in, and nothing is offered twice.
        let again = try await Mix.lineUp(package, history: history, with: yours.project)
        XCTAssertTrue(again.changes.allSatisfy(\.here))
        XCTAssertEqual(again.changes.map(\.side), [.them, .you, .them])
    }

    func testLeavingOutYourOwnChangeSavesThatFirst() async throws {
        let (yours, _, package, history) = try await copies()
        let lineup = try await Mix.lineUp(package, history: history, with: yours.project)
        let saved = try await apply([lineup.changes[0].id], in: lineup)
        XCTAssertEqual(saved, 2)
        XCTAssertEqual(text(yours), "A-them\nb\nc\nd\ne\n")
        XCTAssertNil(text(yours, "Notes.txt"))
        let log = try escape.loose("git log --format=%s -2", in: yours.project.dir).output
        XCTAssertEqual(log.split(separator: "\n"), ["Shout the first line", "Left out “Whisper the first line”"])
    }

    /// A change of theirs taken earlier isn't offered again, but the next one is still measured against it: taking it
    /// brings only what it did, never their earlier edit back over a newer one of yours.
    func testALaterChangeIsMeasuredAgainstTheirEarlierOnes() async throws {
        let (yours, _, package, history) = try await copies()
        let first = try await Mix.lineUp(package, history: history, with: yours.project)
        _ = try await apply([first.changes[0].id, first.changes[1].id], in: first)
        XCTAssertEqual(text(yours), "A-you\nb\nc\nd\ne\n")
        // Newer than their first-line change, older than their last-line one.
        try commit(yours, "Whisper it again", at: 350, ["Sources/App.swift": "A-you-again\nb\nc\nd\ne\n"])

        let lineup = try await Mix.lineUp(package, history: history, with: yours.project)
        let last = try XCTUnwrap(lineup.changes.first { !$0.here })
        XCTAssertEqual(lineup.changes.filter { !$0.here }.map(\.title), ["Shout the last line"])
        _ = try await apply(Set(lineup.changes.filter(\.here).map(\.id) + [last.id]), in: lineup)
        XCTAssertEqual(text(yours), "A-you-again\nb\nc\nd\nE-them\n")
    }

    /// A run longer than a file carries keeps its latest versions and folds the rest into one, so what the earliest
    /// brought (a new file here) still comes over.
    func testALongRunFoldsItsEarliestVersionsIntoOne() async throws {
        let (yours, theirs, _, _) = try await copies()
        try commit(theirs, "Add a helper", at: 450, ["Sources/Extra.swift": "// helper\n"])
        for step in 1...MixHistory.limit {
            try commit(theirs, "Step \(step)", at: 500 + step, ["Sources/App.swift": "A-them\nb\nc\(step)\nd\nE-them\n"])
        }
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-mix-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: stage) }
        MixHistory.write(for: theirs.project, credits: Credits.load(theirs.project), identity: identity, into: stage)
        let history = try XCTUnwrap(MixHistory.read(in: stage))
        XCTAssertEqual(history.versions.count, MixHistory.limit + 1)
        XCTAssertEqual(history.versions.first?.title, "Earlier changes")
        XCTAssertEqual(Set(history.versions.first?.changed ?? []), ["Sources/App.swift", "Sources/Extra.swift"])

        let package = Sharing.Package(name: "Coin Flip", identity: identity, folder: stage, sources: [], attachments: [], fileCount: 0)
        let lineup = try await Mix.lineUp(package, history: history, with: yours.project)
        _ = try await apply(Set(lineup.changes.map(\.id)), in: lineup)
        XCTAssertEqual(text(yours, "Sources/Extra.swift"), "// helper\n")
        XCTAssertEqual(text(yours), "A-them\nb\nc\(MixHistory.limit)\nd\nE-them\n")
    }

    /// Their credits come with their work, but this copy's link keeps the version it was given: a mix that took only
    /// part of their file mustn't make this copy's next file claim to start where theirs ended.
    func testTheirCreditsComeWithoutMovingWhereThisCopyStarts() async throws {
        let (_, theirs, _, _) = try await copies()
        let given = Credits.load(theirs.project).remixOf.last?.commit
        var incoming = Credits()
        incoming.remixOf = [Credits.Remix(name: "Coin Flip", wish: identity, commit: String(repeating: "f", count: 40))]
        incoming.generated = [Credits.Generated(file: "Assets/skyline.png")]
        try FileManager.default.createDirectory(at: theirs.project.dir.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        try Data([0]).write(to: theirs.project.dir.appendingPathComponent("Assets/skyline.png"))
        try Credits.add(Mix.creditsTaken(incoming), to: theirs.project)
        let now = Credits.load(theirs.project)
        XCTAssertEqual(now.remixOf.last?.commit, given)
        XCTAssertEqual(now.generated.map(\.file), ["Assets/skyline.png"])
    }

    /// A remix made here has an identity of its own, so its file finds the wish it was remixed from, starts where it was
    /// remixed, and never offers its new name back to the original.
    func testARemixsFileMixesIntoItsOriginal() async throws {
        let (yours, theirs, _, _) = try await copies()
        let original = try head(yours)
        // Their copy becomes a remix of yours: the same history, a new name, a link back by your identity.
        _ = try escape.loose("rm -rf .git && /bin/cp -R \(Sandbox.quoted(yours.project.dir.path))/.git .git && git reset -q --hard && git clean -qfd",
                             in: theirs.project.dir)
        var credits = Credits()
        credits.remixOf = [Credits.Remix(name: "Coin Flip", wish: identity)]
        try credits.encoded().write(to: theirs.project.dir.appendingPathComponent(Credits.file))
        try commit(theirs, "Remix of Coin Flip", at: 310, ["Sources/Title.swift": "Coin Flip Remix\n"])
        let remix = UUID().uuidString
        Sharing.setIdentity(remix, of: theirs.project)
        try commit(theirs, "Shout the last line", at: 320, ["Sources/App.swift": "A-you\nb\nc\nd\nE-them\n"])

        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-mix-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: stage) }
        MixHistory.write(for: theirs.project, credits: Credits.load(theirs.project), identity: remix, into: stage)
        let history = try XCTUnwrap(MixHistory.read(in: stage))
        XCTAssertEqual(history.versions.map(\.title), ["Remix of Coin Flip", "Shout the last line"])
        XCTAssertEqual(history.versions.map { $0.began == true }, [true, false])

        let package = Sharing.Package(name: "Coin Flip Remix", identity: remix, credits: Credits.load(theirs.project), folder: stage,
                                      sources: [], attachments: [], fileCount: 0)
        try commit(yours, "Whisper the middle", at: 330, ["Sources/App.swift": "A-you\nb\nC-you\nd\ne\n"])
        let lineup = try await Mix.lineUp(package, history: history, with: yours.project)
        XCTAssertEqual(lineup.changes.map(\.title), ["Shout the last line", "Whisper the middle"])
        _ = try await apply(Set(lineup.changes.map(\.id)), in: lineup)
        XCTAssertEqual(text(yours), "A-you\nb\nC-you\nd\nE-them\n")
        XCTAssertNil(text(yours, "Sources/Title.swift"))
        XCTAssertNotEqual(try head(yours), original)
    }

    /// A file finds its wish by identity alone: one an import wouldn't update (here, no app at its root, as a wish
    /// whose apps are in folders of their own) is still the one it's mixed into.
    func testAFileFindsItsWishWhateverItsLayout() async throws {
        let (yours, _, _, _) = try await copies()
        let package = Sharing.Package(name: "Coin Flip", identity: identity, folder: yours.root, sources: [], attachments: [], fileCount: 0)
        XCTAssertNil(Store.copy(of: package, among: [yours.project]))
        XCTAssertEqual(Mix.copy(of: package, among: [yours.project])?.dir, yours.project.dir)
    }

    /// Their removal of a file you changed later is partly replaced by your change: the later one brings the file back.
    func testALaterEditReplacesTheirRemoval() async throws {
        let (yours, theirs, package, _) = try await copies()
        _ = try escape.loose("git rm -q Sources/App.swift", in: theirs.project.dir)
        try commit(theirs, "Remove the app file", at: 410, [:])
        try commit(yours, "Whisper it again", at: 420, ["Sources/App.swift": "A-you-again\nb\nc\nd\ne\n"])
        try FileManager.default.removeItem(at: package.folder.appendingPathComponent(MixHistory.folder))
        MixHistory.write(for: theirs.project, credits: Credits.load(theirs.project), identity: identity, into: package.folder)
        let history = try XCTUnwrap(MixHistory.read(in: package.folder))
        let lineup = try await Mix.lineUp(package, history: history, with: yours.project)
        let removal = try XCTUnwrap(lineup.changes.first { $0.title == "Remove the app file" })
        let preview = await Mix.preview(lineup.changes, in: lineup)
        XCTAssertEqual(preview.replaced[removal.id], "Whisper it again")
    }

    /// Mixing again: what the first mix left out shows out, what it took sits where they made it, and the version that
    /// left things out isn't a change of its own, so it can't undo a later change of theirs taken now.
    func testASecondMixKeepsWhatTheFirstLeftOut() async throws {
        let (yours, theirs, package, _) = try await copies()
        try commit(theirs, "Shout it again", at: 450, ["Sources/App.swift": "A-them-again\nb\nc\nd\nE-them\n"])
        try FileManager.default.removeItem(at: package.folder.appendingPathComponent(MixHistory.folder))
        MixHistory.write(for: theirs.project, credits: Credits.load(theirs.project), identity: identity, into: package.folder)
        let history = try XCTUnwrap(MixHistory.read(in: package.folder))

        let first = try await Mix.lineUp(package, history: history, with: yours.project)
        let shout = try XCTUnwrap(first.changes.first { $0.title == "Shout the first line" })
        _ = try await apply([shout.id], in: first)   // "Whisper the first line" left out
        XCTAssertEqual(text(yours), "A-them\nb\nc\nd\ne\n")

        let second = try await Mix.lineUp(package, history: history, with: yours.project)
        XCTAssertEqual(second.changes.map(\.title), ["Shout the first line", "Whisper the first line", "Shout the last line", "Shout it again"])
        XCTAssertEqual(second.changes.map(\.here), [true, false, false, false])
        let again = try XCTUnwrap(second.changes.first { $0.title == "Shout it again" })
        _ = try await apply(Set(second.changes.filter(\.here).map(\.id) + [again.id]), in: second)
        XCTAssertEqual(text(yours), "A-them-again\nb\nc\nd\ne\n")
        XCTAssertNil(text(yours, "Notes.txt"))

        // Taking the left-out change back brings it in once, under its own row.
        let third = try await Mix.lineUp(package, history: history, with: yours.project)
        let whisper = try XCTUnwrap(third.changes.first { $0.title == "Whisper the first line" })
        _ = try await apply(Set(third.changes.filter(\.here).map(\.id) + [whisper.id]), in: third)
        XCTAssertEqual(text(yours, "Notes.txt"), "x\n")
        let fourth = try await Mix.lineUp(package, history: history, with: yours.project)
        XCTAssertEqual(fourth.changes.filter { $0.title == "Whisper the first line" }.map(\.here), [true])

        // Left out once more, it stays out: the latest word wins.
        let back = try XCTUnwrap(fourth.changes.first { $0.title == "Whisper the first line" })
        _ = try await apply(Set(fourth.changes.filter(\.here).map(\.id)).subtracting([back.id]), in: fourth)
        XCTAssertNil(text(yours, "Notes.txt"))
        let fifth = try await Mix.lineUp(package, history: history, with: yours.project)
        XCTAssertEqual(fifth.changes.filter { $0.title == "Whisper the first line" }.map(\.here), [false])
    }

    /// Leaving out a change a later one had already replaced changes no file, but it's still saved, so it stays out.
    func testLeavingOutAReplacedChangeIsRemembered() async throws {
        let (yours, _, package, history) = try await copies()
        let first = try await Mix.lineUp(package, history: history, with: yours.project)
        _ = try await apply(Set(first.changes.map(\.id)), in: first)
        let second = try await Mix.lineUp(package, history: history, with: yours.project)
        let replaced = try XCTUnwrap(second.changes.first { $0.title == "Shout the first line" })
        let saved = try await apply(Set(second.changes.map(\.id)).subtracting([replaced.id]), in: second)
        XCTAssertEqual(saved, 1)
        XCTAssertEqual(text(yours), "A-you\nb\nc\nd\nE-them\n")
        let third = try await Mix.lineUp(package, history: history, with: yours.project)
        XCTAssertEqual(third.changes.first { $0.title == "Shout the first line" }?.here, false)
    }

    /// Copies that never met at a version both have aren't offered for mixing: an import keeps Update for them.
    func testCopiesThatNeverMetDontLineUp() async throws {
        let (yours, _, package, history) = try await copies()
        let met = await Mix.meeting(package, history: history, with: yours.project)
        XCTAssertNotNil(met)
        let elsewhere = MixHistory(base: String(repeating: "f", count: 40), versions: history.versions)
        let none = await Mix.meeting(package, history: elsewhere, with: yours.project)
        XCTAssertNil(none)
    }

    /// The other way round: an original first shared after it was remixed still starts where the remix was made.
    func testAnOriginalSharedAfterItsRemixMixesIntoTheRemix() async throws {
        let (yours, theirs, _, _) = try await copies()
        MixHistory.keepStart(at: try head(yours), of: yours.project)
        _ = try escape.loose("rm -rf .git && /bin/cp -R \(Sandbox.quoted(yours.project.dir.path))/.git .git && git reset -q --hard && git clean -qfd",
                             in: theirs.project.dir)
        try commit(theirs, "Remix of Coin Flip", at: 310, ["Sources/Title.swift": "Coin Flip Remix\n"])
        try commit(yours, "Shout the last line", at: 320, ["Sources/App.swift": "A-you\nb\nc\nd\nE-you\n"])

        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-mix-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: stage) }
        MixHistory.write(for: yours.project, credits: Credits.load(yours.project), identity: identity, into: stage)
        let history = try XCTUnwrap(MixHistory.read(in: stage))
        XCTAssertEqual(history.versions.map(\.title), ["Shout the last line"])
        let package = Sharing.Package(name: "Coin Flip", identity: identity, folder: stage, sources: [], attachments: [], fileCount: 0)
        let lineup = try await Mix.lineUp(package, history: history, with: theirs.project)
        XCTAssertEqual(lineup.changes.map(\.title), ["Remix of Coin Flip", "Shout the last line"])
        _ = try await apply(Set(lineup.changes.map(\.id)), in: lineup)
        XCTAssertEqual(text(theirs), "A-you\nb\nc\nd\nE-you\n")
        XCTAssertEqual(text(theirs, "Sources/Title.swift"), "Coin Flip Remix\n")
    }

    func testTheirCopyLinesUpWithTheOriginalsNewerFile() async throws {
        // The other way round: the original's file, opened in the copy, starts where the copy was given it.
        let (yours, theirs, _, _) = try await copies()
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-mix-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: stage) }
        // The original's first share was where they met, so its run starts there.
        _ = try escape.loose("mkdir -p .lamp && git rev-parse HEAD~1 > .lamp/mix-start", in: yours.project.dir)
        MixHistory.write(for: yours.project, credits: Credits.load(yours.project), identity: identity, into: stage)
        let history = try XCTUnwrap(MixHistory.read(in: stage))
        XCTAssertEqual(history.versions.map(\.title), ["Whisper the first line"])
        let package = Sharing.Package(name: "Coin Flip", identity: identity, folder: stage, sources: [], attachments: [], fileCount: 0)
        let lineup = try await Mix.lineUp(package, history: history, with: theirs.project)
        XCTAssertEqual(lineup.changes.map(\.title), ["Shout the first line", "Whisper the first line", "Shout the last line"])
        XCTAssertEqual(lineup.changes.map(\.side), [.you, .them, .you])
    }

    /// Mix… on a review that has finished hands the mix that review, and the mix shows it whole rather than checking the
    /// code again. Without one (the review was still checking) the mix checks the package itself, and that check's
    /// answer, coming after another package took its place, is dropped.
    @MainActor
    func testMixTakesTheFinishedReviewInsteadOfCheckingAgain() async throws {
        let (yours, _, unchecked, _) = try await copies()
        let checkedFolder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-mix-test-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: unchecked.folder, to: checkedFolder)
        addTeardownBlock { try? FileManager.default.removeItem(at: checkedFolder) }
        let checked = Sharing.Package(name: "Coin Flip", identity: identity, folder: checkedFolder, sources: [], attachments: [], fileCount: 0)

        final class Checks: @unchecked Sendable {
            let lock = NSLock()
            var folders: [URL] = []
            var release: CheckedContinuation<Void, Never>?
        }
        let checks = Checks()
        let saved = MixModel.reviewForMix
        defer { MixModel.reviewForMix = saved }
        MixModel.reviewForMix = { package in
            checks.lock.withLock { checks.folders.append(package.folder) }
            await withCheckedContinuation { go in checks.lock.withLock { checks.release = go } }
            var late = ImportReview(summary: "late", capabilities: [], concerns: [], detected: [])
            late.note = "late"
            return late
        }
        var finished = ImportReview(summary: "Reads the files you pick.", capabilities: [], concerns: [], detected: [])
        finished.asked = true
        finished.partial = true
        finished.note = "Lamp's AI check didn't finish in time. Look at the list above carefully."

        let store = Store(testingAt: yours.root.appendingPathComponent("Apps"))
        store.projects = [yours.project]
        let model = MixModel()
        func until(_ what: String, _ done: () -> Bool) async throws {
            for _ in 0..<400 where !done() { try await Task.sleep(for: .milliseconds(25)) }
            XCTAssertTrue(done(), what)
        }

        // Still checking when Mix… was clicked: the mix checks it.
        XCTAssertTrue(model.adopt(unchecked, reviewed: nil, store: store))
        try await until("the mix checks a package it was given unchecked") { checks.lock.withLock { checks.release != nil } }
        XCTAssertNil(model.review)

        // A finished review: shown as it is, warnings and notes and all, with no second check.
        XCTAssertTrue(model.adopt(checked, reviewed: finished, store: store))
        try await until("the mix lines up the checked package") { model.stage == .ready && model.review != nil }
        XCTAssertEqual(checks.lock.withLock { checks.folders }, [unchecked.folder], "the checked package isn't checked again")
        XCTAssertEqual(model.review?.summary, finished.summary)
        XCTAssertEqual(model.review?.note, finished.note)
        XCTAssertEqual(model.review?.partial, true)

        // The first package's check answers late: it's not this package's, so it's dropped.
        checks.lock.withLock { checks.release }?.resume()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.review?.summary, finished.summary)
        model.reset()
    }

    // MARK: What a mix brings that no review read

    /// One step of a copy's history: whose, its title, when, and the files it writes (nil removes one).
    private struct Step {
        let theirs: Bool
        let title: String
        let at: Int
        let files: [String: String?]
    }

    /// Yours and theirs from one start, then `steps`; and the file theirs shares as a shared file is laid out: their
    /// latest at its top (`top` in place of a file of it, as a sender's own file could say), read as an import reads it,
    /// and their versions in History/.
    private func shared(_ start: [String: String], _ steps: [Step], top: [String: String] = [:], tamper: (URL) throws -> Void = { _ in })
        async throws -> (yours: HistoryEscapeTests.App, lineup: Mix.Lineup) {
        let yours = try escape.app(), theirs = try escape.app()
        for app in [yours, theirs] {
            try FileManager.default.removeItem(atPath: app.tool)
            try FileManager.default.createDirectory(at: app.project.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        }
        var first = start
        first[".gitignore"] = ".lamp/\n"
        try commit(yours, "Start", at: 100, first)
        Sharing.setIdentity(identity, of: yours.project)
        let met = try head(yours)
        var credits = Credits()
        credits.remixOf = [Credits.Remix(name: "Coin Flip", wish: identity, commit: met)]
        try credits.encoded().write(to: theirs.project.dir.appendingPathComponent(Credits.file))
        try commit(theirs, "Imported from a shared file", at: 100, first)
        Sharing.setIdentity(identity, of: theirs.project)
        for step in steps {
            let app = step.theirs ? theirs : yours
            for (path, content) in step.files where content == nil {
                try FileManager.default.removeItem(at: app.project.dir.appendingPathComponent(path))
            }
            try commit(app, step.title, at: step.at, step.files.compactMapValues { $0 })
        }

        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-mix-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: stage) }
        XCTAssertEqual(try escape.loose("git archive --format=tar HEAD | tar -x -C \(Sandbox.quoted(stage.path))", in: theirs.project.dir).status, 0)
        for (path, content) in top { try content.write(to: stage.appendingPathComponent(path), atomically: true, encoding: .utf8) }
        try #"{"format": 2, "name": "Coin Flip", "exportedAt": "2026-01-01T00:00:00Z", "platform": "mac", "app": "\#(identity)"}"#
            .write(to: stage.appendingPathComponent("lamp-app.json"), atomically: true, encoding: .utf8)
        MixHistory.write(for: theirs.project, credits: Credits.load(theirs.project), identity: identity, into: stage)
        try tamper(stage)
        let package = try Sharing.open(unpacked: stage)
        let history = try XCTUnwrap(MixHistory.read(in: stage))
        return (yours, try await Mix.lineUp(package, history: history, with: yours.project))
    }

    private let lines = "a\nb\nc\nd\ne\n"
    private func ids(_ lineup: Mix.Lineup, _ titles: String...) -> Set<String> {
        Set(lineup.changes.filter { titles.contains($0.title) }.map(\.id))
    }

    /// Two changes of theirs to one file, and one of yours elsewhere.
    private func twoOfTheirs() async throws -> (yours: HistoryEscapeTests.App, lineup: Mix.Lineup) {
        try await shared(["Sources/App.swift": lines], [
            Step(theirs: true, title: "Shout the first line", at: 200, files: ["Sources/App.swift": "A-them\nb\nc\nd\ne\n"]),
            Step(theirs: false, title: "Add mine", at: 300, files: ["Sources/Mine.swift": "mine\n"]),
            Step(theirs: true, title: "Shout the last line", at: 400, files: ["Sources/App.swift": "A-them\nb\nc\nd\nE-them\n"]),
        ])
    }

    /// One change of theirs, beside one of yours: everything the mix saves is either what the file's review read or
    /// what this copy has had, so the file's review is all Mix goes by.
    func testAMixOfOnlyWhatTheReviewReadIsNotCheckedAgain() async throws {
        let (yours, lineup) = try await shared(["Sources/App.swift": lines], [
            Step(theirs: true, title: "Shout the first line", at: 200, files: ["Sources/App.swift": "A-them\nb\nc\nd\ne\n"]),
            Step(theirs: false, title: "Add mine", at: 300, files: ["Sources/Mine.swift": "mine\n"]),
        ])
        let prepared = try await Mix.prepare(Set(lineup.changes.map(\.id)), in: lineup)
        XCTAssertFalse(prepared.needsCheck)
        let saved = try await Mix.apply(prepared, in: lineup, checked: nil)
        XCTAssertEqual(saved, 1)
        XCTAssertEqual(text(yours), "A-them\nb\nc\nd\ne\n")
    }

    /// Their later change without their earlier one comes to a file nobody read: it's checked, as the app the mix
    /// leaves.
    func testALaterChangeOfTheirsWithoutTheEarlierIsChecked() async throws {
        let (_, lineup) = try await twoOfTheirs()
        let prepared = try await Mix.prepare(ids(lineup, "Add mine", "Shout the last line"), in: lineup)
        XCTAssertEqual(prepared.unseen, [prepared.versions.count - 1])
        let input = try await Mix.checkInput(prepared, in: lineup)
        defer { try? FileManager.default.removeItem(at: input.package.folder) }
        let read = Dictionary(input.inspection.files.map { ($0.name, $0.text) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(read["Sources/App.swift"], "a\nb\nc\nd\nE-them\n")
        XCTAssertEqual(read["Sources/Mine.swift"], "mine\n", "the check reads the app the mix leaves, yours included")
    }

    /// Taking all of theirs leaves what the review read, but the version saved for their first change is theirs as it
    /// was then, which Undo goes straight back to: that version's code is checked with the rest.
    func testAVersionTheMixSavesOnTheWayIsCheckedToo() async throws {
        let (_, lineup) = try await twoOfTheirs()
        let prepared = try await Mix.prepare(Set(lineup.changes.map(\.id)), in: lineup)
        XCTAssertEqual(prepared.versions.map(\.title), ["Shout the first line", "Shout the last line"])
        XCTAssertEqual(prepared.unseen, [0])
        let input = try await Mix.checkInput(prepared, in: lineup)
        defer { try? FileManager.default.removeItem(at: input.package.folder) }
        let read = Dictionary(input.inspection.files.map { ($0.name, $0.text) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(read["Sources/App.swift"], "A-them\nb\nc\nd\nE-them\n")
        XCTAssertEqual(read["Sources/App.swift (in “Shout the first line”)"], "A-them\nb\nc\nd\ne\n")
    }

    /// A file both of you changed comes to lines in an order no one read.
    func testAFileBothChangedIsChecked() async throws {
        let (_, lineup) = try await shared(["Sources/App.swift": lines], [
            Step(theirs: true, title: "Shout the first line", at: 200, files: ["Sources/App.swift": "A-them\nb\nc\nd\ne\n"]),
            Step(theirs: false, title: "Whisper the middle", at: 300, files: ["Sources/App.swift": "a\nb\nc-you\nd\ne\n"]),
        ])
        let prepared = try await Mix.prepare(Set(lineup.changes.map(\.id)), in: lineup)
        XCTAssertTrue(prepared.needsCheck)
        let input = try await Mix.checkInput(prepared, in: lineup)
        defer { try? FileManager.default.removeItem(at: input.package.folder) }
        XCTAssertTrue(input.inspection.files.contains { $0.name == "Sources/App.swift" && $0.text == "A-them\nb\nc-you\nd\ne\n" })
    }

    /// A file of theirs that came and went, and one of yours they took away and put back: taking only the first change
    /// brings a file and takes one away, neither as the review read it. A file no shared copy carries stays as yours is.
    func testNewAndRemovedFilesAreCheckedAndUncarriedOnesStayYours() async throws {
        let (yours, lineup) = try await shared(["Sources/App.swift": lines, "Sources/Guard.swift": "guard\n"], [
            Step(theirs: true, title: "Try a helper", at: 200,
                 files: ["Sources/Extra.swift": "extra\n", "Sources/Guard.swift": nil, "Scripts/run.sh": "echo hi\n"]),
            Step(theirs: true, title: "Put it back", at: 400,
                 files: ["Sources/Extra.swift": nil, "Sources/Guard.swift": "guard\n", "Scripts/run.sh": nil]),
        ])
        let prepared = try await Mix.prepare(ids(lineup, "Try a helper"), in: lineup)
        XCTAssertTrue(prepared.needsCheck)
        let input = try await Mix.checkInput(prepared, in: lineup)
        defer { try? FileManager.default.removeItem(at: input.package.folder) }
        let names = Set(input.inspection.files.map(\.name))
        XCTAssertTrue(names.contains("Sources/Extra.swift"))
        XCTAssertFalse(names.contains("Sources/Guard.swift"))
        let checked = ImportReview(summary: "checked", capabilities: [], concerns: [], detected: [])
        let saved = try await Mix.apply(prepared, in: lineup, checked: checked)
        XCTAssertEqual(saved, 1)
        XCTAssertEqual(text(yours, "Sources/Extra.swift"), "extra\n")
        XCTAssertNil(text(yours, "Sources/Guard.swift"))
        XCTAssertNil(text(yours, "Scripts/run.sh"), "a file no shared copy carries doesn't come in")
    }

    /// History/ that says something other than the file's code is what a mix would bring: checked, even taking all.
    func testHistoryThatDiffersFromTheFilesCodeIsChecked() async throws {
        let (_, lineup) = try await shared(["Sources/App.swift": lines], [
            Step(theirs: true, title: "Shout the first line", at: 200, files: ["Sources/App.swift": "A-them\nb\nc\nd\ne\n"]),
        ], top: ["Sources/App.swift": "harmless\n"])
        let prepared = try await Mix.prepare(Set(lineup.changes.map(\.id)), in: lineup)
        XCTAssertEqual(prepared.unseen, [0])
    }

    /// Nothing is saved, nor any file touched, for a mix that needs its check and hasn't had it, or for a copy that has
    /// moved on since the mix was worked out.
    func testAMixIsSavedOnlyAsItWasCheckedAndOnlyOntoTheCopyItWasMadeFor() async throws {
        let (yours, lineup) = try await twoOfTheirs()
        let prepared = try await Mix.prepare(Set(lineup.changes.map(\.id)), in: lineup)
        XCTAssertTrue(prepared.needsCheck)
        let before = try head(yours)
        do { _ = try await Mix.apply(prepared, in: lineup, checked: nil); XCTFail("saved without its check") } catch {}
        XCTAssertEqual(try head(yours), before)
        XCTAssertEqual(text(yours), lines)

        try commit(yours, "Something else", at: 500, ["Sources/Mine.swift": "mine, later\n"])
        let moved = try head(yours)
        let checked = ImportReview(summary: "checked", capabilities: [], concerns: [], detected: [])
        do { _ = try await Mix.apply(prepared, in: lineup, checked: checked); XCTFail("saved onto a copy that moved on") } catch {}
        XCTAssertEqual(try head(yours), moved)
        XCTAssertEqual(text(yours), lines)
        XCTAssertEqual(text(yours, "Sources/Mine.swift"), "mine, later\n")
        let unsaved = await Versions.hasUnsavedChanges(yours.project)
        XCTAssertFalse(unsaved)
    }

    /// The window: Mix on a pick holding code no review read saves nothing and checks it; the check's answer is what Mix
    /// then goes by; a change to the pick drops it, and an answer for a pick that's gone is dropped too.
    @MainActor
    func testTheWindowChecksAPickBeforeMixingItAndForgetsTheCheckWhenThePickChanges() async throws {
        let (yours, lineup) = try await twoOfTheirs()
        final class Gate: @unchecked Sendable {
            let lock = NSLock()
            var waiting: [CheckedContinuation<Void, Never>] = []
            var read: [[String]] = []
        }
        let gate = Gate()
        let saved = MixModel.reviewForCheck
        defer { MixModel.reviewForCheck = saved }
        MixModel.reviewForCheck = { _, inspection in
            gate.lock.withLock { gate.read.append(inspection.files.map(\.name)) }
            await withCheckedContinuation { go in gate.lock.withLock { gate.waiting.append(go) } }
            var risky = ImportReview(summary: "Sends what it reads.", capabilities: [], concerns: ["Sends your files away", "Reads every file"], detected: [])
            risky.risk = .high
            risky.asked = true
            return risky
        }
        var fine = ImportReview(summary: "A coin.", capabilities: [], concerns: [], detected: [])
        fine.risk = .low
        fine.asked = true
        fine.reviewer = ImportReview.Reviewer(name: "A model", onThisMac: false)
        XCTAssertEqual(fine.opening, .byReturn)

        let store = Store(testingAt: yours.root.appendingPathComponent("Apps"))
        store.projects = [yours.project]
        let model = MixModel()
        func until(_ what: String, _ done: () -> Bool) async throws {
            for _ in 0..<400 where !done() { try await Task.sleep(for: .milliseconds(25)) }
            XCTAssertTrue(done(), what)
        }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-mix-test-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: lineup.package.folder, to: copy)
        addTeardownBlock { try? FileManager.default.removeItem(at: copy) }
        let package = try Sharing.open(unpacked: copy)
        XCTAssertTrue(model.adopt(package, reviewed: fine, store: store))
        try await until("lined up") { model.stage == .ready && model.lineup != nil }
        model.takeAllTheirs()
        XCTAssertEqual(model.mixOpening, .byReturn)

        let before = try head(yours)
        model.mix(store: store) { XCTFail("mixed before the check was in") }
        try await until("the pick is checked") { gate.lock.withLock { gate.waiting.count == 1 } }
        XCTAssertNil(model.mixOpening, "nothing to mix by while it's checked")
        XCTAssertTrue(gate.lock.withLock { gate.read[0] }.contains("Sources/App.swift (in “Shout the first line”)"))
        gate.lock.withLock { gate.waiting.removeFirst() }.resume()
        try await until("the check's answer") { model.check?.review != nil }
        XCTAssertEqual(model.mixOpening, .anyway, "Return doesn't mix on a risky check")
        XCTAssertEqual(model.considerations.map(\.text), ["Looks risky. Don't open unless you trust the sender", "Sends your files away", "Reads every file"])
        XCTAssertEqual(try head(yours), before)

        // A new pick: the check was of the old one.
        let mine = try XCTUnwrap(lineup.changes.first { $0.title == "Add mine" })
        model.toggle(mine)
        XCTAssertNil(model.check)
        XCTAssertEqual(model.mixOpening, .byReturn)

        // Checked again, and changed again before the answer: the answer is dropped.
        model.mix(store: store) { XCTFail("mixed before the check was in") }
        try await until("the new pick is checked") { gate.lock.withLock { gate.waiting.count == 1 } }
        model.toggle(mine)
        gate.lock.withLock { gate.waiting.removeFirst() }.resume()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(model.check)
        XCTAssertEqual(try head(yours), before)
        model.reset()
    }

    /// A check that couldn't read what the mix comes to saves nothing and keeps Mix off; Try Again checks the same pick
    /// again, beside the file's review as it was, and Mix goes by that check once it's in.
    @MainActor
    func testTryAgainChecksTheSamePickAfterACheckCouldNotRead() async throws {
        let (yours, lineup) = try await twoOfTheirs()
        final class Reads: @unchecked Sendable {
            let lock = NSLock()
            var count = 0
        }
        let reads = Reads()
        let savedRead = MixModel.readForCheck
        let savedReview = MixModel.reviewForCheck
        defer { MixModel.readForCheck = savedRead; MixModel.reviewForCheck = savedReview }
        MixModel.readForCheck = { prepared, lineup in
            let first = reads.lock.withLock { reads.count += 1; return reads.count == 1 }
            if first { throw Mix.Failure(message: "Lamp couldn't read what the mix came to.") }
            return try await Mix.checkInput(prepared, in: lineup)
        }
        MixModel.reviewForCheck = { _, _ in
            var careful = ImportReview(summary: "Reads a file.", capabilities: [], concerns: ["Reads one file"], detected: [])
            careful.risk = .medium
            careful.asked = true
            return careful
        }
        var fine = ImportReview(summary: "A coin.", capabilities: [], concerns: [], detected: [])
        fine.risk = .low
        fine.asked = true
        fine.reviewer = ImportReview.Reviewer(name: "A model", onThisMac: false)

        let store = Store(testingAt: yours.root.appendingPathComponent("Apps"))
        store.projects = [yours.project]
        let model = MixModel()
        func until(_ what: String, _ done: () -> Bool) async throws {
            for _ in 0..<400 where !done() { try await Task.sleep(for: .milliseconds(25)) }
            XCTAssertTrue(done(), what)
        }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-mix-test-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: lineup.package.folder, to: copy)
        addTeardownBlock { try? FileManager.default.removeItem(at: copy) }
        XCTAssertTrue(model.adopt(try Sharing.open(unpacked: copy), reviewed: fine, store: store))
        try await until("lined up") { model.stage == .ready && model.lineup != nil }
        model.takeAllTheirs()
        let pick = model.picked
        let before = try head(yours)

        model.mix(store: store) { XCTFail("mixed on a check that couldn't read the mix") }
        try await until("the check fails") { model.check?.failure != nil }
        XCTAssertEqual(model.check?.failure, "Lamp couldn't read what the mix came to.")
        XCTAssertNil(model.mixOpening, "nothing to mix by")
        model.mix(store: store) { XCTFail("mixed on a check that couldn't read the mix") }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(try head(yours), before)

        model.retryCheck()
        XCTAssertNil(model.check?.failure)
        XCTAssertNil(model.mixOpening, "nothing to mix by while it's checked again")
        try await until("the check's answer") { model.check?.review != nil }
        XCTAssertEqual(reads.lock.withLock { reads.count }, 2)
        XCTAssertEqual(model.picked, pick, "the pick stays as it was")
        XCTAssertEqual(model.review?.summary, "A coin.", "the file's review stays as it was")
        XCTAssertNil(model.check?.failure)
        XCTAssertEqual(model.mixOpening, .byClick, "the check's answer is what Mix goes by")
        XCTAssertEqual(try head(yours), before, "nothing saved before Mix")

        var mixed = false
        model.mix(store: store) { mixed = true }
        try await until("mixed") { mixed }
        XCTAssertNotEqual(try head(yours), before)
        model.reset()
    }

    /// A file of theirs at a path git would quote, or one holding a character a tool might read as a separator, is
    /// still the path it is: there, named as Lamp's own scene file so no review reads it, and carried by no shared copy,
    /// it stays out. Lamp never writes such a path into History/, so the file is the sender's own doing.
    private func hiddenFileStaysOut(_ hidden: String) async throws {
        let (yours, lineup) = try await shared(["Sources/App.swift": lines], [
            Step(theirs: true, title: "Add a scene", at: 200, files: ["Sources/App.swift": "A-them\nb\nc\nd\ne\n"]),
        ], tamper: { stage in
            let history = stage.appendingPathComponent(MixHistory.folder)
            let json = history.appendingPathComponent(MixHistory.file)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: json)) as? [String: Any])
            var versions = try XCTUnwrap(object["versions"] as? [[String: Any]])
            versions[0]["changed"] = (versions[0]["changed"] as? [String] ?? []) + [hidden]
            object["versions"] = versions
            try JSONSerialization.data(withJSONObject: object).write(to: json)
            let file = history.appendingPathComponent(try XCTUnwrap(versions[0]["folder"] as? String)).appendingPathComponent(hidden)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "// not read by any review\n".write(to: file, atomically: true, encoding: .utf8)
        })
        let prepared = try await Mix.prepare(Set(lineup.changes.map(\.id)), in: lineup)
        let checked = ImportReview(summary: "checked", capabilities: [], concerns: [], detected: [])
        _ = try await Mix.apply(prepared, in: lineup, checked: prepared.needsCheck ? checked : nil)
        XCTAssertEqual(text(yours), "A-them\nb\nc\nd\ne\n")
        XCTAssertNil(text(yours, hidden))
        let saved = try escape.loose("git ls-tree -r -z --name-only HEAD | tr '\\0' '\\n' | grep -c LampScene", in: yours.project.dir)
        XCTAssertEqual(saved.output.trimmingCharacters(in: .whitespacesAndNewlines), "0", "nothing of it is in the saved version")
    }

    func testAFileNoSharedCopyCarriesStaysOutWhateverItsName() async throws {
        try await hiddenFileStaysOut("Sources/x\"y/LampScene.swift")
    }

    func testAFileWhoseNameHoldsAControlCharacterStaysOut() async throws {
        try await hiddenFileStaysOut("Sources/x\u{1e}y/LampScene.swift")
    }

    /// The check reads every file the mix saves as the tree holds it: one the tree's own .gitattributes marks
    /// export-ignore, which `git archive` would leave out, is read like the rest.
    func testTheCheckReadsAFileTheTreeMarksExportIgnore() async throws {
        let (yours, lineup) = try await shared(["Sources/App.swift": lines], [
            Step(theirs: false, title: "Keep the helper out of archives", at: 150, files: [".gitattributes": "Sources/Helper.swift export-ignore\n"]),
            Step(theirs: true, title: "Add a helper", at: 200, files: ["Sources/Helper.swift": "// sends your files away\n"]),
        ], top: ["Sources/Helper.swift": "// harmless\n"])
        let prepared = try await Mix.prepare(Set(lineup.changes.map(\.id)), in: lineup)
        XCTAssertTrue(prepared.needsCheck)
        let input = try await Mix.checkInput(prepared, in: lineup)
        defer { try? FileManager.default.removeItem(at: input.package.folder) }
        XCTAssertTrue(input.inspection.files.contains { $0.name == "Sources/Helper.swift" && $0.text == "// sends your files away\n" },
                      "the file the mix saves is the file the check reads")
        let checked = ImportReview(summary: "checked", capabilities: [], concerns: [], detected: [])
        _ = try await Mix.apply(prepared, in: lineup, checked: checked)
        XCTAssertEqual(text(yours, "Sources/Helper.swift"), "// sends your files away\n")
    }

    /// Two reviews saying one thing: said once, as seriously as the more serious one says it, with each reason given.
    func testWarningsSaidTwiceKeepTheStrongerWeightAndEveryReason() {
        typealias Item = ImportReviewCard.Consideration
        let merged = MixModel.merged([
            [Item(text: "Not checked by AI", weight: .warning, detail: "The provider's filter cut the reply off."),
             Item(text: "Reads every file", weight: .caution)],
            [Item(text: "Not checked by AI", weight: .warning, detail: "The check ran out of time."),
             Item(text: "Reads every file", weight: .warning)],
        ])
        XCTAssertEqual(merged.map(\.text), ["Not checked by AI", "Reads every file"])
        XCTAssertEqual(merged[0].detail, "The provider's filter cut the reply off.\nThe check ran out of time.")
        XCTAssertEqual(merged[1].weight, .warning)
    }

    /// A check adds to the file's review and never softens it: a risky file stays Mix Anyway, its warnings shown, however
    /// the check of the pick comes back.
    @MainActor
    func testACheckNeverTakesBackWhatTheFilesReviewSaid() async throws {
        let (yours, lineup) = try await twoOfTheirs()
        let saved = MixModel.reviewForCheck
        defer { MixModel.reviewForCheck = saved }
        MixModel.reviewForCheck = { _, _ in
            var fine = ImportReview(summary: "A coin.", capabilities: [], concerns: [], detected: [])
            fine.risk = .low
            fine.asked = true
            fine.reviewer = ImportReview.Reviewer(name: "A model", onThisMac: false)
            return fine
        }
        var risky = ImportReview(summary: "Sends what it reads.", capabilities: [], concerns: ["Sends your files away"], detected: [])
        risky.risk = .high
        risky.asked = true
        let store = Store(testingAt: yours.root.appendingPathComponent("Apps"))
        store.projects = [yours.project]
        let model = MixModel()
        func until(_ what: String, _ done: () -> Bool) async throws {
            for _ in 0..<400 where !done() { try await Task.sleep(for: .milliseconds(25)) }
            XCTAssertTrue(done(), what)
        }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-mix-test-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: lineup.package.folder, to: copy)
        addTeardownBlock { try? FileManager.default.removeItem(at: copy) }
        XCTAssertTrue(model.adopt(try Sharing.open(unpacked: copy), reviewed: risky, store: store))
        try await until("lined up") { model.stage == .ready && model.lineup != nil }
        model.takeAllTheirs()
        XCTAssertEqual(model.mixOpening, .anyway)
        model.mix(store: store) { XCTFail("mixed before the check was in") }
        try await until("the check's answer") { model.check?.review != nil }
        XCTAssertEqual(model.mixOpening, .anyway)
        XCTAssertEqual(model.considerations.map(\.text), ["Looks risky. Don't open unless you trust the sender", "Sends your files away"])
        model.reset()
    }
}
