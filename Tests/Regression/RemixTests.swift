import XCTest
@testable import Lamp
import LampSidebarKit

/// The way back into Lamp from an app on a Mac without it: what the panel offers and where Continue with Lamp goes.
final class RemixTests: XCTestCase {
    func testTheRequestGoesToTheWishsPageOrToLampsSiteWithTheApp() throws {
        let linked = RemixOffer(name: "New York", about: "Explore Manhattan.", suggestions: [], shareLink: URL(string: "https://lamp.dev/w/AyTkit4xCc"))
        let url = try XCTUnwrap(RemixLink.url(for: linked, ask: "  Add a helicopter tour\n"))
        XCTAssertEqual(url.host, "lamp.dev")
        XCTAssertEqual(url.path, "/w/AyTkit4xCc")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "ask" }?.value, "Add a helicopter tour")
        // No link: a wish for an app like this one, then the change, to Lamp's site.
        let alone = RemixOffer(name: "New York", about: "Explore Manhattan.", suggestions: [], shareLink: nil)
        let site = try XCTUnwrap(RemixLink.url(for: alone, ask: "Add a helicopter tour"))
        XCTAssertEqual(site.path, "/")
        XCTAssertEqual(URLComponents(url: site, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "ask" }?.value,
                       "Make an app like New York: Explore Manhattan.\n\nThen: Add a helicopter tour")
        XCTAssertNil(RemixLink.url(for: alone, ask: "   "))
        // A starter or a wish on GitHub: Lamp's site with what to copy and the request as it is, even beside a Share Link.
        let starter = RemixOffer(name: "New York", about: nil, suggestions: [], shareLink: linked.shareLink, origin: .starter("newyork"))
        let copied = try XCTUnwrap(RemixLink.url(for: starter, ask: "Add a helicopter tour"))
        XCTAssertEqual(copied.absoluteString, "https://lamp.dev/?starter=newyork&ask=Add%20a%20helicopter%20tour")
        XCTAssertEqual(RemixOffer(name: "X", about: nil, suggestions: [], shareLink: nil).suggestions, RemixOffer.fallback)
    }

    func testSuggestionsAreThreeShortLinesOfTheModelsOwnWithSymbolsMacOSHas() {
        func ideas(_ json: String) -> [RemixIdea]? { RemixSuggestions.lines(from: json) }
        XCTAssertEqual(ideas(#"{"suggestions": [{"text": "Add a monthly view.", "symbol": "calendar"}, {"text": " Let me pin a park ", "symbol": "no.such.symbol"}, {"text": "Show sunrise times"}]}"#),
                       [RemixIdea(text: "Add a monthly view", symbol: "calendar"), RemixIdea(text: "Let me pin a park", symbol: "sparkles"),
                        RemixIdea(text: "Show sunrise times", symbol: "sparkles")])
        XCTAssertNil(ideas(#"{"suggestions": [{"text": "Only two"}, {"text": "lines"}]}"#))
        XCTAssertNil(ideas(#"{"suggestions": [{"text": "Same"}, {"text": "same"}, {"text": "Different"}]}"#), "no two alike")
        XCTAssertNil(ideas(#"{"suggestions": [{"text": "Add a weekly view"}, {"text": "Let me star the ones I love"}, {"text": "Make it remember the last search"}]}"#),
                     "the prompt's own examples handed back are no answer")
        XCTAssertNil(ideas("not json"))
        XCTAssertEqual(RemixIdea.from(plist: [["text": "Add a map", "symbol": "map"], ["text": "", "symbol": "x"], ["text": "Say it aloud"]]),
                       [RemixIdea(text: "Add a map", symbol: "map"), RemixIdea(text: "Say it aloud", symbol: "sparkles")])
    }
}
