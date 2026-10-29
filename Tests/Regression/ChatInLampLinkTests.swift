import XCTest
@testable import Lamp

/// `lamp://chat?app=…`, which the chat beside an app opens when it can't come up there, can be opened by any web page:
/// it only shows the chat of a wish Lamp already has listed, and for any other id does nothing, not even read the
/// apps folder again (a read moves installed copies and refreshes what listens on the network).
@MainActor
final class ChatInLampLinkTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("chat-in-lamp-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testAnIdNotListedDoesNothing() {
        let store = Store(testingAt: root)
        store.showChatInLamp("no-such-wish")
        XCTAssertNil(store.selection)
        XCTAssertFalse(ChatPanel.isOpen("no-such-wish"))
    }

    /// A wish whose folder appeared after Lamp last read the apps folder is not listed, so the link doesn't find it:
    /// finding it would take a read of the folder.
    func testAWishNotYetReadIsNotLookedFor() throws {
        let store = Store(testingAt: root)
        let late = try Template.draft(name: "Late", in: root)
        store.showChatInLamp(late.id)
        XCTAssertFalse(store.projects.contains { $0.id == late.id })
        XCTAssertNil(store.selection)
        XCTAssertFalse(ChatPanel.isOpen(late.id))
    }
}
