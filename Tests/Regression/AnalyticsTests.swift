import XCTest
@testable import Lamp

/// Usage events are anonymous, in PostHog's capture shape, and an idea's words reach PostHog only when they're
/// Lamp's own.
final class AnalyticsTests: XCTestCase {
    func testPayloadIsAnonymousAndInCaptureShape() throws {
        let body = Analytics.payload(.appFirstRun, ["kind": "mac", "seconds": 42], id: "abc",
                                     at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(body["event"] as? String, "app_first_run")
        XCTAssertEqual(body["distinct_id"] as? String, "abc")
        XCTAssertEqual(body["timestamp"] as? String, "1970-01-01T00:00:00Z")
        let properties = try XCTUnwrap(body["properties"] as? [String: Any])
        XCTAssertEqual(properties["$process_person_profile"] as? Bool, false)
        XCTAssertEqual(properties["kind"] as? String, "mac")
        XCTAssertEqual(properties["seconds"] as? Int, 42)
        XCTAssertNotNil(properties["engine"])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(body))
    }

    func testInventedIdeasAreNotSentByName() {
        let builtIn = Ideas.pool[0]
        XCTAssertEqual(Analytics.idea(builtIn), builtIn.title)
        let invented = Idea(.everyday, "Plant Diary", "leaf", 0.3, "Notes on my plants")
        XCTAssertEqual(Analytics.idea(invented), "invented")
    }
}
