import XCTest
@testable import Lamp
import LampSidebarKit

/// Release Update goes to every place the card shows, and only those: while Lamp is still finding the wish on GitHub,
/// the card can't yet show Also update GitHub, so nothing can go until it can.
@MainActor final class WishLinkShareTests: XCTestCase {
    private func card() -> WishLinkCards.Card {
        WishLinkCards.Card(values: .init(name: "Disk Map", line: "Shows what fills the disk", words: ""), pictureDigest: nil, shared: nil)
    }

    func testNothingGoesWhileGitHubIsBeingFound() {
        var card = card()
        card.gitHubFinding = UUID()
        XCTAssertFalse(card.canShare)
    }

    func testGoesOnceGitHubIsFound() {
        XCTAssertTrue(card().canShare)
    }
}
