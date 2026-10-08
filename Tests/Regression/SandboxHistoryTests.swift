import XCTest
@testable import Lamp

/// Lamp's own git runs outside the sandbox, on a folder the agent's confined commands can write. Git runs
/// programs named by what it finds in a repository (hooks, and settings that name a command), so anything a
/// confined command could leave there would run unconfined at the next save. These run the real thing: the
/// profile Lamp writes, a command planting what it can under it, then Lamp's own save and status; the planted
/// program would make a file in a place the sandbox closes.
final class SandboxHistoryTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    /// Under the home folder, like a real app, with a first version saved. `escaped` is beside the app, where
    /// a confined command can't write and an unconfined one can.
    private func project() throws -> (project: LampProject, escaped: URL) {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-sandbox-test-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("Apps/coinflip")
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "one".write(to: dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        let project = LampProject(id: "coinflip", name: "Coin Flip", exe: "CoinFlip", dir: dir)
        let made = try loose("git init -q && git add -A && git -c user.name=Lamp -c user.email=lamp@localhost commit -qm first", in: project)
        XCTAssertEqual(made.status, 0, made.output)
        return (project, root.appendingPathComponent("escaped"))
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

    /// As the agent's command runs: wrapped by Lamp, under the profile Lamp wrote for this app.
    private func confined(_ command: String, in project: LampProject) throws -> (status: Int32, output: String) {
        try loose(try XCTUnwrap(Sandbox.wrap(command, for: project)), in: project)
    }

    /// What Lamp does after a turn and when it looks for unsaved work, twice over: some of what git runs
    /// only starts once something is already recorded.
    private func saveAndLook(_ project: LampProject) async throws {
        for round in ["two", "three"] {
            try round.write(to: project.dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
            _ = await Versions.hasUnsavedChanges(project)
            let saved = await Versions.save(project, message: round)
            XCTAssertTrue(saved, "Lamp's own save should still work (\(round))")
            _ = await Versions.hasUnsavedChanges(project)
        }
    }

    private func script(_ name: String, touching escaped: URL) -> String {
        "printf '#!/bin/sh\\ntouch %s\\n' \(Sandbox.quoted(escaped.path)) > \(name) && chmod +x \(name)"
    }

    /// The reported hole: a confined command writes a hook, or a setting that names a command, into the app's
    /// history, and Lamp's next save runs it outside the sandbox.
    func testAConfinedCommandCantLeaveSomethingForLampsGitToRun() async throws {
        let (project, escaped) = try project()
        let touch = Sandbox.quoted("touch \(Sandbox.quoted(escaped.path)); false")
        let plants = [
            ("a hook", "mkdir -p .git/hooks && " + script(".git/hooks/post-commit", touching: escaped)),
            ("a hook, spelled another way", "mkdir -p .GIT/Hooks && " + script(".GIT/Hooks/pre-commit", touching: escaped)),
            ("the file-watcher setting", "git config core.fsmonitor \(touch)"),
            ("a filter", "git config filter.planted.clean \(touch)"),
            ("a signing program", "git config commit.gpgsign true && git config gpg.program \(touch)"),
            ("settings written straight in", "printf '[core]\\n\\tfsmonitor = %s\\n' \(touch) >> .git/config"),
        ]
        for (what, command) in plants {
            let result = try confined(command, in: project)
            XCTAssertNotEqual(result.status, 0, "\(what) was planted: \(result.output)")
            XCTAssertTrue(result.output.contains("not permitted"), "\(what): \(result.output)")
        }
        _ = try confined("echo '* filter=planted' > .gitattributes", in: project)   // the app's own files stay writable
        try await saveAndLook(project)
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path), "something planted by a confined command ran outside the sandbox")
    }

    /// Nor can the history be swapped for another: moved aside, removed, or started again.
    func testTheHistoryCantBeReplaced() async throws {
        let (project, _) = try project()
        for command in ["mv .git .git-aside", "rm -rf .git", "rm -f .git/HEAD", "mv .git/config .git/config-aside"] {
            let result = try confined(command, in: project)
            XCTAssertNotEqual(result.status, 0, "\(command): \(result.output)")
            XCTAssertTrue(result.output.contains("not permitted"), "\(command): \(result.output)")
        }
        let log = try loose("git log --format=%s", in: project)
        XCTAssertEqual(log.output.trimmingCharacters(in: .whitespacesAndNewlines), "first")
    }

    /// A repository inside the app's folder (a clone, a package checkout) has a `.git` of its own that a
    /// confined command may write. Lamp's git must never run git inside it.
    func testARepositoryInsideTheAppIsNeverEntered() async throws {
        let (project, escaped) = try project()
        let touch = Sandbox.quoted("touch \(Sandbox.quoted(escaped.path)); false")
        let nested = try confined("""
            mkdir -p 'Vendor/odd	name' && cd 'Vendor/odd	name' && git init -q && echo one > file && git add -A \
            && git -c user.name=a -c user.email=a@b -c commit.gpgsign=false commit -qm one && git config core.fsmonitor \(touch) \
            && git config filter.planted.clean \(touch) && echo '* filter=planted' > .gitattributes \
            && \(script(".git/hooks/post-index-change", touching: escaped))
            """, in: project)
        XCTAssertEqual(nested.status, 0, nested.output)   // a repository of its own is the agent's business
        for round in ["two", "three"] {
            try round.write(to: project.dir.appendingPathComponent("Vendor/odd\tname/file"), atomically: true, encoding: .utf8)
            try await saveAndLook(project)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path), "Lamp's git ran something from a repository inside the app")
        let staged = try loose("git ls-files -s", in: project)
        XCTAssertFalse(staged.output.contains("160000 "), staged.output)
        let unsaved = await Versions.hasUnsavedChanges(project)
        XCTAssertFalse(unsaved, "a repository inside the app shouldn't count as unsaved work")
    }

    /// An app whose history was written before it was closed (0.11.0 confined commands and left it open):
    /// hooks and the file-watcher command stay off whatever the history says.
    func testWhatWasAlreadyPlantedStaysOff() async throws {
        let (project, escaped) = try project()
        let touch = Sandbox.quoted("touch \(Sandbox.quoted(escaped.path)); false")
        let planted = try loose("\(script(".git/hooks/post-commit", touching: escaped)) && \(script(".git/hooks/post-index-change", touching: escaped)) && git config core.fsmonitor \(touch)", in: project)
        XCTAssertEqual(planted.status, 0, planted.output)
        try await saveAndLook(project)
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path), "a hook or setting already in the history ran")
    }

    /// What the agent still does with git in the app: look. And a repository of its own, anywhere else.
    func testTheAgentCanStillReadTheHistoryAndCloneBesideIt() async throws {
        let (project, _) = try project()
        try "two".write(to: project.dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        let look = try confined("git status --porcelain && git diff --stat && git log --format=%s && git show --stat --format= HEAD", in: project)
        XCTAssertEqual(look.status, 0, look.output)
        XCTAssertTrue(look.output.contains("M Sources/App.swift") && look.output.contains("first"), look.output)
        let clone = try confined("git clone -q . .lamp/reference/copy && cd .lamp/reference/copy && git log --format=%s", in: project)
        XCTAssertEqual(clone.status, 0, clone.output)
        XCTAssertTrue(clone.output.contains("first"), clone.output)
    }

    /// pi's and Claude Code's file tools aren't inside the profile, so the same rule is theirs too.
    func testTheFileToolsCantWriteTheHistory() throws {
        let (project, _) = try project()
        for path in [".git/config", ".git/hooks/post-commit", ".GIT/config", ".git", "Sources/../.git/config"] {
            for tool in ["write", "edit"] {
                guard case .deny = Privacy.verdict(tool: tool, path: path, project: project) else { return XCTFail("\(tool) \(path) was allowed") }
            }
            guard case .allow = Privacy.verdict(tool: "read", path: path, project: project) else { return XCTFail("read \(path) was refused") }
        }
        for path in ["Sources/App.swift", ".gitignore", ".github/notes.md", ".gitattributes"] {
            guard case .allow = Privacy.verdict(tool: "write", path: path, project: project) else { return XCTFail("write \(path) was refused") }
        }
    }
}
