import XCTest
@testable import Lamp

/// A streamed act step's answer asked for again (`LiveSteps.follow`): the page can't say it got the reply carrying the
/// answer, so when that reply is lost it asks again for the same thing, and must get the same answer, billed once.
@MainActor final class LiveStepsRetryTests: XCTestCase {
    private let released: [[String: Any]] = [["id": "s1c1", "name": "addItem", "args": ["name": "Milk"]],
                                             ["id": "s1c2", "name": "addItem", "args": ["name": "Eggs"]]]
    private let held: [String: Any] = ["id": "s1c3", "name": "addItem", "args": ["name": "Tea"], "failed": "Not a tool."]
    private var grace = 0.0

    override func setUp() async throws { grace = LiveSteps.grace }
    override func tearDown() async throws { LiveSteps.grace = grace }

    private func finished(_ status: Int = 200, _ json: [String: Any]? = nil, cost: Double = 0.25) -> String {
        let (id, step) = LiveSteps.start(until: Date().addingTimeInterval(600))
        for call in released { step.add(call) }
        step.finish((status, json ?? ["reply": "", "ask": false, "calls": [held]], cost))
        return id
    }

    private func ids(_ json: [String: Any]) -> [String] { (json["calls"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String } }

    func testTheSameFollowAskedAgainGetsTheSameAnswerBilledOnce() async {
        let id = finished()
        let (status, json, cost) = await LiveSteps.follow(id, have: 2)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(ids(json), ["s1c3"])
        XCTAssertEqual(cost, 0.25)
        // The reply above lost on the way: the page asks again for just what it asked before.
        let (again, retried, billed) = await LiveSteps.follow(id, have: 2)
        XCTAssertEqual(again, 200)
        XCTAssertEqual(retried["more"] as? Bool, false)
        XCTAssertEqual(ids(retried), ["s1c3"])
        XCTAssertEqual(retried["cost"] as? Double, 0.25, "the page's turn still learns what the step cost")
        XCTAssertEqual(billed, 0, "Lamp bills it once")
    }

    func testEachHaveGetsTheCallsAfterIt() async {
        let id = finished()
        _ = await LiveSteps.follow(id, have: 2)
        let (status, json, _) = await LiveSteps.follow(id, have: 0)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(ids(json), ["s1c1", "s1c2", "s1c3"])
        let (_, one, _) = await LiveSteps.follow(id, have: 1)
        XCTAssertEqual(ids(one), ["s1c2", "s1c3"])
    }

    func testTwoFollowsEndingTogetherBillOnce() async {
        let (id, step) = LiveSteps.start(until: Date().addingTimeInterval(600))
        step.add(released[0])
        async let a = LiveSteps.follow(id, have: 1)
        async let b = LiveSteps.follow(id, have: 1)
        try? await Task.sleep(for: .milliseconds(300))
        step.finish((200, ["reply": "Added Milk.", "ask": false], 0.25))
        let (first, second) = await (a, b)
        XCTAssertEqual([first.0, second.0], [200, 200])
        XCTAssertEqual(first.2 + second.2, 0.25, accuracy: 1e-9)
        XCTAssertEqual(first.1["cost"] as? Double, 0.25)
        XCTAssertEqual(second.1["cost"] as? Double, 0.25)
    }

    func testAFailedStepIsAskedForAgainTheSameWay() async {
        let id = finished(502, ["error": "The AI didn't answer."], cost: 0.1)
        let (status, _, cost) = await LiveSteps.follow(id, have: 2)
        let (again, json, billed) = await LiveSteps.follow(id, have: 2)
        XCTAssertEqual([status, again], [502, 502])
        XCTAssertEqual(json["error"] as? String, "The AI didn't answer.")
        XCTAssertEqual(json["cost"] as? Double, 0.1)
        XCTAssertEqual([cost, billed], [0.1, 0])
    }

    func testAnAnsweredStepIsKeptThroughItsTimeWhenOthersStart() async throws {
        let (id, step) = LiveSteps.start(until: Date().addingTimeInterval(600))
        step.finish((200, ["reply": "Done.", "ask": false], 0))
        _ = await LiveSteps.follow(id, have: 0)
        // Answered over two minutes ago and followed by nobody for longer than an unanswered step is kept, but still
        // inside the step's time: another step starting doesn't let it go.
        step.answered = Date().addingTimeInterval(-130)
        step.seen = Date().addingTimeInterval(-400)
        _ = LiveSteps.start(until: Date().addingTimeInterval(60))
        let (status, _, _) = await LiveSteps.follow(id, have: 0)
        XCTAssertEqual(status, 200)
    }

    func testAnAnsweredStepIsLetGoOnceItsTimeIsUpWithNothingElseHappening() async throws {
        LiveSteps.grace = 0.5
        let (id, step) = LiveSteps.start(until: Date())
        step.finish((200, ["reply": "Done.", "ask": false], 0))
        _ = await LiveSteps.follow(id, have: 0)
        let (kept, _, _) = await LiveSteps.follow(id, have: 0)
        XCTAssertEqual(kept, 200, "kept a little past its time")
        try await Task.sleep(for: .seconds(1))
        let (status, json, _) = await LiveSteps.follow(id, have: 0)
        XCTAssertEqual(status, 404)
        XCTAssertEqual(json["error"] as? String, "This step is over.")
    }
}
