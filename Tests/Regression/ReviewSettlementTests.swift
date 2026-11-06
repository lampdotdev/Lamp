import XCTest
@testable import Lamp

/// The AI's part of a shared app's review is settled only by the review that asked: a review that was cancelled or ran
/// out of time, and whose AI answers after the next review began, never puts its answer on the next review's sheet.
@MainActor final class ReviewSettlementTests: XCTestCase {
    /// Whether `task` has finished, after giving everything waiting on the main actor a chance to run.
    private func finished(_ done: () -> Bool) async -> Bool {
        for _ in 0..<20 { await Task.yield() }
        return done()
    }

    private func lateAnswerLeavesTheNextReviewAlone(stop: (ReviewSettlement<String>, UUID) -> Void) async {
        let settlement = ReviewSettlement<String>()
        let a = UUID(), b = UUID()
        let first = Task { await settlement.wait(for: a) }
        for _ in 0..<20 { await Task.yield() }
        stop(settlement, a)
        let firstOutcome = await first.value
        XCTAssertNil(firstOutcome, "the stopped review gets no answer")

        var secondDone = false
        let second = Task { () -> String? in
            let outcome = await settlement.wait(for: b)
            secondDone = true
            return outcome
        }
        for _ in 0..<20 { await Task.yield() }
        // The first review's AI answers late.
        settlement.settle("A's findings", for: a)
        let settledByA = await finished { secondDone }
        XCTAssertFalse(settledByA, "the first review's late answer settled the second review")
        settlement.settle("B's findings", for: b)
        let secondOutcome = await second.value
        XCTAssertEqual(secondOutcome, "B's findings")
    }

    func testACancelledReviewsLateAnswerLeavesTheNextOneWaiting() async {
        // Cancel, or a newer review, settles the one waiting with nothing.
        await lateAnswerLeavesTheNextReviewAlone { settlement, a in settlement.settle(nil, for: a) }
    }

    func testATimedOutReviewsLateAnswerLeavesTheNextOneWaiting() async {
        // The deadline settles it the same way while its AI goes on; then a newer review starts waiting.
        await lateAnswerLeavesTheNextReviewAlone { settlement, a in
            settlement.settle(nil, for: a)
            settlement.settle(nil, for: a)   // a second stop for the same review changes nothing
        }
    }

    func testAnAnswerBeforeTheWaitIsKeptForItsOwnReviewOnly() async {
        let settlement = ReviewSettlement<String>()
        let a = UUID(), b = UUID()
        settlement.settle("A's findings", for: a)
        let ownOutcome = await settlement.wait(for: a)
        XCTAssertEqual(ownOutcome, "A's findings")

        settlement.settle("A's findings", for: a)
        var done = false
        let other = Task { () -> String? in
            let outcome = await settlement.wait(for: b)
            done = true
            return outcome
        }
        let settledByA = await finished { done }
        XCTAssertFalse(settledByA, "an early answer of another review settled this one")
        settlement.settle(nil, for: b)
        let otherOutcome = await other.value
        XCTAssertNil(otherOutcome)
    }
}
