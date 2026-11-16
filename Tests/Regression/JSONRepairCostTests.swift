import XCTest
@testable import Lamp

/// An app's AI call whose JSON reply doesn't parse is asked again once. Both tries are billed, so when the second
/// fails too, what the app is told it spent, and what Lamp records, is both charges.
final class JSONRepairCostTests: XCTestCase {
    /// A paid reply that isn't JSON, then a paid second try that fails: the failure carries both charges, and keeps
    /// what the second try said.
    func testAFailedRepairCarriesBothCharges() async {
        var asked: [String] = []
        do {
            _ = try await AppAI.repairingJSON(("{\"cut off", 0.10), prompt: "List the shelves", deadline: Date().addingTimeInterval(60)) { again, _ in
                asked.append(again)
                throw AppAI.Failure(message: "The reply was cut off.", cost: 0.60, needs: .text)
            }
            XCTFail("a failed repair answered")
        } catch let failure as AppAI.Failure {
            XCTAssertEqual(failure.cost, 0.70, accuracy: 1e-9)
            XCTAssertEqual(failure.message, "The reply was cut off.")
            XCTAssertEqual(failure.needs, .text)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(asked.count, 1)
        XCTAssertTrue(asked.first?.hasPrefix("List the shelves") ?? false)
    }

    /// A paid second try that answers in JSON returns both charges with the answer.
    func testARepairThatAnswersCountsBothCharges() async throws {
        let (reply, cost) = try await AppAI.repairingJSON(("not json", 0.10), prompt: "List the shelves", deadline: Date().addingTimeInterval(60)) { _, _ in
            ("```json\n{\"shelves\": 3}\n```", 0.60)
        }
        XCTAssertEqual(reply, "{\"shelves\": 3}")
        XCTAssertEqual(cost, 0.70, accuracy: 1e-9)
    }
}
