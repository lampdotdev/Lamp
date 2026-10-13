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

/// A shared app that declares `background` is shown as starting at login before the person decides, and the
/// reviewer sees the declaration as a file, even when its code never mentions the login item.
final class BackgroundSharedAppTests: XCTestCase {
    func testADeclaredBackgroundAppIsListedAsStartingAtLogin() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-background-share-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("Sources/App.swift")
        try "import SwiftUI\n@main struct App: SwiftUI.App { var body: some Scene { LampMenuBar(\"W\", systemImage: \"eye\") { Text(\"hi\") } } }\n"
            .write(to: source, atomically: true, encoding: .utf8)
        let plain = Sharing.inspect(Sharing.Package(name: "Watcher", folder: folder, sources: [source], attachments: [], fileCount: 1))
        XCTAssertFalse(plain.detected.contains { $0.label == "Starts at login" })
        XCTAssertFalse(plain.files.contains { $0.name == "capabilities.json" })
        let declared = Sharing.inspect(Sharing.Package(name: "Watcher", capabilities: Template.Capabilities(background: true),
                                                       folder: folder, sources: [source], attachments: [], fileCount: 1))
        XCTAssertTrue(declared.detected.contains { $0.label == "Starts at login" })
        let file = try XCTUnwrap(declared.files.first { $0.name == "capabilities.json" })
        XCTAssertTrue(file.text.contains("\"background\" : true"), file.text)
    }
}
