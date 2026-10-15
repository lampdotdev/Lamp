import XCTest
@testable import Lamp

/// An app with a sidebar in Chrome keeps it when shared: its browser.json, as Lamp checked it, goes in the file and
/// comes out in the copy. Without it the copy's sidebar code would run with nothing listing or lighting it.
final class SharingBrowserTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func project(_ id: String, browser: String?) throws -> LampProject {
        let fm = FileManager.default
        let root = self.root ?? fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-share-browser-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent(id)
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try "let box = 1".write(to: dir.appendingPathComponent("Sources/ContentView.swift"), atomically: true, encoding: .utf8)
        if let browser { try browser.write(to: dir.appendingPathComponent("browser.json"), atomically: true, encoding: .utf8) }
        return LampProject(id: id, name: "Recipe Box", exe: "RecipeBox", dir: dir)
    }

    func testTheSidebarDeclarationTravelsWithTheApp() throws {
        let declared = #"{"offer": "Save this recipe to Recipe Box", "fits": [{"site": "allrecipes.com"}, {"selector": ".wprm-recipe-container"}], "extra": "dropped"}"#
        let sender = try project("sender", browser: declared)
        let package = try Sharing.open(try Sharing.export(sender))
        XCTAssertEqual(package.browser?.offer, "Save this recipe to Recipe Box")
        XCTAssertEqual(package.browser?.fits.count, 2)
        let mine = try project("mine", browser: nil)
        try Sharing.install(package, into: mine, replacing: true)
        let copied = try XCTUnwrap(BrowserCompanions.Declaration.load(mine))
        XCTAssertEqual(copied, BrowserCompanions.Declaration.load(sender))
        XCTAssertFalse(try String(contentsOf: BrowserCompanions.Declaration.url(mine), encoding: .utf8).contains("extra"))
    }

    /// A declaration Lamp's checks refuse doesn't travel, and an update without one takes the old one away.
    func testARefusedDeclarationStaysBehindAndAnUpdateWithoutOneRemovesIt() throws {
        let sender = try project("sender", browser: #"{"offer": "Everything", "fits": [{"selector": "a[href"}]}"#)
        let package = try Sharing.open(try Sharing.export(sender))
        XCTAssertNil(package.browser)
        let mine = try project("mine", browser: #"{"offer": "Old", "fits": [{"site": "example.com"}]}"#)
        try Sharing.install(package, into: mine, replacing: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: BrowserCompanions.Declaration.url(mine).path))
    }
}
