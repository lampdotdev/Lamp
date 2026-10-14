import XCTest
@testable import Lamp

/// Chats from before the icon's own setup card still open, with their picture cards about pictures.
final class IconsByHandTests: XCTestCase {
    func testACardFromBeforeIsNotAboutTheIcon() throws {
        let saved = #"{"id":"6F1C8E2A-3B9D-4C1E-9A7F-2D5B8E0C4A12","kind":"offer","text":"Recipe Box just tried to make a picture.","offer":{"capability":"pictures"}}"#
        let line = try JSONDecoder().decode(LogLine.self, from: Data(saved.utf8))
        XCTAssertNil(line.setupOffer?.icon)
    }
}
