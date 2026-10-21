import XCTest
@testable import Lamp

/// While the person is away Lamp presses a waiting Reload for them and, once the change is in and the agent's turn is
/// over, carries the agent on. These are the cases a review found going wrong: a Stop undone by a later Reload, a
/// Reload put off until the turn's end that lost its carry-on, and a later held change never reloaded because the
/// first one's mark stayed.
final class AwayReloadTests: XCTestCase {
    private let away = AwayReloads.after + 1

    /// The person pressed Stop with a change waiting: stepping away afterwards neither reloads for the agent nor
    /// starts it again, until they send a request of their own.
    func testAStopHoldsUntilThePersonAsksAgain() {
        var reloads = AwayReloads()
        _ = reloads.personStopped("app")
        XCTAssertEqual(reloads.toPress(waiting: ["app"], idle: away), [])
        XCTAssertFalse(reloads.carriesOn("app"))
        reloads.personAsked("app")
        XCTAssertEqual(reloads.toPress(waiting: ["app"], idle: away), ["app"])
        XCTAssertTrue(reloads.landed("app", stillWaits: false))
        XCTAssertTrue(reloads.carriesOn("app"))
    }

    /// Stop pressed after Lamp pressed Reload but before it went in: that Reload is given up, and when one lands
    /// anyway the agent isn't carried on.
    func testAStopAfterLampPressedGivesTheReloadBack() {
        var reloads = AwayReloads()
        XCTAssertEqual(reloads.toPress(waiting: ["app"], idle: away), ["app"])
        XCTAssertTrue(reloads.personStopped("app"))
        XCTAssertFalse(reloads.landed("app", stillWaits: false))
        XCTAssertFalse(reloads.carriesOn("app"))
    }

    /// Pressed while the turn still had the app, the Reload is put off until the turn's end; it's still Lamp's when
    /// it lands there, so the carry-on is decided then, and it isn't pressed twice meanwhile.
    func testAReloadPutOffToTheTurnsEndIsDecidedWhenItLands() {
        var reloads = AwayReloads()
        XCTAssertEqual(reloads.toPress(waiting: ["app"], idle: away), ["app"])
        XCTAssertEqual(reloads.toPress(waiting: ["app"], idle: away + 15), [])
        XCTAssertTrue(reloads.landed("app", stillWaits: false))
        XCTAssertTrue(reloads.carriesOn("app"))
        // The person's own Reload is no carry-on of Lamp's.
        XCTAssertFalse(reloads.landed("other", stillWaits: false))
    }

    /// A Reload that went in leaves no mark: a later change waiting for Reload, made before the next look round,
    /// is pressed in the same away stretch.
    func testALaterHeldChangeIsReloadedAfterOneThatWentIn() {
        var reloads = AwayReloads()
        XCTAssertEqual(reloads.toPress(waiting: ["app"], idle: away), ["app"])
        XCTAssertTrue(reloads.landed("app", stillWaits: false))
        XCTAssertEqual(reloads.toPress(waiting: ["app"], idle: away + 15), ["app"])
    }

    /// One that didn't go in isn't tried every few seconds, only again once the person has been back.
    func testAFailedReloadWaitsForThePersonToComeBack() {
        var reloads = AwayReloads()
        XCTAssertEqual(reloads.toPress(waiting: ["app"], idle: away), ["app"])
        XCTAssertFalse(reloads.landed("app", stillWaits: true))
        XCTAssertEqual(reloads.toPress(waiting: ["app"], idle: away + 15), [])
        XCTAssertEqual(reloads.toPress(waiting: ["app"], idle: 5), [])
        XCTAssertEqual(reloads.toPress(waiting: ["app"], idle: away), ["app"])
    }

    /// While the person is at the Mac nothing is pressed.
    func testNothingIsPressedWhileThePersonIsThere() {
        var reloads = AwayReloads()
        XCTAssertEqual(reloads.toPress(waiting: ["app"], idle: AwayReloads.after - 1), [])
    }
}
