import XCTest
@testable import Lamp

/// A provider refusing a request for its size (the pictures in a conversation add up) is told from the context
/// window overflowing, which the engines handle themselves.
final class RequestTooLargeTests: XCTestCase {
    func testAnthropicsRefusalIsOne() {
        let text = #"413 {"type":"error","error":{"type":"invalid_request_error","message":"Downloaded image content cannot exceed 30MB","error_type":"payload_too_large"}}"#
        XCTAssertTrue(Agent.isRequestTooLarge(text))
    }

    func testClaudeCodesWordsForItAre() {
        XCTAssertTrue(Agent.isRequestTooLarge("Accumulated images and attachments in the conversation pushed the request over the limit. Remove older images or compact the conversation."))
    }

    func testOpenAIsIs() {
        XCTAssertTrue(Agent.isRequestTooLarge(#"{"error":{"message":"Request too large","code":"request_too_large"}}"#))
    }

    func testOtherFailuresArent() {
        XCTAssertFalse(Agent.isRequestTooLarge("prompt is too long: 213000 tokens > 200000 maximum"))
        XCTAssertFalse(Agent.isRequestTooLarge("429 rate limit exceeded"))
        XCTAssertFalse(Agent.isRequestTooLarge("Connection error."))
        XCTAssertFalse(Agent.isRequestTooLarge("request id gen-1791908413 failed"))
    }
}
