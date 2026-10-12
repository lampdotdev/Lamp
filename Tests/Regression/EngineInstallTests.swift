import XCTest
@testable import Lamp

/// The Claude Code and Codex Lamp runs: the person's own when the Mac has one, else Lamp's, with which
/// version is in use, what's kept, and what's refused.
final class EngineInstallTests: XCTestCase {
    private var saved: URL!
    private var savedFinder: ((Engine) -> String?)!
    private var root: URL!

    override func setUp() {
        saved = EngineInstall.folder
        savedFinder = EngineInstall.personsCopy
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-engines-\(UUID().uuidString)")
        EngineInstall.folder = root
        EngineInstall.personsCopy = { _ in nil }   // whatever the Mac running the tests has
    }

    override func tearDown() {
        EngineInstall.folder = saved
        EngineInstall.personsCopy = savedFinder
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

    /// The person's own copy wins over Lamp's, and runs as it does for them: their folder, nothing set.
    /// Lamp's copy stays where it is, for when theirs goes.
    func testThePersonsOwnCopyIsUsedAsItIs() throws {
        let own = try put(.claude, "2.1.287")
        try write("2.1.287", current: .claude)
        let theirs = root.appendingPathComponent("person/.local/bin/claude").path
        EngineInstall.personsCopy = { $0 == .claude ? theirs : nil }
        XCTAssertEqual(EngineInstall.path(for: .claude), theirs)
        XCTAssertTrue(EngineInstall.usesPersonsCopy(.claude))
        XCTAssertEqual(EngineInstall.environment(for: .claude), [:])
        XCTAssertEqual(EngineInstall.configFolder(.claude).lastPathComponent, ".claude")
        XCTAssertEqual(EngineInstall.ownPath(for: .claude), own.path)
        // Codex has no copy of the person's here, so it's Lamp's (none yet), with its own folder.
        XCTAssertNil(EngineInstall.path(for: .codex))
        XCTAssertFalse(EngineInstall.usesPersonsCopy(.codex))
        XCTAssertEqual(EngineInstall.environment(for: .codex)["CODEX_HOME"], root.appendingPathComponent("codex/home").path)
        XCTAssertFalse(EngineInstall.usesPersonsCopy(.pi))
        XCTAssertNil(EngineInstall.path(for: .pi))
    }

    /// A conversation Lamp's copy kept is brought to the person's folder once Lamp runs their copy.
    func testConversationsGoToThePersonsCopy() throws {
        let fm = FileManager.default
        let home = root.appendingPathComponent("person")
        let id = "0f3c2a9e-5b1d-4c7a-9e2f-123456789abc"
        let claude = EngineInstall.ownConfigFolder(.claude).appendingPathComponent("projects/-Users-someone-Coin-Flip")
        try fm.createDirectory(at: claude, withIntermediateDirectories: true)
        try "{}".write(to: claude.appendingPathComponent("\(id).jsonl"), atomically: true, encoding: .utf8)
        let codex = EngineInstall.ownConfigFolder(.codex).appendingPathComponent("sessions/2026/10/01")
        try fm.createDirectory(at: codex, withIntermediateDirectories: true)
        try "{}".write(to: codex.appendingPathComponent("rollout-2026-10-01T11-08-27-\(id).jsonl"), atomically: true, encoding: .utf8)
        EngineInstall.personsCopy = { _ in "/usr/local/bin/somewhere" }

        XCTAssertTrue(EngineInstall.carryOver(session: id, for: .claude, from: home))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(".claude/projects/-Users-someone-Coin-Flip/\(id).jsonl").path))
        XCTAssertTrue(EngineInstall.carryOver(session: id, for: .codex, from: home))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(".codex/sessions/2026/10/01/rollout-2026-10-01T11-08-27-\(id).jsonl").path))
        // Lamp's copy's folder was only read.
        XCTAssertTrue(fm.fileExists(atPath: claude.appendingPathComponent("\(id).jsonl").path))
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

    /// An app's conversation kept by the person's copy is brought over once Lamp runs its own, with what Claude
    /// Code keeps beside it, and then found where it is; one that's nowhere can't be resumed.
    func testConversationsFromBeforeAreBroughtOver() throws {
        let fm = FileManager.default
        let home = root.appendingPathComponent("person")
        let id = "0f3c2a9e-5b1d-4c7a-9e2f-123456789abc"
        let claude = home.appendingPathComponent(".claude/projects/-Users-someone-Coin-Flip")
        try fm.createDirectory(at: claude.appendingPathComponent("\(id)/tool-results"), withIntermediateDirectories: true)
        try "{}".write(to: claude.appendingPathComponent("\(id).jsonl"), atomically: true, encoding: .utf8)
        try "out".write(to: claude.appendingPathComponent("\(id)/tool-results/toolu_01.txt"), atomically: true, encoding: .utf8)
        let codex = home.appendingPathComponent(".codex/sessions/2026/10/01")
        try fm.createDirectory(at: codex, withIntermediateDirectories: true)
        try "{}".write(to: codex.appendingPathComponent("rollout-2026-10-01T11-08-27-\(id).jsonl"), atomically: true, encoding: .utf8)

        XCTAssertTrue(EngineInstall.carryOver(session: id, for: .claude, from: home))
        let mine = EngineInstall.configFolder(.claude).appendingPathComponent("projects/-Users-someone-Coin-Flip")
        XCTAssertTrue(fm.fileExists(atPath: mine.appendingPathComponent("\(id).jsonl").path))
        XCTAssertTrue(fm.fileExists(atPath: mine.appendingPathComponent("\(id)/tool-results/toolu_01.txt").path))
        XCTAssertTrue(EngineInstall.carryOver(session: id, for: .codex, from: home))
        XCTAssertTrue(fm.fileExists(atPath: EngineInstall.configFolder(.codex)
            .appendingPathComponent("sessions/2026/10/01/rollout-2026-10-01T11-08-27-\(id).jsonl").path))

        // Found in Lamp's copy's folder now, even with the person's gone.
        try fm.removeItem(at: home)
        XCTAssertTrue(EngineInstall.carryOver(session: id, for: .claude, from: home))
        XCTAssertTrue(EngineInstall.carryOver(session: id, for: .codex, from: home))
        // Nowhere, or not a conversation's id.
        XCTAssertFalse(EngineInstall.carryOver(session: "11111111-1111-1111-1111-111111111111", for: .claude, from: home))
        XCTAssertFalse(EngineInstall.carryOver(session: "11111111-1111-1111-1111-111111111111", for: .codex, from: home))
        XCTAssertFalse(EngineInstall.carryOver(session: "../\(id)", for: .claude, from: home))
        XCTAssertFalse(EngineInstall.carryOver(session: "", for: .codex, from: home))
    }

    /// A sign-in waiting for the browser ends when cancelled, says it was cancelled rather than failed, and
    /// leaves nothing running.
    func testASignInCanBeCancelled() async throws {
        let program = try put(.claude, "2.1.287")
        try """
        #!/bin/sh
        if [ "$1 $2" = "auth login" ]; then sleep 30; exit 0; fi
        echo '{"loggedIn": false}'
        """.write(to: program, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        try write("2.1.287", current: .claude)
        let started = Date()
        let signIn = Task { await EngineSignIn.signIn(.claude) }
        try await Task.sleep(for: .seconds(1))
        EngineSignIn.cancelSignIn(.claude)
        let result = await signIn.value
        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        // Cancelling when nothing is under way does nothing, and the next sign-in isn't cancelled by it.
        EngineSignIn.cancelSignIn(.claude)
        try """
        #!/bin/sh
        if [ "$1 $2" = "auth login" ]; then exit 0; fi
        echo '{"loggedIn": true}'
        """.write(to: program, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        let again = await EngineSignIn.signIn(.claude)
        XCTAssertEqual(again, true)
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
