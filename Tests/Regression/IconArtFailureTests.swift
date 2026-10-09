import XCTest
@testable import Lamp

/// Icon artwork that can't be drawn says why and what to do. A picture model that was busy left the chat
/// with "The operation couldn't be completed. (Lamp.AppAI.Failure error 1.)" and the app without artwork,
/// though the key was fine and the other models were drawing.
final class IconArtFailureTests: XCTestCase {
    func testAFailureShownAsAnyErrorShowsItsMessage() {
        let error: Error = AppAI.Failure(message: "The image model didn't return a picture.")
        XCTAssertEqual(error.localizedDescription, "The image model didn't return a picture.")
    }

    func testTheChatSaysWhatHappenedAndWhatToDo() {
        let busy = AppAI.Failure(message: AppAI.imageModelBusy("google/gemini-nano-banana-2.1"), busy: true)
        XCTAssertEqual(Icons.artFailed(busy), "Couldn't draw the icon's artwork. Nano Banana 2.1 is busy right now. "
            + "Try again in a minute, or pick another picture model in Lamp → Settings (⌘,).")
        XCTAssertFalse(Icons.artFailed(busy).contains("AppAI"))
    }

    func testABusyModelIsNotPutDownToThePersonsAccount() {
        XCTAssertTrue(AppAI.busyStatuses.contains(429))
        XCTAssertFalse(AppAI.busyStatuses.contains(402), "an empty account is the person's to top up")
        XCTAssertFalse(AppAI.busyStatuses.contains(401))
    }

    func testAnotherModelDrawsWhileTheChosenOneIsBusy() {
        let first = Icons.artModels[0].id
        XCTAssertEqual(Icons.standIn(for: "google/gemini-nano-banana-2.1"), first)
        XCTAssertEqual(Icons.standIn(for: first), Icons.artModels.last?.id)
        XCTAssertNotEqual(Icons.standIn(for: first), first)
        for model in Icons.artModels {
            let other = Icons.artModels.first { $0.id == Icons.standIn(for: model.id) }
            XCTAssertFalse(other?.label.contains("pricier") ?? true, "\(model.id) must not fall to a pricier model")
        }
        XCTAssertNil(Icons.standIn(for: Icons.localArt))
    }
}
