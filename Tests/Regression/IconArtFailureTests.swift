import XCTest
@testable import Lamp

/// Icon artwork that can't be drawn says why and what to do. A picture model that was busy left the chat
/// with "The operation couldn't be completed. (Lamp.AppAI.Failure error 1.)", though the key and the
/// account were fine.
final class IconArtFailureTests: XCTestCase {
    func testAFailureShownAsAnyErrorShowsItsMessage() {
        let error: Error = AppAI.Failure(message: "The image model didn't return a picture.")
        XCTAssertEqual(error.localizedDescription, "The image model didn't return a picture.")
    }

    func testTheChatSaysWhatHappenedAndWhatToDo() {
        let busy = AppAI.Failure(message: AppAI.imageModelBusy("google/gemini-nano-banana-2.1"))
        XCTAssertEqual(Icons.artFailed(busy), "Couldn't draw the icon's artwork. Nano Banana 2.1 is busy right now. "
            + "Try again in a minute, or pick another picture model in Lamp → Settings (⌘,).")
        XCTAssertFalse(Icons.artFailed(busy).contains("AppAI"))
        XCTAssertFalse(Icons.artFailed(busy).contains("credit"), "the account is fine: it's the model that's busy")
    }
}
