import XCTest
@testable import Lamp

/// A result card saved before there were rows for what's new still reads.
final class TalkTests: XCTestCase {
    func testAnEarlierResultStillReads() throws {
        let saved = Data(#"{"summary":"Done","guesses":[]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(Talk.Result.self, from: saved).news)
    }
}
