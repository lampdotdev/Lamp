import XCTest
@testable import Lamp

/// An app with no name yet says on screen what it is: "Your wish" when a wish from the site made it, "New App"
/// otherwise. Underneath it is the same untitled draft as ever, and a real name takes over everywhere.
final class DraftTitleTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("lamp-draft-title-\(UUID().uuidString)")

    override func setUpWithError() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func meta(_ project: LampProject) throws -> ProjectMeta {
        try JSONDecoder().decode(ProjectMeta.self, from: Data(contentsOf: project.dir.appendingPathComponent(".lamp/meta.json")))
    }

    func testAWishsDraftReadsYourWishAndAPlainOneNewApp() throws {
        let wish = try Template.draft(name: "Untitled", untitled: true, fromWish: true, in: root)
        let plain = try Template.draft(name: "Untitled 2", untitled: true, in: root)
        XCTAssertEqual(wish.title, "Your wish")
        XCTAssertEqual(plain.title, "New App")
        // Still the untitled draft everything else goes by: its stand-in name and folder are unchanged.
        XCTAssertTrue(wish.untitled)
        XCTAssertEqual(wish.name, "Untitled")
        XCTAssertEqual(wish.id, "untitled")
    }

    func testItIsStillAWishAfterLampRestarts() throws {
        let wish = try Template.draft(name: "Untitled", untitled: true, fromWish: true, in: root)
        XCTAssertEqual(try meta(wish).wish, true)
        XCTAssertEqual(try meta(wish).untitled, true)
        XCTAssertNil(try meta(try Template.draft(name: "Untitled 2", untitled: true, in: root)).wish)
    }

    func testARealNameTakesOver() throws {
        var named = try Template.draft(name: "Untitled", untitled: true, fromWish: true, in: root)
        named = LampProject(id: named.id, name: "Downloads Tidy", exe: named.exe, dir: named.dir, fromWish: true)
        XCTAssertEqual(named.title, "Downloads Tidy")
        // Once it has a name, nothing on disk still calls it a wish.
        try Template.saveMeta(named)
        XCTAssertNil(try meta(named).wish)
    }
}
