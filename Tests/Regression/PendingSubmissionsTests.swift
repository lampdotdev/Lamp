import XCTest
@testable import Lamp

final class PendingSubmissionsTests: XCTestCase {
    func testReturningToAChatCannotClaimItsPendingSendAgain() throws {
        var state = PendingSubmissions()
        let firstViewToken = try XCTUnwrap(state.begin("phone-app"))
        // A newly-created view reads the same store-owned state.
        XCTAssertTrue(state.contains("phone-app"))
        XCTAssertNil(state.begin("phone-app"))
        state.end(firstViewToken)
        XCTAssertNotNil(state.begin("phone-app"))
    }

    func testRescaffoldMovesOwnershipAndOriginalTokenStillReleasesIt() throws {
        var state = PendingSubmissions()
        let token = try XCTUnwrap(state.begin("untitled"))
        state.move(from: "untitled", to: "renamed")
        XCTAssertFalse(state.contains("untitled"))
        XCTAssertTrue(state.contains("renamed"))
        XCTAssertNil(state.begin("renamed"))
        state.end(token)
        XCTAssertFalse(state.contains("renamed"))
    }

    func testFinishingOneChatDoesNotUnlockAnotherChat() throws {
        var state = PendingSubmissions()
        let first = try XCTUnwrap(state.begin("first"))
        _ = try XCTUnwrap(state.begin("second"))
        state.end(first)
        XCTAssertFalse(state.contains("first"))
        XCTAssertTrue(state.contains("second"))
    }
}
