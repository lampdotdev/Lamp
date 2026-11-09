import AppKit
import XCTest
@testable import Lamp

/// Try Again on a review whose sheet is up, after its reading of the code didn't finish: the retry reads the same
/// package again on that sheet, so a second failure is shown there with Try Again, rather than going to the desk while
/// the sheet goes on saying it's checking. The update is fetched as Review Update… fetches it, with git, from a
/// repository on this Mac standing in for GitHub.
@MainActor
final class ReviewRetryTests: XCTestCase {
    private var roots: [URL] = []
    private let realInspect = Store.inspectForReview

    override func setUp() { expectNoSharingFoldersLeft() }

    override func tearDown() {
        Store.inspectForReview = realInspect
        unsetenv("GIT_CONFIG_GLOBAL")
        for root in roots { try? FileManager.default.removeItem(at: root) }
    }

    /// In the temporary folder, which Lamp's own git may read. git's Mac-wide settings are a file of the test's own,
    /// which sends GitHub's someone/ to a folder there.
    private func newRoot() throws -> (root: URL, repos: URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-review-retry-test-\(UUID().uuidString)")
        let repos = root.appendingPathComponent("repos", isDirectory: true)
        try fm.createDirectory(at: repos, withIntermediateDirectories: true)
        roots.append(root)
        let settings = root.appendingPathComponent("gitconfig")
        try "[url \"\(repos.absoluteString)\"]\n\tinsteadOf = https://github.com/someone/\n".write(to: settings, atomically: true, encoding: .utf8)
        setenv("GIT_CONFIG_GLOBAL", settings.path, 1)
        return (root, repos)
    }

    /// A wish's repository, as Publish leaves one: its manifest and its code, in one commit.
    private func makeRepository(in repos: URL) throws {
        let fm = FileManager.default
        let repo = repos.appendingPathComponent("tally.git")
        try fm.createDirectory(at: repo.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["format": 2, "name": "Tally", "exportedAt": "2026-10-01T00:00:00Z"])
            .write(to: repo.appendingPathComponent("lamp-app.json"))
        try "let a = 1\n".write(to: repo.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        let made = TestShell.run("git init -q && git add -A && git -c user.name=t -c user.email=t@localhost commit -qm one", in: repo)
        XCTAssertEqual(made.status, 0, made.output)
    }

    private func waitUntil(_ what: String, _ done: () -> Bool) async throws {
        let until = Date().addingTimeInterval(60)
        while !done() {
            guard Date() < until else { return XCTFail("timed out waiting until \(what)") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    func testAReadingThatFailsAgainAfterTryAgainStaysOnItsSheet() async throws {
        _ = NSApplication.shared
        let (root, repos) = try newRoot()
        try makeRepository(in: repos)
        // The reading of the code never finishes, as when the review's time runs out while it reads.
        let counted = Counted()
        Store.inspectForReview = { _ in
            counted.add()
            var found = Sharing.Inspection()
            found.finished = false
            return found
        }
        let store = Store(testingAt: root.appendingPathComponent("Apps"))
        store.welcomeFinished = true
        store.lookedAtSetupForTest()

        store.importRepository(RepoImport.Source(owner: "someone", name: "tally"), request: nil, updating: "tally-wish")
        try await waitUntil("the first reading failed") { store.reviewWork?.failed == true }
        let pending = try XCTUnwrap(store.pendingImport, "the sheet is up: \(store.reviewWork?.line ?? "")")
        XCTAssertEqual(store.reviewWork?.sheet, pending.id)
        XCTAssertNil(store.deskReview(of: "tally-wish"), "shown on the sheet, not the desk")

        // Fetching it again now would fail: the repository is gone, as a connection can be.
        try FileManager.default.removeItem(at: repos.appendingPathComponent("tally.git"))
        store.retryReview()
        try await waitUntil("the retry failed") { store.reviewWork?.failed == true }

        // The same sheet, saying why, with Try Again: nothing went to the desk.
        XCTAssertEqual(store.pendingImport?.id, pending.id)
        XCTAssertEqual(store.reviewWork?.sheet, pending.id, "the retry's failure is the sheet's")
        XCTAssertEqual(store.reviewWork?.line, "Lamp couldn't finish checking this. Nothing was changed.")
        XCTAssertNil(store.deskReview(of: "tally-wish"))
        XCTAssertEqual(counted.count, 2, "the same package read again, not fetched")

        // A Cancel right after Try Again isn't undone by the retry it overtook.
        store.retryReview()
        store.cancelImport()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(store.pendingImport)
        XCTAssertNil(store.reviewWork)
        XCTAssertEqual(counted.count, 2)

        // The fetch's own folder: the review was made from a copy of the tree in it, which Cancel removed.
        let fm = FileManager.default
        for left in (try? fm.contentsOfDirectory(at: Sharing.workFolder, includingPropertiesForKeys: nil)) ?? []
        where left.lastPathComponent.hasPrefix(Store.fetchedPrefix) { try? fm.removeItem(at: left) }
    }
}

/// How many times the code was read, from whichever thread read it.
private final class Counted: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}
