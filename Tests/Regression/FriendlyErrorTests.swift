import XCTest
@testable import Lamp

/// A failed AI call is put down to what it went through. An app's AI, pictures and decisions each have their
/// own route, so naming whatever builds apps sent people to check a sign-in they had never used.
final class FriendlyErrorTests: XCTestCase {
    private var savedEngine: String?

    override func setUp() {
        savedEngine = UserDefaults.standard.string(forKey: "engine")
        Builder.engine = .codex
    }

    override func tearDown() {
        UserDefaults.standard.set(savedEngine, forKey: "engine")
    }

    func testARefusedOpenRouterKeyIsNotPutDownToTheBuilder() {
        let message = Provider.friendlyError("401 No auth credentials found", from: Provider.openRouter)
        XCTAssertEqual(message, ErrorMessages.authenticationFailed("OpenRouter"))
        XCTAssertFalse(message.contains(Engine.codex.title))
    }

    func testAnEmptyOpenRouterAccountIsNotPutDownToTheBuilder() {
        let message = Provider.friendlyError("402 Insufficient credits", from: Provider.openRouter)
        XCTAssertEqual(message, ErrorMessages.quotaExceeded("OpenRouter"))
    }

    func testASignInThatFailedIsNamedWhateverBuildsApps() {
        Builder.engine = .pi
        XCTAssertEqual(Provider.friendlyError("401 Unauthorized", from: Provider.name(of: .codex)),
                       ErrorMessages.authenticationFailed(Engine.codex.title))
        XCTAssertEqual(Provider.friendlyError("401 Unauthorized", from: Provider.name(of: .claude)),
                       ErrorMessages.authenticationFailed(Engine.claude.title))
    }

    /// A picture model with no room answered 429 "You exceeded your current quota…": the status says busy,
    /// and the person, whose account was fine, was about to be told to top it up.
    func testAStatusSaysWhatKindOfFailureItWasWhateverTheWordsSay() {
        let busy = Provider.friendlyError(status: 429, "You exceeded your current quota, please check your plan and billing details.",
                                          from: Provider.openRouter)
        XCTAssertEqual(busy, ErrorMessages.providerBusy)
        XCTAssertEqual(Provider.friendlyError(status: 402, "Insufficient credits", from: Provider.openRouter),
                       ErrorMessages.quotaExceeded("OpenRouter"))
        XCTAssertEqual(Provider.friendlyError(status: 401, "No auth credentials found", from: Provider.openRouter),
                       ErrorMessages.authenticationFailed("OpenRouter"))
    }

    func testAStatusThatDoesNotSayLeavesItToTheWords() {
        XCTAssertEqual(Provider.friendlyError(status: 400, "Rate limit reached", from: Provider.openRouter), ErrorMessages.providerBusy)
        XCTAssertEqual(Provider.friendlyError(status: 500, "Internal error", from: Provider.openRouter),
                       ErrorMessages.aiFailed("500 Internal error"))
    }

    /// It was shown as "The operation couldn't be completed. (Lamp.AppAI.Failure error 1.)" wherever a
    /// failed call was reported as any other error (an icon's artwork, for one).
    func testAFailedCallShownAsAnyErrorShowsItsOwnWords() {
        let error: Error = AppAI.Failure(message: ErrorMessages.providerBusy)
        XCTAssertEqual(error.localizedDescription, ErrorMessages.providerBusy)
    }
}
