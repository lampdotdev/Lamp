import XCTest
@testable import Lamp

/// The app's folder is the agent's to write, its history included, and git runs the programs a repository
/// names. Each test has a confined command (wrapped by Lamp, as the agent's are) leave one such thing in
/// the history, then does what Lamp does with git on its own. The planted program makes a file beside the
/// app, where the sandbox doesn't let a command write: wherever it ran, it must not have got there.
final class HistoryEscapeTests: XCTestCase {
    private var roots: [URL] = []
    override func tearDown() {
        unsetenv("GIT_CONFIG_GLOBAL")
        for root in roots { try? FileManager.default.removeItem(at: root) }
    }

    struct App {
        let project: LampProject
        let root: URL
        /// Beside the app: closed to a confined command, open to an unconfined one.
        var escaped: URL { root.appendingPathComponent("escaped") }
        /// Inside the app: what a confined program may do.
        var ranInside: URL { project.dir.appendingPathComponent("ran-inside") }
        var tool: String { project.dir.appendingPathComponent("tool").path }
    }

    /// Under the home folder, like a real app, with a first version and a program the agent could have
    /// written. Git's Mac-wide settings are an empty file, so this Mac's own don't decide the result.
    func app() throws -> App {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-sandbox-test-\(UUID().uuidString)")
        roots.append(root)
        let dir = root.appendingPathComponent("Apps/coinflip", isDirectory: true)
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "one\n".write(to: dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        let settings = fm.temporaryDirectory.appendingPathComponent("lamp-test-git-settings-\(UUID().uuidString)")
        roots.append(settings)
        try "".write(to: settings, atomically: true, encoding: .utf8)
        setenv("GIT_CONFIG_GLOBAL", settings.path, 1)
        let app = App(project: LampProject(id: "coinflip", name: "Coin Flip", exe: "CoinFlip", dir: dir), root: root)
        let made = try loose("git init -q -b main && git add -A && git -c user.name=Lamp -c user.email=lamp@localhost commit -qm first", in: dir)
        XCTAssertEqual(made.status, 0, made.output)
        try "#!/bin/sh\ntouch \(Sandbox.quoted(app.escaped.path))\ntouch \(Sandbox.quoted(app.ranInside.path))\ncat\n"
            .write(toFile: app.tool, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.tool)
        return app
    }

    func loose(_ command: String, in folder: URL) throws -> (status: Int32, output: String) {
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

    /// As the agent's command runs: wrapped by Lamp, under the profile Lamp wrote for this app.
    func confined(_ command: String, in app: App) throws -> (status: Int32, output: String) {
        try loose(try XCTUnwrap(Sandbox.wrap(command, for: app.project)), in: app.project.dir)
    }

    /// Everything Lamp does with git on its own, twice over where git only acts on what is already recorded.
    func everythingLampDoes(_ app: App) async throws {
        let project = app.project
        for content in ["two\n", "three\n"] {
            try content.write(to: project.dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
            _ = await Versions.hasUnsavedChanges(project)
            _ = await Versions.save(project, message: content.trimmingCharacters(in: .newlines))
        }
        let versions = await Versions.list(project)
        if let newest = versions.first { await Versions.name(project, newest.id, "Before the redesign") }
        if let oldest = versions.last { _ = await Versions.restoreFiles(project, to: oldest) }
        _ = await Versions.save(project, message: "back to the first")
        _ = await Versions.hasUnsavedChanges(project)
    }

    private func plantAndCheck(_ what: String, _ plant: (App) -> String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let app = try app()
        let planted = try confined(plant(app), in: app)
        XCTAssertEqual(planted.status, 0, "\(what): the agent's command should work: \(planted.output)", file: file, line: line)
        try await everythingLampDoes(app)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.escaped.path), "\(what): the planted program reached outside the app", file: file, line: line)
    }

    private let everyFile = "printf '* filter=planted\\n' > .gitattributes"

    func testAHook() async throws {
        try await plantAndCheck("a hook") { _ in "cp tool .git/hooks/post-commit && cp tool .git/hooks/pre-commit && cp tool .git/hooks/post-index-change" }
    }

    func testAHookNamedInSettings() async throws {
        try await plantAndCheck("a hook named in settings") { "git config hook.planted.command \(Sandbox.quoted($0.tool)) && git config hook.planted.event post-commit" }
    }

    func testTheFileWatcherCommand() async throws {
        try await plantAndCheck("the file-watcher command") { "git config core.fsmonitor \(Sandbox.quoted($0.tool))" }
    }

    func testAFilterForFilesGoingIn() async throws {
        try await plantAndCheck("a filter (in)") { "git config filter.planted.clean \(Sandbox.quoted($0.tool)) && \(self.everyFile)" }
    }

    func testAFilterForFilesComingOut() async throws {
        try await plantAndCheck("a filter (out)") { "git config filter.planted.smudge \(Sandbox.quoted($0.tool)) && \(self.everyFile)" }
    }

    func testALongRunningFilter() async throws {
        try await plantAndCheck("a long-running filter") { "git config filter.planted.process \(Sandbox.quoted($0.tool)) && \(self.everyFile)" }
    }

    func testASigningProgram() async throws {
        try await plantAndCheck("a signing program") { "git config commit.gpgsign true && git config tag.gpgsign true && git config gpg.program \(Sandbox.quoted($0.tool))" }
    }

    func testSettingsBroughtInFromAnotherFile() async throws {
        try await plantAndCheck("an include") {
            "printf '[filter \"planted\"]\\n\\tclean = %s\\n' \(Sandbox.quoted($0.tool)) > more-settings && git config include.path ../more-settings && \(self.everyFile)"
        }
    }

    func testARepositoryInsideTheApp() async throws {
        try await plantAndCheck("a repository inside the app") {
            let tool = Sandbox.quoted($0.tool)
            return "mkdir -p Vendor/kit && cd Vendor/kit && git init -q && echo x > file && git add -A && git -c user.name=a -c user.email=a@b commit -qm one && git config core.fsmonitor \(tool) && git config filter.planted.clean \(tool) && \(self.everyFile) && cp ../../tool .git/hooks/post-index-change"
        }
    }

    func testAHistoryThatPointsElsewhere() async throws {
        try await plantAndCheck("a history that points elsewhere") {
            "mv .git .history && echo 'gitdir: .history' > .git && git config filter.planted.clean \(Sandbox.quoted($0.tool)) && cp tool .history/hooks/post-commit && \(self.everyFile)"
        }
    }

    /// Not a program: the history says its files live in another folder, and Lamp's restore, with the
    /// clean-up after it, would empty that one.
    func testAHistoryThatSaysItsFilesAreElsewhere() async throws {
        let app = try app()
        let other = app.root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try "keep".write(to: other.appendingPathComponent("letter.txt"), atomically: true, encoding: .utf8)
        let planted = try confined("git config core.worktree \(Sandbox.quoted(other.path))", in: app)
        XCTAssertEqual(planted.status, 0, planted.output)
        try await everythingLampDoes(app)
        XCTAssertEqual(try? String(contentsOf: other.appendingPathComponent("letter.txt"), encoding: .utf8), "keep", "Lamp's restore emptied another folder")
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.appendingPathComponent("Sources/App.swift").path), "Lamp's restore wrote into another folder")
    }
}
