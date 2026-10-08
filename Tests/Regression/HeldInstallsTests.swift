import XCTest
@testable import Lamp

/// Lamp never replaces an app on disk while it's running: an icon that's ready while the app is open is
/// installed when the app closes, or with the next build.
final class HeldInstallsTests: XCTestCase {
    func testAnAppThatIsClosedGetsItsIconAtOnce() {
        var held = HeldInstalls()
        XCTAssertTrue(held.mayInstall("sips", running: false))
        XCTAssertTrue(held.waiting.isEmpty)
    }

    func testAnOpenAppWaitsUntilItCloses() {
        var held = HeldInstalls()
        XCTAssertFalse(held.mayInstall("sips", running: true))
        XCTAssertEqual(held.waiting, ["sips"])
        // Another app closing is nothing to it.
        XCTAssertTrue(held.due(amongClosed: ["tally"]).isEmpty)
        XCTAssertEqual(held.due(amongClosed: ["sips", "tally"]), ["sips"])
        // Closed now, the install goes ahead and nothing is left waiting.
        XCTAssertTrue(held.mayInstall("sips", running: false))
        XCTAssertTrue(held.due(amongClosed: ["sips"]).isEmpty)
    }

    func testAnAppReopenedBeforeItsInstallKeepsWaiting() {
        var held = HeldInstalls()
        XCTAssertFalse(held.mayInstall("sips", running: true))
        // It closed and was opened again before Lamp got to it: still not replaced, still waiting.
        XCTAssertFalse(held.mayInstall("sips", running: true))
        XCTAssertEqual(held.waiting, ["sips"])
    }

    func testABuildBringsTheIconAndEndsTheWait() {
        var held = HeldInstalls()
        XCTAssertFalse(held.mayInstall("sips", running: true))
        held.installed("sips")   // a build quits the app and installs it, icon and all
        XCTAssertTrue(held.due(amongClosed: ["sips"]).isEmpty)
    }
}
