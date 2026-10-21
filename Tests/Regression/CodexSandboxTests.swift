import XCTest
@testable import Lamp

/// Codex's own sandbox, with the profile Lamp hands it (`Sandbox.codexPermissions`): run through `codex sandbox`,
/// which applies a profile the way Codex does for the agent's commands. Skipped where Codex isn't installed.
final class CodexSandboxTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private var codex: String? {
        let given = ProcessInfo.processInfo.environment["LAMP_TEST_CODEX"]
        return [given, "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
                "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "/opt/homebrew/bin/codex"]
            .compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Under the home folder, like a real app, so closing the home folder is what's tested.
    private func project() throws -> (LampProject, URL) {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-codex-sandbox-test-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("Apps/coinflip")
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "inside".write(to: dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        try "secret".write(to: root.appendingPathComponent("outside.txt"), atomically: true, encoding: .utf8)
        return (LampProject(id: "coinflip", name: "Coin Flip", exe: "CoinFlip", dir: dir), root)
    }

    private func run(_ command: String, in project: LampProject, codex: String) throws -> (status: Int32, output: String) {
        XCTAssertTrue(Sandbox.prepareShims())
        let line = "/usr/bin/env \(Sandbox.shimEnvironment) \(Sandbox.quoted(codex)) sandbox -c "
            + Sandbox.quoted(Sandbox.codexPermissions(for: project)) + " -c 'default_permissions=\"lamp\"' -- /bin/zsh -lc "
            + Sandbox.quoted(command)
        return TestShell.run("/bin/bash", ["-c", line], in: project.dir)
    }

    func testTheAppIsOpenAndTheRestOfTheHomeFolderIsClosed() throws {
        guard let codex else { throw XCTSkip("Codex isn't installed here") }
        let (project, root) = try project()
        let inside = try run("cat Sources/App.swift && echo more >> Sources/App.swift && wc -l < Sources/App.swift", in: project, codex: codex)
        XCTAssertEqual(inside.status, 0, inside.output)
        XCTAssertTrue(inside.output.contains("inside"), inside.output)
        let outside = try run("cat \(Sandbox.quoted(root.appendingPathComponent("outside.txt").path))", in: project, codex: codex)
        XCTAssertNotEqual(outside.status, 0)
        XCTAssertTrue(outside.output.contains("not permitted"), outside.output)
        XCTAssertFalse(outside.output.contains("secret"), outside.output)
        let documents = try run("ls ~/Documents", in: project, codex: codex)
        XCTAssertTrue(documents.output.contains("not permitted"), documents.output)
        let lamp = try run("ls \(Sandbox.quoted(Edition.supportFolder.path))", in: project, codex: codex)
        XCTAssertTrue(lamp.output.contains("not permitted"), lamp.output)
        let written = try run("echo x > \(Sandbox.quoted(root.appendingPathComponent("left.txt").path))", in: project, codex: codex)
        XCTAssertNotEqual(written.status, 0, written.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("left.txt").path))
    }

    /// A link inside the app's folder doesn't lead out of it.
    func testALinkInsideTheAppDoesNotLeadOut() throws {
        guard let codex else { throw XCTSkip("Codex isn't installed here") }
        let (project, root) = try project()
        try FileManager.default.createSymbolicLink(at: project.dir.appendingPathComponent("away"), withDestinationURL: root)
        let through = try run("cat away/outside.txt", in: project, codex: codex)
        XCTAssertNotEqual(through.status, 0)
        XCTAssertFalse(through.output.contains("secret"), through.output)
    }

    /// An app's folder swapped for a link leads nowhere: a command could do it between Lamp's look at the folder and
    /// Codex's start, and Codex would otherwise take where it leads for the app.
    func testAnAppFolderSwappedForALinkOpensNothing() throws {
        guard let codex else { throw XCTSkip("Codex isn't installed here") }
        let (project, root) = try project()
        let elsewhere = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: project.dir)
        try FileManager.default.createSymbolicLink(at: project.dir, withDestinationURL: elsewhere)
        let written = try run("echo x > left.txt", in: project, codex: codex)
        XCTAssertNotEqual(written.status, 0, written.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent("left.txt").path), written.output)
    }

    /// Lamp's `swift` is first on a login shell's path, as Codex starts its commands, and temporary folders open.
    func testLampsSwiftComesFirstAndTemporaryFoldersAreOpen() throws {
        guard let codex else { throw XCTSkip("Codex isn't installed here") }
        let (project, _) = try project()
        let found = try run("command -v swift; echo t > \"$TMPDIR/lamp-codex-test-$$\" && rm \"$TMPDIR/lamp-codex-test-$$\" && echo tmp-ok", in: project, codex: codex)
        XCTAssertTrue(found.output.contains(Sandbox.bin.appendingPathComponent("swift").path), found.output)
        XCTAssertTrue(found.output.contains("tmp-ok"), found.output)
    }
}
