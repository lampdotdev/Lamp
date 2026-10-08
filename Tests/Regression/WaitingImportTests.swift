import XCTest
@testable import Lamp

/// A shared app opened before setup is done is kept, through a relaunch too, and handed to its review once,
/// when the person is through setup: everything in place and the welcome over.
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
        let folder = try XCTUnwrap(relaunched.keptFolder)
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
        XCTAssertNil(try launch().keptFolder)
    }

    func testItWaitsForStartBuildingEvenOnceAnAgentIsChosen() throws {
        let waiting = try launch()
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp")))

        // An agent chosen on the welcome's setup step makes setup ready; the person is still in the welcome.
        XCTAssertNil(waiting.take(setupReady: true, welcomeOver: false))
        XCTAssertNotNil(waiting.keptFolder)
        // "Start building" ends the welcome.
        XCTAssertEqual(try XCTUnwrap(waiting.take(setupReady: true, welcomeOver: true)).lastPathComponent, "Tally.lampapp")
    }

    func testAfterTheWelcomeItStillWaitsForSetup() throws {
        let waiting = try launch()
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp")))

        // The welcome is over but Apple's tools are still installing.
        XCTAssertNil(waiting.take(setupReady: false, welcomeOver: true))
        XCTAssertNotNil(waiting.keptFolder)
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

    func testAnotherAppOpenedMeanwhileReplacesTheKeptOne() throws {
        let waiting = try launch()
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp")))
        let copy = try XCTUnwrap(waiting.keptFolder)
        // An agent is chosen, and the person opens another shared app before "Start building": that one is
        // reviewed straight away, and the older one must not turn up when the welcome ends.
        waiting.discard()

        XCTAssertFalse(FileManager.default.fileExists(atPath: copy))
        XCTAssertNil(waiting.take(setupReady: true, welcomeOver: true))
        XCTAssertNil(try launch().take(setupReady: true, welcomeOver: true))
    }

    func testNothingKeptMeansNothingToOpen() throws {
        XCTAssertNil(try launch().take(setupReady: true, welcomeOver: true))
        XCTAssertNil(try launch().keptFolder)
    }

    func testTheNewestFileWinsAndTheEarlierCopyGoes() throws {
        let waiting = try launch()
        XCTAssertTrue(waiting.keep(try sharedFile("Tally.lampapp", [1])))
        let first = try XCTUnwrap(waiting.keptFolder)
        XCTAssertTrue(waiting.keep(try sharedFile("Recipes.lampapp", [2])))

        XCTAssertFalse(FileManager.default.fileExists(atPath: first))
        let kept = try XCTUnwrap(waiting.take(setupReady: true, welcomeOver: true))
        XCTAssertEqual(kept.lastPathComponent, "Recipes.lampapp")
        XCTAssertEqual(try Data(contentsOf: kept), Data([2]))
        XCTAssertNil(waiting.take(setupReady: true, welcomeOver: true))
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
        XCTAssertNil(waiting.keptFolder)
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
