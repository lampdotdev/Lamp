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

    func testOnlyThisLampsWishLinksCount() throws {
        XCTAssertNil(Wish.from(link: try XCTUnwrap(URL(string: "lamp://edit?app=tally")), scheme: "lamp"))
        XCTAssertNil(Wish.from(link: try XCTUnwrap(URL(string: "lamp-dev://wish?text=hello")), scheme: "lamp"))
        XCTAssertNil(Wish.from(link: try XCTUnwrap(URL(string: "lamp://wish")), scheme: "lamp"))
        // The exact wish a link names, with its request: an https address only.
        let exact = Wish.exact(from: try XCTUnwrap(URL(string: "lamp://wish?file=https%3A%2F%2Ffiles.example%2Fw%2Fabc.lampapp&text=Add%20a%20map")), scheme: "lamp")
        XCTAssertEqual(exact, Wish.Exact(file: try XCTUnwrap(URL(string: "https://files.example/w/abc.lampapp")), text: "Add a map"))
        XCTAssertNil(Wish.exact(from: try XCTUnwrap(URL(string: "lamp://wish?file=http%3A%2F%2Ffiles.example%2Fabc.lampapp&text=x")), scheme: "lamp"))
        XCTAssertNil(Wish.exact(from: try XCTUnwrap(URL(string: "lamp://wish?file=file%3A%2F%2F%2Fetc%2Fpasswd")), scheme: "lamp"))
        XCTAssertNil(Wish.exact(from: try XCTUnwrap(URL(string: "lamp://wish?text=hello")), scheme: "lamp"))
        XCTAssertNil(Wish.from(link: try XCTUnwrap(URL(string: "lamp://wish?text=%20%20")), scheme: "lamp"))
    }

    func testARemixLinkNamesOnlyAStarterOrAGitHubRepository() throws {
        func remix(_ link: String) throws -> Wish.Remix? { Wish.remix(from: try XCTUnwrap(URL(string: link)), scheme: "lamp") }
        XCTAssertEqual(try remix("lamp://wish?starter=newyork&text=Make%20it%20snow"), Wish.Remix(from: .starter("newyork"), text: "Make it snow"))
        // A browser's form writes a space as "+", and "+" itself as "%2B".
        XCTAssertEqual(try remix("lamp://wish?starter=newyork&text=Snow+%2B+ice"), Wish.Remix(from: .starter("newyork"), text: "Snow + ice"))
        let repo = try XCTUnwrap(try remix("lamp://wish?repo=https%3A%2F%2Fgithub.com%2Flampdotdev%2Fnewyork&commit=ABC1234def&text=x"))
        XCTAssertEqual(repo.from, .repository(url: "https://github.com/lampdotdev/newyork", commit: "abc1234def"))
        XCTAssertEqual(repo.source, RepoImport.Source(owner: "lampdotdev", name: "newyork", ref: "abc1234def"))
        // Anything else that names an origin is refused, never taken for a plain wish.
        for bad in ["lamp://wish?starter=..%2Fetc&text=x", "lamp://wish?starter=New%20York", "lamp://wish?starter=a&repo=https%3A%2F%2Fgithub.com%2Fa%2Fb",
                    "lamp://wish?repo=http%3A%2F%2Fgithub.com%2Fa%2Fb", "lamp://wish?repo=https%3A%2F%2Fgitlab.com%2Fa%2Fb",
                    "lamp://wish?repo=https%3A%2F%2Fgithub.com%2Fa%2Fb%2Ftree%2Fmain", "lamp://wish?repo=github.com%2Fa%2Fb",
                    "lamp://wish?repo=https%3A%2F%2Fgithub.com%2Fa%2Fb&commit=--upload-pack%3Devil", "lamp://wish?starter=newyork&commit=abc1234"] {
            let url = try XCTUnwrap(URL(string: bad))
            XCTAssertTrue(Wish.isRemix(url, scheme: "lamp"), bad)
            XCTAssertNil(Wish.remix(from: url, scheme: "lamp"), bad)
        }
        XCTAssertFalse(Wish.isRemix(try XCTUnwrap(URL(string: "lamp://wish?text=hello")), scheme: "lamp"))
        XCTAssertNil(try remix("lamp-dev://wish?starter=newyork"))
        // The site's Download copies the same in its mark's value.
        XCTAssertEqual(Wish.markedRemix(html: #"<span data-lamp-wish="starter=newyork" style="x">Make it snow</span>"#, plain: "Make it snow"),
                       Wish.Remix(from: .starter("newyork"), text: "Make it snow"))
        XCTAssertNil(Wish.markedRemix(html: #"<span data-lamp-wish="1">Make it snow</span>"#, plain: "Make it snow"))
        XCTAssertNil(Wish.markedRemix(html: #"<span data-lamp-wish="repo=https%3A%2F%2Fevil.example%2Fa%2Fb">x</span>"#, plain: "x"))
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
}
