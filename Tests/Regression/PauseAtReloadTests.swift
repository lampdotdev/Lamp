import XCTest
@testable import Lamp

/// An agent whose change waits for Reload goes on with what's left, but a look after it has been told, or any
/// `use_app`, is it asking to see an app that doesn't show its change: the turn stops there (`Store.pause`), is over
/// at its next tool call, and carries on only once the change is in. One run went on for eleven minutes and a hundred
/// tool calls after a look said its change waited for Reload, then said the result was in; the rules here are what
/// hold that to a stop and a sentence, the same for every engine.
@MainActor
final class PauseAtReloadTests: XCTestCase {
    /// The first look that finds the change held tells the agent and lets it go on; the next look stops it, and
    /// `use_app` stops it at once, since nothing can be tried in an app that doesn't show the change.
    func testALookAfterBeingToldStopsTheTurnAndUseAppAlwaysDoes() {
        XCTAssertFalse(Store.stopsToSee(told: false, using: false))
        XCTAssertTrue(Store.stopsToSee(told: true, using: false))
        XCTAssertTrue(Store.stopsToSee(told: false, using: true))
    }

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
        // What a message points at ("Make this darker") comes back with it, picture and all, while the picture is there.
        let picture = FileManager.default.temporaryDirectory.appendingPathComponent("pointed-\(UUID().uuidString).png")
        FileManager.default.createFile(atPath: picture.path, contents: Data([0x89, 0x50]))
        defer { try? FileManager.default.removeItem(at: picture) }
        let pointing = QueuedMessage(text: "Make this darker",
                                     pointed: PointedAt(title: "Shelf title", detail: "The Hot Shelf", picture: picture.path))
        let pointedBack = QueuedMessage(saved: pointing.saved, attachments: [])
        XCTAssertEqual(pointedBack.pointed?.title, "Shelf title")
        XCTAssertEqual(pointedBack.pointed?.detail, "The Hot Shelf")
        XCTAssertEqual(pointedBack.pointed?.url, picture)
        try? FileManager.default.removeItem(at: picture)
        XCTAssertNil(QueuedMessage(saved: pointing.saved, attachments: []).pointed)
        XCTAssertTrue(Store.keptAcrossRelaunch([carryOn, typed], setupReady: true))
        XCTAssertFalse(Store.keptAcrossRelaunch([typed], setupReady: true))
        XCTAssertTrue(Store.keptAcrossRelaunch([typed], setupReady: false))
        XCTAssertFalse(Store.keptAcrossRelaunch([], setupReady: false))
    }
}
