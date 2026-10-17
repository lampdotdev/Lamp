import XCTest
@testable import Lamp

/// The app's notes sit in its folder, where the agent can put a link, and Lamp reads them outside the sandbox for
/// `read_notes` and the summary sent with each request. A link there must bring the agent nothing it can't read itself.
final class MemoryLinksTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    /// An app under the home folder, as a real one is, and a private folder beside it the agent can't read.
    private func project() throws -> (LampProject, URL) {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-memory-links-test-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("Apps/coinflip")
        try fm.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        let mine = root.appendingPathComponent("Private")
        try fm.createDirectory(at: mine, withIntermediateDirectories: true)
        try "summary: secret summary\n\nsecret notes".write(to: mine.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        try #"{"waiting":{"pi":{"app":["secret line"]}}}"#.write(to: mine.appendingPathComponent("undone.json"), atomically: true, encoding: .utf8)
        return (LampProject(id: "coinflip", name: "Coin Flip", exe: "CoinFlip", dir: dir), mine)
    }

    func testTheAppsOwnNotesAreRead() throws {
        let (project, _) = try project()
        try "summary: Coin colours\n\nGold coins, not silver.".write(to: project.dir.appendingPathComponent(".lamp/notes.md"), atomically: true, encoding: .utf8)
        let notes = Memory.read(.app(project))
        XCTAssertEqual(notes.summary, "Coin colours")
        XCTAssertEqual(notes.text, "Gold coins, not silver.")
    }

    func testNotesLinkedElsewhereAreNotRead() throws {
        let (project, mine) = try project()
        try FileManager.default.createSymbolicLink(at: project.dir.appendingPathComponent(".lamp/notes.md"), withDestinationURL: mine.appendingPathComponent("notes.md"))
        let notes = Memory.read(.app(project))
        XCTAssertFalse(notes.text.contains("secret"), notes.text)
        XCTAssertFalse(notes.summary.contains("secret"), notes.summary)
        XCTAssertFalse(Memory.brief(for: project, engine: .pi, session: nil).contains("secret"))
    }

    func testTheLampFolderLinkedElsewhereIsNotRead() throws {
        let (project, mine) = try project()
        try FileManager.default.removeItem(at: project.dir.appendingPathComponent(".lamp"))
        try FileManager.default.createSymbolicLink(at: project.dir.appendingPathComponent(".lamp"), withDestinationURL: mine)
        // `.lamp/notes.md` now names the private notes through the linked folder.
        XCTAssertFalse(Memory.read(.app(project)).text.contains("secret"))
    }

    func testWhatWasTakenBackIsTheAppsOwn() throws {
        let (project, mine) = try project()
        try FileManager.default.createSymbolicLink(at: project.dir.appendingPathComponent(".lamp/notes-undone.json"), withDestinationURL: mine.appendingPathComponent("undone.json"))
        XCTAssertFalse(Memory.brief(for: project, engine: .pi, session: nil).contains("secret line"))
    }
}
