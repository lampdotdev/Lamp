import XCTest
@testable import Lamp

/// A change that goes into the open Mac app is in it within seconds, but its whole build, which writes what the app was
/// built from, runs for a minute after (`Store.reloadBeforeBuilding`). A turn's end looks again at every app of the wish
/// until each one's code is built, and saves nothing while one isn't: read off the build record alone, an app whose last
/// change went in live looked unbuilt, and the turn ended saying the change didn't work, with no version saved, though
/// the change was in the app.
@MainActor
final class LiveChangeCountsAsBuiltTests: XCTestCase {
    private var root: URL?

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func app() throws -> LampProject {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-live-built-\(UUID().uuidString)")
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let project = try Template.scaffold(name: "Plus", in: root)
        // A build of the app as it was, then the agent's change.
        try fm.createDirectory(at: project.builtURL, withIntermediateDirectories: true)
        Runtime.markBuilt(project, from: Runtime.fingerprint(project))
        try edit(project, "Color.green")
        return project
    }

    private func edit(_ project: LampProject, _ text: String) throws {
        try "let plusColor = \(text)\n".write(to: project.dir.appendingPathComponent("Sources/Plus.swift"), atomically: true, encoding: .utf8)
    }

    /// The change that went in, with its whole build running, is built as far as the turn's end goes.
    func testAChangeThatWentInLiveIsNotStillToBuild() throws {
        let project = try app()
        XCTAssertTrue(Runtime.needsBuild(project))
        LiveReload.startedBuilding(project, from: Runtime.fingerprint(project))
        XCTAssertFalse(Runtime.needsBuild(project), "the change in the open app was taken for one still to build")
    }

    /// An edit after the change went in is still to build, and so is the change once its whole build has failed.
    func testAnEditSinceOrAFailedWholeBuildIsStillToBuild() throws {
        let project = try app()
        LiveReload.startedBuilding(project, from: Runtime.fingerprint(project))
        try edit(project, "Color.red")
        XCTAssertTrue(Runtime.needsBuild(project))
        try edit(project, "Color.green")
        LiveReload.finishedBuilding(project)
        XCTAssertTrue(Runtime.needsBuild(project))
    }
}
