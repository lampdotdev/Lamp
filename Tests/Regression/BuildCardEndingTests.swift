import XCTest
@testable import Lamp

/// What a new app's card says under the name once its first turn is over.
final class BuildCardEndingTests: XCTestCase {
    func testABuiltAppThatOpenedIsReady() {
        var progress = TurnProgress(newApp: true)
        XCTAssertNil(progress.ending)
        progress.finish(worked: true)
        XCTAssertEqual(progress.ending, .ready)
    }

    /// An install or an open that failed leaves its own line in the chat and isn't a failed turn. The card
    /// above that line mustn't say the app is ready.
    func testABuiltAppThatCouldNotBeOpenedIsNotReady() {
        var progress = TurnProgress(newApp: true)
        progress.finish(worked: true, opened: false)
        XCTAssertEqual(progress.ending, .didNotOpen)
    }

    func testATurnThatFailedDidNotFinishWhetherOrNotAnythingOpened() {
        var progress = TurnProgress(newApp: true)
        progress.finish(worked: false, opened: false)
        XCTAssertEqual(progress.ending, .didNotFinish)
    }
}
