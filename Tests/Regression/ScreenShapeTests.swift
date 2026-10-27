import XCTest
@testable import Lamp

/// A screen fills whatever it's shown on, but one made before that is laid out at a fixed 1920x1080 and must still be
/// zoomed whole, or it would open cropped on every Mac and iPad it's on.
final class ScreenShapeTests: XCTestCase {
    func testFixedPagesAreToldApart() {
        XCTAssertTrue(ScreenKit.isFixed(TVTemplate.indexHTML))
        XCTAssertTrue(ScreenKit.isFixed(#"<META name='viewport' content="width = 1920">"#))
        XCTAssertFalse(ScreenKit.isFixed(ScreenKit.indexHTML))
        XCTAssertFalse(ScreenKit.isFixed("<html><body>No viewport</body></html>"))
    }

    func testShapesAreRead() {
        XCTAssertEqual(ScreenKit.shape("1920x1080"), CGSize(width: 1920, height: 1080))
        XCTAssertEqual(ScreenKit.shape(" 390 × 844 "), CGSize(width: 390, height: 844))
        XCTAssertNil(ScreenKit.shape("phone"))
        XCTAssertNil(ScreenKit.shape("100x100"))
    }

    /// iOS ends an app on the spot when its page asks for photos or calendars without the reason in its Info.plist; a
    /// screen also turns upright, where a game keeps to landscape.
    func testPageBuildsCarryReasonsAndScreensTurn() {
        for script in [GameKit.webBuildSh, ScreenKit.buildSh] {
            XCTAssertTrue(script.contains("{{USAGE}}") && script.contains("{{MAC_USAGE}}"))
        }
        XCTAssertTrue(ScreenKit.buildSh.contains("UIInterfaceOrientationPortrait"))
        XCTAssertFalse(GameKit.webBuildSh.contains("UIInterfaceOrientationPortrait"))
    }
}
