import XCTest
@testable import Lamp

/// A new name asked for in the chat is the wish's name, as Rename on the desk gives it: `rename_app` is called here as
/// Claude Code and Codex call it (`Store.mcp`; pi's extension posts the same arguments to `/agent/rename`).
@MainActor
final class AgentRenameTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDown() {
        unsetenv("GIT_CONFIG_GLOBAL")
        for root in roots { try? FileManager.default.removeItem(at: root) }
    }

    /// Under the home folder, as Lamp's own git runs confined to it, with git's Mac-wide settings an empty file.
    private func newRoot() throws -> URL {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-agent-rename-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        let settings = fm.temporaryDirectory.appendingPathComponent("lamp-test-git-settings-\(UUID().uuidString)")
        roots.append(settings)
        try "".write(to: settings, atomically: true, encoding: .utf8)
        setenv("GIT_CONFIG_GLOBAL", settings.path, 1)
        return root
    }

    private func call(_ store: Store, _ arguments: [String: Any], on wish: LampProject) async throws -> (text: String, failed: Bool) {
        let body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                                               "params": ["name": "rename_app", "arguments": arguments]])
        let (_, answer) = await store.mcp(body, for: wish, fileTools: false)
        let result = try XCTUnwrap(answer["result"] as? [String: Any])
        let text = (result["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
        return (text, result["isError"] as? Bool == true)
    }

    /// Renamed while the agent works in the wish: the desk, the app's window title and Undo all follow the new name, and
    /// the wish keeps its folder and id, even with nothing done in it yet (the desk's Rename would make that one again).
    func testTheAgentRenamesTheWishInPlace() async throws {
        let root = try newRoot()
        let made = try Template.scaffold(name: "Water \(UUID().uuidString.prefix(6))", platform: .mac, in: root)
        let store = Store(testingAt: root)
        let saved = await store.initRepo(made, message: "Scaffold")
        XCTAssertTrue(saved)
        let wish = try XCTUnwrap(store.current(made))
        let newName = "Sprout \(UUID().uuidString.prefix(6))"

        let renamed = try await call(store, ["name": newName], on: wish)
        XCTAssertFalse(renamed.failed, renamed.text)
        XCTAssertTrue(renamed.text.contains(newName), renamed.text)

        let now = try XCTUnwrap(store.projects.first { $0.id == wish.id })
        XCTAssertEqual(now.name, newName)
        XCTAssertEqual(now.dir, wish.dir)
        XCTAssertEqual(Store(testingAt: root).projects.first { $0.id == wish.id }?.name, newName, "read again from its files")
        let sources = try String(contentsOf: wish.dir.appendingPathComponent("Sources/App.swift"), encoding: .utf8)
        XCTAssertTrue(sources.contains("\"\(newName)\""), "the window title")
        let versions = await Versions.list(now)
        let latest = try XCTUnwrap(versions.first)
        XCTAssertEqual(latest.renamedTo, newName)
        XCTAssertEqual(latest.renamedFrom, wish.name, "Undo gives the old name back")
    }

    /// A name with nothing usable in it changes nothing, and the agent is told so.
    func testANameThatCantBeUsedIsRefused() async throws {
        let root = try newRoot()
        let made = try Template.scaffold(name: "Water \(UUID().uuidString.prefix(6))", platform: .mac, in: root)
        let store = Store(testingAt: root)
        _ = await store.initRepo(made, message: "Scaffold")
        let wish = try XCTUnwrap(store.current(made))

        let refused = try await call(store, ["name": "///"], on: wish)
        XCTAssertTrue(refused.failed, refused.text)
        XCTAssertEqual(store.projects.first { $0.id == wish.id }?.name, wish.name)
    }

    /// A request that only renames a wish nothing has been asked of yet still ends in a build: the rename's version
    /// leaves the folder clean, and without the build the installed app and its window titles keep the old name.
    func testARenameOnlyTurnIsBuilt() async throws {
        let root = try newRoot()
        let made = try Template.scaffold(name: "Water \(UUID().uuidString.prefix(6))", platform: .mac, in: root)
        let store = Store(testingAt: root)
        _ = await store.initRepo(made, message: "Scaffold")
        let wish = try XCTUnwrap(store.current(made))
        let turn = try XCTUnwrap(store.begin(wish))

        let renamed = try await call(store, ["name": "Sprout \(UUID().uuidString.prefix(6))"], on: wish)
        XCTAssertFalse(renamed.failed, renamed.text)
        let now = try XCTUnwrap(store.current(wish))
        let leftUnsaved = await Versions.hasUnsavedChanges(now)
        XCTAssertFalse(leftUnsaved, "the rename's own version holds everything")
        let replied = await store.onlyReplied(now, in: turn)
        XCTAssertFalse(replied, "the turn goes on to build the new name")
        store.finish(now)
    }
}

