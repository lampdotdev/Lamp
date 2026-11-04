import XCTest
@testable import Lamp

/// Following another copy of a wish: a shared link names the copy and nothing else, a link's version is told apart
/// exactly, and a pull-in is measured against what the two copies last shared, never against nothing, which would make
/// every file new on both sides.
final class FollowingTests: XCTestCase {
    private let a = String(repeating: "a", count: 40), b = String(repeating: "b", count: 40), c = String(repeating: "c", count: 40)

    func testLinkNamesTheCopy() {
        XCTAssertEqual(Following.copy(fromLink: "https://lamp.dev/w/abcd2345XY"), .lamp("abcd2345XY"))
        XCTAssertEqual(Following.copy(fromLink: "lamp-dev-x://wish?shared=abcd2345XY&text=hi", scheme: "lamp-dev-x"), .lamp("abcd2345XY"))
        XCTAssertEqual(Following.Place.lamp("abcd2345XY").link, "abcd2345XY")
        XCTAssertEqual(Wish.shared(from: URL(string: "lamp://wish?shared=abcd2345XY&text=Snow")!, scheme: "lamp"), Wish.Shared(id: "abcd2345XY", text: "Snow"))
        XCTAssertEqual(Following.copy(fromLink: "github.com/ann/tally"), Following.Place(kind: "github", url: "https://github.com/ann/tally"))
        for bad in ["https://lamp.dev/w/../etc", "https://lamp.dev/w/abcd2345X0", "https://example.com/w/abcd2345XY", "lamp://wish?shared=short"] {
            XCTAssertNil(Following.copy(fromLink: bad, scheme: "lamp"), bad)
        }
    }

    func testALinksVersionIsToldApartExactly() {
        var followed = Following.Followed(place: .lamp("abcd2345XY"), brought: "1")
        XCTAssertEqual(Following.state(of: followed, check: AppUpdates.Check(tip: "12", at: Date())), .new)
        XCTAssertEqual(Following.state(of: followed, check: AppUpdates.Check(tip: "1", at: Date())), .upToDate)
        followed.brought = nil
        XCTAssertEqual(Following.state(of: followed, check: AppUpdates.Check(tip: "0", at: Date())), .upToDate, "a link with no file has nothing to pull in")
        XCTAssertEqual(Following.state(of: Following.Followed(place: Following.Place(kind: "relay", url: "x")), check: nil), .unreachable)
    }

    func testPullInBase() {
        let origin = Credits.Remix(name: "Tally", wish: "w", url: "https://github.com/ann/tally", commit: a)
        // As Lamp keeps them: the wish's own repository isn't on its own chain (Put on GitHub keeps it apart).
        let ours = Credits(remixOf: [origin])
        var spider = Following.Followed(place: Following.Place(kind: "github", url: "https://github.com/sam/tally-spider"))
        // A sibling made from the same copy: measured against where this wish has that copy.
        let theirs = Credits(remixOf: [Credits.Remix(name: "Tally", wish: "w", url: "https://github.com/ann/tally", commit: b),
                                       Credits.Remix(name: "Tally", wish: "w", url: "https://github.com/sam/tally-spider", commit: b)])
        XCTAssertEqual(Following.base(for: spider, ours: ours, theirs: theirs, own: "https://github.com/me/tally")?.commit, a)
        // A copy made from this one: measured against the version of this one it was made from, which only their chain names.
        let fromMe = Credits(remixOf: [origin, Credits.Remix(name: "Tally", wish: "w", url: "https://github.com/me/tally", commit: b)])
        XCTAssertEqual(Following.base(for: spider, ours: ours, theirs: fromMe, own: "https://github.com/me/tally")?.commit, b)
        // Once something was pulled in, the next pull-in starts from it; a link's version is no commit, and its base is
        // kept at its own ref instead.
        spider.brought = c
        XCTAssertEqual(Following.base(for: spider, ours: ours, theirs: theirs, own: nil)?.commit, c)
        XCTAssertNil(Following.base(for: Following.Followed(place: .lamp("abcd2345XY"), brought: "3"), ours: ours, theirs: theirs, own: nil),
                     "once pulled in, a link's copy goes by its own ref, never the repository both came from")
    }
}
