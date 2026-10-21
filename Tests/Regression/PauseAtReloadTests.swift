import XCTest
@testable import Lamp

/// A change the person hasn't seen yet pauses the request (`Store.pause`): the agent's turn is over at its next tool
/// call, and the request carries on only once the change is in. One run went on for eleven minutes and a hundred tool
/// calls after a look said its change waited for Reload, with nothing reaching the screen; the rule here is what stops
/// that, the same for every engine.
@MainActor
final class PauseAtReloadTests: XCTestCase {
    /// After a look answered that the change waits for Reload, the agent's next edit ended its turn.
    func testAnyToolCallEndsAPausedTurn() {
        XCTAssertTrue(Store.endsAgent(asked: false, paused: true, before: "Edit"))
        XCTAssertTrue(Store.endsAgent(asked: false, paused: true, before: "mcp__lamp__look_at_app"))
        XCTAssertTrue(Store.endsAgent(asked: false, paused: true, before: "ask"))
    }

    /// Asking still ends the turn at the first call that isn't the ask itself, as before.
    func testAskingEndsTheTurnAtTheNextOtherCall() {
        XCTAssertFalse(Store.endsAgent(asked: true, paused: false, before: "ask"))
        XCTAssertTrue(Store.endsAgent(asked: true, paused: false, before: "write"))
        XCTAssertFalse(Store.endsAgent(asked: false, paused: false, before: "write"))
    }

    /// Lamp's own request to carry on, and anything the person types behind it, waits while the change is held from
    /// the app, and goes once it's in. A queue the person started themselves isn't held.
    func testTheQueueWaitsForTheHeldChange() {
        let carryOn = QueuedMessage(text: Agent.afterReload, byLamp: true, afterReload: true)
        let typed = QueuedMessage(text: "Make the shelves darker")
        XCTAssertFalse(Store.startsNow([carryOn, typed], changeHeld: true))
        XCTAssertTrue(Store.startsNow([carryOn, typed], changeHeld: false))
        XCTAssertTrue(Store.startsNow([typed], changeHeld: true))
        XCTAssertTrue(Store.startsNow([], changeHeld: true))
    }

    /// The chat draws the person's waiting message, never Lamp's own: the Reload line stands for that one.
    func testOnlyThePersonsMessagesAreDrawnWaiting() {
        let carryOn = QueuedMessage(text: Agent.afterReload, byLamp: true, afterReload: true)
        let typed = QueuedMessage(text: "Make the shelves darker")
        XCTAssertEqual(Talk.drawnWaiting([carryOn, typed], in: []).map(\.id), [typed.id])
    }
}

extension PauseAtReloadTests {
    /// The paused queue outlives a Lamp relaunch, as the held build it waits for does: Lamp's own request keeps its
    /// flags through the saved form, and a queue with one in it is kept even once setup is done, while an ordinary
    /// queue is kept only while setup isn't.
    func testThePausedQueueIsKeptAcrossARelaunch() {
        let carryOn = QueuedMessage(text: Agent.afterReload, byLamp: true, afterReload: true)
        let typed = QueuedMessage(text: "Make the shelves darker")
        let back = QueuedMessage(saved: carryOn.saved, attachments: [])
        XCTAssertTrue(back.afterReload)
        XCTAssertTrue(back.byLamp)
        XCTAssertEqual(back.text, Agent.afterReload)
        XCTAssertFalse(QueuedMessage(saved: typed.saved, attachments: []).afterReload)
        XCTAssertTrue(Store.keptAcrossRelaunch([carryOn, typed], setupReady: true))
        XCTAssertFalse(Store.keptAcrossRelaunch([typed], setupReady: true))
        XCTAssertTrue(Store.keptAcrossRelaunch([typed], setupReady: false))
        XCTAssertFalse(Store.keptAcrossRelaunch([], setupReady: false))
    }
}
