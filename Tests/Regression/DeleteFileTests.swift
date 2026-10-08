import XCTest
@testable import Lamp

/// `delete_file` has its own list of what is Lamp's (it also covers files the agent may edit and not
/// delete), so the history is checked here as well as in Privacy.
@MainActor
final class DeleteFileTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    func testTheHistoryAndLampsOwnFilesCantBeDeleted() throws {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-sandbox-test-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("coinflip", isDirectory: true)
        try fm.createDirectory(at: dir.appendingPathComponent(".git/hooks"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        for file in [".git/config", ".git/HEAD", ".git/hooks/post-commit", ".gitignore", "Package.swift", "Sources/Old.swift"] {
            try "x".write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        let project = LampProject(id: "coinflip", name: "Coin Flip", exe: "CoinFlip", dir: dir)
        for path in [".git/config", ".git/HEAD", ".GIT/config", ".git/hooks/post-commit", "Sources/../.git/config", dir.path + "/.git/config", ".gitignore", "package.swift"] {
            let (status, answer) = Store.deleteFile(path, in: project)
            XCTAssertEqual(status, 400, "\(path): \(answer)")
            XCTAssertTrue((answer["error"] as? String ?? "").contains("belongs to Lamp"), "\(path): \(answer)")
        }
        for file in [".git/config", ".git/HEAD", ".git/hooks/post-commit", ".gitignore", "Package.swift"] {
            XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent(file).path), file)
        }
        let (status, answer) = Store.deleteFile("Sources/Old.swift", in: project)
        XCTAssertEqual(status, 200, "\(answer)")
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("Sources/Old.swift").path))
    }
}
