import XCTest
@testable import Lamp

final class PhoneWishLedgerTests: XCTestCase {
    private func file() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("wishes.json")
    }

    // Dan's case: the phone disappears after Send, so it cannot know whether the Mac received it.
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

    // Dan's case: locking the phone during work must preserve the job and show its progress on return.
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
}
