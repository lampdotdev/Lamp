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
        // Nor a link that comes in later with what's copied into the bundle, such as the app's assets.
        let staged = try Store.stage(project, in: apps)
        XCTAssertNoThrow(try Store.checkContained(staged))
        try FileManager.default.createSymbolicLink(at: staged.appendingPathComponent("Contents/Assets"), withDestinationURL: project.dir)
        XCTAssertThrowsError(try Store.checkContained(staged))
        let real = project.dir.appendingPathComponent("Elsewhere.app")
        try FileManager.default.moveItem(at: built, to: real)
        try FileManager.default.createSymbolicLink(at: built, withDestinationURL: real)
        XCTAssertThrowsError(try Store.stage(project, in: apps))
    }

    /// The build can be swapped for a link after any look at it, so the copy is what's checked: a staged copy
    /// that is itself a link into the app's folder is refused.
    func testAStagedCopyThatIsALinkIsRefused() throws {
        let project = LampProject(id: "tallymarks", name: "Tally Marks", exe: "TallyMarks", dir: root.appendingPathComponent("tallymarks"))
        try bundle(project.builtURL, id: project.bundleID)
        let apps = root.appendingPathComponent("Apps")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let copy = apps.appendingPathComponent(".TallyMarks-staged.app")
        try FileManager.default.createSymbolicLink(at: copy, withDestinationURL: project.builtURL)
        XCTAssertNoThrow(try Store.checkOwnIDs(in: copy, for: project))
        XCTAssertThrowsError(try Store.checkContained(copy))
    }

    /// A signature made while Info.plist named another app still names it after the file is put back, and the
    /// seal no longer matches: the signed copy is read again before it's installed and refused.
    func testASignatureMadeAsAnotherAppIsRefused() throws {
        let project = LampProject(id: "tallymarks", name: "Tally Marks", exe: "TallyMarks", dir: root.appendingPathComponent("tallymarks"))
        let other = LampProject(id: "pocketnotes", name: "Pocket Notes", exe: "PocketNotes", dir: root.appendingPathComponent("pocketnotes"))
        let app = try executableBundle(at: root.appendingPathComponent("TallyMarks.app"), id: project.bundleID)
        XCTAssertEqual(try sign(app, entitlements: nil), 0)
        XCTAssertNoThrow(try Store.checkOwnIDs(in: app, for: project, signed: true))

        try info(app, id: other.bundleID)
        XCTAssertEqual(try sign(app, entitlements: nil), 0)
        try info(app, id: project.bundleID)
        XCTAssertNoThrow(try Store.checkOwnIDs(in: app, for: project))
        XCTAssertThrowsError(try Store.checkOwnIDs(in: app, for: project, signed: true))
    }

    /// The Mac half of an app for both is signed with Lamp's entitlements (what Xcode signed Lamp's own project with,
    /// `TeamSigning`), not with what the build's own signature claims: anything in the app's folder can sign the build
    /// with another app's group.
    func testAnAppForBothIsSignedWithLampsEntitlementsOnly() throws {
        let project = LampProject(id: "tallymarks", name: "Tally Marks", exe: "TallyMarks", dir: root.appendingPathComponent("tallymarks"))
        let app = try executableBundle(at: root.appendingPathComponent("TallyMarks.app"), id: project.bundleID)
        let claimed = root.appendingPathComponent("claimed.plist")
        try PropertyListSerialization.data(fromPropertyList: ["com.apple.security.application-groups": ["ABCDE12345.dev.lamp.app.pocketnotes"],
                                                              "com.apple.security.cs.disable-library-validation": true],
                                           format: .xml, options: 0).write(to: claimed)
        XCTAssertEqual(try sign(app, entitlements: claimed), 0)
        XCTAssertNotNil(try entitlements(of: app)["com.apple.security.application-groups"])

        let lamps = root.appendingPathComponent("app-entitlements.plist")
        let teamIdentity = "  <key>com.apple.developer.team-identifier</key><string>ABCDE12345</string>\n" +
            "  <key>com.apple.application-identifier</key><string>ABCDE12345.\(project.bundleID)</string>\n"
        try Template.Capabilities.load(project).entitlementsPlist(for: project, platform: .mac)
            .replacingOccurrences(of: "<plist version=\"1.0\"><dict>\n", with: "<plist version=\"1.0\"><dict>\n" + teamIdentity)
            .write(to: lamps, atomically: true, encoding: .utf8)
        XCTAssertEqual(try shell(AppSigning.universalCommand, ["LAMP_APP": app.path, "LAMP_IDENTITY": "-", "LAMP_APP_ENTITLEMENTS": lamps.path,
                                                               "LAMP_SIDEBAR": app.appendingPathComponent("Contents/Extensions/None.appex").path]), 0)
        let signed = try entitlements(of: app)
        XCTAssertNil(signed["com.apple.security.application-groups"])
        XCTAssertNil(signed["com.apple.security.cs.disable-library-validation"])
        XCTAssertEqual(signed["com.apple.developer.team-identifier"] as? String, "ABCDE12345")
        XCTAssertEqual(signed["com.apple.application-identifier"] as? String, "ABCDE12345." + project.bundleID)
    }

    private func info(_ app: URL, id: String) throws {
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id, "CFBundleExecutable": "TallyMarks",
                                                              "CFBundlePackageType": "APPL"], format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
    }

    /// A bundle codesign will sign: a copy of a small system program as its executable.
    private func executableBundle(at app: URL, id: String) throws -> URL {
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: app.appendingPathComponent("Contents/MacOS/TallyMarks"))
        try info(app, id: id)
        return app
    }

    private func sign(_ app: URL, entitlements: URL?) throws -> Int32 {
        try shell("codesign --force -s - \(entitlements.map { "--entitlements '\($0.path)'" } ?? "") \"$LAMP_APP\"", ["LAMP_APP": app.path])
    }

    private func entitlements(of app: URL) throws -> [String: Any] {
        let out = root.appendingPathComponent("entitlements-\(UUID().uuidString).plist")
        _ = try shell("codesign -d --entitlements \"$OUT\" --xml \"$LAMP_APP\"", ["LAMP_APP": app.path, "OUT": out.path])
        guard let data = try? Data(contentsOf: out), !data.isEmpty else { return [:] }
        return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
    }

    @discardableResult
    private func shell(_ command: String, _ env: [String: String]) throws -> Int32 {
        TestShell.run(command, env: env).status
    }
}
