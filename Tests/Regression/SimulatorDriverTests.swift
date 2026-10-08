import XCTest
import ApplicationServices
@testable import Lamp

/// Driving the simulator's window from outside: Lamp never waits on it without a limit, and when the
/// iPhone's screen can't be used, the agent is told the reason that happened, in the words of the Xcode in use.
final class SimulatorDriverTests: XCTestCase {
    private typealias Trouble = Simulator.Driver.Trouble
    private let all: [Simulator.Driver.Trouble] = [.locked, .notOpen, .notAnswering, .noDevice, .notListed, .noWindow, .connecting, .unclear]

    private nonisolated static func onMainThread() -> Bool { Thread.isMainThread }
    private nonisolated static func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    func testReadingAnotherAppsWindowNeverHappensOnTheMainThread() async {
        let onMain = await Task { @AccessibilityActor in Self.onMainThread() }.value
        XCTAssertFalse(onMain)
    }

    func testAStuckAppIsWaitedOnOnceAndThenLeftAlone() async {
        await Task { @AccessibilityActor in
            let patience = Simulator.Driver.patience
            XCTAssertFalse(Simulator.Driver.notAnswering)
            // A call that fails at once is an app that quit or an element that's gone, not a stuck app.
            XCTAssertEqual(Simulator.Driver.call { .cannotComplete }, .cannotComplete)
            XCTAssertFalse(Simulator.Driver.notAnswering)
            // One that fails only after the whole wait is: nothing more is asked of it for a moment.
            _ = Simulator.Driver.call { Thread.sleep(forTimeInterval: patience * 0.8); return .cannotComplete }
            XCTAssertTrue(Simulator.Driver.notAnswering)
            var asked = 0
            let began = Date()
            for _ in 0..<400 { _ = Simulator.Driver.call { asked += 1; return .success } }
            XCTAssertEqual(asked, 0)
            XCTAssertLessThan(Date().timeIntervalSince(began), 0.5)
            // And then it's tried again, in case it came back.
            Self.pause(patience + 0.1)
            XCTAssertFalse(Simulator.Driver.notAnswering)
            XCTAssertEqual(Simulator.Driver.call { asked += 1; return .success }, .success)
            XCTAssertEqual(asked, 1)
        }.value
    }

    func testEveryReasonHasItsOwnWordsAndSaysNothingWasTapped() {
        let messages = all.map { $0.message(viewer: "Device Hub", device: "iPhone") }
        XCTAssertEqual(Set(messages).count, all.count)
        for message in messages {
            XCTAssertTrue(message.contains("Nothing was tapped") || message.contains("nothing was tapped"), message)
        }
    }

    func testTheReasonNamesTheAppThisXcodeHasAndTheDeviceBeingTried() {
        for trouble in all {
            let hub = trouble.message(viewer: "Device Hub", device: "iPad")
            XCTAssertFalse(hub.contains("Simulator"), hub)
            XCTAssertFalse(hub.contains("iPhone"), hub)
            XCTAssertFalse(trouble.message(viewer: "Simulator", device: "iPhone").contains("Device Hub"))
        }
        XCTAssertEqual(Simulator.viewerName(oneAtATime: true), "Device Hub")
        XCTAssertEqual(Simulator.viewerName(oneAtATime: false), "Simulator")
    }

    func testStillConnectingIsNotMistakenForAnAppThatIsNotOpen() {
        let connecting = Trouble.connecting.message(viewer: "Device Hub", device: "iPhone")
        XCTAssertTrue(connecting.contains("still connecting"))
        XCTAssertTrue(connecting.contains("Try again once"))
        XCTAssertTrue(connecting.contains("click another device in Device Hub's list"))
        XCTAssertTrue(Trouble.notOpen.message(viewer: "Device Hub", device: "iPhone").contains("isn't open"))
        XCTAssertTrue(Trouble.notListed.message(viewer: "Device Hub", device: "iPhone").contains("list of devices"))
    }

    func testTheSameScreenListedTwiceIsOnePlaceAndTwoPlacesAreRefused() {
        // Device Hub (Xcode 27.0) holds the screen twice, with one frame.
        let screen = CGRect(x: 750, y: 226, width: 187, height: 407)
        XCTAssertEqual(Simulator.Driver.places([screen, screen]), 1)
        XCTAssertEqual(Simulator.Driver.places([screen, screen.offsetBy(dx: 300, dy: 0)]), 2)
        XCTAssertEqual(Simulator.Driver.places([screen, screen.insetBy(dx: 20, dy: 43.5)]), 2)
    }

    func testARowsOwnActionsAreReadByTheNameAPersonSees() {
        // As Device Hub (Xcode 27.0) lists a row's swipe action beside the standard ones.
        XCTAssertEqual(Simulator.Driver.actionName("Name:Delete\nTarget:0x0\nSelector:(null)"), "Delete")
        XCTAssertNil(Simulator.Driver.actionName("AXPress"))
        XCTAssertNil(Simulator.Driver.actionName("AXScrollDownByPage"))
    }

    func testTheScreenIsTakenByItsShapeAtAnyZoom() {
        let iPhone = CGSize(width: 402, height: 874)
        XCTAssertTrue(Simulator.Driver.isShaped(CGRect(x: 300, y: 80, width: 402, height: 874), like: iPhone))
        XCTAssertTrue(Simulator.Driver.isShaped(CGRect(x: 300, y: 80, width: 281.4, height: 611.8), like: iPhone))
        XCTAssertFalse(Simulator.Driver.isShaped(CGRect(x: 0, y: 0, width: 900, height: 700), like: iPhone))
        XCTAssertFalse(Simulator.Driver.isShaped(CGRect(x: 0, y: 0, width: 20, height: 43.5), like: iPhone))
    }
}
