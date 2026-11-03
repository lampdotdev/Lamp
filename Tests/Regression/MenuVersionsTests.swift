import XCTest
@testable import Lamp

/// Name This Version… can be chosen once the wish File's commands act on has a version, read with git away from the
/// menu. The answer follows the desk's pick and the chat in front, and belongs only to the wish it was read for.
@MainActor
final class MenuVersionsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("menu-versions-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func wish(_ name: String) throws -> LampProject { try Template.scaffold(name: name, platform: .mac, in: root) }

    private func settle(_ what: String, until done: @escaping () -> Bool) async {
        for _ in 0..<500 where !done() { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(done(), what)
    }

    func testAPickWithAVersionCanBeNamedOnTheDesk() async throws {
        let made = try wish("Picked")
        let store = Store(testingAt: root)
        let picked = try XCTUnwrap(store.current(made))
        let saved = await store.initRepo(picked, message: "Scaffold")
        XCTAssertTrue(saved)
        let pick = DeskPick()
        let versions = MenuVersions(store: store, pick: pick)
        pick.wish = picked.id
        pick.deskIsKey = true
        await settle("the desk's pick has a version") { versions.hasVersions(picked) }
        XCTAssertNil(store.selection, "a pick stays out of the selection")

        pick.deskIsKey = false
        await settle("Settings in front acts on nothing") { !versions.hasVersions(picked) }
        pick.deskIsKey = true
        await settle("back on the desk") { versions.hasVersions(picked) }
    }

    func testAChatInFrontIsAskedAbout() async throws {
        let made = try wish("Chat")
        let store = Store(testingAt: root)
        let chat = try XCTUnwrap(store.current(made))
        let saved = await store.initRepo(chat, message: "Scaffold")
        XCTAssertTrue(saved)
        let versions = MenuVersions(store: store, pick: DeskPick())
        store.selection = chat.id
        await settle("the chat's wish has a version") { versions.hasVersions(chat) }
    }

    /// A wish with no commits is off, comes on with its first one, and choosing it early shows no dialog.
    func testAWishWithNoCommitsHasNothingToName() async throws {
        let made = try wish("Empty")
        let store = Store(testingAt: root)
        let empty = try XCTUnwrap(store.current(made))
        var reads = 0
        let pick = DeskPick()
        let versions = MenuVersions(store: store, pick: pick) { project in
            reads += 1
            return await Versions.head(project) != nil
        }
        pick.wish = empty.id
        pick.deskIsKey = true
        await settle("read") { reads == 1 }
        await Task.yield()
        XCTAssertFalse(versions.hasVersions(empty))

        await store.nameCurrentVersion(of: empty)
        XCTAssertNil(store.naming)

        let saved = await store.initRepo(empty, message: "Scaffold")
        XCTAssertTrue(saved)
        await settle("the first version is seen without the pick moving") { versions.hasVersions(empty) }
    }

    /// A slow read for the wish left behind says nothing of the one picked since.
    func testALateAnswerForAnotherWishIsDropped() async throws {
        let (first, second) = (try wish("First"), try wish("Second"))
        let store = Store(testingAt: root)
        var waiting: [String: CheckedContinuation<Bool, Never>] = [:]
        let pick = DeskPick()
        let versions = MenuVersions(store: store, pick: pick) { project in
            await withCheckedContinuation { waiting[project.id] = $0 }
        }
        pick.deskIsKey = true
        pick.wish = first.id
        await settle("first asked") { waiting[first.id] != nil }
        pick.wish = second.id
        await settle("second asked") { waiting[second.id] != nil }

        waiting[second.id]?.resume(returning: true)
        await settle("second answered") { versions.hasVersions(second) }
        waiting[first.id]?.resume(returning: false)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(versions.hasVersions(second))
        XCTAssertFalse(versions.hasVersions(first))
    }

    /// A starter picked on the desk that isn't a wish yet has no target, whatever was read before it.
    func testAStarterNotOnTheDeskYetCanBeNeither() async throws {
        let made = try wish("Made")
        let store = Store(testingAt: root)
        let current = try XCTUnwrap(store.current(made))
        let pick = DeskPick()
        let versions = MenuVersions(store: store, pick: pick) { _ in true }
        pick.deskIsKey = true
        pick.wish = current.id
        await settle("made") { versions.hasVersions(current) }
        pick.wish = "starter-not-copied"
        await settle("no target") { !versions.hasVersions(current) }
        XCTAssertNil(store.commandTarget(deskPick: pick.target))
    }
}
