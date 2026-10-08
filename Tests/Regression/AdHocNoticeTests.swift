import XCTest
@testable import Lamp

/// An app Lamp could only sign ad hoc works, but macOS forgets its permissions at every build. The chat says
/// so once, not after each build.
final class AdHocNoticeTests: XCTestCase {
    func testAChatIsToldOnce() {
        var lines = [LogLine(kind: .user, text: "A timer"), LogLine(kind: .status, text: "Timer is ready")]
        XCTAssertTrue(AppSigning.needsAdHocNotice(after: lines))
        lines.append(LogLine(kind: .status, text: AppSigning.adHocNotice(for: "Timer")))
        XCTAssertFalse(AppSigning.needsAdHocNotice(after: lines))
    }

    func testARenamedAppIsNotToldAgain() {
        let lines = [LogLine(kind: .status, text: AppSigning.adHocNotice(for: "Untitled"))]
        XCTAssertFalse(AppSigning.needsAdHocNotice(after: lines))
        XCTAssertNotEqual(AppSigning.adHocNotice(for: "Timer"), AppSigning.adHocNotice(for: "Untitled"))
    }

    /// Someone quoting the line back to the agent hasn't been told by Lamp.
    func testOnlyLampsOwnLineCounts() {
        let lines = [LogLine(kind: .user, text: "Why does it say: " + AppSigning.adHocNotice(for: "Timer"))]
        XCTAssertTrue(AppSigning.needsAdHocNotice(after: lines))
    }
}
