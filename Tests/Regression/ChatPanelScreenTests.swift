import XCTest
@testable import Lamp

/// A chat on its own opens on the screen the person is working on, not on the first screen, where a new panel's frame
/// starts. Screens are in AppKit's coordinates: the first at the origin, a second beside it.
final class ChatPanelScreenTests: XCTestCase {
    private let first = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let second = CGRect(x: 1512, y: -200, width: 2560, height: 1440)
    private let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)

    func testWishFromTheDeskOnTheSecondScreenOpensThere() {
        let desk = CGRect(x: 2200, y: 200, width: 1100, height: 760)
        XCTAssertEqual(ChatPanel.aloneScreen([first, second], shown: nil, from: desk, pointer: CGPoint(x: 2700, y: 600)), second)
        XCTAssertEqual(ChatPanel.aloneScreen([first, left], shown: nil, from: desk.offsetBy(dx: -3800, dy: 0), pointer: .zero), left)
    }

    func testDeskAcrossTwoScreensGoesByTheLargerPart() {
        let desk = CGRect(x: 1300, y: 100, width: 1000, height: 700)
        XCTAssertEqual(ChatPanel.aloneScreen([first, second], shown: nil, from: desk, pointer: .zero), second)
    }

    func testNothingToGoByTakesTheScreenUnderThePointer() {
        XCTAssertEqual(ChatPanel.aloneScreen([first, second], shown: nil, from: nil, pointer: CGPoint(x: 3000, y: 900)), second)
    }

    func testAChatAlreadyUpStaysOnItsScreen() {
        let chat = CGRect(x: 2400, y: 100, width: 620, height: 820)
        let desk = CGRect(x: 100, y: 100, width: 1100, height: 760)
        XCTAssertEqual(ChatPanel.aloneScreen([first, second], shown: chat, from: desk, pointer: CGPoint(x: 10, y: 10)), second)
    }
}
