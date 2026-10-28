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

    /// The chat came back beside a copy and went again before the first wait's next look: the second quit gets a wait of
    /// its own, which the first one ending doesn't take away.
    func testAQuitAfterTheChatCameBackGetsAWaitOfItsOwn() {
        let waits = ChatReturn.Waits()
        guard let first = waits.begin("wish", because: .appLeft) else { return XCTFail("no first wait") }
        waits.placed("wish")
        XCTAssertFalse(waits.isCurrent(first, for: "wish"))
        guard let second = waits.begin("wish", because: .appLeft) else { return XCTFail("the second quit was folded into a wait that's over") }
        waits.end(first, for: "wish")
        XCTAssertTrue(waits.isCurrent(second, for: "wish"))
        // A third reason while the second waits is folded into it.
        XCTAssertNil(waits.begin("wish", because: .crashed))
        XCTAssertEqual(second.reason, .crashed)
    }

    /// A device chosen, its setup waiting on a download or the device's approval, and the Mac copy quit meanwhile: the
    /// setup finishing minutes later is still the app moving.
    func testASetupThatTakesLongStillBringsTheChatBack() {
        let quit = Date(timeIntervalSinceReferenceDate: 0)
        // Chosen before the quit, or just after it.
        XCTAssertTrue(ChatReturn.leftLately(quit, moveBegan: quit.addingTimeInterval(-30), now: quit.addingTimeInterval(300)))
        XCTAssertTrue(ChatReturn.leftLately(quit, moveBegan: quit.addingTimeInterval(5), now: quit.addingTimeInterval(121)))
        // With no device choice pending, only a place chosen soon after.
        XCTAssertTrue(ChatReturn.leftLately(quit, moveBegan: nil, now: quit.addingTimeInterval(60)))
        XCTAssertFalse(ChatReturn.leftLately(quit, moveBegan: nil, now: quit.addingTimeInterval(121)))
        // A device chosen long after the quit isn't the app moving off with its chat.
        XCTAssertFalse(ChatReturn.leftLately(quit, moveBegan: quit.addingTimeInterval(500), now: quit.addingTimeInterval(510)))
    }

    /// Two reasons for one wish: the wait keeps the stronger.
    func testTheStrongerReasonIsKept() {
        XCTAssertEqual(max(ChatReturn.Reason.appLeft, .crashed), .crashed)
        XCTAssertEqual(max(ChatReturn.Reason.placeChanged, .appLeft), .appLeft)
    }
}
