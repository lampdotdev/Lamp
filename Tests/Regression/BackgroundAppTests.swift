import XCTest
@testable import Lamp

/// A utility that watches or waits declares `background` in capabilities.json; Lamp puts it in the app's
/// Info.plist, where LampSupport reads it at launch to open the app at login, and takes it back when the
/// declaration goes.
final class BackgroundAppTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    func testOnlyTrueIsKeptAndTravels() {
        XCTAssertEqual(Template.Capabilities(background: true).checked, Template.Capabilities(background: true))
        XCTAssertTrue(Template.Capabilities(background: false).isEmpty)
        XCTAssertEqual(Template.Capabilities(opens: ["folder"], background: true).checked, Template.Capabilities(opens: ["folder"], background: true))
    }

    func testTheDeclarationIsWrittenAndTakenBack() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-background-test-\(UUID().uuidString)")
        self.root = root
        let app = root.appendingPathComponent("build/Watcher.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist = app.appendingPathComponent("Contents/Info.plist")
        XCTAssertTrue(NSDictionary(dictionary: ["CFBundleIdentifier": "dev.lamp.app.watcher"]).write(to: plist, atomically: true))
        Template.Capabilities(background: true).apply(to: app)
        XCTAssertEqual(try XCTUnwrap(NSDictionary(contentsOf: plist))["LampBackground"] as? Bool, true)
        Template.Capabilities().apply(to: app)
        XCTAssertNil(try XCTUnwrap(NSDictionary(contentsOf: plist))["LampBackground"])
    }
}
