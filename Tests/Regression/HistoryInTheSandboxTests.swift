import XCTest
@testable import Lamp

/// Lamp's own git runs under the agent's sandbox. What that must not cost: the agent still does what it
/// likes with the app's history, histories people set up by hand are saved as before and left as they
/// were, and the person's own Mac-wide git settings still apply to Lamp's saves.
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

    private func settings(_ app: HistoryEscapeTests.App) throws -> String {
        try escape.loose("cat .git/config .git/config.worktree 2>/dev/null", in: app.project.dir).output
    }

    // MARK: The agent and the history

    func testTheAgentCanCommitRestoreAndBranch() async throws {
        let app = try escape.app()
        let work = try escape.confined("""
            echo two > Sources/App.swift && git add -A && git -c user.name=Agent -c user.email=agent@example.com commit -qm "the agent's own" \
            && git branch attempt && git switch -q attempt && echo three > Sources/App.swift && git checkout -- Sources/App.swift \
            && echo four > Sources/App.swift && git stash -q && git stash pop -q && git restore Sources/App.swift \
            && git tag mine && git config alias.st status && git st --porcelain && git switch -q main && cat Sources/App.swift
            """, in: app)
        XCTAssertEqual(work.status, 0, work.output)
        XCTAssertEqual(work.output.trimmingCharacters(in: .whitespacesAndNewlines), "two")
        // Lamp's versions carry on from there, the agent's own included.
        try write("five\n", app)
        let saved = await Versions.save(app.project, message: "five")
        XCTAssertTrue(saved)
        let versions = await Versions.list(app.project)
        XCTAssertEqual(versions.map(\.message), ["five", "the agent's own", "first"])
        let back = await Versions.restore(app.project, to: versions[1], message: "Back")
        XCTAssertTrue(back)
        XCTAssertEqual(text(app), "two\n")
    }

    // MARK: Histories set up by hand are saved as before, and left as they were

    func testAPlainHistory() async throws {
        try await saveUndoAndGoBack(try escape.app(), "plain")
    }

    func testACheckoutOfOnlySomeOfTheFiles() async throws {
        let app = try escape.app()
        let set = try escape.loose("mkdir Extra && echo x > Extra/x && git add -A && \(Versions.commit) -qm extra && git sparse-checkout init --cone && git sparse-checkout set Sources", in: app.project.dir)
        XCTAssertEqual(set.status, 0, set.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.project.dir.appendingPathComponent("Extra/x").path))
        let before = try settings(app)
        try write("two\n", app)
        let saved = await Versions.save(app.project, message: "two")
        XCTAssertTrue(saved)
        let versions = await Versions.list(app.project)
        let back = await Versions.restore(app.project, to: versions[1], message: "Back")
        XCTAssertTrue(back)
        XCTAssertEqual(text(app), "one\n")
        XCTAssertEqual(try settings(app), before)
        // What the checkout leaves out is still in every version, and still left out of the folder.
        XCTAssertTrue(try escape.loose("git ls-tree -r --name-only HEAD", in: app.project.dir).output.contains("Extra/x"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.project.dir.appendingPathComponent("Extra/x").path))
    }

    func testAPartialClonesSettings() async throws {
        let app = try escape.app()
        let set = try escape.loose("git config core.repositoryformatversion 1 && git config extensions.partialclone origin && git config remote.origin.url https://example.com/x.git && git config remote.origin.promisor true && git config remote.origin.partialclonefilter blob:none && git config alias.st status && git config pull.ff only", in: app.project.dir)
        XCTAssertEqual(set.status, 0, set.output)
        let before = try settings(app)
        try await saveUndoAndGoBack(app, "partial clone")
        XCTAssertEqual(try settings(app), before)
    }

    /// Git LFS set up in this one history: large files are saved as pointers and come back whole.
    func testLargeFilesSetUpInThisHistory() async throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/git-lfs"), "Git LFS isn't installed here")
        let app = try escape.app()
        let set = try escape.loose("export PATH=/opt/homebrew/bin:$PATH && git lfs install --local && git lfs track '*.bin' && git config lfs.storage large-files", in: app.project.dir)
        XCTAssertEqual(set.status, 0, set.output)
        try await largeFilesRoundTrip(app, "set up in this history, kept in a folder of its own inside the app")
    }

    /// Git LFS set up for the whole Mac, the usual way.
    func testLargeFilesSetUpForTheWholeMac() async throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/git-lfs"), "Git LFS isn't installed here")
        let app = try escape.app()
        try macWide("[filter \"lfs\"]\n\tclean = git-lfs clean -- %f\n\tsmudge = git-lfs smudge -- %f\n\tprocess = git-lfs filter-process\n\trequired = true\n")
        try "*.bin filter=lfs diff=lfs merge=lfs -text\n".write(to: app.project.dir.appendingPathComponent(".gitattributes"), atomically: true, encoding: .utf8)
        try await largeFilesRoundTrip(app, "set up for the whole Mac")
    }

    private func largeFilesRoundTrip(_ app: HistoryEscapeTests.App, _ what: String) async throws {
        try write(String(repeating: "large ", count: 2000), app, "asset.bin")
        let saved = await Versions.save(app.project, message: "asset")
        XCTAssertTrue(saved, what)
        let before = try settings(app)   // Git LFS notes its own format there the first time it runs
        XCTAssertTrue(try escape.loose("git cat-file -p HEAD:asset.bin", in: app.project.dir).output.hasPrefix("version https://git-lfs"), "\(what): not saved as a pointer")
        try FileManager.default.removeItem(at: app.project.dir.appendingPathComponent("asset.bin"))
        let versions = await Versions.list(app.project)
        let restored = await Versions.restoreFiles(app.project, to: try XCTUnwrap(versions.first))
        XCTAssertTrue(restored, what)
        XCTAssertEqual(text(app, "asset.bin"), String(repeating: "large ", count: 2000), "\(what): didn't come back whole")
        XCTAssertEqual(try settings(app), before, what)
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

    /// The same with this Mac's real settings, whatever they are.
    func testThisMacsOwnSettings() async throws {
        let app = try escape.app()
        unsetenv("GIT_CONFIG_GLOBAL")
        try await saveUndoAndGoBack(app, "this Mac's own settings")
        XCTAssertEqual(try escape.loose("git log -4 --format=%G? | sort -u", in: app.project.dir).output, "N\n")
    }

    /// An ignore file for every repository, kept in the home folder where the sandbox doesn't look.
    func testTheMacWideIgnoreFileStillApplies() async throws {
        let app = try escape.app()
        let ignored = app.root.appendingPathComponent(".gitignore_global")
        try "*.log\n".write(to: ignored, atomically: true, encoding: .utf8)
        try macWide("[core]\n\texcludesFile = \(ignored.path)\n")
        let first = await Versions.save(app.project, message: "everything so far")
        XCTAssertTrue(first)
        try write("noise", app, "debug.log")
        var unsaved = await Versions.hasUnsavedChanges(app.project)
        XCTAssertFalse(unsaved, "a file the person ignores everywhere reads as unsaved work")
        try write("two\n", app)
        let saved = await Versions.save(app.project, message: "two")
        XCTAssertTrue(saved)
        XCTAssertFalse(try escape.loose("git ls-tree -r --name-only HEAD", in: app.project.dir).output.contains("debug.log"))
        // And when the person changes their mind while Lamp is open.
        try macWide("")
        unsaved = await Versions.hasUnsavedChanges(app.project)
        XCTAssertTrue(unsaved)
    }

    /// Mac-wide settings spread over several files in the home folder (work and personal, say), one of them
    /// brought in only for some folders: git stops at a settings file it is told of and can't read.
    func testMacWideSettingsSplitOverSeveralFiles() async throws {
        let app = try escape.app()
        let ignored = app.root.appendingPathComponent(".gitignore_global")
        try "*.log\n".write(to: ignored, atomically: true, encoding: .utf8)
        try "[core]\n\texcludesFile = \(ignored.path)\n[include]\n\tpath = more/deeper.inc\n".write(to: app.root.appendingPathComponent(".gitconfig-work"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: app.root.appendingPathComponent("more"), withIntermediateDirectories: true)
        try "[pull]\n\tff = only\n".write(to: app.root.appendingPathComponent("more/deeper.inc"), atomically: true, encoding: .utf8)
        // The one brought in only for this folder names an ignore file of its own, which then wins.
        let ignoredHere = app.root.appendingPathComponent("ignored for apps")
        try "*.log\n*.tmp\n".write(to: ignoredHere, atomically: true, encoding: .utf8)
        try "[user]\n\tname = Someone\n[core]\n\texcludesFile = \"\(ignoredHere.path)\"\n".write(to: app.root.appendingPathComponent(".gitconfig for apps"), atomically: true, encoding: .utf8)
        try macWide("[include]\n\tpath = \(app.root.path)/.gitconfig-work\n[includeIf \"gitdir:\(app.root.path)/\"]\n\tpath = \"\(app.root.path)/.gitconfig for apps\"\n")
        let first = await Versions.save(app.project, message: "everything so far")
        XCTAssertTrue(first)
        try write("noise", app, "debug.log")
        try write("noise", app, "scratch.tmp")
        let unsaved = await Versions.hasUnsavedChanges(app.project)
        XCTAssertFalse(unsaved, "a file ignored through an included settings file reads as unsaved work")
        try await saveUndoAndGoBack(app, "settings in several files")
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
