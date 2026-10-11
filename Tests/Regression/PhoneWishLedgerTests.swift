import XCTest
@testable import Lamp

final class PhoneWishLedgerTests: XCTestCase {
    private func file() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("wishes.json")
    }

    // The phone can disappear after Send without knowing whether the Mac received it.
    func testLostAcknowledgementAndMacReopenKeepOneWish() throws {
        let file = try file(), id = UUID(), pair = UUID()
        var first = try PhoneWishLedger(file: file)
        _ = try first.accept(id: id, pairID: pair, wish: "Make a counter")
        var reopened = try PhoneWishLedger(file: file)
        for _ in 0..<30 { _ = try reopened.accept(id: id, pairID: pair, wish: "Make a counter") }
        XCTAssertEqual(reopened.jobs.count, 1)
        XCTAssertEqual(reopened.jobs.first?.wish, "Make a counter")
        XCTAssertEqual(reopened.jobs.first?.id, id)
    }

    // Locking the phone during work must preserve the job and show its progress on return.
    func testReconnectGetsCompletedStatusForTheOriginalRequest() throws {
        let file = try file(), id = UUID(), pair = UUID()
        var ledger = try PhoneWishLedger(file: file)
        _ = try ledger.accept(id: id, pairID: pair, wish: "Make a counter")
        try ledger.update(.init(id: id, phase: .waitingPhone))
        ledger = try PhoneWishLedger(file: file)
        let ready = PhoneLink.Status(id: id, phase: .ready, appURL: "lamp-app-test://open")
        try ledger.update(ready)
        var reopened = try PhoneWishLedger(file: file)
        let repeated = try reopened.accept(id: id, pairID: pair, wish: "Make a counter")
        XCTAssertEqual(repeated.status, ready)
        XCTAssertEqual(reopened.jobs.count, 1)
    }

    func testFailedDiskWriteCannotAcknowledgeOrStartAWish() throws {
        let file = try file()
        var ledger = try PhoneWishLedger(file: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertThrowsError(try ledger.accept(id: UUID(), pairID: UUID(), wish: "Make a counter"))
        XCTAssertTrue(ledger.jobs.isEmpty)
    }

    // A reply changes the same app, even when its acknowledgement is lost.
    func testFollowupReconnectKeepsOneConversationAndOneCopyOfTheReply() throws {
        let file = try file(), chat = UUID(), pair = UUID(), reply = UUID()
        var ledger = try PhoneWishLedger(file: file)
        _ = try ledger.accept(id: chat, pairID: pair, wish: "Make a counter")
        try ledger.record(chat, in: chat, as: .posted)
        try ledger.update(.init(id: chat, phase: .ready))
        _ = try ledger.reply(id: reply, to: chat, pairID: pair, text: "Add a reset button")
        try ledger.record(reply, in: chat, as: .dispatched)
        ledger = try PhoneWishLedger(file: file)
        for _ in 0..<30 { _ = try ledger.reply(id: reply, to: chat, pairID: pair, text: "Add a reset button") }
        let job = try XCTUnwrap(ledger.job(chat, for: pair))
        XCTAssertEqual(ledger.jobs.count, 1)
        XCTAssertEqual(job.id, chat)
        XCTAssertEqual(job.submissions.map(\.text), ["Make a counter", "Add a reset button"])
        XCTAssertEqual(job.submissions.last?.state, .dispatched)
    }

    func testFollowupsWhileBuildingStayInTheSameConversationInSendOrder() throws {
        var ledger = try PhoneWishLedger(file: file())
        let chat = UUID(), pair = UUID(), first = UUID(), second = UUID()
        _ = try ledger.accept(id: chat, pairID: pair, wish: "Make a counter")
        try ledger.update(.init(id: chat, phase: .building))
        _ = try ledger.reply(id: first, to: chat, pairID: pair, text: "Add reset")
        _ = try ledger.reply(id: second, to: chat, pairID: pair, text: "Make the number larger")
        let job = try XCTUnwrap(ledger.job(chat, for: pair))
        XCTAssertEqual(ledger.jobs.count, 1)
        XCTAssertEqual(job.submissions.map(\.id), [chat, first, second])
        XCTAssertEqual(job.status.phase, .building)
    }
}
