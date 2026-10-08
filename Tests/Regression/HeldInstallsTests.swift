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

    /// The app closed while Lamp was busy with it, so the install couldn't happen at that moment. Asking
    /// doesn't use the wait up: it's still due when Lamp asks again once the app is free.
    func testAnAppThatClosedWhileLampHadItIsStillDueAfterwards() {
        var held = HeldInstalls()
        XCTAssertFalse(held.mayInstall("sips", running: true))
        XCTAssertEqual(held.due(amongClosed: ["sips"]), ["sips"])   // it closed; Lamp couldn't take it then
        XCTAssertEqual(held.due(amongClosed: ["sips"]), ["sips"])   // asked again when the turn gave it back
        XCTAssertTrue(held.mayInstall("sips", running: false))
        XCTAssertTrue(held.due(amongClosed: ["sips"]).isEmpty)       // installed: asking again finds nothing
    }

    func testABuildBringsTheIconAndEndsTheWait() {
        var held = HeldInstalls()
        XCTAssertFalse(held.mayInstall("sips", running: true))
        held.installed("sips")   // a build quits the app and installs it, icon and all
        XCTAssertTrue(held.due(amongClosed: ["sips"]).isEmpty)
    }
}
