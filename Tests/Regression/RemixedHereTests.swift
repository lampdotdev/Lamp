import XCTest
@testable import Lamp

/// A remix made here stays the person's on the desk, whether or not its original is still there; the mark that says so
/// never leaves with a shared file.
@MainActor
final class RemixedHereTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        // Under the home folder, as Lamp keeps its wishes: a wish's folder is written only where no link leads on the way.
        root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-remixed-here-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        expectNoSharingFoldersLeft()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func rows(_ store: Store) -> [String: String] {
        let wishes = store.wishes
        let entries = Dictionary(uniqueKeysWithValues: wishes.map { ($0.id, DeskEntry.read($0, apps: [])) })
        return Dictionary(uniqueKeysWithValues: DeskList.rows(wishes, entries: entries, by: .name, ascending: true).map { ($0.project.name, $0.madeBy) })
    }

    /// Remix a wish, delete the original, and open the desk again: the remix still says "You".
    func testARemixStaysYoursWhenItsOriginalIsDeleted() throws {
        let original = try Template.scaffold(name: "Water", platform: .mac, in: root)
        let store = Store(testingAt: root)
        let remix = try store.remixCopy(of: try XCTUnwrap(store.current(original)))
        store.reload()
        XCTAssertEqual(rows(store), ["Water": "You", "Water Remix": "You"])

        try FileManager.default.removeItem(at: original.dir)
        let relaunched = Store(testingAt: root)
        XCTAssertEqual(relaunched.wishes.map(\.id), [remix.id])
        XCTAssertEqual(rows(relaunched), ["Water Remix": "You"])
    }

    /// The remix shared and opened as another wish is someone else's: the copy has no mark.
    func testASharedRemixDoesNotCarryTheMark() throws {
        let original = try Template.scaffold(name: "Water", platform: .mac, in: root)
        let store = Store(testingAt: root)
        let remix = try store.remixCopy(of: try XCTUnwrap(store.current(original)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: remix.dir.appendingPathComponent(Store.remixedHereMark).path))

        let package = try opened(try exported(remix))
        let received = try Template.scaffold(name: "Water Remix Received", platform: package.platform, family: package.family, in: root)
        try Sharing.install(package, into: received)
        XCTAssertFalse(FileManager.default.fileExists(atPath: received.dir.appendingPathComponent(Store.remixedHereMark).path))
        XCTAssertFalse(DeskEntry.read(received, apps: []).remixedHere)
        XCTAssertTrue(DeskEntry.read(received, apps: []).arrived)
    }
}
