import XCTest
@testable import Lamp

/// Lamp's own git runs under the agent's sandbox. What that must not cost: versions are still saved, undone
/// and restored, whatever the history or the person's Mac-wide git settings hold, and those settings open
/// nothing to Lamp's git but their own files.
final class HistoryInTheSandboxTests: XCTestCase {
    private let escape = HistoryEscapeTests()
    override func tearDown() { escape.tearDown() }

    private func text(_ app: HistoryEscapeTests.App, _ file: String = "Sources/App.swift") -> String {
        (try? String(contentsOf: app.project.dir.appendingPathComponent(file), encoding: .utf8)) ?? "(missing)"
    }

    private func write(_ content: String, _ app: HistoryEscapeTests.App, _ file: String = "Sources/App.swift") throws {
        try content.write(to: app.project.dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }

    /// Git's Mac-wide settings for this test: the file `app()` made empty, with these lines in it.
    private func macWide(_ settings: String) throws {
        try settings.write(toFile: String(cString: getenv("GIT_CONFIG_GLOBAL")), atomically: true, encoding: .utf8)
    }

    /// Two more versions, Undo as Store.undo does it, then back to the first.
    private func saveUndoAndGoBack(_ app: HistoryEscapeTests.App, _ what: String) async throws {
        for content in ["two\n", "three\n"] {
            try write(content, app)
            let unsaved = await Versions.hasUnsavedChanges(app.project)
            XCTAssertTrue(unsaved, "\(what): a change should read as unsaved")
            let saved = await Versions.save(app.project, message: content.trimmingCharacters(in: .newlines))
            XCTAssertTrue(saved, "\(what): saving \(content.trimmingCharacters(in: .newlines))")
        }
        var versions = await Versions.list(app.project)
        XCTAssertEqual(Array(versions.map(\.message).prefix(2)), ["three", "two"], what)
        let (undoing, target) = try XCTUnwrap(Versions.undoTarget(in: versions), what)
        let undone = await Versions.restore(app.project, to: target, message: "Undid “\(undoing.label)”", trailer: "Lamp-Undid: \(undoing.id)")
        XCTAssertTrue(undone, "\(what): Undo")
        XCTAssertEqual(text(app), "two\n", "\(what): after Undo")
        versions = await Versions.list(app.project)
        let back = await Versions.restore(app.project, to: try XCTUnwrap(versions.last), message: "Back to first")
        XCTAssertTrue(back, "\(what): going back to the first version")
        XCTAssertEqual(text(app), "one\n", "\(what): after going back")
        let unsaved = await Versions.hasUnsavedChanges(app.project)
        XCTAssertFalse(unsaved, "\(what): nothing unsaved at the end")
    }

    // MARK: Histories set up by hand are saved as before, and left as they were

    func testAPlainHistory() async throws {
        try await saveUndoAndGoBack(try escape.app(), "plain")
    }

    // MARK: The person's Mac-wide settings

    /// Signing every commit, with keys the sandbox closes: Lamp's versions are saved, unsigned.
    func testMacWideSigningDoesNotStopASave() async throws {
        let app = try escape.app()
        try macWide("[commit]\n\tgpgsign = true\n[tag]\n\tgpgsign = true\n\tforceSignAnnotated = true\n[gpg]\n\tprogram = /usr/bin/false\n")
        try await saveUndoAndGoBack(app, "signing on")
        let versions = await Versions.list(app.project)
        await Versions.name(app.project, try XCTUnwrap(versions.first).id, "Named")
        XCTAssertEqual(try escape.loose("git tag -l 'forge/*' | wc -l", in: app.project.dir).output.trimmingCharacters(in: .whitespacesAndNewlines), "1")
        XCTAssertEqual(try escape.loose("git log --format=%G? | sort -u", in: app.project.dir).output, "N\n")
    }

    /// The person's settings open their own git files to Lamp's git, and nothing more: a setting that names
    /// a folder, or a file in Lamp's own folder (keys, sign-ins, other apps), opens neither.
    func testAPersonsSettingsOpenOnlyTheirOwnGitFiles() async throws {
        let app = try escape.app()
        let beside = app.root.appendingPathComponent("beside.txt")
        try "private".write(to: beside, atomically: true, encoding: .utf8)
        let lamps = Sandbox.folder.appendingPathComponent("test-\(UUID().uuidString).txt")
        try FileManager.default.createDirectory(at: Sandbox.folder, withIntermediateDirectories: true)
        try "a key".write(to: lamps, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: lamps) }
        let link = app.root.appendingPathComponent(".gitignore_global")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: lamps)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for named in [home, home + "/", app.root.path, lamps.path, link.path, Sandbox.folder.deletingLastPathComponent().path] {
            try macWide("[core]\n\texcludesFile = \"\(named)\"\n\tattributesFile = \"\(named)\"\n")
            var output = ""
            _ = await Versions.git("cat \(Sandbox.quoted(beside.path)) \(Sandbox.quoted(lamps.path)) 2>/dev/null; ls \(Sandbox.quoted(app.root.path)) 2>/dev/null", cwd: app.project.dir) { output += $0 + "\n" }
            XCTAssertFalse(output.contains("private"), "\(named): a file beside the app was read")
            XCTAssertFalse(output.contains("a key"), "\(named): a file in Lamp's own folder was read")
            XCTAssertFalse(output.contains("beside.txt"), "\(named): a folder outside the app was listed")
        }
        // The app still saves with any of them set.
        try write("two\n", app)
        let saved = await Versions.save(app.project, message: "two")
        XCTAssertTrue(saved)
    }

    // MARK: What can't escape can't stall a save either

    func testAHookThatHangsOrFailsDoesNotStopASave() async throws {
        let app = try escape.app()
        let planted = try escape.confined("""
            printf '#!/bin/sh\\nsleep 300\\n' > .git/hooks/post-commit && printf '#!/bin/sh\\nexit 1\\n' > .git/hooks/pre-commit \
            && printf '#!/bin/sh\\nsleep 300\\n' > .git/hooks/post-index-change && chmod +x .git/hooks/* && git config core.fsmonitor 'sleep 300'
            """, in: app)
        XCTAssertEqual(planted.status, 0, planted.output)
        let start = Date()
        try await saveUndoAndGoBack(app, "hooks that hang or fail")
        XCTAssertLessThan(Date().timeIntervalSince(start), 60)
    }

    // MARK: The rest of Lamp's git

    /// Reading what a version changed (for its title) runs a text converter the history names.
    func testReadingAVersionsChangesStaysInside() async throws {
        let app = try escape.app()
        let planted = try escape.confined("git config diff.planted.textconv \(Sandbox.quoted(app.tool)) && printf '*.swift diff=planted\\n' > .gitattributes", in: app)
        XCTAssertEqual(planted.status, 0, planted.output)
        try write("two\n", app)
        let saved = await Versions.save(app.project, message: "two")
        XCTAssertTrue(saved)
        var lines: [String] = []
        let shown = await Versions.git("git show --format= --unified=1 HEAD -- .", cwd: app.project.dir) { lines.append($0) }
        XCTAssertEqual(shown, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.ranInside.path), "the converter should have run, inside the app")
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.escaped.path), "the converter reached outside the app")
    }

    /// The migration at launch can't await, and runs git its own way: confined as well.
    func testTheMigrationsGitIsConfinedToo() async throws {
        let app = try escape.app()
        let planted = try escape.confined("git config filter.planted.clean \(Sandbox.quoted(app.tool)) && printf '* filter=planted\\n' > .gitattributes", in: app)
        XCTAssertEqual(planted.status, 0, planted.output)
        try write("two\n", app)
        let result = Versions.gitBlocking("git add -A && \(Versions.commit) -qm migrated && git log --format=%s -1", cwd: app.project.dir)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "migrated", result.errors)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.ranInside.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.escaped.path))
    }
}
