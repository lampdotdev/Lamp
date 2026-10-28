import XCTest
@testable import Lamp

/// The latest of a wish is merged into it by git, under Lamp's sandbox: what changed on one side only goes in with no
/// agent, and what both sides changed in the same place is left marked for the agent, each side readable from the ref.
final class UpstreamMergeTests: XCTestCase {
    private let escape = HistoryEscapeTests()
    override func setUp() { expectNoSharingFoldersLeft() }
    override func tearDown() { escape.tearDown() }

    /// A shared tree holding one app with this code, opened as the import opens one.
    private func package(code: String) throws -> Sharing.Package {
        let folder = Sharing.workFolder.appendingPathComponent("upstream-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try code.write(to: folder.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        try #"{"format": 2, "name": "Coin Flip", "exportedAt": "2026-01-01T00:00:00Z", "description": "Flips a coin"}"#
            .write(to: folder.appendingPathComponent("lamp-app.json"), atomically: true, encoding: .utf8)
        return try Sharing.open(unpacked: folder)
    }

    func testGitMergesEachSidesChangesAndMarksOnlyWhatBothChanged() async throws {
        let app = try escape.app()
        let file = app.project.dir.appendingPathComponent("Sources/App.swift")
        func code() -> String { (try? String(contentsOf: file, encoding: .utf8)) ?? "(missing)" }
        try "a\nb\nc\n".write(to: file, atomically: true, encoding: .utf8)
        let arrived = await Versions.save(app.project, message: "Imported from a shared file")
        XCTAssertTrue(arrived)
        let arrival = await Versions.head(app.project)
        try "A\nb\nc\n".write(to: file, atomically: true, encoding: .utf8)
        let changed = await Versions.save(app.project, message: "Call it A")
        XCTAssertTrue(changed)

        // Upstream changed the last line, this wish the first: both in, nothing to settle.
        let theirs = try package(code: "a\nb\nC\n")
        defer { try? FileManager.default.removeItem(at: theirs.folder) }
        let merged = try await Upstream.merge(theirs, into: app.project, from: nil, base: nil, arrival: arrival)
        XCTAssertEqual(merged.conflicts, [])
        XCTAssertEqual(code(), "A\nb\nC\n")
        XCTAssertEqual(AppDescription.description(of: app.project), "Flips a coin", "the description comes with the code when none was written here")
        let saved = await Versions.save(app.project, message: "Merged the latest from GitHub")
        XCTAssertTrue(saved)

        // Both changed the first line: that file is marked, with each side kept where the agent can read it.
        let again = try package(code: "X\nb\nC\n")
        defer { try? FileManager.default.removeItem(at: again.folder) }
        let conflicted = try await Upstream.merge(again, into: app.project, from: nil, base: nil, arrival: arrival)
        XCTAssertEqual(conflicted.conflicts, ["Sources/App.swift"])
        XCTAssertEqual(code(), "<<<<<<< HEAD\nA\n=======\nX\n>>>>>>> \(Upstream.ref)\nb\nC\n")
        let upstream = try escape.loose("git show \(Upstream.ref):Sources/App.swift", in: app.project.dir)
        XCTAssertEqual(upstream.output, "X\nb\nC\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.project.dir.appendingPathComponent(".lamp/merge").path), "the merge's own indexes are cleared")
    }
}
