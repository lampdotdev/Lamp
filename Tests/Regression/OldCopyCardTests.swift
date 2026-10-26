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
}
