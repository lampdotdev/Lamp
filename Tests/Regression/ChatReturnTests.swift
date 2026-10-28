import XCTest
@testable import Lamp

/// A wish's chat beside its Mac app goes with the app when it quits. Whether it then comes up in Lamp's panel.
final class ChatReturnTests: XCTestCase {
    /// The app moved to a TV or another device with no turn going on: its Mac copy quit, and nothing on the Mac
    /// shows the wish any more.
    func testAnAppMovedOffTheMacBringsItsChatBack() {
        XCTAssertTrue(ChatReturn.shows(.appLeft, onTheMac: false, leftAppLately: true, dismissed: false, connected: false, panelOpen: false))
    }

    /// The Mac copy quit first, and the place was chosen a moment later.
    func testAPlaceChosenJustAfterTheAppQuitBringsItsChatBack() {
        XCTAssertTrue(ChatReturn.shows(.placeChanged, onTheMac: false, leftAppLately: true, dismissed: false, connected: false, panelOpen: false))
    }

    /// The person quit an app that still opens on the Mac: its chat went with it, as it always has.
    func testAPlainQuitLeavesTheChatClosed() {
        XCTAssertFalse(ChatReturn.shows(.appLeft, onTheMac: true, leftAppLately: true, dismissed: false, connected: false, panelOpen: false))
    }

    /// Put back on the Mac before the chat came up.
    func testAnAppPutBackOnTheMacLeavesTheChatClosed() {
        XCTAssertFalse(ChatReturn.shows(.placeChanged, onTheMac: true, leftAppLately: true, dismissed: false, connected: false, panelOpen: false))
    }

    /// A device app whose chat the person closed in Lamp's panel, given another device: the chat stays closed.
    func testAPlaceChangeLongAfterLeavesTheChatClosed() {
        XCTAssertFalse(ChatReturn.shows(.placeChanged, onTheMac: false, leftAppLately: false, dismissed: false, connected: false, panelOpen: false))
    }

    /// The person closed the chat beside the app (it stays connected, hidden), then the app moved off the Mac and its
    /// Mac copy quit: the chat they closed stays closed.
    func testAChatThePersonClosedStaysClosedWhenTheAppMoves() {
        XCTAssertFalse(ChatReturn.shows(.appLeft, onTheMac: false, leftAppLately: true, dismissed: true, connected: false, panelOpen: false))
        XCTAssertFalse(ChatReturn.shows(.placeChanged, onTheMac: false, leftAppLately: true, dismissed: true, connected: false, panelOpen: false))
    }

    /// The chat is somewhere already: beside a copy of the app again, or in Lamp's panel.
    func testAChatThatIsSomewhereIsLeftThere() {
        for reason in [ChatReturn.Reason.placeChanged, .appLeft, .turnGoing, .crashed] {
            XCTAssertFalse(ChatReturn.shows(reason, onTheMac: false, leftAppLately: true, dismissed: false, connected: true, panelOpen: false))
            XCTAssertFalse(ChatReturn.shows(reason, onTheMac: false, leftAppLately: true, dismissed: false, connected: false, panelOpen: true))
        }
    }

    /// A crash, or a quit in the middle of a turn, brings the chat back wherever the app opens.
    func testACrashOrAQuitInATurnBringsTheChatBack() {
        XCTAssertTrue(ChatReturn.shows(.crashed, onTheMac: true, leftAppLately: true, dismissed: false, connected: false, panelOpen: false))
        XCTAssertTrue(ChatReturn.shows(.turnGoing, onTheMac: true, leftAppLately: true, dismissed: false, connected: false, panelOpen: false))
    }

    /// Two reasons for one wish: the wait keeps the stronger.
    func testTheStrongerReasonIsKept() {
        XCTAssertEqual(max(ChatReturn.Reason.appLeft, .crashed), .crashed)
        XCTAssertEqual(max(ChatReturn.Reason.placeChanged, .appLeft), .appLeft)
    }
}
