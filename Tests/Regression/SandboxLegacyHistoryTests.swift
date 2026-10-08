import XCTest
@testable import Lamp

/// An app's history written before it was closed to the agent (0.11.0 confined commands and left `.git`
/// open) can hold anything. Each test plants one such thing loose, as a command could then, and runs what
/// Lamp runs on its own afterwards: save, look for unsaved work, name a version, read a version's changes,
/// and restore one. The planted program would make a file outside the app.
final class SandboxLegacyHistoryTests: XCTestCase {
    private var roots: [URL] = []
    override func tearDown() { for root in roots { try? FileManager.default.removeItem(at: root) } }

    private func project() throws -> (project: LampProject, root: URL, escaped: URL) {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-sandbox-test-\(UUID().uuidString)")
        roots.append(root)
        let dir = root.appendingPathComponent("Apps/coinflip")
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "one".write(to: dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        let project = LampProject(id: "coinflip", name: "Coin Flip", exe: "CoinFlip", dir: dir)
        let made = try loose("git init -q && git add -A && git -c user.name=Lamp -c user.email=lamp@localhost -c commit.gpgsign=false commit -qm first", in: project)
        XCTAssertEqual(made.status, 0, made.output)
        return (project, root, root.appendingPathComponent("escaped"))
    }

    private func loose(_ command: String, in project: LampProject) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = project.dir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func confined(_ command: String, in project: LampProject) throws -> (status: Int32, output: String) {
        try loose(try XCTUnwrap(Sandbox.wrap(command, for: project)), in: project)
    }

    /// Everything Lamp does with git on its own, in the order a person would cause it.
    private func everythingLampDoes(_ project: LampProject) async throws {
        try "two".write(to: project.dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        _ = await Versions.hasUnsavedChanges(project)
        _ = await Versions.save(project, message: "second")
        let versions = await Versions.list(project)
        if let newest = versions.first {
            await Versions.name(project, newest.id, "Before the redesign")
            _ = await Versions.git("git show --format= --unified=1 \"$LAMP_VERSION\" -- .", cwd: project.dir, env: ["LAMP_VERSION": newest.id])
        }
        if let oldest = versions.last { _ = await Versions.restoreFiles(project, to: oldest) }
        _ = await Versions.save(project, message: "back to the first")
        _ = await Versions.hasUnsavedChanges(project)
    }

    /// A program for a setting that wants a path, kept where a command could have left one (not in the app).
    private func program(_ name: String, in root: URL, touching escaped: URL) throws -> String {
        let file = root.appendingPathComponent(name)
        try "#!/bin/sh\ntouch \(Sandbox.quoted(escaped.path))\ncat\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file.path
    }

    func testSettingsAlreadyInTheHistoryRunNothing() async throws {
        // Each: what to leave in the history's settings, given the path of a program that marks its run. A
        // filter isn't removed (a real one decides what the saved files are): Lamp leaves that history alone.
        let filters = ["a filter for files going in", "a filter for files coming out", "a long-running filter"]
        let plants: [(String, (String) -> String)] = [
            ("a filter for files going in", { "git config filter.planted.clean \($0)" }),
            ("a filter for files coming out", { "git config filter.planted.smudge \($0)" }),
            ("a long-running filter", { "git config filter.planted.process \($0)" }),
            ("a text converter", { "git config diff.planted.textconv \($0)" }),
            ("another program to compare files", { "git config diff.external \($0)" }),
            ("a signing program for versions", { "git config commit.gpgsign true && git config gpg.program \($0)" }),
            ("a signing program for names", { "git config tag.gpgsign true && git config gpg.program \($0)" }),
            ("a hook named in the settings", { "git config hook.planted.command \($0) && git config hook.planted.event post-commit" }),
            ("settings brought in from another file", { "printf '[filter \"planted\"]\\n\\tclean = %s\\n' \($0) > ../../extra.cfg && git config include.path ../../../extra.cfg" }),
        ]
        for (what, plant) in plants {
            let (project, root, escaped) = try project()
            let planted = try loose(plant(Sandbox.quoted(try program("program", in: root, touching: escaped))), in: project)
            XCTAssertEqual(planted.status, 0, "\(what): \(planted.output)")
            // The app's own files stay the agent's to write, this one included.
            _ = try confined("printf '* filter=planted diff=planted\\n' > .gitattributes", in: project)
            try await everythingLampDoes(project)
            XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path), "\(what), already in the history, ran outside the sandbox")
            let log = try loose("git log --format=%s | tr '\\n' ','", in: project)
            if filters.contains(what) {
                XCTAssertEqual(log.output, "first,", "\(what): Lamp should have left this history alone")
                XCTAssertTrue(try String(contentsOf: project.dir.appendingPathComponent(".git/config"), encoding: .utf8).contains("planted"), what)
            } else {
                XCTAssertTrue(log.output.contains("second"), "\(what): Lamp's save should still work: \(log.output)")
            }
        }
    }

