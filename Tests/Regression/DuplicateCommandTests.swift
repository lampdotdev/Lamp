import XCTest
@testable import Lamp

/// File → Duplicate… acts on the wish picked on the desk while the desk is in front, else on the chat in front, and can
/// be chosen for the same wishes as Duplicate… in a wish's own menu. A pick on the desk is never `Store.selection`, which
/// also says what's been read and which window asks the store's questions.
@MainActor
final class DuplicateCommandTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("duplicate-command-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func wish(_ name: String) throws -> LampProject { try Template.scaffold(name: name, platform: .mac, in: root) }

    func testTheDesksPickIsTheTargetOverTheChat() throws {
        let (picked, chat) = (try wish("Picked"), try wish("Chat"))
        let store = Store(testingAt: root)
        store.selection = chat.id
        XCTAssertEqual(store.commandTarget(deskPick: picked.id)?.id, picked.id)
        XCTAssertEqual(store.selection, chat.id, "a pick on the desk leaves the chat's selection as it was")
    }

    func testWithTheDeskNotInFrontTheChatIsTheTarget() throws {
        let chat = try wish("Chat")
        let store = Store(testingAt: root)
        store.selection = chat.id
        XCTAssertEqual(store.commandTarget(deskPick: nil)?.id, chat.id)
    }

    func testWithNeitherThereIsNoTarget() throws {
        _ = try wish("Unpicked")
        let store = Store(testingAt: root)
        XCTAssertNil(store.commandTarget(deskPick: nil))
    }

    /// The pick is kept while another window is in front, and is the target again as soon as the desk is key.
    func testThePickCountsOnlyWhileTheDeskIsKey() {
        let pick = DeskPick()
        pick.wish = "hotshelf"
        XCTAssertNil(pick.target)
        pick.deskIsKey = true
        XCTAssertEqual(pick.target, "hotshelf")
        pick.deskIsKey = false
        XCTAssertNil(pick.target)
        pick.deskIsKey = true
        XCTAssertEqual(pick.target, "hotshelf")
    }

    func testOnlyAMadeWishAtRestCanBeDuplicated() throws {
        let made = try wish("Made")
        let store = Store(testingAt: root)
        let ready = try XCTUnwrap(store.current(made))
        XCTAssertTrue(store.canDuplicate(ready))

        store.busy.insert(ready.id)
        XCTAssertFalse(store.canDuplicate(ready), "being changed")
        store.busy.remove(ready.id)

        var unnamed = ready
        unnamed.untitled = true
        XCTAssertFalse(store.canDuplicate(unnamed), "not named yet")

        try FileManager.default.removeItem(at: ready.dir.appendingPathComponent("Package.swift"))
        XCTAssertFalse(store.canDuplicate(ready), "nothing built to copy")
    }

    /// A copy waiting for its review isn't offered in either menu, rather than being refused once chosen.
    func testACopyAwaitingReviewCannotBeDuplicated() throws {
        let made = try wish("Update")
        let store = Store(testingAt: root)
        let copy = try XCTUnwrap(store.current(made))
        try AppUpdates.Job(url: "https://github.com/mrdoob/slop-newyork", base: "dcb453f", target: "13dd142", wish: "newyork").save(in: copy)
        XCTAssertFalse(store.canDuplicate(copy))
    }
}
