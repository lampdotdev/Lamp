import XCTest
@testable import Lamp

/// The sidebar rule is in a Mac app's prompt exactly while Apps in Chrome is on, including after it's switched
/// while Lamp runs (the prompt was once made once and kept).
final class BrowserPromptTests: XCTestCase {
    override func tearDown() { BrowserBridge.testOverride = nil }

    func testTheMacPromptFollowsTheSwitch() {
        let rule = "Declare it in `browser.json`"
        BrowserBridge.testOverride = false
        XCTAssertFalse(Agent.systemPrompt.contains(rule))
        BrowserBridge.testOverride = true
        XCTAssertTrue(Agent.systemPrompt.contains(rule))
        XCTAssertTrue(Agent.universalPrompt(for: .iphone).contains(rule))
        BrowserBridge.testOverride = false
        XCTAssertFalse(Agent.systemPrompt.contains(rule))
        XCTAssertFalse(Agent.universalPrompt(for: .iphone).contains(rule))
    }
}
