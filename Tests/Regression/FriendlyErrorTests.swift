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

    private func reply(_ message: String, code: Any? = nil, type: String? = nil) -> [String: Any] {
        var error: [String: Any] = ["message": message]
        error["code"] = code
        error["type"] = type
        return ["error": error]
    }

    /// A picture model with no room answered 429 "You exceeded your current quota…": the status says busy,
    /// and the person, whose account was fine, was about to be told to top it up.
    func testAStatusSaysWhatKindOfFailureItWasWhateverTheWordsSay() {
        let noRoom = reply("You exceeded your current quota, please check your plan and billing details.", code: 429)
        XCTAssertEqual(Provider.friendlyError(status: 429, reply: noRoom, from: Provider.openRouter), ErrorMessages.providerBusy)
        XCTAssertEqual(Provider.friendlyError(status: 402, reply: reply("Insufficient credits", code: 402), from: Provider.openRouter),
                       ErrorMessages.quotaExceeded("OpenRouter"))
        XCTAssertEqual(Provider.friendlyError(status: 401, reply: reply("No auth credentials found", code: 401), from: Provider.openRouter),
                       ErrorMessages.authenticationFailed("OpenRouter"))
    }

    /// OpenAI answers 429 for an empty account as well as for too many requests, and says which in the
    /// error's code. Waiting a minute fixes only one of them.
    func testAnEmptyAccountAnswering429IsNotToldToWait() {
        let empty = reply("You exceeded your current quota, please check your plan and billing details.",
                          code: "insufficient_quota", type: "insufficient_quota")
        XCTAssertEqual(Provider.friendlyError(status: 429, reply: empty, from: "OpenAI"), ErrorMessages.quotaExceeded("OpenAI"))
        XCTAssertEqual(Provider.friendlyError(status: 429, reply: reply("No more.", type: "insufficient_quota"), from: "OpenAI"),
                       ErrorMessages.quotaExceeded("OpenAI"))
        let tooFast = reply("Rate limit reached for requests", code: "rate_limit_exceeded", type: "requests")
        XCTAssertEqual(Provider.friendlyError(status: 429, reply: tooFast, from: "OpenAI"), ErrorMessages.providerBusy)
    }

    func testAReplyThatDoesNotSayLeavesItToTheWords() {
        XCTAssertEqual(Provider.friendlyError(status: 400, reply: reply("Rate limit reached"), from: Provider.openRouter), ErrorMessages.providerBusy)
        XCTAssertEqual(Provider.friendlyError(status: 500, reply: reply("Internal error"), from: Provider.openRouter),
                       ErrorMessages.aiFailed("500 Internal error"))
        XCTAssertEqual(Provider.friendlyError(status: 503, reply: [:], from: Provider.openRouter), ErrorMessages.aiFailed("503 HTTP 503"))
    }

    /// It was shown as "The operation couldn't be completed. (Lamp.AppAI.Failure error 1.)" wherever a
    /// failed call was reported as any other error (an icon's artwork, for one).
    func testAFailedCallShownAsAnyErrorShowsItsOwnWords() {
        let error: Error = AppAI.Failure(message: ErrorMessages.providerBusy)
        XCTAssertEqual(error.localizedDescription, ErrorMessages.providerBusy)
    }
}
