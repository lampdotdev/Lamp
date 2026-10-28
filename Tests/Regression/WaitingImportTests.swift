import XCTest
@testable import Lamp

/// A shared app opened before setup is done is kept, through a relaunch too, until the person is through
/// setup: the original may have been a temporary file, so a copy that's lost can't be had again.
final class WaitingImportTests: XCTestCase {
    private let suite = "lamp-waiting-import-\(UUID().uuidString)"
    private let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("lamp-waiting-import-\(UUID().uuidString)")

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    /// What a launch of Lamp would have: the saved settings and the folder are all that carry over.
    private func launch() throws -> WaitingImport {
        WaitingImport(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), folder: root.appendingPathComponent("Waiting"))
    }

    private func sharedFile(_ name: String, _ bytes: [UInt8] = [1, 2, 3]) throws -> URL {
        let folder = root.appendingPathComponent("Downloads-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name)
        try Data(bytes).write(to: file)
        return file
    }

    func testAFileOpenedDuringSetupIsKeptEvenAfterTheOriginalIsGone() throws {
        let waiting = try launch()
        let original = try sharedFile("Tally.lampapp")
        XCTAssertTrue(waiting.keep(original))
        // Opened straight from Mail or Messages, the original can be a temporary file.
        try FileManager.default.removeItem(at: original)

        let kept = try XCTUnwrap(waiting.take(setupReady: true, welcomeOver: true))
        XCTAssertEqual(kept.lastPathComponent, "Tally.lampapp")
        XCTAssertEqual(try Data(contentsOf: kept), Data([1, 2, 3]))
    }

    /// A file a link fetched, with its request beside it, keeps the request through the wait: the copy has it too.
    func testARequestKeptBesideAFetchedFileGoesWithTheCopy() throws {
        let folder = root.appendingPathComponent("lamp-fetched-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Shared Wish.lampapp")
        try Data([1, 2, 3]).write(to: file)
        try "Add a map".write(to: folder.appendingPathComponent(WaitingImport.requestFile), atomically: true, encoding: .utf8)
        XCTAssertEqual(Store.fetchedRequest(beside: file), "Add a map")
        XCTAssertTrue(try launch().keep(file))
        try FileManager.default.removeItem(at: folder)
        let kept = try XCTUnwrap(try launch().take(setupReady: true, welcomeOver: true))
        XCTAssertEqual(Store.fetchedRequest(beside: kept), "Add a map")
        // The same file fetched again with another request, while the first still waits: the newer request is kept.
        let again = root.appendingPathComponent("lamp-fetched-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: again, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: again.appendingPathComponent("Shared Wish.lampapp"))
        try "Add a map".write(to: again.appendingPathComponent(WaitingImport.requestFile), atomically: true, encoding: .utf8)
        XCTAssertTrue(try launch().keep(again.appendingPathComponent("Shared Wish.lampapp")))
        let once = root.appendingPathComponent("lamp-fetched-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: once, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: once.appendingPathComponent("Shared Wish.lampapp"))
        try "Add a bike".write(to: once.appendingPathComponent(WaitingImport.requestFile), atomically: true, encoding: .utf8)
        XCTAssertTrue(try launch().keep(once.appendingPathComponent("Shared Wish.lampapp")))
        XCTAssertEqual(try launch().count, 1)
        let keptAgain = try XCTUnwrap(try launch().take(setupReady: true, welcomeOver: true))
        XCTAssertEqual(Store.fetchedRequest(beside: keptAgain), "Add a bike")
        // A file opened by hand, with a file of that name beside it, brings none.
        let byHand = try sharedFile("Tally.lampapp")
        try "Not mine".write(to: byHand.deletingLastPathComponent().appendingPathComponent(WaitingImport.requestFile), atomically: true, encoding: .utf8)
        XCTAssertNil(Store.fetchedRequest(beside: byHand))
    }

    func testTheKeptFileSurvivesARelaunch() throws {
        XCTAssertTrue(try launch().keep(try sharedFile("Tally.lampapp")))

        let relaunched = try launch()
        // Clearing out old waiting files on launch must leave this one alone.
        let folder = try XCTUnwrap(relaunched.keptFolders.first)
        let kept = try XCTUnwrap(relaunched.take(setupReady: true, welcomeOver: true))
        XCTAssertEqual(kept.deletingLastPathComponent().path, folder)
        XCTAssertEqual(try Data(contentsOf: kept), Data([1, 2, 3]))
    }

    func testASecondAppOpenedMeanwhileIsKeptBehindTheFirst() throws {
        let waiting = try launch()
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp", [1])))
        // An agent is chosen, and the person opens another shared app before "Start building": the welcome is
        // still up, so it waits too, and the first one is not lost.
        XCTAssertTrue(waiting.keep(try sharedFile("Recipes.lampapp", [2])))
        XCTAssertNil(waiting.take(setupReady: true, welcomeOver: false))
        XCTAssertEqual(waiting.count, 2)
        XCTAssertEqual(waiting.keptFolders.count, 2)

        // After "Start building" each gets its review, in the order they were opened; the second when the
        // first one's review closes.
        let first = try XCTUnwrap(waiting.take(setupReady: true, welcomeOver: true))
        XCTAssertEqual(first.lastPathComponent, "Tally.lampapp")
        XCTAssertEqual(try Data(contentsOf: first), Data([1]))
        XCTAssertEqual(waiting.count, 1)
        let second = try XCTUnwrap(waiting.take(setupReady: true, welcomeOver: true))
        XCTAssertEqual(second.lastPathComponent, "Recipes.lampapp")
        XCTAssertEqual(try Data(contentsOf: second), Data([2]))
        XCTAssertNil(waiting.take(setupReady: true, welcomeOver: true))
    }

    func testTwoDifferentAppsWithTheSameFileNameAreBothKept() throws {
        let waiting = try launch()
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp", [1])))
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp", [2])))

        XCTAssertEqual(waiting.count, 2)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(waiting.take(setupReady: true, welcomeOver: true))), Data([1]))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(waiting.take(setupReady: true, welcomeOver: true))), Data([2]))
    }

    func testTheOneFileAnEarlierLampKeptIsStillOpened() throws {
        // Lamp used to remember a single path under another name.
        let earlier = try launch()
        XCTAssertTrue(earlier.keep(try sharedFile("Tally.lampapp")))
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let path = try XCTUnwrap(defaults.stringArray(forKey: WaitingImport.key)?.first)
        defaults.removeObject(forKey: WaitingImport.key)
        defaults.set(path, forKey: WaitingImport.earlierKey)

        let waiting = try launch()
        XCTAssertEqual(waiting.keptFolders.count, 1)
        XCTAssertTrue(waiting.keep(try sharedFile("Recipes.lampapp", [2])))
        XCTAssertEqual(try XCTUnwrap(waiting.take(setupReady: true, welcomeOver: true)).lastPathComponent, "Tally.lampapp")
        XCTAssertEqual(try XCTUnwrap(waiting.take(setupReady: true, welcomeOver: true)).lastPathComponent, "Recipes.lampapp")
        XCTAssertNil(defaults.string(forKey: WaitingImport.earlierKey))
    }

    func testAFileThatCouldNotBeCopiedLeavesTheEarlierOneWaiting() throws {
        let waiting = try launch()
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp")))
        // Gone before Lamp could copy it.
        XCTAssertFalse(waiting.keep(root.appendingPathComponent("Missing.lampapp")))

        XCTAssertEqual(try XCTUnwrap(waiting.take(setupReady: true, welcomeOver: true)).lastPathComponent, "Tally.lampapp")
    }
}
