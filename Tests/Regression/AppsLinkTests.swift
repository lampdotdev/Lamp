import XCTest
@testable import Lamp

/// The Mac's Applications folder gets a link to the folder Lamp installs apps in, and nothing already
/// there is ever replaced.
final class AppsLinkTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("AppsLinkTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testTheLinkIsMadeAndLeadsToTheAppsFolder() throws {
        let apps = dir.appendingPathComponent("Lamp Apps"), link = dir.appendingPathComponent("Applications Lamp Apps")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        XCTAssertTrue(AppsLink.link(at: link, to: apps))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), apps.path)
        XCTAssertTrue(AppsLink.link(at: link, to: apps))   // made already: nothing to do
    }

    func testAFolderAlreadyThereIsLeftAlone() throws {
        let apps = dir.appendingPathComponent("Lamp Apps"), taken = dir.appendingPathComponent("Taken")
        try FileManager.default.createDirectory(at: taken, withIntermediateDirectories: true)
        XCTAssertFalse(AppsLink.link(at: taken, to: apps))
        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: taken.path))
    }

    /// Another account's link, even one whose folder is gone, stays theirs.
    func testAnotherLinkIsLeftAlone() throws {
        let apps = dir.appendingPathComponent("Lamp Apps"), link = dir.appendingPathComponent("Link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/Users/someone-else/Applications/Lamp Apps")
        XCTAssertFalse(AppsLink.link(at: link, to: apps))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), "/Users/someone-else/Applications/Lamp Apps")
    }
}
