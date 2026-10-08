import XCTest
@testable import Lamp

/// When Lamp won't run git on an app's history it says so (Store puts a line in the app's chat), rather
/// than save nothing in silence. These check that each reason is reported, and an ordinary history never is.
@MainActor
final class HistoryRefusalTests: XCTestCase {
    private var roots: [URL] = []
    private var reported: [Versions.Refusal] = []

    override func setUp() async throws {
        reported = []
        Versions.refused = { [weak self] _, refusal in self?.reported.append(refusal) }
    }

    override func tearDown() async throws {
        Versions.refused = nil
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

    private func project(_ setup: String) throws -> LampProject {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-sandbox-test-\(UUID().uuidString)")
        roots.append(root)
        let dir = root.appendingPathComponent("Apps/coinflip", isDirectory: true)
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "one\n".write(to: dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("global-settings"), atomically: true, encoding: .utf8)
        setenv("GIT_CONFIG_GLOBAL", root.appendingPathComponent("global-settings").path, 1)
        let made = try run("git init -q && git add -A && git -c user.name=Lamp -c user.email=lamp@localhost commit -qm first && \(setup)", in: dir)
        XCTAssertEqual(made.status, 0, made.output)
        return LampProject(id: "coinflip", name: "Coin Flip", exe: "CoinFlip", dir: dir)
    }

    private func saveAfterAChange(_ project: LampProject) async throws -> Bool {
        try "two\n".write(to: project.dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        return await Versions.save(project, message: "two")
    }

    func testAnOrdinaryHistoryIsNeverReported() async throws {
        let project = try project("git remote add origin https://example.com/me/coinflip.git && git config alias.st status")
        let saved = try await saveAfterAChange(project)
        XCTAssertTrue(saved)
        _ = await Versions.hasUnsavedChanges(project)
        _ = await Versions.list(project)
        XCTAssertEqual(reported, [])
    }

    func testAHistoryThatPointsElsewhereIsReported() async throws {
        let project = try project("mv .git .history && echo 'gitdir: .history' > .git")
        let saved = try await saveAfterAChange(project)
        XCTAssertFalse(saved)
        XCTAssertEqual(reported, [.shape])
    }

    func testAHistoryKeptInAWayLampCantUseIsReported() async throws {
        for setup in ["git config extensions.partialclone origin", "git config filter.lfs.clean 'git-lfs clean -- %f'", "echo '[broken' >> .git/config"] {
            reported = []
            let project = try project(setup)
            let saved = try await saveAfterAChange(project)
            XCTAssertFalse(saved, setup)
            XCTAssertEqual(reported, [.format], setup)
        }
    }

    /// Settings Lamp has to remove and can't (the file is locked): it used to stop saving without a word.
    func testSettingsThatCantBeChangedAreReported() async throws {
        let project = try project("git config alias.st status && chflags uchg .git/config")
        let saved = try await saveAfterAChange(project)
        XCTAssertFalse(saved)
        XCTAssertEqual(reported, [.locked])
        // A settings file that is only marked read-only can still be replaced, and saving goes on.
        reported = []
        let readOnly = try self.project("git config alias.st status && chmod 444 .git/config")
        let savedReadOnly = try await saveAfterAChange(readOnly)
        XCTAssertTrue(savedReadOnly)
        XCTAssertEqual(reported, [])
    }
}
