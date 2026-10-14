import XCTest
@testable import Lamp

/// A task in the person's other apps ends at its limit, whatever it is waiting on: a task that ran on would
/// go on spending the person's money.
final class ComputerUseRouteTests: XCTestCase {
    /// A call still in flight when the task passes its limit is cut off there, not waited for.
    func testWorkInFlightAtTheLimitIsCutOff() async {
        let began = Date()
        var cut = false
        do {
            _ = try await ComputerUse.within({ Date().timeIntervalSince(began) > 0.2 ? ComputerUse.tookTooLong : nil },
                                             every: .milliseconds(50), cut: { cut = true }) {
                try await Task.sleep(for: .seconds(30))
                return "late"
            }
            XCTFail("The work should not have finished.")
        } catch {
            XCTAssertEqual(error.localizedDescription, ComputerUse.tookTooLong.message)
        }
        XCTAssertTrue(cut)
        XCTAssertLessThan(Date().timeIntervalSince(began), 5)
    }

    /// Some of what a task waits on can't be cancelled (a browser's AppleScript): the limit doesn't wait for it.
    func testTheLimitDoesNotWaitForWorkThatCannotBeCancelled() async {
        let began = Date()
        do {
            _ = try await ComputerUse.within({ Date().timeIntervalSince(began) > 0.2 ? ComputerUse.tookTooLong : nil },
                                             every: .milliseconds(50)) {
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 4) { done.resume() }
                }
                return "late"
            }
            XCTFail("The work should not have been waited for.")
        } catch {
            XCTAssertEqual(error.localizedDescription, ComputerUse.tookTooLong.message)
        }
        XCTAssertLessThan(Date().timeIntervalSince(began), 2)
    }
}
