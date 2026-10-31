import XCTest
@testable import Lamp

/// What Lamp records of putting a TV app on a TV is what the agent's note says the TV has, so it must name the copy
/// that went there, and it's read from the app's folder, where the agent's commands write too.
final class OnTVRecordTests: XCTestCase {
    private func tvApp() throws -> (LampProject, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("on-tv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Web"), withIntermediateDirectories: true)
        try "<p>one</p>".write(to: dir.appendingPathComponent("Web/index.html"), atomically: true, encoding: .utf8)
        var project = LampProject(id: "on-tv", name: "Clock", exe: "Clock", dir: dir)
        project.platform = .tv
        return (project, dir)
    }

    /// An edit made after the copy was staged (during a slow upload, say) isn't on the TV, so the record must not
    /// say the TV has it.
    func testTheRecordNamesTheStagedCodeNotAnEditMadeSince() throws {
        let (project, dir) = try tvApp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let staged = Runtime.fingerprint(project)
        Runtime.markBuilt(project, from: staged)
        try "<p>two</p>".write(to: dir.appendingPathComponent("Web/index.html"), atomically: true, encoding: .utf8)
        Runtime.putOnTV(project, tv: "lg:tv")
        XCTAssertEqual(Runtime.onTV(project)["lg:tv"]?.fingerprint, staged)
        XCTAssertNotEqual(Runtime.onTV(project)["lg:tv"]?.fingerprint, Runtime.fingerprint(project))
    }

    /// A record that is a link is not followed: it could lead anywhere the agent can't read itself.
    func testARecordThatIsALinkIsNotRead() throws {
        let (project, dir) = try tvApp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("on-tv-elsewhere-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        let record = try JSONEncoder().encode(["lg:tv": Runtime.OnTV(at: Date(), fingerprint: "x")])
        try record.write(to: elsewhere)
        let runtime = dir.appendingPathComponent(".lamp/runtime")
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: runtime.appendingPathComponent("on-tv.json"), withDestinationURL: elsewhere)
        XCTAssertTrue(Runtime.onTV(project).isEmpty)
    }
}
