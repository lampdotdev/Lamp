import XCTest
@testable import Lamp

/// Lamp signs an app as itself only while it is the app: the build folder is the agent's to write, so the id is
/// read from a copy outside it, the copy that is then signed, and a copy carrying another app's id isn't signed.
final class DeployOwnIDTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DeployOwnIDTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func bundle(_ url: URL, id: String) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Contents/Info.plist"))
    }

    func testOnlyACopyCarryingTheAppsOwnIDsIsSigned() throws {
        let project = LampProject(id: "tallymarks", name: "Tally Marks", exe: "TallyMarks", dir: root.appendingPathComponent("tallymarks"))
        let other = LampProject(id: "pocketnotes", name: "Pocket Notes", exe: "PocketNotes", dir: root.appendingPathComponent("pocketnotes"))
        let apps = root.appendingPathComponent("Apps")
        let built = project.builtURL
        try bundle(built, id: project.bundleID)
        try bundle(Template.widgetURL(in: built, of: project), id: Template.widgetBundleID(for: project))

        // Rewritten in the build folder once the copy is made, the id doesn't reach what Lamp signs.
        let copy = try Store.stage(project, in: apps)
        try bundle(built, id: other.bundleID)
        XCTAssertNoThrow(try Store.checkOwnIDs(in: copy, for: project))

        // Rewritten before the copy, it does, and nothing is signed.
        XCTAssertThrowsError(try Store.checkOwnIDs(in: try Store.stage(project, in: apps), for: project))
        try bundle(built, id: project.bundleID)
        try bundle(Template.widgetURL(in: built, of: project), id: Template.widgetBundleID(for: other))
        XCTAssertThrowsError(try Store.checkOwnIDs(in: try Store.stage(project, in: apps), for: project))

        // A copy doesn't follow links: one leading back into the build folder, or a build that is a link, isn't copied.
        try bundle(Template.widgetURL(in: built, of: project), id: Template.widgetBundleID(for: project))
        let plist = built.appendingPathComponent("Contents/Info.plist"), kept = project.dir.appendingPathComponent("Info.plist")
        try FileManager.default.moveItem(at: plist, to: kept)
        try FileManager.default.createSymbolicLink(at: plist, withDestinationURL: kept)
        XCTAssertThrowsError(try Store.stage(project, in: apps))
        try FileManager.default.removeItem(at: plist)
        try FileManager.default.moveItem(at: kept, to: plist)
        XCTAssertNoThrow(try Store.stage(project, in: apps))
        let real = project.dir.appendingPathComponent("Elsewhere.app")
        try FileManager.default.moveItem(at: built, to: real)
        try FileManager.default.createSymbolicLink(at: built, withDestinationURL: real)
        XCTAssertThrowsError(try Store.stage(project, in: apps))
    }
}
