import XCTest
@testable import Lamp

/// A shared app opened before setup is done is kept, through a relaunch too, and handed to its review once,
/// when the person is through setup: everything in place and the welcome over. Several are kept side by side
/// and handed over in the order they were opened.
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

    func testTheKeptFileSurvivesARelaunch() throws {
        XCTAssertTrue(try launch().keep(try sharedFile("Tally.lampapp")))

        let relaunched = try launch()
        // Clearing out old waiting files on launch must leave this one alone.
        let folder = try XCTUnwrap(relaunched.keptFolders.first)
        let kept = try XCTUnwrap(relaunched.take(setupReady: true, welcomeOver: true))
        XCTAssertEqual(kept.deletingLastPathComponent().path, folder)
        XCTAssertEqual(try Data(contentsOf: kept), Data([1, 2, 3]))
    }

    func testItIsHandedToReviewOnceNotTwice() throws {
        let waiting = try launch()
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp")))

        XCTAssertNotNil(waiting.take(setupReady: true, welcomeOver: true))
        // Setup being found ready a second time, in this run or the next, opens nothing more.
        XCTAssertNil(waiting.take(setupReady: true, welcomeOver: true))
        XCTAssertNil(try launch().take(setupReady: true, welcomeOver: true))
        XCTAssertTrue(try launch().keptFolders.isEmpty)
    }

    func testAReviewOpensOnlyWithSetupDoneAndTheWelcomeOver() {
        XCTAssertTrue(WaitingImport.reviewsCanOpen(setupReady: true, welcomeOver: true))
        // An agent chosen on the welcome's setup step, "Start building" not yet clicked.
        XCTAssertFalse(WaitingImport.reviewsCanOpen(setupReady: true, welcomeOver: false))
        // The welcome over, Apple's tools or the agent still missing.
        XCTAssertFalse(WaitingImport.reviewsCanOpen(setupReady: false, welcomeOver: true))
        XCTAssertFalse(WaitingImport.reviewsCanOpen(setupReady: false, welcomeOver: false))
    }

    func testItWaitsForStartBuildingEvenOnceAnAgentIsChosen() throws {
        let waiting = try launch()
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp")))

        // An agent chosen on the welcome's setup step makes setup ready; the person is still in the welcome.
        XCTAssertNil(waiting.take(setupReady: true, welcomeOver: false))
        XCTAssertEqual(waiting.count, 1)
        // "Start building" ends the welcome.
        XCTAssertEqual(try XCTUnwrap(waiting.take(setupReady: true, welcomeOver: true)).lastPathComponent, "Tally.lampapp")
    }

    func testAfterTheWelcomeItStillWaitsForSetup() throws {
        let waiting = try launch()
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp")))

        // The welcome is over but Apple's tools are still installing.
        XCTAssertNil(waiting.take(setupReady: false, welcomeOver: true))
        XCTAssertEqual(waiting.count, 1)
        XCTAssertNotNil(waiting.take(setupReady: true, welcomeOver: true))
    }

    func testARelaunchThatIsAlreadySetUpOpensIt() throws {
        let waiting = try launch()
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp")))
        // Quit in the welcome with an agent chosen: nothing was handed over.
        XCTAssertNil(waiting.take(setupReady: true, welcomeOver: false))

        // The next launch finds setup done and no welcome to go through, so no button will be clicked.
        XCTAssertEqual(try XCTUnwrap(try launch().take(setupReady: true, welcomeOver: true)).lastPathComponent, "Tally.lampapp")
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

    func testSeveralKeptAppsSurviveARelaunchInOrder() throws {
        XCTAssertTrue(try launch().keep(try sharedFile("Tally.lampapp", [1])))
        XCTAssertTrue(try launch().keep(try sharedFile("Recipes.lampapp", [2])))

        let relaunched = try launch()
        XCTAssertEqual(relaunched.keptFolders.count, 2)
        XCTAssertEqual(try XCTUnwrap(relaunched.take(setupReady: true, welcomeOver: true)).lastPathComponent, "Tally.lampapp")
        XCTAssertEqual(try XCTUnwrap(try launch().take(setupReady: true, welcomeOver: true)).lastPathComponent, "Recipes.lampapp")
        XCTAssertNil(try launch().take(setupReady: true, welcomeOver: true))
    }

    func testTwoDifferentAppsWithTheSameFileNameAreBothKept() throws {
        let waiting = try launch()
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp", [1])))
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp", [2])))

        XCTAssertEqual(waiting.count, 2)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(waiting.take(setupReady: true, welcomeOver: true))), Data([1]))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(waiting.take(setupReady: true, welcomeOver: true))), Data([2]))
    }

    func testAKeptAppWhoseCopyIsGoneDoesNotHoldUpTheNext() throws {
        let waiting = try launch()
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp", [1])))
        let first = try XCTUnwrap(waiting.keptFolders.first)
        XCTAssertTrue(waiting.keep(try sharedFile("Recipes.lampapp", [2])))
        try FileManager.default.removeItem(atPath: first)

        XCTAssertEqual(try XCTUnwrap(waiting.take(setupReady: true, welcomeOver: true)).lastPathComponent, "Recipes.lampapp")
        XCTAssertNil(waiting.take(setupReady: true, welcomeOver: true))
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

    func testNothingKeptMeansNothingToOpen() throws {
        XCTAssertNil(try launch().take(setupReady: true, welcomeOver: true))
        XCTAssertTrue(try launch().keptFolders.isEmpty)
    }

    func testTheSameFileOpenedTwiceIsKeptOnce() throws {
        let waiting = try launch()
        let file = try sharedFile("Tally.lampapp")
        XCTAssertTrue(waiting.keep(file))
        XCTAssertTrue(waiting.keep(file))

        let copies = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Waiting").path)
        XCTAssertEqual(copies.count, 1)
        XCTAssertNotNil(waiting.take(setupReady: true, welcomeOver: true))
        XCTAssertNil(waiting.take(setupReady: true, welcomeOver: true))
    }

    func testAFileThatCouldNotBeCopiedIsNotPromised() throws {
        // No copy can be made here: a file sits where the Waiting folder would go.
        let blocked = root.appendingPathComponent("blocked")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: blocked)
        let waiting = WaitingImport(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), folder: blocked)
        let original = try sharedFile("Tally.lampapp")

        XCTAssertFalse(waiting.keep(original))
        XCTAssertTrue(waiting.keptFolders.isEmpty)
        XCTAssertNil(waiting.take(setupReady: true, welcomeOver: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testAFileThatCouldNotBeCopiedLeavesTheEarlierOneWaiting() throws {
        let waiting = try launch()
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp")))
        // Gone before Lamp could copy it.
        XCTAssertFalse(waiting.keep(root.appendingPathComponent("Missing.lampapp")))

        XCTAssertEqual(try XCTUnwrap(waiting.take(setupReady: true, welcomeOver: true)).lastPathComponent, "Tally.lampapp")
    }
}
