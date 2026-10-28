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

/// Chats saved while Lamp could offer to connect Chrome hold that offer's card (`"capability": "browser"`), a
/// capability Lamp no longer has. The card's offer is dropped and the rest of its line, and of the chat, is read.
final class RetiredOfferTests: XCTestCase {
    private let saved = Data(#"""
    [{"id":"6F3C1D0E-5B0A-4C55-9E57-0B8C6C1F5B01","kind":"user","text":"Keep the recipes I find online"},
     {"id":"6F3C1D0E-5B0A-4C55-9E57-0B8C6C1F5B02","kind":"offer","text":"Recipe Box also works in Chrome.","offer":{"capability":"browser"}},
     {"id":"6F3C1D0E-5B0A-4C55-9E57-0B8C6C1F5B03","kind":"offer","text":"Recipe Box can draw each dish.","offer":{"capability":"pictures"}}]
    """#.utf8)

    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    func testReadingAChatDropsOnlyTheRetiredOffer() throws {
        let file = try folder().appendingPathComponent(".lamp/chat.json")
        try saved.write(to: file)

        let read = try XCTUnwrap(LogLine.readChat(file))
        XCTAssertEqual(read.lines.map(\.text), ["Keep the recipes I find online", "Recipe Box also works in Chrome.", "Recipe Box can draw each dish."])
        XCTAssertEqual(read.lines.map(\.offer), [nil, nil, SetupOffer(capability: .pictures)])
        XCTAssertNil(read.unkept)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().appendingPathComponent("chat.json.unreadable").path))
    }

    func testANoteIsAddedToAChatHoldingTheRetiredOffer() throws {
        let dir = try folder()
        let file = dir.appendingPathComponent(".lamp/chat.json")
        try saved.write(to: file)

        LogLine.noteInChat("Renamed.", at: dir)
        let lines = try JSONDecoder().decode([LogLine].self, from: Data(contentsOf: file))
        XCTAssertEqual(lines.map(\.text).last, "Renamed.")
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[2].offer, SetupOffer(capability: .pictures))
    }
}
