import XCTest
@testable import Lamp

/// Following another copy of a wish: a shared link names the copy and nothing else, and a pull-in is measured against
/// what the two copies last shared, never against nothing, which would make every file new on both sides.
final class FollowingTests: XCTestCase {
    private let a = String(repeating: "a", count: 40), b = String(repeating: "b", count: 40), c = String(repeating: "c", count: 40)

    func testLinkNamesTheCopyAndOnlyItsOwnersPage() {
        let shared = Following.copy(fromLink: "https://lamp.dev/?repo=https%3A%2F%2Fgithub.com%2Fann%2Ftally&commit=\(a)&page=https%3A%2F%2Fann.github.io%2Ftally%2F")
        XCTAssertEqual(shared?.place, Following.Place(kind: "github", url: "https://github.com/ann/tally"))
        XCTAssertEqual(shared?.page, "https://ann.github.io/tally/")
        XCTAssertNil(Following.copy(fromLink: "https://lamp.dev/?repo=https%3A%2F%2Fgithub.com%2Fann%2Ftally&page=https%3A%2F%2Fevil.github.io%2F")?.page)
        XCTAssertEqual(Following.copy(fromLink: "lamp-dev-x://wish?repo=https://github.com/ann/tally", scheme: "lamp-dev-x")?.place.url, "https://github.com/ann/tally")
        XCTAssertEqual(Following.copy(fromLink: "github.com/ann/tally")?.place.url, "https://github.com/ann/tally")
        XCTAssertNil(Following.copy(fromLink: "https://example.com/?repo=https://github.com/ann/tally"))
    }

    func testPullInBase() {
        let origin = Credits.Remix(name: "Tally", wish: "w", url: "https://github.com/ann/tally", commit: a)
        let ours = Credits(remixOf: [origin, Credits.Remix(name: "Tally", wish: "w", url: "https://github.com/me/tally", commit: c)])
        var spider = Following.Followed(place: Following.Place(kind: "github", url: "https://github.com/sam/tally-spider"), added: Date())
        // A sibling made from the same copy: measured against where this wish has that copy.
        let theirs = Credits(remixOf: [Credits.Remix(name: "Tally", wish: "w", url: "https://github.com/ann/tally", commit: b),
                                       Credits.Remix(name: "Tally", wish: "w", url: "https://github.com/sam/tally-spider", commit: b)])
        XCTAssertEqual(Following.base(for: spider, ours: ours, theirs: theirs, own: "https://github.com/me/tally")?.commit, a)
        // A copy made from this one: measured against the version of this one it was made from.
        let fromMe = Credits(remixOf: [origin, Credits.Remix(name: "Tally", wish: "w", url: "https://github.com/me/tally", commit: b)])
        XCTAssertEqual(Following.base(for: spider, ours: ours, theirs: fromMe, own: "https://github.com/me/tally")?.url, "https://github.com/me/tally")
        XCTAssertEqual(Following.base(for: spider, ours: ours, theirs: fromMe, own: "https://github.com/me/tally")?.commit, b)
        // Once something was pulled in, the next pull-in starts from it.
        spider.brought = c
        XCTAssertEqual(Following.base(for: spider, ours: ours, theirs: theirs, own: nil)?.commit, c)
    }
}
