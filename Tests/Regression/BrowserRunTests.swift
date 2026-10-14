import XCTest
@testable import Lamp

/// What an app built from a shown task may do on a site without asking: looking around goes ahead, anything
/// that does something waits for the person, and some things are never done for them.
@MainActor
final class BrowserRunTests: XCTestCase {
    private let site = "https://openlibrary.org"

    private func control(_ kind: String, _ name: String, _ change: (inout BrowserRun.Control) -> Void = { _ in }) -> BrowserRun.Control {
        var control = BrowserRun.Control()
        control.kind = kind
        control.name = name
        change(&control)
        return control
    }

    func testSendingBuyingAndDeletingAsk() {
        for name in ["Send", "Send message", "Buy now", "Place order", "Delete", "Delete account", "Borrow", "Post reply",
                     "Save The secret garden to your reading log", "Want to Read", "Pay $12", "Remove from list"] {
            XCTAssertEqual(BrowserRun.verdict(click: control("button", name), site: site), .ask, name)
        }
    }

    func testALinkThatDoesSomethingAsksToo() {
        XCTAssertEqual(BrowserRun.verdict(click: control("link", "Delete this list") { $0.href = "https://openlibrary.org/lists/1/delete" }, site: site), .ask)
        XCTAssertEqual(BrowserRun.verdict(click: control("link", "Log out") { $0.href = "https://openlibrary.org/account/logout" }, site: site), .ask)
    }

    func testLookingAroundGoesAhead() {
        XCTAssertEqual(BrowserRun.verdict(click: control("link", "Vegetable Gardening For Dummies") { $0.href = "https://openlibrary.org/works/OL1W" }, site: site), .free)
        XCTAssertEqual(BrowserRun.verdict(click: control("switch", "Readable Only 6,347"), site: site), .free)
        XCTAssertEqual(BrowserRun.verdict(click: control("box", "English"), site: site), .free)
        XCTAssertEqual(BrowserRun.verdict(click: control("button", "Language") { $0.opener = true }, site: site), .free)
        XCTAssertEqual(BrowserRun.verdict(click: control("button", "Search"), site: site), .free)
        XCTAssertEqual(BrowserRun.verdict(click: control("button", "See all 6,154 books"), site: site), .free)
        XCTAssertEqual(BrowserRun.verdict(click: control("button", "2"), site: site), .free)
    }

    func testAButtonLampCannotPlaceAsks() {
        XCTAssertEqual(BrowserRun.verdict(click: control("button", "Continue"), site: site), .ask)
        XCTAssertEqual(BrowserRun.verdict(click: control("button", "OK"), site: site), .ask)
        XCTAssertEqual(BrowserRun.verdict(click: control("button", ""), site: site), .ask)
    }

    func testAFormIsSentFreelyOnlyWhenItSearches() {
        XCTAssertEqual(BrowserRun.verdict(click: control("button", "Go") { $0.submit = true; $0.method = "get" }, site: site), .free)
        XCTAssertEqual(BrowserRun.verdict(click: control("button", "Go") { $0.submit = true; $0.method = "post" }, site: site), .ask)
        XCTAssertEqual(BrowserRun.verdict(returnIn: control("field", "Search") { $0.search = true }), .free)
        XCTAssertEqual(BrowserRun.verdict(returnIn: control("field", "Message") { $0.method = "post" }), .ask)
        XCTAssertEqual(BrowserRun.verdict(returnIn: control("field", "Message")), .ask)
    }

    func testLeavingTheSiteAndPasswordsAreRefused() {
        guard case .refuse = BrowserRun.verdict(click: control("link", "Internet Archive") { $0.href = "https://archive.org/" }, site: site) else {
            return XCTFail("A link to another site must be refused")
        }
        guard case .refuse = BrowserRun.verdict(click: control("field", "Password") { $0.password = true }, site: site) else {
            return XCTFail("A password field must be refused")
        }
        guard case .refuse = BrowserRun.verdict(returnIn: control("field", "Password") { $0.password = true }) else {
            return XCTFail("Return in a password field must be refused")
        }
    }
}
