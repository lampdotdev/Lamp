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

        let saved = try await Mix.apply(all, in: lineup)
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
        XCTAssertEqual(again.changes.map(\.side), [.you, .them, .them])
    }

    func testLeavingOutYourOwnChangeSavesThatFirst() async throws {
        let (yours, _, package, history) = try await copies()
        let lineup = try await Mix.lineUp(package, history: history, with: yours.project)
        let saved = try await Mix.apply([lineup.changes[0].id], in: lineup)
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
        _ = try await Mix.apply([first.changes[0].id, first.changes[1].id], in: first)
        XCTAssertEqual(text(yours), "A-you\nb\nc\nd\ne\n")
        // Newer than their first-line change, older than their last-line one.
        try commit(yours, "Whisper it again", at: 350, ["Sources/App.swift": "A-you-again\nb\nc\nd\ne\n"])

        let lineup = try await Mix.lineUp(package, history: history, with: yours.project)
        let last = try XCTUnwrap(lineup.changes.first { !$0.here })
        XCTAssertEqual(lineup.changes.filter { !$0.here }.map(\.title), ["Shout the last line"])
        _ = try await Mix.apply(Set(lineup.changes.filter(\.here).map(\.id) + [last.id]), in: lineup)
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
        _ = try await Mix.apply(Set(lineup.changes.map(\.id)), in: lineup)
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
        _ = try await Mix.apply(Set(lineup.changes.map(\.id)), in: lineup)
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
        _ = try await Mix.apply(Set(lineup.changes.map(\.id)), in: lineup)
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
}
