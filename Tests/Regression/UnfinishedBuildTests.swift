import XCTest
@testable import Lamp

/// What Lamp knows of an open app (the sources it runs) outlives a relaunch, unless a whole build was still going
/// when Lamp quit (`LiveReload.recoverUnfinishedBuild`). The marker of such a build and what build.sh leaves in the
/// live folder must not be taken for each other: when they were, every launch dropped what the open app runs, and
/// the next change waited for Reload.
@MainActor
final class UnfinishedBuildTests: XCTestCase {
    private var root: URL?

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func app() throws -> LampProject {
        let fm = FileManager.default
        // Under the home folder, where the app's sandbox (which the build runs in) opens an app's folder.
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-unfinished-test-\(UUID().uuidString)")
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return try Template.scaffold(name: "Unfinished", in: root)
    }

    private func knowsWhatItRuns(_ project: LampProject) -> Bool {
        FileManager.default.fileExists(atPath: LiveReload.running(project).path)
    }

    /// A real live build, then a relaunch: what the installed app runs is still known. Only a build that was going
    /// when Lamp quit drops it. Runs a whole build, a minute or so.
    func testAFinishedLiveBuildIsNotTakenForAnUnfinishedOne() async throws {
        let project = try app()
        var output: [String] = []
        let status = await Store.runBuild("./build.sh", for: project, env: ["LAMP_LIVE": "1"]) { output.append($0) }
        XCTAssertEqual(status, 0, output.joined(separator: "\n"))
        LiveReload.markRunning(project, from: LiveReload.built(project))
        XCTAssertTrue(knowsWhatItRuns(project))

        LiveReload.recoverUnfinishedBuild(project)
        XCTAssertTrue(knowsWhatItRuns(project), "a finished build was taken for one Lamp quit during")

        LiveReload.startedBuilding(project)
        LiveReload.recoverUnfinishedBuild(project)
        XCTAssertFalse(knowsWhatItRuns(project), "a build Lamp quit during went unnoticed")
    }

    /// An app last built by an earlier build.sh has its copy of the compiled sources where the marker goes. It is
    /// cleared at launch without dropping what the app runs, and a build started later is still caught.
    func testTheCopyAnEarlierBuildLeftIsClearedForTheMarker() throws {
        let project = try app()
        let leftover = LiveReload.folder(project).appendingPathComponent("building")
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try "struct A {}".write(to: leftover.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        LiveReload.markRunning(project, from: project.dir.appendingPathComponent("Sources"))

        LiveReload.recoverUnfinishedBuild(project)
        XCTAssertTrue(knowsWhatItRuns(project), "the earlier build's copy was taken for an unfinished build")
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))

        LiveReload.startedBuilding(project)
        LiveReload.recoverUnfinishedBuild(project)
        XCTAssertFalse(knowsWhatItRuns(project), "a build Lamp quit during went unnoticed")
    }
}