    /// `core.worktree` points Lamp's restore, and the clean-up after it, at another folder.
    func testTheHistoryCantPointLampAtAnotherFolder() async throws {
        let (project, root, _) = try project()
        let victim = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: true)
        try "keep".write(to: victim.appendingPathComponent("letter.txt"), atomically: true, encoding: .utf8)
        let planted = try loose("git config core.worktree \(Sandbox.quoted(victim.path))", in: project)
        XCTAssertEqual(planted.status, 0, planted.output)
        try await everythingLampDoes(project)
        XCTAssertTrue(FileManager.default.fileExists(atPath: victim.appendingPathComponent("letter.txt").path), "Lamp's restore cleaned out another folder")
        XCTAssertFalse(FileManager.default.fileExists(atPath: victim.appendingPathComponent("Sources/App.swift").path), "Lamp's restore wrote into another folder")
    }

    /// Restoring a version on a clean history: the files come back, and nothing else is touched.
    func testRestoringAVersionPutsItsFilesBack() async throws {
        let (project, _, _) = try project()
        try "two".write(to: project.dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        try "extra".write(to: project.dir.appendingPathComponent("Sources/Extra.swift"), atomically: true, encoding: .utf8)
        let saved = await Versions.save(project, message: "second")
        XCTAssertTrue(saved)
        let versions = await Versions.list(project)
        let first = try XCTUnwrap(versions.last)
        XCTAssertEqual(first.message, "first")
        let restored = await Versions.restore(project, to: first, message: "Back to first")
        XCTAssertTrue(restored)
        XCTAssertEqual(try String(contentsOf: project.dir.appendingPathComponent("Sources/App.swift"), encoding: .utf8), "one")
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.dir.appendingPathComponent("Sources/Extra.swift").path))
        let unsaved = await Versions.hasUnsavedChanges(project)
        XCTAssertFalse(unsaved)
        let log = try loose("git log --format=%s | head -1", in: project)
        XCTAssertEqual(log.output.trimmingCharacters(in: .whitespacesAndNewlines), "Back to first")
    }

    /// A `.git` that is a pointer (a file naming another folder, a link, or a shared folder named inside
    /// it) leads to a place the agent's commands can still write. Lamp runs no git there at all.
    func testAHistoryThatPointsElsewhereIsNotUsed() async throws {
        let moves = [
            ("a file naming another folder", "mv .git .history && echo 'gitdir: .history' > .git"),
            ("a link to another folder", "mv .git .history && ln -s .history .git"),
            ("a shared folder named inside it", "cp -R .git .history && echo ../.history > .git/commondir"),
            ("settings that are a link", "mv .git/config .settings && ln -s ../.settings .git/config"),
        ]
        for (what, move) in moves {
            let (project, root, escaped) = try project()
            let moved = try loose(move, in: project)
            XCTAssertEqual(moved.status, 0, "\(what): \(moved.output)")
            let touch = Sandbox.quoted(try program("program", in: root, touching: escaped))
            // What the agent can do now, confined: the other place is an ordinary folder of the app.
            _ = try confined("for file in .history/config .settings; do [ -f $file ] && git config --file $file filter.planted.clean \(touch); done; printf '* filter=planted\\n' > .gitattributes", in: project)
            try await everythingLampDoes(project)
            XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path), "\(what): something the agent wrote there ran outside the sandbox")
        }
    }

    /// A settings file with a second name (a hard link made while `.git` was open) can be written by that name.
    func testSettingsWithASecondNameAreMadeLampsOwn() async throws {
        let (project, root, escaped) = try project()
        // And whatever name Lamp might use for the copy is taken already, by a link to a file outside the app.
        let letter = root.appendingPathComponent("letter.txt")
        try "keep".write(to: letter, atomically: true, encoding: .utf8)
        let linked = try loose("ln .git/config Sources/settings-by-another-name && for name in config.lamp config.lock config.tmp config.new; do ln -s \(Sandbox.quoted(letter.path)) .git/$name; done; rm .git/config.lock", in: project)
        XCTAssertEqual(linked.status, 0, linked.output)
        _ = await Versions.hasUnsavedChanges(project)   // any call of Lamp's git
        let touch = Sandbox.quoted(try program("program", in: root, touching: escaped))
        _ = try confined("printf '[filter \"planted\"]\\n\\tclean = %s\\n' \(touch) >> Sources/settings-by-another-name; printf '* filter=planted\\n' > .gitattributes", in: project)
        let settings = try String(contentsOf: project.dir.appendingPathComponent(".git/config"), encoding: .utf8)
        XCTAssertFalse(settings.contains("planted"), settings)
        XCTAssertEqual(try String(contentsOf: letter, encoding: .utf8), "keep")
        let kind = try loose("stat -f '%HT %l' .git/config", in: project)
        XCTAssertEqual(kind.output.trimmingCharacters(in: .whitespacesAndNewlines), "Regular File 1")
        try await everythingLampDoes(project)
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path))
    }

    /// What an ordinary history holds is left as it is, and so is where a person pushes it.
    func testOrdinarySettingsAreKept() async throws {
        let (project, _, _) = try project()
        let before = try loose("git remote add origin https://example.com/me/coinflip.git && git config branch.main.remote origin && git config branch.main.merge refs/heads/main && git config user.name Me && git config --list --local | sort", in: project)
        XCTAssertEqual(before.status, 0, before.output)
        try await everythingLampDoes(project)
        let after = try loose("git config --list --local | sort", in: project)
        XCTAssertEqual(after.output, before.output)
    }

    /// Codex runs whole inside the profile, with folders of its own opened: the history stays closed
    /// whatever was opened, the app's folder and the history itself included.
    func testTheHistoryStaysClosedWhateverAnEngineOpens() throws {
        let (project, root, _) = try project()
        let history = project.dir.appendingPathComponent(".git").path
        let state = root.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        let wrapped = try XCTUnwrap(Sandbox.wrapEngine("touch \(Sandbox.quoted(state.path))/ok && echo opened && touch .git/planted; echo x >> .git/config; mkdir .git/hooks/x",
                                                      for: project, opening: [state.path, project.dir.path, history],
                                                      reading: [history], writing: [history, project.dir.path], keeping: [state.appendingPathComponent("kept").path]))
        let result = try loose(wrapped, in: project)
        XCTAssertTrue(result.output.contains("opened"), result.output)   // what was opened is open
        XCTAssertEqual(result.output.components(separatedBy: "not permitted").count - 1, 3, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: history + "/planted"))
        let profile = Sandbox.profile(for: project, opening: [state.path, history], writing: [history], keeping: [history + "/config"])
        let lines = profile.split(separator: "\n").map(String.init)
        let rule = try XCTUnwrap(lines.lastIndex { $0.hasPrefix("(deny file-write* (subpath") && $0.hasSuffix("/.git\"))") })
        XCTAssertFalse(lines[(rule + 1)...].contains { $0.hasPrefix("(allow") && $0.contains("file-write") }, profile)
    }
}
