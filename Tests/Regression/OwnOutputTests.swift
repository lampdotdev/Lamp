import XCTest
@testable import Lamp

/// Claude Code saves a command's long output under its own folder and reads it back. A turn once waited ten
/// minutes on an approval card for that read: the conversation's own output goes through, and nothing wider.
final class OwnOutputTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private let session = "0f3c2a9e-5b1d-4c7a-9e2f-123456789abc"

    /// A home folder with an app and Claude Code's folder for it, as Claude Code names it.
    private func setUp(_ name: String = "Coin Flip") throws -> (home: URL, project: LampProject, results: URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-own-output-\(UUID().uuidString)").resolvingSymlinksInPath()
        self.root = root
        let home = root.appendingPathComponent("home")
        let dir = home.appendingPathComponent("Applications/Lamp Apps/\(name)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let slug = String(dir.path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        let results = home.appendingPathComponent(".claude/projects/\(slug)/\(session)/tool-results")
        try fm.createDirectory(at: results, withIntermediateDirectories: true)
        try "lots of grep".write(to: results.appendingPathComponent("toolu_01.txt"), atomically: true, encoding: .utf8)
        return (home, LampProject(id: "coinflip", name: name, exe: "CoinFlip", dir: dir), results)
    }

    func testReadingThisConversationsOutputGoesThrough() throws {
        let (home, project, results) = try setUp()
        let file = results.appendingPathComponent("toolu_01.txt").path
        XCTAssertTrue(Privacy.isOwnOutput(tool: "read", path: file, session: session, project: project, claudeFolder: home.appendingPathComponent(".claude")))
        XCTAssertTrue(Privacy.isOwnOutput(tool: "grep", path: results.path, session: session, project: project, claudeFolder: home.appendingPathComponent(".claude")))
    }

    func testNothingWider() throws {
        let (home, project, results) = try setUp()
        let file = results.appendingPathComponent("toolu_01.txt").path
        // Writing it, or a tool Lamp doesn't know.
        for tool in ["write", "edit", ""] {
            XCTAssertFalse(Privacy.isOwnOutput(tool: tool, path: file, session: session, project: project, claudeFolder: home.appendingPathComponent(".claude")), tool)
        }
        // Another conversation, or a session that isn't one.
        XCTAssertFalse(Privacy.isOwnOutput(tool: "read", path: file, session: "another-session", project: project, claudeFolder: home.appendingPathComponent(".claude")))
        XCTAssertFalse(Privacy.isOwnOutput(tool: "read", path: file, session: "", project: project, claudeFolder: home.appendingPathComponent(".claude")))
        let up = results.deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertFalse(Privacy.isOwnOutput(tool: "read", path: up.appendingPathComponent("x.jsonl").path,
                                           session: "..", project: project, claudeFolder: home.appendingPathComponent(".claude")))
        // The conversation itself, beside its tool-results, and Claude Code's other folders.
        XCTAssertFalse(Privacy.isOwnOutput(tool: "read", path: results.deletingLastPathComponent().path + ".jsonl",
                                           session: session, project: project, claudeFolder: home.appendingPathComponent(".claude")))
        XCTAssertFalse(Privacy.isOwnOutput(tool: "read", path: home.appendingPathComponent(".claude/.credentials.json").path,
                                           session: session, project: project, claudeFolder: home.appendingPathComponent(".claude")))
        // The same session under another app's folder.
        let other = LampProject(id: "other", name: "Other", exe: "Other", dir: home.appendingPathComponent("Applications/Lamp Apps/Other"))
        XCTAssertFalse(Privacy.isOwnOutput(tool: "read", path: file, session: session, project: other, claudeFolder: home.appendingPathComponent(".claude")))
        // A path that steps out with "..".
        XCTAssertFalse(Privacy.isOwnOutput(tool: "read", path: results.path + "/../../../../.credentials.json",
                                           session: session, project: project, claudeFolder: home.appendingPathComponent(".claude")))
    }

    func testALinkThereCantLeadElsewhere() throws {
        let (home, project, results) = try setUp()
        let secret = home.appendingPathComponent("secret.txt")
        try "secret".write(to: secret, atomically: true, encoding: .utf8)
        let link = results.appendingPathComponent("toolu_02.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)
        XCTAssertFalse(Privacy.isOwnOutput(tool: "read", path: link.path, session: session, project: project, claudeFolder: home.appendingPathComponent(".claude")))
        // A linked folder on the way in is worked out too: the real one is what's compared.
        let linkedHome = root!.appendingPathComponent("linked-home")
        try FileManager.default.createSymbolicLink(at: linkedHome, withDestinationURL: home)
        let viaLink = linkedHome.path + String(results.path.dropFirst(home.path.count)) + "/toolu_01.txt"
        XCTAssertTrue(Privacy.isOwnOutput(tool: "read", path: viaLink, session: session, project: project, claudeFolder: home.appendingPathComponent(".claude")))
    }

    /// The folder that doesn't ask is the one where Claude Code keeps it, not wherever a link there leads.
    func testARedirectedOutputFolderIsntTrusted() throws {
        let (home, project, results) = try setUp()
        let fm = FileManager.default
        let elsewhere = home.appendingPathComponent("Documents")
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try "private".write(to: elsewhere.appendingPathComponent("taxes.txt"), atomically: true, encoding: .utf8)
        let session = results.deletingLastPathComponent()
        let slug = session.deletingLastPathComponent()
        // tool-results, the session's folder and the app's folder each linked elsewhere in turn.
        for link in [results, session, slug] {
            let moved = link.deletingLastPathComponent().appendingPathComponent(".moved-\(UUID().uuidString)")
            try fm.moveItem(at: link, to: moved)
            try fm.createSymbolicLink(at: link, withDestinationURL: elsewhere)
            let through = results.appendingPathComponent("taxes.txt").path
            XCTAssertFalse(Privacy.isOwnOutput(tool: "read", path: through, session: self.session, project: project, claudeFolder: home.appendingPathComponent(".claude")),
                           link.lastPathComponent)
            try fm.removeItem(at: link)
            try fm.moveItem(at: moved, to: link)
        }
        XCTAssertTrue(Privacy.isOwnOutput(tool: "read", path: results.appendingPathComponent("toolu_01.txt").path,
                                          session: self.session, project: project, claudeFolder: home.appendingPathComponent(".claude")))
    }

    /// Claude Code replaces every character but ASCII letters and digits, one per UTF-16 unit.
    func testFoldersNamedWithMoreThanASCII() throws {
        let (home, project, _) = try setUp("Café Board")
        let slug = String(decoding: project.dir.path.utf16.map { unit -> UInt16 in
            (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit) ? unit : 0x2D
        }, as: UTF16.self)
        // A file URL's path is decomposed, as the folder's name on disk is: "e" and its accent, two dashes in all.
        XCTAssertTrue(slug.hasSuffix("Cafe--Board"), slug)
        let file = home.appendingPathComponent(".claude/projects/\(slug)/\(session)/tool-results/toolu_01.txt").path
        XCTAssertTrue(Privacy.isOwnOutput(tool: "read", path: file, session: session, project: project, claudeFolder: home.appendingPathComponent(".claude")))
    }
}
