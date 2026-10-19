import XCTest
@testable import Lamp

/// Files Lamp keeps in an app's folder and reads back outside the sandbox: what it reads goes into the app's code,
/// the next request, or back into the folder. A link the agent put in their place must bring none of what it leads to.
final class AppFolderLinksTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func project() throws -> (LampProject, URL) {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-folder-links-test-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("Apps/coinflip")
        try fm.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        let mine = root.appendingPathComponent("Private")
        try fm.createDirectory(at: mine, withIntermediateDirectories: true)
        // Shaped like a secret Lamp makes, so only the link gives it away.
        try "SECRET-0123456789".write(to: mine.appendingPathComponent("key"), atomically: true, encoding: .utf8)
        try "secret text".write(to: mine.appendingPathComponent("text.txt"), atomically: true, encoding: .utf8)
        return (LampProject(id: "coinflip", name: "Coin Flip", exe: "CoinFlip", dir: dir), mine)
    }

    private func link(_ name: String, in project: LampProject, to target: URL) throws {
        try FileManager.default.createSymbolicLink(at: project.dir.appendingPathComponent(name), withDestinationURL: target)
    }

    func testTheAppsTokenIsLampsOwn() throws {
        let (project, mine) = try project()
        try link(".lamp/token", in: project, to: mine.appendingPathComponent("key"))
        XCTAssertNotEqual(Template.token(for: project), "SECRET-0123456789")
        XCTAssertEqual(try String(contentsOf: mine.appendingPathComponent("key"), encoding: .utf8), "SECRET-0123456789")
        // Made once, then the same.
        XCTAssertEqual(Template.token(for: project), Template.token(for: project))
    }

    func testTheNoteAfterARestoreIsLampsOwn() throws {
        let (project, mine) = try project()
        try link(".lamp/restored-note", in: project, to: mine.appendingPathComponent("text.txt"))
        XCTAssertFalse(Versions.note(for: project).contains("secret"))
    }

    func testTheMigrationCopiesNothingInThroughALink() throws {
        let (project, mine) = try project()
        try link(".gitignore", in: project, to: mine.appendingPathComponent("text.txt"))
        Migration.normalize(project.dir, commit: false)
        let ignore = (try? String(contentsOf: project.dir.appendingPathComponent(".gitignore"), encoding: .utf8)) ?? ""
        XCTAssertFalse(ignore.contains("secret") && (try? FileManager.default.destinationOfSymbolicLink(atPath: project.dir.appendingPathComponent(".gitignore").path)) == nil,
                       "the linked file's text was written into the app's folder")
        XCTAssertEqual(try String(contentsOf: mine.appendingPathComponent("text.txt"), encoding: .utf8), "secret text")
    }
}
