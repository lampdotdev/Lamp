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
}
