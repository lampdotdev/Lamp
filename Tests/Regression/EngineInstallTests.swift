import XCTest
@testable import Lamp

/// Lamp's own Claude Code and Codex: which version is in use, what's kept, and what's refused.
final class EngineInstallTests: XCTestCase {
    private var saved: URL!
    private var root: URL!

    override func setUp() {
        saved = EngineInstall.folder
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-engines-\(UUID().uuidString)")
        EngineInstall.folder = root
    }

    override func tearDown() {
        EngineInstall.folder = saved
        try? FileManager.default.removeItem(at: root)
    }

    func testVersions() {
        XCTAssertTrue(EngineInstall.isVersion("2.1.287"))
        XCTAssertTrue(EngineInstall.isVersion("0.162.1"))
        for bad in ["", "latest", "2", "../2.1", "2.1.287/../../x", "2.1.287\n", "v2.1.0"] {
            XCTAssertFalse(EngineInstall.isVersion(bad), bad)
        }
        XCTAssertTrue(EngineInstall.isOlder("2.1.9", than: "2.1.10"))
        XCTAssertFalse(EngineInstall.isOlder("2.1.10", than: "2.1.9"))
        XCTAssertFalse(EngineInstall.isOlder("0.162.1", than: "0.162.1"))
    }

    /// Nothing until a version is in use, and then that version's program; a `current` naming anything
    /// but a version is no version.
    func testThePathIsTheCurrentVersionsProgram() throws {
        XCTAssertNil(EngineInstall.path(for: .codex))
        let program = try put(.codex, "0.162.1")
        XCTAssertNil(EngineInstall.path(for: .codex))
        try write("0.162.1", current: .codex)
        XCTAssertEqual(EngineInstall.path(for: .codex), program.path)
        try write("../../elsewhere", current: .claude)
        XCTAssertNil(EngineInstall.path(for: .claude))
        XCTAssertNil(EngineInstall.path(for: .pi))
    }

    /// The version in use and the one before it stay (a turn may still be running on it); the rest go.
    func testPruneKeepsTheCurrentAndThePrevious() throws {
        for version in ["2.1.280", "2.1.285", "2.1.287", "2.1.290"] { _ = try put(.claude, version) }
        EngineInstall.prune(.claude, keeping: "2.1.290")
        let left = try FileManager.default.contentsOfDirectory(atPath: EngineInstall.versionsFolder(.claude).path).sorted()
        XCTAssertEqual(left, ["2.1.287", "2.1.290"])
        // Going back (the brake): the one kept beside it is the newest other.
        EngineInstall.prune(.claude, keeping: "2.1.287")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: EngineInstall.versionsFolder(.claude).path).sorted(),
                       ["2.1.287", "2.1.290"])
    }

    /// Each engine gets its own folder for its sign-in, made before it's named, and Claude Code's updater off.
    func testEachEngineHasItsOwnFolder() {
        let claude = EngineInstall.environment(for: .claude)
        XCTAssertEqual(claude["CLAUDE_CONFIG_DIR"], root.appendingPathComponent("claude/home").path)
        XCTAssertEqual(claude["DISABLE_AUTOUPDATER"], "1")
        let codex = EngineInstall.environment(for: .codex)
        XCTAssertEqual(codex["CODEX_HOME"], root.appendingPathComponent("codex/home").path)
        var isFolder: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: codex["CODEX_HOME"]!, isDirectory: &isFolder) && isFolder.boolValue)
        XCTAssertEqual(EngineInstall.environment(for: .pi), [:])
    }

    /// Only a Developer ID signature of the vendor's team passes: not Apple's own, not an unsigned file.
    func testSignaturesOfAnyoneElseAreRefused() throws {
        XCTAssertFalse(EngineInstall.isSigned(URL(fileURLWithPath: "/bin/ls"), by: EngineInstall.team(.claude)))
        let unsigned = root.appendingPathComponent("unsigned")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "#!/bin/sh\necho 2.1.287\n".write(to: unsigned, atomically: true, encoding: .utf8)
        XCTAssertFalse(EngineInstall.isSigned(unsigned, by: EngineInstall.team(.claude)))
    }

    /// A download that doesn't hash to what the vendor published never reaches the versions folder.
    func testAMismatchedDownloadIsRefused() async throws {
        let file = root.appendingPathComponent("served")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "not claude".write(to: file, atomically: true, encoding: .utf8)
        let release = EngineInstall.Release(version: "2.1.287", url: file, sha256: String(repeating: "0", count: 64), size: nil, isArchive: false)
        do {
            try await EngineInstall.install(release, for: .claude) { _ in }
            XCTFail("installed a file that didn't match its checksum")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("didn't match"), error.localizedDescription)
        }
        XCTAssertNil(EngineInstall.path(for: .claude))
        XCTAssertFalse(FileManager.default.fileExists(atPath: EngineInstall.versionsFolder(.claude).appendingPathComponent("2.1.287").path))
    }

    /// Against the real download sites: set LAMP_LIVE_ENGINES=1. Downloads both engines (about 230 MB
    /// for Claude Code and 130 MB for Codex) into the test's own folder and runs each.
    func testLiveInstall() async throws {
        guard ProcessInfo.processInfo.environment["LAMP_LIVE_ENGINES"] == "1" else { throw XCTSkip("LAMP_LIVE_ENGINES isn't set") }
        for engine in [Engine.claude, .codex] {
            let release = try await EngineInstall.target(engine)
            try await EngineInstall.install(release, for: engine) { _ in }
            let path = try XCTUnwrap(EngineInstall.path(for: engine))
            XCTAssertEqual(EngineInstall.currentVersion(engine), release.version)
            let result = await Subprocess.run(path, ["--version"], env: EngineInstall.environment(for: engine), timeout: 60)
            XCTAssertTrue(result.output.contains(release.version), result.output)
            // Installed again: it's already here, and nothing is downloaded.
            try await EngineInstall.install(release, for: engine) { _ in XCTFail("downloaded again") }
        }
    }

    private func put(_ engine: Engine, _ version: String) throws -> URL {
        let program = EngineInstall.versionsFolder(engine).appendingPathComponent(version)
            .appendingPathComponent(engine == .codex ? "bin/codex" : "claude")
        try FileManager.default.createDirectory(at: program.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: program.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        return program
    }

    private func write(_ version: String, current engine: Engine) throws {
        try FileManager.default.createDirectory(at: EngineInstall.root(engine), withIntermediateDirectories: true)
        try Data(version.utf8).write(to: EngineInstall.root(engine).appendingPathComponent("current"))
        EngineInstall.folder = root   // forgets what was read before
    }
}
