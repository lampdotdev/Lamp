import XCTest
import AppKit
@testable import Lamp

/// A wish written on lamp.dev reaches Lamp by its link or, on a first open, by the clipboard. Lamp takes from
/// the clipboard only what carries its mark, never makes macOS ask about it, and a link's words are tidied
/// and cut to size, since any web page can open one.
final class WishTests: XCTestCase {
    private let wish = "A Mac app that watches my Downloads folder and suggests a clear name for each new file."

    // What each browser really left on the clipboard for the site's copy (macOS 26.6, a test page).
    private var safari: String {
        "<span data-lamp-wish=\"1\" style=\"caret-color: rgb(0, 0, 0); color: rgb(0, 0, 0); font-style: normal; white-space: normal;\">\(wish)</span>"
    }
    private var chrome: String {
        "<meta charset='utf-8'><html><head></head><body><span data-lamp-wish=\"1\">\(wish)</span></body></html>"
    }

    private func board(_ items: [NSPasteboard.PasteboardType: String]) -> NSPasteboard {
        let board = NSPasteboard.withUniqueName()
        board.declareTypes(Array(items.keys), owner: nil)
        for (type, value) in items { board.setString(value, forType: type) }
        addTeardownBlock { board.releaseGlobally() }
        return board
    }

    func testALinkCarriesTheWish() throws {
        let link = try XCTUnwrap(URL(string: "lamp://wish?text=A%20Mac%20app%20that%20sorts%20my%20files%20%26%20more.%0AAsk%20first."))
        XCTAssertEqual(Wish.from(link: link, scheme: "lamp"), "A Mac app that sorts my files & more.\nAsk first.")
    }

    func testOnlyThisLampsWishLinksCount() throws {
        XCTAssertNil(Wish.from(link: try XCTUnwrap(URL(string: "lamp://edit?app=tally")), scheme: "lamp"))
        XCTAssertNil(Wish.from(link: try XCTUnwrap(URL(string: "lamp-dev://wish?text=hello")), scheme: "lamp"))
        XCTAssertNil(Wish.from(link: try XCTUnwrap(URL(string: "lamp://wish")), scheme: "lamp"))
        XCTAssertNil(Wish.from(link: try XCTUnwrap(URL(string: "lamp://wish?text=%20%20")), scheme: "lamp"))
    }

    func testALinksWordsAreTidiedAndCut() throws {
        var parts = URLComponents()
        parts.scheme = "lamp"
        parts.host = "wish"
        parts.queryItems = [URLQueryItem(name: "text", value: "  one\u{0}\u{7}two\t" + String(repeating: "x", count: 9000))]
        let got = try XCTUnwrap(Wish.from(link: try XCTUnwrap(parts.url), scheme: "lamp"))
        XCTAssertTrue(got.hasPrefix("onetwox"))
        XCTAssertEqual(got.count, Wish.limit)
    }

    func testTheClipboardIsTakenOnlyWithLampsMark() {
        XCTAssertEqual(Wish.marked(html: safari, plain: wish), wish)
        XCTAssertEqual(Wish.marked(html: chrome, plain: wish), wish)
        // The same words copied from anywhere else, and anything with no web form at all, are left alone.
        XCTAssertNil(Wish.marked(html: "<span>\(wish)</span>", plain: wish))
        XCTAssertNil(Wish.marked(html: nil, plain: wish))
        XCTAssertNil(Wish.marked(html: safari, plain: "  "))
    }

    @MainActor func testLookingFindsAMarkedWishAndNothingElse() throws {
        // A private clipboard is always readable, as the real one is wherever macOS doesn't ask.
        XCTAssertEqual(Wish.look(at: board([.html: chrome, .string: wish])), .wish(wish))
        XCTAssertEqual(Wish.look(at: board([.html: "<b>a password</b>", .string: "a password"])), .nothing)
        XCTAssertEqual(Wish.look(at: board([.string: wish])), .nothing)
        XCTAssertEqual(Wish.look(at: board([:])), .nothing)
    }

    /// With Apple's developer switch for the clipboard question on, macOS 27.0.1 never answered whether a
    /// read would ask, and Lamp's welcome froze waiting for it (seen 2026-10-09). There Lamp no longer asks.
    @MainActor func testWhereMacOSNeverAnswersLampDoesNotAsk() throws {
        let suite = "lamp-wish-\(UUID().uuidString)"
        let settings = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { settings.removePersistentDomain(forName: suite) }
        let macOS27 = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)
        let macOS26 = OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 2)

        // As every Mac ships: asked, on either system.
        XCTAssertTrue(Wish.canAsk(system: macOS27, settings: settings))
        XCTAssertTrue(Wish.canAsk(system: macOS26, settings: settings))

        settings.set(true, forKey: Wish.questionSwitch)
        XCTAssertFalse(Wish.canAsk(system: macOS27, settings: settings))
        // On macOS 26 the switch answers at once and the Paste button works, so nothing changes there.
        XCTAssertTrue(Wish.canAsk(system: macOS26, settings: settings))

        // Not asking means nothing is taken and nothing offered, even with a wish waiting.
        let waiting = board([.html: chrome, .string: wish])
        XCTAssertEqual(Wish.look(at: waiting, canAsk: false), .nothing)
        XCTAssertFalse(Wish.offersPaste(from: waiting, canAsk: false))
        XCTAssertEqual(Wish.look(at: waiting, canAsk: true), .wish(wish))
    }

    func testOnlyABrowsersCopyIsOfferedForPasting() {
        func type(_ name: String) -> NSPasteboard.PasteboardType { NSPasteboard.PasteboardType(name) }
        XCTAssertTrue(Wish.fromBrowser([.string, .html, type("com.apple.WebKit.custom-pasteboard-data")]))
        XCTAssertTrue(Wish.fromBrowser([.html, .string, type("org.chromium.source-url")]))
        XCTAssertFalse(Wish.fromBrowser([.string, .html, .rtf]))
    }

    func testTheWishIsWrittenInAWordAtATimeAndEndsWhole() {
        let text = "Sort my  files,\nthen ask."
        XCTAssertEqual(Wish.steps(text), ["Sort", "Sort my", "Sort my  files,", "Sort my  files,\nthen", text])
        XCTAssertEqual(Wish.steps("One"), ["One"])
        // A long wish is written faster, so it never takes more than a moment.
        XCTAssertLessThanOrEqual(Wish.pace(words: 400) * 400, .seconds(4))
        XCTAssertEqual(Wish.pace(words: 10), .milliseconds(45))
    }
}
