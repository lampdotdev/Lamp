import XCTest
@testable import Lamp

/// A wish can be more than one app (`Parts`): a TV app with an iPhone app that controls it.
final class WishPartsTests: XCTestCase {
    /// "A TV app that I can control with my phone" is a TV app and an iPhone app, made to work together; "both", to
    /// "TV, Mac or both?", is a TV app and a Mac app.
    func testATVAppControlledFromThePhoneIsATVAppWithAnIPhoneApp() throws {
        let remote = try XCTUnwrap(Parts.kinds(for: ["tv", "iphone"]))
        XCTAssertEqual(remote.main, .tv)
        XCTAssertEqual(remote.parts, [.iphone])
        let both = try XCTUnwrap(Parts.kinds(for: ["tv", "mac"]))
        XCTAssertEqual(both.main, .tv)
        XCTAssertEqual(both.parts, [.mac])
    }

    /// A part's folder is inside its wish's, which the agent may swap for a link: the part's own folder, which its build's
    /// sandbox opens, is still found by name under the wish's, never where that link leads.
    func testAPartsFolderIsNeverWhereALinkInPlaceOfItsWishLeads() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("wish-parts-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        let apps = root.appendingPathComponent("Apps"), elsewhere = root.appendingPathComponent("elsewhere")
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        try fm.createDirectory(at: elsewhere.appendingPathComponent("iPhone"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: apps.appendingPathComponent("remote"), withDestinationURL: elsewhere)
        let part = LampProject(id: "remote.iphone", name: "Remote", exe: "Remote", dir: apps.appendingPathComponent("remote/iPhone"),
                               platform: .iphone, partOf: "remote")
        XCTAssertEqual(part.realDir.path, apps.appendingPathComponent("remote/iPhone").path)
    }
}
