import XCTest
@testable import Lamp

/// Lamp signs a build as the app only while the build still says it is the app: an id rewritten after the build
/// (by anything that can write the app's folder) would have Lamp's certificate vouch for another app.
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

    func testABuildCarryingAnotherAppsIDIsNotSigned() throws {
        let project = LampProject(id: "tallymarks", name: "Tally Marks", exe: "TallyMarks", dir: root.appendingPathComponent("tallymarks"))
        let other = LampProject(id: "pocketnotes", name: "Pocket Notes", exe: "PocketNotes", dir: root.appendingPathComponent("pocketnotes"))
        let app = project.builtURL
        try bundle(app, id: project.bundleID)
        try bundle(Template.widgetURL(in: app, of: project), id: Template.widgetBundleID(for: project))
        XCTAssertNoThrow(try Store.checkOwnIDs(in: app, for: project))

        try bundle(app, id: other.bundleID)
        XCTAssertThrowsError(try Store.checkOwnIDs(in: app, for: project))

        try bundle(app, id: project.bundleID)
        try bundle(Template.widgetURL(in: app, of: project), id: Template.widgetBundleID(for: other))
        XCTAssertThrowsError(try Store.checkOwnIDs(in: app, for: project))
    }
}
