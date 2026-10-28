import XCTest
@testable import Lamp

/// After an app goes on a phone signed for another Apple team, the old team's copy stays there until the person
/// answers the card: Remove Old Copy takes it off, Keep Old Copy leaves it, and a removal that fails keeps asking.
@MainActor
final class OldCopyCardTests: XCTestCase {
    private var root: URL!
    private let old = "dev.lamp.app.today.abcde12345"
    private let udid = "00008110-test"

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-old-copy-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A store with one app whose chat holds the card, and the card's id.
    private func card() throws -> (Store, LampProject, UUID) {
        let project = try Template.scaffold(name: "Todayoc", platform: .mac, in: root)
        let store = Store(testingAt: root)
        let line = LogLine(kind: .oldCopy, text: old, retryPhone: udid)
        store.logs[project.id] = [line]
        return (store, project, line.id)
    }

    private func text(_ store: Store, _ project: LampProject, _ id: UUID) -> String? {
        store.logs[project.id]?.first { $0.id == id }?.text
    }

    func testRemoveTakesTheOldCopyOffThatPhone() async throws {
        let (store, project, id) = try card()
        var removed: [String] = []
        await store.answerOldCopy(project, line: id, remove: true) { removed.append("\($0) from \($1)") }
        XCTAssertEqual(removed, ["\(old) from \(udid)"])
        XCTAssertEqual(text(store, project, id), OldCopyLine.removed + old)
        // Answered: pressing again does nothing more.
        await store.answerOldCopy(project, line: id, remove: true) { removed.append("\($0) from \($1)") }
        XCTAssertEqual(removed.count, 1)
    }

    func testKeepLeavesTheOldCopyOnThePhone() async throws {
        let (store, project, id) = try card()
        var removed = false
        await store.answerOldCopy(project, line: id, remove: false) { _, _ in removed = true }
        XCTAssertFalse(removed)
        XCTAssertEqual(text(store, project, id), OldCopyLine.kept + old)
    }

    func testAFailedRemovalSaysWhyAndKeepsAsking() async throws {
        let (store, project, id) = try card()
        await store.answerOldCopy(project, line: id, remove: true) { _, _ in
            throw PhoneFailure(stage: .install, output: "The device is locked.")
        }
        XCTAssertEqual(text(store, project, id), old, "the card still asks")
        XCTAssertTrue(store.logs[project.id]?.contains { $0.kind == .error && $0.text == OldCopyLine.failed(phone: "your phone") } == true)
        // Asked again, it can still be removed.
        var removed = false
        await store.answerOldCopy(project, line: id, remove: true) { _, _ in removed = true }
        XCTAssertTrue(removed)
        XCTAssertEqual(text(store, project, id), OldCopyLine.removed + old)
    }

    /// Another install, or another destination in Try On, takes the Retry off the chat's failed installs. The card
    /// keeps its phone, since that's where the old copy is, and both its answers still work.
    func testTheCardKeepsItsPhoneAfterAnotherInstall() async throws {
        let (store, project, id) = try card()
        store.clearPhoneRetry(project)
        XCTAssertEqual(store.logs[project.id]?.first { $0.id == id }?.retryPhone, udid)
        var removed: [String] = []
        await store.answerOldCopy(project, line: id, remove: true) { removed.append("\($0) from \($1)") }
        XCTAssertEqual(removed, ["\(old) from \(udid)"])
        XCTAssertEqual(text(store, project, id), OldCopyLine.removed + old)
    }

    /// While a removal is under way the card is taken: pressing Remove again starts no second one, and Keep doesn't
    /// mark it kept while the old copy is being deleted.
    func testAnAnswerUnderWayTakesTheCard() async throws {
        let (store, project, id) = try card()
        var calls = 0
        var finish: CheckedContinuation<Void, Never>?
        let first = Task {
            await store.answerOldCopy(project, line: id, remove: true) { _, _ in
                calls += 1
                await withCheckedContinuation { finish = $0 }
            }
        }
        while finish == nil { await Task.yield() }
        await store.answerOldCopy(project, line: id, remove: true) { _, _ in calls += 1 }
        await store.answerOldCopy(project, line: id, remove: false) { _, _ in calls += 1 }
        XCTAssertEqual(calls, 1, "one removal at a time")
        XCTAssertEqual(text(store, project, id), old, "not marked kept while the removal runs")
        finish?.resume()
        await first.value
        XCTAssertEqual(text(store, project, id), OldCopyLine.removed + old)
    }
}
