import XCTest
@testable import Lamp

/// A wish is what keeps its name, chat and history: its last app taken away with `remove_app` leaves the wish with no
/// app, never a draft that a request writes a new app into, and `make_app_for` then gives it a new app in a folder of its
/// own. Both tools are called as Claude Code and Codex call them (`Store.mcp`), on a wish in a folder of a test's own.
@MainActor
final class EmptyWishTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDown() {
        unsetenv("GIT_CONFIG_GLOBAL")
        for root in roots { try? FileManager.default.removeItem(at: root) }
    }

    /// Under the home folder, as Lamp's own git runs confined to it, with git's Mac-wide settings an empty file.
    private func newRoot() throws -> URL {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-empty-wish-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        let settings = fm.temporaryDirectory.appendingPathComponent("lamp-test-git-settings-\(UUID().uuidString)")
        roots.append(settings)
        try "".write(to: settings, atomically: true, encoding: .utf8)
        setenv("GIT_CONFIG_GLOBAL", settings.path, 1)
        return root
    }

    private func call(_ store: Store, _ tool: String, _ arguments: [String: Any], on wish: LampProject) async throws -> (text: String, failed: Bool) {
        let body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                                               "params": ["name": tool, "arguments": arguments]])
        let (_, answer) = await store.mcp(body, for: wish, fileTools: false)
        let result = try XCTUnwrap(answer["result"] as? [String: Any])
        let text = (result["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
        return (text, result["isError"] as? Bool == true)
    }

    func testAWishKeepsGoingWithNoAppAndIsGivenANewOne() async throws {
        let root = try newRoot()
        // A name of its own, so nothing installed under another wish's name is anywhere near it.
        let made = try Template.scaffold(name: "Empty \(UUID().uuidString.prefix(8))", platform: .mac, in: root)
        var store = Store(testingAt: root)
        let saved = await store.initRepo(made, message: "Scaffold")
        XCTAssertTrue(saved)
        let wish = try XCTUnwrap(store.projects.first { $0.id == made.id })

        let removed = try await call(store, "remove_app", ["app": "."], on: wish)
        XCTAssertFalse(removed.failed, removed.text)
        XCTAssertTrue(removed.text.contains("no apps now"), removed.text)

        // Read again from its files, as after a restart: only the wish, never a draft.
        store = Store(testingAt: root)
        let empty = try XCTUnwrap(store.projects.first { $0.id == made.id })
        XCTAssertFalse(empty.holdsApp)
        XCTAssertTrue(store.apps(of: empty).isEmpty)
        XCTAssertEqual(NewerWish.savedLayout(at: empty.dir) ?? Template.layout(of: empty), NewerWish.layout)
        XCTAssertEqual(Template.layout(of: empty), 3, "a Lamp that reads 2 would take it for a draft")
        XCTAssertEqual(Agent.wishPrompt(for: empty, parts: []), Agent.emptyWishPrompt)
        XCTAssertFalse(Agent.emptyWishPrompt.contains("This wish is "), "nothing of the app that went")
        XCTAssertEqual(WishPlace.of(empty).caption, "No apps")
        XCTAssertNil(TryOnMenu.make(for: empty, store: store))

        let given = try await call(store, "make_app_for", ["kind": "app", "made": "native", "devices": ["mac"]], on: empty)
        XCTAssertFalse(given.failed, given.text)
        let now = try XCTUnwrap(store.projects.first { $0.id == made.id })
        XCTAssertFalse(now.hasScaffold, "the wish's own folder holds no app again")
        let parts = store.parts(of: now)
        XCTAssertEqual(parts.map(\.platform), [.mac])
        // Not Mac/: the Mac app taken away was installed under the wish's name, as one in Mac/ would be, and Undo puts it back.
        XCTAssertEqual(parts.map { $0.dir.lastPathComponent }, ["Mac2"])
        XCTAssertNotEqual(parts.first?.id, made.id, "a new app, never the old one's identity")

    }

    /// The mark that keeps a wish with no app from being a draft is written before anything is taken away: when it can't
    /// be (here a folder stands where it goes), the app stays, its files untouched, and `remove_app` says why, never
    /// that the app went or that the person kept it open.
    func testAnAppStaysWhenTheWishsMarkCantBeWritten() async throws {
        let root = try newRoot()
        let draft = try Template.draft(name: "Kept \(UUID().uuidString.prefix(8))", in: root)
        var store = Store(testingAt: root)
        let first = try await call(store, "make_app_for", ["kind": "app", "made": "native", "devices": ["mac"]],
                                   on: try XCTUnwrap(store.projects.first { $0.id == draft.id }))
        XCTAssertFalse(first.failed, first.text)
        let mark = draft.dir.appendingPathComponent(Parts.wishOnly)
        try FileManager.default.removeItem(at: mark)
        try FileManager.default.createDirectory(at: mark, withIntermediateDirectories: false)
        store = Store(testingAt: root)
        let wish = try XCTUnwrap(store.projects.first { $0.id == draft.id })
        let mac = draft.dir.appendingPathComponent("Mac")
        let files = try FileManager.default.contentsOfDirectory(atPath: mac.path).sorted()

        let removed = try await call(store, "remove_app", ["app": "Mac"], on: wish)
        XCTAssertTrue(removed.failed, removed.text)
        XCTAssertFalse(removed.text.contains("kept it open"), removed.text)
        XCTAssertTrue(removed.text.contains("couldn't"), removed.text)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: mac.path))?.sorted(), files, "its files are all still there")
        let after = try XCTUnwrap(Store(testingAt: root).projects.first { $0.id == draft.id })
        XCTAssertFalse(after.holdsApp, "never a draft")
        XCTAssertEqual(Parts.load(after).map(\.platform), [.mac])
    }

    /// A wish whose app is a web app, a kind a Lamp of layout 2 doesn't know, says layout 3, so that Lamp leaves it alone
    /// rather than find no app in it and write one into its own folder.
    func testAWishWithAWebAppIsLeftAloneByALampFromBefore() throws {
        let root = try newRoot()
        let draft = try Template.draft(name: "Board \(UUID().uuidString.prefix(8))", in: root)
        let folder = draft.dir.appendingPathComponent("WebApp")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try ScreenKit.webAppPage.says.write(to: folder.appendingPathComponent(ScreenKit.webAppPage.marker), atomically: true, encoding: .utf8)
        try "\(Parts.wishOnlyText)".write(to: draft.dir.appendingPathComponent(Parts.wishOnly), atomically: true, encoding: .utf8)
        let wish = try XCTUnwrap(Store.readWish(at: draft.dir))
        XCTAssertEqual(Parts.load(wish).map(\.platform), [.webApp])
        XCTAssertEqual(Template.layout(of: wish), 3)

        // Beside a Mac app in the wish's own folder too: that Lamp would read the Mac app and leave the web app out.
        let mac = try Template.scaffold(name: "Shelf \(UUID().uuidString.prefix(8))", platform: .mac, in: root)
        let beside = mac.dir.appendingPathComponent("WebApp")
        try FileManager.default.createDirectory(at: beside.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try ScreenKit.webAppPage.says.write(to: beside.appendingPathComponent(ScreenKit.webAppPage.marker), atomically: true, encoding: .utf8)
        let both = try XCTUnwrap(Store.readWish(at: mac.dir))
        XCTAssertTrue(both.holdsApp)
        XCTAssertEqual(Template.layout(of: both), 3)
        XCTAssertNil(Template.layout(of: try Template.scaffold(name: "Plain \(UUID().uuidString.prefix(8))", platform: .mac, in: root)))
    }

    /// A new wish's first app goes in a folder of its own, its own folder marked as only the wish's before that, so the
    /// first app is never one in the wish's folder.
    func testANewWishsFirstAppIsInAFolderOfItsOwn() async throws {
        let root = try newRoot()
        let draft = try Template.draft(name: "First \(UUID().uuidString.prefix(8))", in: root)
        let store = Store(testingAt: root)
        let wish = try XCTUnwrap(store.projects.first { $0.id == draft.id })
        XCTAssertFalse(wish.scaffolded)
        // A native game: the Mac's own code, which a test builds from Lamp's sources alone (a web game's page comes
        // from Lamp's bundle).
        let given = try await call(store, "make_app_for", ["kind": "game", "made": "native", "devices": ["mac"]], on: wish)
        XCTAssertFalse(given.failed, given.text)
        let now = try XCTUnwrap(store.projects.first { $0.id == draft.id })
        XCTAssertFalse(now.holdsApp)
        XCTAssertTrue(Parts.isWishOnly(now.dir))
        XCTAssertEqual(store.parts(of: now).map(\.platform), [.mac], given.text)
        XCTAssertEqual(store.parts(of: now).map { $0.dir.lastPathComponent }, ["Mac"])
        XCTAssertTrue(given.text.contains("game skill"), "told it's a game, though it's the Mac's own code")
        XCTAssertNil(now.undecided)
        XCTAssertTrue(FileManager.default.fileExists(atPath: now.dir.appendingPathComponent(".git").path), "its first version is saved")
    }
}
