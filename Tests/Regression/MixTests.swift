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
        for app in [yours, theirs] { try FileManager.default.removeItem(atPath: app.tool) }
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
