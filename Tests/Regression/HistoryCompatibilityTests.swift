import XCTest
@testable import Lamp

/// What Lamp's care with an app's history must not cost the person: saving, Undo and going back to a
/// version keep working on the histories people really have, and a history Lamp can't use is left exactly
/// as it was. Each test has its own global git settings, so the Mac's own don't decide the result.
final class HistoryCompatibilityTests: XCTestCase {
    private var roots: [URL] = []
    override func tearDown() {
        unsetenv("GIT_CONFIG_GLOBAL")
        for root in roots {
            _ = try? run("chflags -R nouchg . 2>/dev/null; chmod -R u+w . 2>/dev/null", in: root)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func run(_ command: String, in folder: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = folder
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// An app's folder with one file, and the global settings every git started from here will read.
    private func folder(global: String = "") throws -> (project: LampProject, root: URL) {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-sandbox-test-\(UUID().uuidString)")
        roots.append(root)
        let dir = root.appendingPathComponent("Apps/coinflip", isDirectory: true)
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "one\n".write(to: dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        let settings = root.appendingPathComponent("global-settings")
        try global.write(to: settings, atomically: true, encoding: .utf8)
        setenv("GIT_CONFIG_GLOBAL", settings.path, 1)
        return (LampProject(id: "coinflip", name: "Coin Flip", exe: "CoinFlip", dir: dir), root)
    }

    /// The first version, made as Lamp makes it for a new app.
    private func started(global: String = "", with create: String = "git init -q") async throws -> (project: LampProject, root: URL) {
        let (project, root) = try folder(global: global)
        let made = await Versions.git("\(create) && git add -A && \(Versions.commit) -qm first", cwd: project.dir)
        XCTAssertEqual(made, 0, "the first version")
        return (project, root)
    }

    private func text(_ project: LampProject) -> String {
        (try? String(contentsOf: project.dir.appendingPathComponent("Sources/App.swift"), encoding: .utf8)) ?? "(missing)"
    }

    private func settings(_ project: LampProject) -> String {
        (try? String(contentsOf: project.dir.appendingPathComponent(".git/config"), encoding: .utf8)) ?? "(missing)"
    }

    /// Two more versions, Undo, then back to the first: what a person does with an app's history.
    private func saveUndoAndGoBack(_ project: LampProject, _ what: String) async throws {
        for content in ["two\n", "three\n"] {
            try content.write(to: project.dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
            let unsaved = await Versions.hasUnsavedChanges(project)
            XCTAssertTrue(unsaved, "\(what): a change should read as unsaved")
            let saved = await Versions.save(project, message: content.trimmingCharacters(in: .newlines))
            XCTAssertTrue(saved, "\(what): saving \(content.trimmingCharacters(in: .newlines))")
        }
        var versions = await Versions.list(project)
        XCTAssertEqual(versions.map(\.message), ["three", "two", "first"], what)
        // Undo, as Store.undo does it.
        let unsaved = await Versions.hasUnsavedChanges(project)
        XCTAssertFalse(unsaved, "\(what): nothing should read as unsaved after a save")
        let (undoing, target) = try XCTUnwrap(Versions.undoTarget(in: versions), what)
        let undone = await Versions.restore(project, to: target, message: "Undid “\(undoing.label)”", trailer: "Lamp-Undid: \(undoing.id)")
        XCTAssertTrue(undone, "\(what): Undo")
        XCTAssertEqual(text(project), "two\n", "\(what): after Undo")
        versions = await Versions.list(project)
        let first = try XCTUnwrap(versions.last)
        let back = await Versions.restore(project, to: first, message: "Back to first")
        XCTAssertTrue(back, "\(what): going back to the first version")
        XCTAssertEqual(text(project).replacingOccurrences(of: "\r\n", with: "\n"), "one\n", "\(what): after going back")
        await Versions.name(project, first.id, "The start")
        versions = await Versions.list(project)
        XCTAssertEqual(versions.count, 5, what)
        XCTAssertEqual(versions.last?.name, "The start", what)
    }

    // MARK: Ordinary histories keep working

    func testAPlainHistory() async throws {
        let (project, _) = try await started()
        try await saveUndoAndGoBack(project, "plain")
    }

    func testAHistoryPushedSomewhere() async throws {
        // The branch is named here: the settings below are about it, and git's default name varies.
        let (project, root) = try await started(with: "git init -q -b main")
        let pushed = try run("git init -q --bare -b main ../../remote.git && git remote add origin ../../remote.git && git push -q -u origin HEAD 2>&1 && git config user.name Me && git config user.email me@example.com && git config push.default current && git config remote.origin.push refs/heads/main:refs/heads/published && git config branch.main.pushRemote origin && git config lfs.url https://example.com/me/coinflip.git/info/lfs && git config core.excludesFile ../../ignored-everywhere && echo '*.log' > ../../ignored-everywhere",
                             in: project.dir)
        XCTAssertEqual(pushed.status, 0, pushed.output)
        let before = try run("git config --local --list | sort", in: project.dir).output
        try await saveUndoAndGoBack(project, "pushed")
        XCTAssertEqual(try run("git config --local --list | sort", in: project.dir).output, before)
        let again = try run("git push -q 2>&1 && git status -sb | head -1 && git -C ../../remote.git log --format=%s -1 main", in: project.dir)
        XCTAssertEqual(again.status, 0, again.output)
        XCTAssertTrue(again.output.contains("origin/"), again.output)
        // The push went where this history says pushes go, not to the branch's own name.
        XCTAssertEqual(try run("git -C ../../remote.git log --format=%s -1 published", in: project.dir).output, "Back to first\n")
        // And what this history ignores is still ignored.
        try "noise".write(to: project.dir.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
        let unsaved = await Versions.hasUnsavedChanges(project)
        XCTAssertFalse(unsaved)
        _ = root
    }

    /// Hashes of the newer kind.
    func testASHA256History() async throws {
        let (project, _) = try await started(with: "git init -q --object-format=sha256")
        XCTAssertTrue(settings(project).contains("sha256"))
        try await saveUndoAndGoBack(project, "sha256")
        XCTAssertTrue(settings(project).contains("sha256"))
    }

    /// The person's own settings make every new history keep its version names the newer way; Lamp's own
    /// `git init` then makes one like that.
    func testAHistoryMadeWithTheNewerNameStoreByDefault() async throws {
        let (project, _) = try await started(global: "[init]\n\tdefaultRefFormat = reftable\n")
        XCTAssertTrue(settings(project).lowercased().contains("refstorage = reftable"), settings(project))
        try await saveUndoAndGoBack(project, "reftable")
        XCTAssertTrue(settings(project).lowercased().contains("refstorage = reftable"), settings(project))
    }

    /// Filters set up for the whole Mac (as Git LFS's installer does) are the person's own, and still run.
    func testFiltersSetUpForTheWholeMacStillRun() async throws {
        let global = "[filter \"lfs\"]\n\tclean = sed s/^/POINTER:/\n\tsmudge = sed s/^POINTER://\n\trequired = true\n"
        let (project, _) = try await started(global: global)
        try "*.bin filter=lfs\n".write(to: project.dir.appendingPathComponent(".gitattributes"), atomically: true, encoding: .utf8)
        try "big\n".write(to: project.dir.appendingPathComponent("asset.bin"), atomically: true, encoding: .utf8)
        let saved = await Versions.save(project, message: "asset")
        XCTAssertTrue(saved)
        XCTAssertEqual(try run("git show HEAD:asset.bin", in: project.dir).output, "POINTER:big\n")
        try FileManager.default.removeItem(at: project.dir.appendingPathComponent("asset.bin"))
        let versions = await Versions.list(project)
        let restored = await Versions.restoreFiles(project, to: try XCTUnwrap(versions.first))
        XCTAssertTrue(restored)
        XCTAssertEqual(try String(contentsOf: project.dir.appendingPathComponent("asset.bin"), encoding: .utf8), "big\n")
    }

    /// Line endings the history was told to check out stay as they were told.
    func testLineEndingsAreCheckedOutAsTheHistorySays() async throws {
        let (project, _) = try await started()
        let set = try run("git config core.eol crlf && git config core.autocrlf false && echo '*.swift text' > .gitattributes && git add -A && \(Versions.commit) -qm endings && rm Sources/App.swift && git checkout -q -- Sources/App.swift",
                          in: project.dir)
        XCTAssertEqual(set.status, 0, set.output)
        XCTAssertEqual(text(project), "one\r\n")
        try "two\n".write(to: project.dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        let saved = await Versions.save(project, message: "two")
        XCTAssertTrue(saved)
        let versions = await Versions.list(project)
        let back = await Versions.restore(project, to: try XCTUnwrap(versions.dropFirst().first), message: "Back")
        XCTAssertTrue(back)
        XCTAssertEqual(text(project), "one\r\n")
        XCTAssertTrue(settings(project).contains("eol = crlf"), settings(project))
    }

    // MARK: A history Lamp can't use is left as it was

    /// Settings Lamp can neither keep (they reach a program or another file of settings) nor remove (the
    /// history would stop meaning what it did): nothing in the history changes.
    func testAHistoryLampCantUseIsNotChanged() async throws {
        let cases = [
            ("a partial clone", "git config core.repositoryformatversion 1 && git config extensions.partialclone origin && git config remote.origin.url https://example.com/x.git && git config remote.origin.promisor true && git config remote.origin.partialclonefilter blob:none"),
            ("settings per worktree", "git config core.repositoryformatversion 1 && git config extensions.worktreeConfig true && git config --worktree core.autocrlf true"),
            ("a checkout of only part of the files", "git config core.sparseCheckout true && echo '/Sources/' > .git/info/sparse-checkout"),
            ("a checkout of only part of the files, set up with git's own command", "mkdir -p Extra && echo x > Extra/x && git add -A && \(Versions.commit) -qm extra && git sparse-checkout init --cone && git sparse-checkout set Sources"),
            ("a partial clone as git writes one now", "git config remote.origin.url https://example.com/x.git && git config remote.origin.promisor true && git config remote.origin.partialclonefilter blob:none"),
            ("a filter brought in from another file of settings", "printf '[filter \"kept\"]\\n\\tclean = cat\\n\\tsmudge = cat\\n' > ../../more-settings && git config include.path ../../../more-settings"),
            ("a filter set up in this history", "git config filter.lfs.clean 'git-lfs clean -- %f' && git config filter.lfs.smudge 'git-lfs smudge -- %f' && git config filter.lfs.process 'git-lfs filter-process' && git config filter.lfs.required true"),
        ]
        for (what, setup) in cases {
            let (project, _) = try await started()
            let set = try run(setup, in: project.dir)
            XCTAssertEqual(set.status, 0, "\(what): \(set.output)")
            let before = settings(project)
            let head = try run("git rev-parse HEAD", in: project.dir).output
            try "two\n".write(to: project.dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
            _ = await Versions.hasUnsavedChanges(project)
            _ = await Versions.save(project, message: "two")
            let versions = await Versions.list(project)
            if let first = versions.last { _ = await Versions.restoreFiles(project, to: first) }
            XCTAssertEqual(settings(project), before, "\(what): its settings were changed")
            XCTAssertEqual(try run("git rev-parse HEAD", in: project.dir).output, head, "\(what): a version was saved")
            XCTAssertEqual(text(project), "two\n", "\(what): the app's files were changed")
        }
    }

    // MARK: A repository inside the app's folder

    /// It is never part of a version, so it isn't unsaved work either, whatever its folder is called:
    /// Undo takes "unsaved work" to mean a turn that didn't finish, and throws that work away.
    func testARepositoryInsideTheAppIsNotUnsavedWork() async throws {
        for name in ["Vendor/kit", "Vendor/odd\nname", "Vendor/ spaced \"quoted\" ", "Vendor/tab\there"] {
            let (project, _) = try await started()
            let nested = project.dir.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            let made = try run("git init -q && echo x > file && git add -A && git -c user.name=a -c user.email=a@b commit -qm one", in: nested)
            XCTAssertEqual(made.status, 0, made.output)
            try "beside\n".write(to: project.dir.appendingPathComponent("Vendor/Beside.swift"), atomically: true, encoding: .utf8)
            var unsaved = await Versions.hasUnsavedChanges(project)
            XCTAssertTrue(unsaved, "\(name.debugDescription): the file beside it is unsaved work")
            let saved = await Versions.save(project, message: "beside")
            XCTAssertTrue(saved, name.debugDescription)
            unsaved = await Versions.hasUnsavedChanges(project)
            XCTAssertFalse(unsaved, "\(name.debugDescription): reads as unsaved after a save")
            // It is still something in the folder: renaming a new app replaces its folder, and asks first.
            var lines: [String] = []
            _ = await Versions.git(Versions.status(".", everything: true), cwd: project.dir) { lines.append($0) }
            XCTAssertFalse(lines.isEmpty, "\(name.debugDescription): the folder would read as holding nothing of the person's")
            try await saveUndoAndGoBackKeeping(nested, in: project, name.debugDescription)
        }
    }

    /// Whatever state it is in. Git stops at one it can't read (none of these has a version git could
    /// record a link to), and that must not stop the app's own files being saved.
    func testARepositoryInsideTheAppNeverStopsASave() async throws {
        let shapes = [
            ("just made, nothing saved in it", "git init -q && echo x > file"),
            ("settings that can't be read", "git init -q && echo x > file && echo '[broken' >> .git/config"),
            ("a format this git doesn't know", "git init -q && echo x > file && git config core.repositoryformatversion 1 && git config extensions.nosuch true"),
            ("a pointer to nowhere", "echo 'gitdir: /nonexistent/elsewhere' > .git && echo x > file"),
            ("an empty folder called .git", "mkdir .git && echo x > file"),
        ]
        for (what, make) in shapes {
            let (project, _) = try await started()
            let nested = project.dir.appendingPathComponent("Vendor/kit", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            let made = try run(make, in: nested)
            XCTAssertEqual(made.status, 0, "\(what): \(made.output)")
            try "two\n".write(to: project.dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
            let saved = await Versions.save(project, message: "two")
            XCTAssertTrue(saved, "\(what): the app's own change wasn't saved")
            XCTAssertEqual(try run("git show HEAD:Sources/App.swift", in: project.dir).output, "two\n", what)
            XCTAssertTrue(FileManager.default.fileExists(atPath: nested.appendingPathComponent("file").path), what)
            // And the next one, with the folder still there.
            try "three\n".write(to: project.dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
            let again = await Versions.save(project, message: "three")
            XCTAssertTrue(again, "\(what): the second save")
            XCTAssertFalse(try run("git ls-files -s", in: project.dir).output.contains("160000 "), what)
        }
    }

    private func saveUndoAndGoBackKeeping(_ nested: URL, in project: LampProject, _ what: String) async throws {
        try "two\n".write(to: project.dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        let saved = await Versions.save(project, message: "two")
        XCTAssertTrue(saved, what)
        let versions = await Versions.list(project)
        let (undoing, target) = try XCTUnwrap(Versions.undoTarget(in: versions), what)
        let undone = await Versions.restore(project, to: target, message: "Undid “\(undoing.label)”", trailer: "Lamp-Undid: \(undoing.id)")
        XCTAssertTrue(undone, what)
        XCTAssertEqual(text(project), "one\n", what)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.appendingPathComponent("file").path), "\(what): the repository inside was touched")
        let unsaved = await Versions.hasUnsavedChanges(project)
        XCTAssertFalse(unsaved, what)
    }
}
