import XCTest
@testable import Lamp

/// A TV app's phone page is handed out from Lamp's copy while the app runs: only plain files under it, reached through no
/// link at any step, and a new copy takes the old one's place whole.
final class TVPhonePageTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("tv-phone-page-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ text: String, to path: String, in root: URL) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    func testALinkAboveTheFileIsNoWayOut() throws {
        let page = folder.appendingPathComponent("phone")
        let outside = folder.appendingPathComponent("outside")
        try write("<p>wheel</p>", to: "index.html", in: page)
        try write("secret", to: "secret.txt", in: outside)
        try FileManager.default.createSymbolicLink(at: page.appendingPathComponent("assets"), withDestinationURL: outside)

        XCTAssertNotNil(TVs.phoneFile(["index.html"], in: page))
        XCTAssertNil(TVs.phoneFile(["assets", "secret.txt"], in: page), "a folder of the page that is a link leads outside it")

        let linkedRoot = folder.appendingPathComponent("linked-phone")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: page)
        XCTAssertNil(TVs.phoneFile(["index.html"], in: linkedRoot), "the published folder itself is a link")
    }

    func testANewCopyTakesTheOldOnesPlaceWhole() throws {
        let published = folder.appendingPathComponent("phone")
        let first = folder.appendingPathComponent(".phone-first")
        try write("first", to: "index.html", in: first)
        try TVs.publishPhone(first, as: published)
        XCTAssertEqual(try String(contentsOf: published.appendingPathComponent("index.html"), encoding: .utf8), "first")

        let second = folder.appendingPathComponent(".phone-second")
        try write("second", to: "index.html", in: second)
        try TVs.publishPhone(second, as: published)
        XCTAssertEqual(try String(contentsOf: published.appendingPathComponent("index.html"), encoding: .utf8), "second")
        XCTAssertEqual(try String(contentsOf: second.appendingPathComponent("index.html"), encoding: .utf8), "first",
                       "the old copy is swapped out whole, for the caller to remove")

        try TVs.publishPhone(nil, as: published)
        XCTAssertFalse(FileManager.default.fileExists(atPath: published.path), "an app with no page any more has none published")
    }
}
