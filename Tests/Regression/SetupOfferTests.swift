import XCTest
@testable import Lamp

/// Setup offers in an app's chat name their capability. Chats from before that kept a key card, which was
/// always about pictures, and must still open as one.
final class SetupOfferTests: XCTestCase {
    func testAnOlderKeyCardIsAPictureOffer() throws {
        let saved = #"{"id":"6F1C8E2A-3B9D-4C1E-9A7F-2D5B8E0C4A11","kind":"needsKey","text":"Recipe Box wants to make a picture, and nothing here can yet."}"#
        let line = try JSONDecoder().decode(LogLine.self, from: Data(saved.utf8))
        XCTAssertEqual(line.setupOffer, SetupOffer(capability: .pictures))
        XCTAssertEqual(line.setupOffer?.context, .mac)
    }

    func testAnOfferKeepsItsCapabilityAndPlace() throws {
        let line = LogLine(kind: .offer, text: "Works on your phone anywhere with a key.", offer: SetupOffer(capability: .text, away: true))
        let read = try JSONDecoder().decode(LogLine.self, from: JSONEncoder().encode(line))
        XCTAssertEqual(read.setupOffer, SetupOffer(capability: .text, away: true))
        XCTAssertEqual(read.setupOffer?.context, .phoneAway)
    }

    func testOtherLinesOfferNothing() {
        XCTAssertNil(LogLine(kind: .agent, text: "Done.").setupOffer)
        // A stray capability on another kind of line isn't an offer.
        XCTAssertNil(LogLine(kind: .status, text: "Ready", offer: SetupOffer(capability: .pictures)).setupOffer)
    }
}
