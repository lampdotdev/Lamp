import XCTest
@testable import Lamp

/// The note at the end of a look says only what Lamp saw: a launch it didn't watch isn't reported as an app that was
/// already open, and a long log is described without reading all of it.
final class EvidenceNoteTests: XCTestCase {
    /// A widget-only Mac app's first look opens its helper with no watch on it, and the helper may quit at once.
    func testAnUnwatchedOpeningIsntCalledAlreadyOpen() {
        let launch = Evidence.launch(watch: nil, opened: true, wentInLive: false, running: false)
        XCTAssertEqual(launch, .openedUnwatched)
    }

    func testAnAppNoLongerOpenIsntCalledAlreadyOpen() {
        XCTAssertNotEqual(Evidence.launch(watch: nil, opened: false, wentInLive: false, running: false), .alreadyOpen)
    }

    func testAChangeThatWentIntoTheOpenAppIsAlreadyOpen() {
        XCTAssertEqual(Evidence.launch(watch: nil, opened: true, wentInLive: true, running: true), .alreadyOpen)
    }

    /// An emulator's log has no size limit: the look reads only a bounded tail of it.
    func testALongLogIsReadOnlyAtItsEnd() {
        var asked: [Int?] = []
        let log = Evidence.log(size: 200_000_000) { last in
            asked.append(last)
            return Data(repeating: UInt8(ascii: "\n"), count: min(last ?? 200_000_000, 200_000_000))
        }
        XCTAssertTrue(asked.allSatisfy { ($0 ?? .max) <= 64 * 1024 }, "read \(asked)")
        XCTAssertEqual(log, .large(bytes: 200_000_000))
    }

    func testAShortLogIsCountedByLine() {
        let text = Data("one\ntwo\nthree\n".utf8)
        XCTAssertEqual(Evidence.log(size: text.count) { _ in text }, .lines(3))
        XCTAssertEqual(Evidence.log(size: 0) { _ in Data() }, .empty)
    }
}
