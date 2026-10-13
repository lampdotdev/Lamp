import XCTest
@testable import Lamp

/// Saving a version while Lamp reads the same app's state: the read must not make the save fail, a save that
/// is briefly shut out gets through, and one that can't says so instead of passing for "nothing changed".
@MainActor final class SaveBesideAReadTests: XCTestCase {
    private var project: LampProject!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        for file in 0..<8 {
            try String(repeating: "let value\(file) = 1\n", count: 2000)
                .write(to: dir.appendingPathComponent("Sources/File\(file).swift"), atomically: true, encoding: .utf8)
        }
        project = LampProject(id: dir.lastPathComponent, name: "Saves", exe: "Saves", dir: dir)
        let made = await Versions.git("git init -q && git add -A && \(Versions.commit) -qm Scaffold", cwd: dir)
        XCTAssertEqual(made, 0)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: project.dir)
    }

    private func change(_ round: Int) throws {
        try "let added\(round) = \(round)\n".write(to: project.dir.appendingPathComponent("Sources/New\(round).swift"), atomically: true, encoding: .utf8)
        try "// \(round)\n".write(to: project.dir.appendingPathComponent("Sources/File\(round % 8).swift"), atomically: true, encoding: .utf8)
    }

    /// The look for unsaved changes, made as a chat line arrives, at the same moment as the turn's save.
    func testAReadNeverShutsOutTheSave() async throws {
        var failed = 0
        for round in 0..<120 {
            try change(round)
            let read = Task { _ = await Versions.hasUnsavedChanges(project) }
            let status = await Versions.git("git add -A && \(Versions.commit) -qm \"$LAMP_PROMPT\"", cwd: project.dir,
                                            env: ["LAMP_PROMPT": "request \(round)"])
            await read.value
            if status != 0 {
                failed += 1
                _ = await Versions.git("git add -A && \(Versions.commit) -qm later", cwd: project.dir)
            }
        }
        XCTAssertEqual(failed, 0, "saves that failed beside a read, of 120")
    }

    /// Something else at work in the folder holds the index for a moment: the save waits and gets through.
    func testASaveShutOutForAMomentGetsThrough() async throws {
        try change(0)
        let lock = project.dir.appendingPathComponent(".git/index.lock")
        try Data().write(to: lock)
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            try? FileManager.default.removeItem(at: lock)
        }
        let saved = await Versions.commitAll("-qm held", in: project.dir)
        XCTAssertEqual(saved, .saved)
    }

    /// Shut out for good, it says it failed: the change is there and has no version.
    func testASaveThatCannotGetThroughSaysSo() async throws {
        try change(0)
        try Data().write(to: project.dir.appendingPathComponent(".git/index.lock"))
        let saved = await Versions.commitAll("-qm held", in: project.dir)
        XCTAssertEqual(saved, .failed)
    }

    /// The agent changed nothing: that isn't a failure, and isn't tried again.
    func testNothingChangedIsNotAFailure() async throws {
        let saved = await Versions.commitAll("-qm empty", in: project.dir)
        XCTAssertEqual(saved, .nothingToSave)
    }
}
