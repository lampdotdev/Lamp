import XCTest
@testable import Lamp

/// Every build of Lamp brings a newly signed helper. Once Chrome is connected, Lamp puts that helper in place itself,
/// so the person isn't asked to set up the connection again; and it does so only for the connection it set up,
/// writing only the helper it ships, so Chrome still runs nothing else.
@MainActor
final class BrowserSetupUpdateTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-setup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    /// A connection set up by an earlier build: everything in place except that build's helper.
    private func layout(manifestPath: String? = nil, extensionChanged: Bool = false, manifest: Bool = true) throws -> BrowserSetup.Layout {
        let fm = FileManager.default
        let id = String(repeating: "a", count: 32)
        // A folder of its own for each case, so building one never rewrites another's files.
        let root = self.root.appendingPathComponent(UUID().uuidString)
        let layout = BrowserSetup.Layout(
            hostManifest: root.appendingPathComponent("NativeMessagingHosts/\(BrowserSetup.hostName).json"),
            helper: root.appendingPathComponent("support/BrowserNativeHost"),
            bundledHelper: root.appendingPathComponent("bundle/Helpers/BrowserNativeHost"),
            bundledExtension: root.appendingPathComponent("bundle/extension"),
            extensionFolder: root.appendingPathComponent("support/Extension"),
            config: root.appendingPathComponent("support/config.json"),
            secret: root.appendingPathComponent("support/secret"),
            extensionID: id, port: 47821)
        for folder in [layout.bundledExtension, layout.extensionFolder, layout.bundledHelper.deletingLastPathComponent(),
                       layout.hostManifest.deletingLastPathComponent()] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data("worker".utf8).write(to: layout.bundledExtension.appendingPathComponent("worker.js"))
        try Data(extensionChanged ? "older worker".utf8 : "worker".utf8).write(to: layout.extensionFolder.appendingPathComponent("worker.js"))
        try Data("helper, signed by this build".utf8).write(to: layout.bundledHelper)
        try Data("helper, signed by the build before".utf8).write(to: layout.helper)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: layout.helper.path)
        try XCTUnwrap(layout.configData).write(to: layout.config)
        try Data("secret".utf8).write(to: layout.secret)
        if manifest {
            let body: [String: Any] = ["name": BrowserSetup.hostName, "path": manifestPath ?? layout.helper.path, "type": "stdio",
                                       "allowed_origins": ["chrome-extension://\(id)/"]]
            try JSONSerialization.data(withJSONObject: body).write(to: layout.hostManifest)
        }
        return layout
    }

    func testANewBuildsHelperIsPutInPlaceWithoutAskingAgain() throws {
        let layout = try layout()
        XCTAssertFalse(BrowserSetup.validBridge(layout), "the old helper doesn't pass the check")
        XCTAssertTrue(BrowserSetup.bringUpToDate(layout))
        XCTAssertTrue(BrowserSetup.validBridge(layout), "set up again without a click")
        XCTAssertEqual(try Data(contentsOf: layout.helper), try Data(contentsOf: layout.bundledHelper))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: layout.helper.path))
        XCTAssertFalse(BrowserSetup.bringUpToDate(layout), "nothing left to change")
    }

    func testOnlyAConnectionThisLampSetUpIsTouched() throws {
        for (layout, why) in [(try layout(manifest: false), "never set up"),
                              (try layout(manifestPath: root.appendingPathComponent("elsewhere/host").path), "a manifest naming another helper"),
                              (try layout(extensionChanged: true), "an extension Chrome has to load again")] {
            let before = try Data(contentsOf: layout.helper)
            XCTAssertFalse(BrowserSetup.bringUpToDate(layout), why)
            XCTAssertEqual(try Data(contentsOf: layout.helper), before, why)
            XCTAssertFalse(BrowserSetup.validBridge(layout), why)
        }
    }
}
