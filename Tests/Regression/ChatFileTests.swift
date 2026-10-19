import XCTest
@testable import Lamp

/// Two Lamps sharing one folder (a Lamp Dev from another branch, a newer Lamp) can write chat lines this one
/// can't read. Those lines are skipped, the rest of the chat opens, and the file as it was is kept beside it.
final class ChatFileTests: XCTestCase {
    func testALineOfAnUnknownKindCostsOnlyThatLine() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("chat.json")
        let saved = Data(#"""
        [{"id":"6F3C1D0E-5B0A-4C55-9E57-0B8C6C1F5A01","kind":"user","text":"A tracker"},
         {"id":"6F3C1D0E-5B0A-4C55-9E57-0B8C6C1F5A02","kind":"somethingNewer","text":"Halfway there"},
         {"id":"6F3C1D0E-5B0A-4C55-9E57-0B8C6C1F5A03","kind":"agent","text":"It's ready."}]
        """#.utf8)
        try saved.write(to: file)

        let read = try XCTUnwrap(LogLine.readChat(file))
        XCTAssertNil(read.unkept)
        let lines = read.lines

        XCTAssertEqual(lines.map(\.text), ["A tracker", "It's ready."])
        let copy = folder.appendingPathComponent("chat.json.unreadable")
        XCTAssertEqual(try Data(contentsOf: copy), saved)

        // Saving over the chat, as the next line does, leaves the copy; reading it again makes no second one.
        try JSONEncoder().encode(lines).write(to: file)
        XCTAssertEqual(LogLine.readChat(file)?.lines.count, 2)
        try saved.write(to: file)
        _ = LogLine.readChat(file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("chat.json.unreadable-2").path))
        XCTAssertEqual(try Data(contentsOf: copy), saved)
    }

    func testAChatThatReadsWholeLeavesNoCopy() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("chat.json")
        try JSONEncoder().encode([LogLine(kind: .user, text: "Hi")]).write(to: file)

        XCTAssertEqual(LogLine.readChat(file)?.lines.map(\.text), ["Hi"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("chat.json.unreadable").path))
        XCTAssertNil(LogLine.readChat(folder.appendingPathComponent("missing.json")))
    }

    /// When the copy can't be made, the reader hands back the file as it was, so nothing writes over it until it's kept.
    func testAChatThatCantBeCopiedIsHandedBack() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        let file = folder.appendingPathComponent("chat.json")
        let saved = Data(#"[{"id":"6F3C1D0E-5B0A-4C55-9E57-0B8C6C1F5A01","kind":"somethingNewer","text":"?"}]"#.utf8)
        try saved.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)

        let read = try XCTUnwrap(LogLine.readChat(file))
        XCTAssertEqual(read.lines, [])
        XCTAssertEqual(read.unkept, saved)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        XCTAssertTrue(LogLine.keepAside(saved, of: file))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("chat.json.unreadable")), saved)
    }
}
