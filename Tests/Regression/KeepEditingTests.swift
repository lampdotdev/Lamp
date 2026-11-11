import AppKit
import XCTest
@testable import Lamp

/// Keep Editing on the review of a copy made for part of someone's suggested change: the review closes and the copy stays
/// as it was, ready and still unopened, with Review Changes… in its chat to come back to the review. Cancel on the same
/// review throws the copy away.
@MainActor
final class KeepEditingTests: XCTestCase {
    private var root: URL!
    private let realInspect = Store.inspectForReview

    override func setUpWithError() throws {
        // Under the home folder, as Lamp keeps its wishes: a wish's folder is written only where no link leads on the way.
        root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-keep-editing-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        Store.inspectForReview = realInspect
        try? FileManager.default.removeItem(at: root)
    }

    private func waitUntil(_ what: String, _ done: () -> Bool) async throws {
        let until = Date().addingTimeInterval(60)
        while !done() {
            guard Date() < until else { return XCTFail("timed out waiting until \(what)") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    func testKeepEditingKeepsTheCopyThatCancelThrowsAway() async throws {
        _ = NSApplication.shared
        // The reading of the code never finishes, so no AI is asked: the review stays up, saying so.
        Store.inspectForReview = { _ in
            var found = Sharing.Inspection()
            found.finished = false
            return found
        }
        let wish = try Template.scaffold(name: "Bike Map", platform: .mac, in: root)
        let made = try Template.scaffold(name: "Bike Map Update", platform: .mac, in: root)
        var job = AppUpdates.Job(url: "https://github.com/someone/bike-map", base: "1111111111111111111111111111111111111111",
                                 target: "2222222222222222222222222222222222222222", wish: wish.id,
                                 suggestion: AppUpdates.Suggestion(number: 12, login: "sam", wanted: "The bike lanes, not the night map"))
        job.ready = true
        try job.save(in: made)
        let laidOut = made.dir.appendingPathComponent(AppUpdates.Job.folder + "/changes.diff")
        try "the request's diff\n".write(to: laidOut, atomically: true, encoding: .utf8)

        let store = Store(testingAt: root)
        store.welcomeFinished = true
        store.lookedAtSetupForTest()
        let copy = try XCTUnwrap(store.current(made))
        XCTAssertTrue(store.offersReviewChanges(copy, busy: false), "a ready copy, idle: its chat offers the review")
        XCTAssertFalse(store.offersReviewChanges(copy, busy: true), "not while a turn runs in it")

        store.reviewChanges(copy)
        try await waitUntil("the review is up") { store.pendingImport != nil }
        let pending = try XCTUnwrap(store.pendingImport)
        XCTAssertEqual(pending.copy, copy.id)
        XCTAssertFalse(store.offersReviewChanges(copy, busy: false), "not while its review is up")

        store.keepEditing()
        XCTAssertNil(store.pendingImport)
        XCTAssertNil(store.reviewWork, "its check is stopped")
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.package.folder.path), "the review's unpacked package goes")
        // The copy as it was: listed, its job still ready, what was laid out for it still there, and still not to be opened.
        XCTAssertNotNil(store.current(copy))
        XCTAssertEqual(AppUpdates.Job.load(copy), job)
        XCTAssertTrue(FileManager.default.fileExists(atPath: laidOut.path))
        XCTAssertFalse(AppUpdates.mayOpen(copy))
        XCTAssertTrue(store.offersReviewChanges(copy, busy: false), "Review Changes… brings the review back")
        // As after a restart: worked out from the copy's job alone.
        XCTAssertTrue(Store(testingAt: root).offersReviewChanges(copy, busy: false))

        // Cancel on the review it comes back to throws the copy away.
        store.reviewChanges(copy)
        try await waitUntil("the review is up again") { store.pendingImport != nil }
        store.cancelImport()
        try await waitUntil("the copy is gone") { !FileManager.default.fileExists(atPath: copy.dir.path) }
        XCTAssertNil(store.current(copy))
        XCTAssertNotNil(store.current(wish), "the wish itself is never touched")
    }
}
