import XCTest
@testable import Lamp

/// Settings saves a key only once OpenRouter has had its say: a key it refuses is turned away, and one it
/// couldn't be asked about is not, so being offline never stops a good key being saved.
final class KeyVerdictTests: XCTestCase {
    func testAKeyOpenRouterRefusesIsTurnedAway() {
        for status in [401, 403] {
            XCTAssertEqual(SetupView.verdict(status: status, body: Data()),
                           .refused("OpenRouter didn't accept that key. Copy it again from openrouter.ai/keys."))
        }
    }

    func testAKeyWithNoCreditLeftIsTurnedAway() {
        let body = Data(#"{"data": {"limit": 5, "limit_remaining": 0}}"#.utf8)
        guard case .refused(let why) = SetupView.verdict(status: 200, body: body) else { return XCTFail("saved") }
        XCTAssertTrue(why.contains("no credit left"))
    }

    func testAGoodKeyIsAccepted() {
        XCTAssertEqual(SetupView.verdict(status: 200, body: Data(#"{"data": {"limit_remaining": 4.2}}"#.utf8)), .accepted)
        // No spending limit set: OpenRouter sends null, which is not "nothing left".
        XCTAssertEqual(SetupView.verdict(status: 200, body: Data(#"{"data": {"limit_remaining": null}}"#.utf8)), .accepted)
    }

    func testOpenRouterBeingInTroubleIsNotTheKeysFault() {
        for status in [0, 429, 500, 503] {
            guard case .unchecked = SetupView.verdict(status: status, body: Data()) else {
                return XCTFail("\(status) turned the key away")
            }
        }
    }
}
