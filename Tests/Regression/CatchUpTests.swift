import XCTest
@testable import Lamp

/// Switching engines mid-chat: the engine switched to has a conversation of its own for the app, which never saw what
/// was said with the other one, so those messages go with its request.
final class CatchUpTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func line(_ kind: LogLine.Kind, _ text: String, at minutes: Double, midTurn: Bool? = nil) -> LogLine {
        LogLine(kind: kind, text: text, midTurn: midTurn, at: t0.addingTimeInterval(minutes * 60))
    }

    /// Dan's case: a chat with ChatGPT, then Claude, which has never worked on this app.
    func testAnEngineNewToTheChatIsToldAllOfIt() {
        let chat = [line(.user, "Make a recipe box", at: 0), line(.tool, "write Recipes.swift", at: 1),
                    line(.agent, "Your recipe box is ready.", at: 2), line(.status, "Ready", at: 3),
                    line(.user, "What did I ask for first?", at: 4)]
        let missed = CatchUp.missed(in: chat, since: nil, before: chat[4].id)
        XCTAssertEqual(missed.map(\.text), ["Make a recipe box", "Your recipe box is ready."])
        let note = CatchUp.note(missed)
        XCTAssertTrue(note.contains("The person: Make a recipe box"))
        XCTAssertTrue(note.contains("The agent: Your recipe box is ready."))
        XCTAssertFalse(note.contains("Recipes.swift"))
    }

    /// Back to an engine that worked on the app before: only what came after its last run, from the next request on.
    func testAnEngineComingBackIsToldWhatItMissed() {
        let chat = [line(.user, "Make a recipe box", at: 0), line(.agent, "Ready.", at: 2),       // Claude, run at 1
                    line(.user, "Add a dark theme", at: 10), line(.agent, "Dark theme added.", at: 12),  // ChatGPT
                    line(.user, "Thanks", at: 20)]
        let missed = CatchUp.missed(in: chat, since: t0.addingTimeInterval(60), before: chat[4].id)
        XCTAssertEqual(missed.map(\.text), ["Add a dark theme", "Dark theme added."])
    }

    /// The same engine again: nothing, including a message it took while it worked.
    func testTheSameEngineIsToldNothing() {
        let chat = [line(.user, "Make a recipe box", at: 0), line(.user, "and make it blue", at: 2, midTurn: true),
                    line(.agent, "Ready, in blue.", at: 3), line(.user, "Thanks", at: 10)]
        XCTAssertTrue(CatchUp.missed(in: chat, since: t0.addingTimeInterval(60), before: chat[3].id).isEmpty)
    }

    func testALongChatKeepsItsNewestMessages() {
        let chat = (0..<40).map { line(.user, String(repeating: "\($0 % 10)", count: 1_000), at: Double($0)) }
        let note = CatchUp.note(chat)
        XCTAssertTrue(note.contains("Older messages are left out"))
        XCTAssertTrue(note.hasSuffix(String(repeating: "9", count: 1_000)))
        XCTAssertLessThan(note.count, CatchUp.budget + 1_000)
    }

    /// pi's conversation counts as begun only once pi has written its file.
    func testAPiConversationWithNoFileIsNew() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("catchup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessions = dir.appendingPathComponent(".lamp/pi-sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let project = LampProject(id: "app", name: "App", exe: "App", dir: dir)
        XCTAssertNil(CatchUp.lastRun(of: .pi, session: "lamp-1", in: project))
        try Data().write(to: sessions.appendingPathComponent("2026-10-19T14-32-58-541Z_lamp-1.jsonl"))
        XCTAssertNotNil(CatchUp.lastRun(of: .pi, session: "lamp-1", in: project))
        XCTAssertNil(CatchUp.lastRun(of: .claude, session: nil, in: project))
    }
}
