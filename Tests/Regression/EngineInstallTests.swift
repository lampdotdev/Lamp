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
        savedFinder = EngineInstall.finder
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-engines-\(UUID().uuidString)")
        EngineInstall.folder = root
        EngineInstall.finder = { _ in nil }   // whatever the Mac running the tests has
        EngineInstall.lookNow()
    }

    override func tearDown() {
        EngineInstall.folder = saved
        EngineInstall.finder = savedFinder
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
        let theirs = root.appendingPathComponent("person/.local/bin/claude")
        try fm.createDirectory(at: theirs.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: theirs.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        EngineInstall.finder = { _ in theirs.path }
        EngineInstall.lookNow()

        XCTAssertTrue(EngineInstall.carryOver(session: id, for: .claude, from: home))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(".claude/projects/-Users-someone-Coin-Flip/\(id).jsonl").path))
        XCTAssertTrue(EngineInstall.carryOver(session: id, for: .codex, from: home))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(".codex/sessions/2026/10/01/rollout-2026-10-01T11-08-27-\(id).jsonl").path))
        // Lamp's copy's folder was only read.
        XCTAssertTrue(fm.fileExists(atPath: claude.appendingPathComponent("\(id).jsonl").path))
    }

    /// Going back to a copy that ran the conversation before: the turns the other copy added since come
    /// along, rather than the conversation resuming from where it was left there.
    func testGoingBackBringsTheLatestTurns() throws {
        let fm = FileManager.default
        let home = root.appendingPathComponent("person")
        let id = "0f3c2a9e-5b1d-4c7a-9e2f-123456789abc"
        let older = Date().addingTimeInterval(-3600)
        func put(_ text: String, at url: URL, modified: Date) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        // Lamp's copy has the start of each conversation; the person's copy went on with both since.
        let ownClaude = EngineInstall.ownConfigFolder(.claude).appendingPathComponent("projects/-App/\(id).jsonl")
        try put("first", at: ownClaude, modified: older)
        try put("old output", at: ownClaude.deletingLastPathComponent().appendingPathComponent("\(id)/tool-results/a.txt"), modified: older)
        try put("first\nsecond", at: home.appendingPathComponent(".claude/projects/-App/\(id).jsonl"), modified: Date())
        let ownCodex = EngineInstall.ownConfigFolder(.codex).appendingPathComponent("sessions/2026/10/01/rollout-x-\(id).jsonl")
        try put("first", at: ownCodex, modified: older)
        try put("first\nsecond", at: home.appendingPathComponent(".codex/sessions/2026/10/01/rollout-x-\(id).jsonl"), modified: Date())

        // The person's copy went: Lamp's runs again, and gets every turn.
        XCTAssertFalse(EngineInstall.usesPersonsCopy(.claude))
        XCTAssertTrue(EngineInstall.carryOver(session: id, for: .claude, from: home))
        XCTAssertEqual(try String(contentsOf: ownClaude, encoding: .utf8), "first\nsecond")
        XCTAssertFalse(fm.fileExists(atPath: ownClaude.deletingLastPathComponent().appendingPathComponent(id).path))
        XCTAssertTrue(EngineInstall.carryOver(session: id, for: .codex, from: home))
        XCTAssertEqual(try String(contentsOf: ownCodex, encoding: .utf8), "first\nsecond")

        // Once it's current, nothing is copied again; a later turn here stays.
        try put("first\nsecond\nthird", at: ownClaude, modified: Date().addingTimeInterval(60))
        XCTAssertTrue(EngineInstall.carryOver(session: id, for: .claude, from: home))
        XCTAssertEqual(try String(contentsOf: ownClaude, encoding: .utf8), "first\nsecond\nthird")
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
