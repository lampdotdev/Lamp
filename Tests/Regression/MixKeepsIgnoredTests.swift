import XCTest
@testable import Lamp

/// What this copy's `.lampignore` files keep to this computer is never touched by a mix, whatever the other copy's
/// file carries: not by their changes, not by leaving out one of yours, not in any version the mix saves, not by a mix
/// made again later, and not on disk when a file of theirs lands where an unsaved one of yours is kept. Their copy here
/// has no `.lampignore`, as a copy from before it was written, or from an older Lamp, sends everything.
final class MixKeepsIgnoredTests: XCTestCase {
    private let escape = HistoryEscapeTests()
    override func tearDown() { escape.tearDown() }

    private let identity = UUID().uuidString
    private let lines = "a\nb\nc\nd\ne\n"

    /// One step of a copy's history: whose, its title, when, and the files it writes (nil removes one).
    private struct Step {
        let theirs: Bool
        let title: String
        let at: Int
        let files: [String: String?]
    }

    private struct Copies {
        let yours: HistoryEscapeTests.App
        let theirs: HistoryEscapeTests.App
        let package: Sharing.Package
        let history: MixHistory
        func lineUp() async throws -> Mix.Lineup { try await Mix.lineUp(package, history: history, with: yours.project) }
    }

    private func save(_ app: HistoryEscapeTests.App, _ message: String, at seconds: Int, _ files: [String: String?]) throws {
        for (path, content) in files {
            let url = app.project.dir.appendingPathComponent(path)
            if let content {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: url, atomically: true, encoding: .utf8)
            } else {
                try FileManager.default.removeItem(at: url)
            }
        }
        let made = try escape.loose("git add -A && GIT_COMMITTER_DATE='@\(seconds) +0000' GIT_AUTHOR_DATE='@\(seconds) +0000' "
                                    + "git -c user.name=Lamp -c user.email=lamp@localhost commit -qm \(Sandbox.quoted(message))", in: app.project.dir)
        XCTAssertEqual(made.status, 0, made.output)
    }

    private func head(_ app: HistoryEscapeTests.App) throws -> String {
        try XCTUnwrap(Credits.validCommit(try escape.loose("git rev-parse HEAD", in: app.project.dir).output))
    }

    /// Yours and theirs from one start, then `steps`, and the file theirs shares: their latest at its top, their
    /// versions in History/.
    private func copies(_ start: [String: String], _ steps: [Step], parts: [String: Platform] = [:]) async throws -> Copies {
        let yours = try escape.app(), theirs = try escape.app()
        for app in [yours, theirs] {
            try FileManager.default.removeItem(atPath: app.tool)
            try FileManager.default.createDirectory(at: app.project.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        }
        var first: [String: String?] = start
        first[".gitignore"] = ".lamp/\n"
        try save(yours, "Start", at: 100, first)
        Sharing.setIdentity(identity, of: yours.project)
        var credits = Credits()
        credits.remixOf = [Credits.Remix(name: "Coin Flip", wish: identity, commit: try head(yours))]
        try credits.encoded().write(to: theirs.project.dir.appendingPathComponent(Credits.file))
        try save(theirs, "Imported from a shared file", at: 100, first)
        Sharing.setIdentity(identity, of: theirs.project)
        for step in steps { try save(step.theirs ? theirs : yours, step.title, at: step.at, step.files) }

        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-mix-keep-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: stage) }
        XCTAssertEqual(try escape.loose("git archive --format=tar HEAD | tar -x -C \(Sandbox.quoted(stage.path))", in: theirs.project.dir).status, 0)
        let manifest = Sharing.Manifest(format: Sharing.formatVersion, name: "Coin Flip", exportedAt: Date(), app: identity, platform: .mac,
                                        parts: parts.isEmpty ? nil : parts.map { Sharing.Manifest.Part(folder: $0.key, platform: $0.value) })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: stage.appendingPathComponent("lamp-app.json"))
        try MixHistory.write(for: theirs.project, credits: Credits.load(theirs.project), identity: identity, into: stage)
        let package = try Sharing.open(unpacked: stage)
        return Copies(yours: yours, theirs: theirs, package: package, history: try XCTUnwrap(MixHistory.read(in: stage)))
    }

    /// Mixes a pick as the window does once any check of it is in.
    @discardableResult
    private func mix(_ picked: Set<String>, in lineup: Mix.Lineup) async throws -> Int {
        let prepared = try await Mix.prepare(picked, in: lineup)
        let stand = ImportReview(summary: "checked", capabilities: [], concerns: [], detected: [])
        return try await Mix.apply(prepared, in: lineup, checked: prepared.needsCheck ? stand : nil)
    }

    private func ids(_ lineup: Mix.Lineup, except titles: String...) -> Set<String> {
        Set(lineup.changes.filter { !titles.contains($0.title) }.map(\.id))
    }

    /// Each version saved since `since`, oldest first: what `path` held in it, nil where it held nothing.
    private func saved(_ path: String, in app: HistoryEscapeTests.App, since: String) throws -> [String?] {
        let listed = try escape.loose("git rev-list --reverse \(since)..HEAD", in: app.project.dir)
        XCTAssertEqual(listed.status, 0, listed.output)
        return try listed.output.split(separator: "\n").map { commit in
            let shown = try escape.loose("git cat-file blob \(Sandbox.quoted("\(commit):\(path)")) 2>/dev/null", in: app.project.dir)
            return shown.status == 0 ? shown.output : nil
        }
    }

    private func onDisk(_ path: String, in app: HistoryEscapeTests.App) -> String? {
        try? String(contentsOf: app.project.dir.appendingPathComponent(path), encoding: .utf8)
    }

    /// Their edits, removals and additions to files yours keeps, by its own `.lampignore` and, for an app in a folder of
    /// its own, by that app's and its page's (Web/), reach none of the versions the mix saves nor the folder; a file yours removed
    /// stays gone. What else they changed comes in.
    func testTheirChangesLeaveWhatYoursKeepsAsYoursHasIt() async throws {
        let copies = try await copies([
            "Package.swift": "// made-up\n", "Sources/App.swift": lines, "Assets/data.csv": "start\n", "Assets/old.csv": "old\n", "Assets/gone.csv": "gone\n",
            "WebApp/" + ScreenKit.webAppPage.marker: ScreenKit.webAppPage.says, "WebApp/Web/index.html": "<p>start</p>\n",
            "WebApp/Web/scores.csv": "start\n", "WebApp/Web/local.json": "start\n",
        ], [
            Step(theirs: false, title: "Keep data here", at: 150, files: [
                ".lampignore": "*.csv\n", "WebApp/.lampignore": "/Web/scores.csv\n", "WebApp/Web/.lampignore": "local.json\n",
                "Assets/data.csv": "yours\n", "Assets/gone.csv": nil, "Sources/Mine.swift": "mine\n",
            ]),
            Step(theirs: true, title: "Their data", at: 200, files: [
                "Sources/App.swift": "A-them\nb\nc\nd\ne\n", "Assets/data.csv": "theirs\n", "Assets/old.csv": nil,
                "Assets/gone.csv": "theirs\n", "Assets/new.csv": "new\n", "WebApp/Web/index.html": "<p>theirs</p>\n",
                "WebApp/Web/scores.csv": "theirs\n", "WebApp/Web/local.json": "theirs\n",
            ]),
            Step(theirs: true, title: "Their more", at: 300, files: ["Sources/App.swift": "A-them\nb\nc\nd\nE-them\n", "Assets/data.csv": "theirs again\n"]),
        ], parts: ["WebApp": .webApp])
        let lineup = try await copies.lineUp()
        let before = try head(copies.yours)
        let mixed2lineup = try await mix(Set(lineup.changes.map(\.id)), in: lineup)
        XCTAssertEqual(mixed2lineup, 2)
        XCTAssertEqual(onDisk("Sources/App.swift", in: copies.yours), "A-them\nb\nc\nd\nE-them\n", "their other changes come in")
        XCTAssertEqual(onDisk("WebApp/Web/index.html", in: copies.yours), "<p>theirs</p>\n", "their other changes come in")
        let kept: [String: String?] = ["Assets/data.csv": "yours\n", "Assets/old.csv": "old\n", "Assets/gone.csv": nil, "Assets/new.csv": nil,
                                       "WebApp/Web/scores.csv": "start\n", "WebApp/Web/local.json": "start\n"]
        for (path, content) in kept {
            XCTAssertEqual(try saved(path, in: copies.yours, since: before), [content, content], "\(path) in every saved version")
            XCTAssertEqual(onDisk(path, in: copies.yours), content, path)
        }
    }

    /// Leaving out a change of yours that touched kept files beside code takes the code out and leaves the kept files as
    /// they are, a name git would quote among them.
    func testLeavingOutYourChangeKeepsItsKeptFiles() async throws {
        let quoted = "Assets/local\"notes.csv"
        let copies = try await copies(["Sources/App.swift": lines, "Assets/data.csv": "start\n", quoted: "start\n"], [
            Step(theirs: false, title: "Keep data here", at: 150, files: [".lampignore": "*.csv\n"]),
            Step(theirs: false, title: "Data and code", at: 200, files: ["Assets/data.csv": "yours\n", quoted: "yours\n", "Sources/Mine.swift": "mine\n"]),
            Step(theirs: true, title: "Shout", at: 300, files: ["Sources/App.swift": "A-them\nb\nc\nd\ne\n"]),
        ])
        let lineup = try await copies.lineUp()
        let before = try head(copies.yours)
        let mixed2lineup = try await mix(ids(lineup, except: "Data and code"), in: lineup)
        XCTAssertEqual(mixed2lineup, 2)
        XCTAssertNil(onDisk("Sources/Mine.swift", in: copies.yours), "the code left out goes")
        for path in ["Assets/data.csv", quoted] {
            XCTAssertEqual(try saved(path, in: copies.yours, since: before), ["yours\n", "yours\n"], path)
            XCTAssertEqual(onDisk(path, in: copies.yours), "yours\n", path)
        }
    }

    /// A version that changed only kept files isn't offered, yours or theirs, one of theirs taken before the file was kept
    /// included; mixing again later keeps what's kept, and offers the rest of theirs by what it changed elsewhere.
    func testVersionsOfOnlyKeptFilesAreNotOfferedAndAMixMadeAgainKeepsThem() async throws {
        let copies = try await copies(["Sources/App.swift": lines, "Assets/data.csv": "start\n"], [
            Step(theirs: true, title: "Their data", at: 200, files: ["Assets/data.csv": "theirs\n"]),
            Step(theirs: true, title: "Their code", at: 300, files: ["Sources/App.swift": "A-them\nb\nc\nd\ne\n", "Assets/data.csv": "theirs again\n"]),
        ])
        let first = try await copies.lineUp()
        let mixed1first = try await mix(ids(first, except: "Their code"), in: first)
        XCTAssertEqual(mixed1first, 1)
        XCTAssertEqual(onDisk("Assets/data.csv", in: copies.yours), "theirs\n", "before it was kept, their data came in")

        try save(copies.yours, "Keep data here", at: 400, [".lampignore": "*.csv\n", "Assets/data.csv": "yours\n"])
        try save(copies.yours, "Only data", at: 450, ["Assets/data.csv": "yours again\n"])
        let again = try await copies.lineUp()
        XCTAssertEqual(again.changes.map(\.title).sorted(), ["Keep data here", "Their code"])
        XCTAssertEqual(again.changes.first { $0.title == "Their code" }?.files, ["Sources/App.swift"])
        XCTAssertEqual(again.changes.first { $0.title == "Keep data here" }?.files, [".lampignore"])
        let before = try head(copies.yours)
        let mixed1again = try await mix(Set(again.changes.map(\.id)), in: again)
        XCTAssertEqual(mixed1again, 1)
        XCTAssertEqual(onDisk("Sources/App.swift", in: copies.yours), "A-them\nb\nc\nd\ne\n")
        XCTAssertEqual(try saved("Assets/data.csv", in: copies.yours, since: before), ["yours again\n"])
        XCTAssertEqual(onDisk("Assets/data.csv", in: copies.yours), "yours again\n")
    }

    /// A kept file no version holds, in a folder where their copy puts a file: the mix isn't made, and the file stays.
    func testAMixThatWouldReplaceAnUnsavedKeptFileIsRefused() async throws {
        let copies = try await copies(["Sources/App.swift": lines], [
            Step(theirs: false, title: "Keep data here", at: 150, files: [".lampignore": "*.csv\n"]),
            Step(theirs: true, title: "Add a helper", at: 200, files: ["Sources/Helper.swift": "// helper\n"]),
        ])
        let kept = copies.yours.project.dir.appendingPathComponent("Sources/Helper.swift/data.csv")
        try FileManager.default.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "only here\n".write(to: kept, atomically: true, encoding: .utf8)
        let lineup = try await copies.lineUp()
        let before = try head(copies.yours)
        do {
            try await mix(Set(lineup.changes.map(\.id)), in: lineup)
            XCTFail("the mix was made")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Sources/Helper.swift/data.csv"), error.localizedDescription)
        }
        XCTAssertEqual(try String(contentsOf: kept, encoding: .utf8), "only here\n")
        XCTAssertEqual(try head(copies.yours), before)
    }

    /// The `.lampignore` files the copies were lined up by are the ones the mix goes by: changed since, it isn't made.
    func testAMixWhoseKeptFilesChangedSinceItWasLinedUpIsNotMade() async throws {
        let copies = try await copies(["Sources/App.swift": lines, "Assets/data.csv": "start\n"], [
            Step(theirs: true, title: "Their data", at: 200, files: ["Sources/App.swift": "A-them\nb\nc\nd\ne\n", "Assets/data.csv": "theirs\n"]),
        ])
        let lineup = try await copies.lineUp()
        try "*.csv\n".write(to: copies.yours.project.dir.appendingPathComponent(".lampignore"), atomically: true, encoding: .utf8)
        let before = try head(copies.yours)
        do {
            try await mix(Set(lineup.changes.map(\.id)), in: lineup)
            XCTFail("the mix was made")
        } catch {}
        XCTAssertEqual(try head(copies.yours), before)
        XCTAssertEqual(onDisk("Assets/data.csv", in: copies.yours), "start\n")
    }

    /// On a disk that doesn't tell names apart by case (a Mac's usual), a file of theirs spelled like a kept one of yours
    /// is that file: it doesn't come in over it, in any saved version or on disk.
    func testTheirFileSpelledLikeAKeptOneDoesNotReplaceIt() async throws {
        let copies = try await copies(["Sources/App.swift": lines, "Assets/data.csv": "start\n"], [
            Step(theirs: false, title: "Keep data here", at: 150, files: [".lampignore": "/Assets/data.csv\n", "Assets/data.csv": "yours\n"]),
            Step(theirs: true, title: "Drop data", at: 200, files: ["Assets/data.csv": nil]),
            Step(theirs: true, title: "Their data", at: 250, files: ["Assets/Data.csv": "theirs\n", "Sources/App.swift": "A-them\nb\nc\nd\ne\n"]),
        ])
        let disk = try copies.yours.project.dir.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        try XCTSkipIf(disk.volumeSupportsCaseSensitiveNames == true, "this disk keeps the two names apart")
        let lineup = try await copies.lineUp()
        let before = try head(copies.yours)
        try await mix(Set(lineup.changes.map(\.id)), in: lineup)
        XCTAssertEqual(onDisk("Sources/App.swift", in: copies.yours), "A-them\nb\nc\nd\ne\n", "their other change comes in")
        XCTAssertEqual(onDisk("Assets/data.csv", in: copies.yours), "yours\n")
        for path in ["Assets/data.csv", "Assets/Data.csv"] {
            XCTAssertFalse(try saved(path, in: copies.yours, since: before).contains("theirs\n"), path)
        }
    }

    /// The same for a kept file no version holds: the mix isn't made.
    func testTheirFileSpelledLikeAnUnsavedKeptOneIsRefused() async throws {
        let copies = try await copies(["Sources/App.swift": lines], [
            Step(theirs: false, title: "Keep notes here", at: 150, files: [".lampignore": "/Assets/notes.csv\n"]),
            Step(theirs: true, title: "Their notes", at: 200, files: ["Assets/Notes.csv": "theirs\n", "Sources/App.swift": "A-them\nb\nc\nd\ne\n"]),
        ])
        let kept = copies.yours.project.dir.appendingPathComponent("Assets/notes.csv")
        let disk = try copies.yours.project.dir.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        try XCTSkipIf(disk.volumeSupportsCaseSensitiveNames == true, "this disk keeps the two names apart")
        try FileManager.default.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "only here\n".write(to: kept, atomically: true, encoding: .utf8)
        let lineup = try await copies.lineUp()
        let before = try head(copies.yours)
        do {
            try await mix(Set(lineup.changes.map(\.id)), in: lineup)
            XCTFail("the mix was made")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Assets/notes.csv"), error.localizedDescription)
        }
        XCTAssertEqual(try String(contentsOf: kept, encoding: .utf8), "only here\n")
        XCTAssertEqual(try head(copies.yours), before)
    }

    /// A version on the way counts as much as the last, since Undo puts it in the folder: their file added where an
    /// unsaved kept file's folder is, then removed again, still refuses the mix.
    func testAMixThatWouldReplaceAnUnsavedKeptFileOnTheWayIsRefused() async throws {
        let copies = try await copies(["Sources/App.swift": lines], [
            Step(theirs: false, title: "Keep data here", at: 150, files: [".lampignore": "*.csv\n"]),
            Step(theirs: true, title: "Add a helper", at: 200, files: ["Sources/Helper.swift": "// helper\n"]),
            Step(theirs: true, title: "Drop the helper", at: 300, files: ["Sources/Helper.swift": nil, "Sources/App.swift": "A-them\nb\nc\nd\ne\n"]),
        ])
        let kept = copies.yours.project.dir.appendingPathComponent("Sources/Helper.swift/data.csv")
        try FileManager.default.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "only here\n".write(to: kept, atomically: true, encoding: .utf8)
        let lineup = try await copies.lineUp()
        let before = try head(copies.yours)
        do {
            try await mix(Set(lineup.changes.map(\.id)), in: lineup)
            XCTFail("the mix was made")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Sources/Helper.swift/data.csv"), error.localizedDescription)
        }
        XCTAssertEqual(try String(contentsOf: kept, encoding: .utf8), "only here\n")
        XCTAssertEqual(try head(copies.yours), before)
    }
}
