import XCTest
@testable import Lamp

/// Sharing an app makes its file in a temporary folder of its own. Whether the file is shared, copied or exported,
/// or can't be made at all, that folder goes, so sharing again and again leaves nothing behind.
final class SharingTemporaryFilesTests: XCTestCase {
    private var root: URL?
    /// In every name the test's app gives its files, so only its own folders are counted while other runs share.
    private let mark = UUID().uuidString
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func project(files: Int = 1) throws -> LampProject {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-sharing-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("tally")
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        for index in 0..<files {
            try "let count\(index) = 0".write(to: dir.appendingPathComponent("Sources/\(mark)-\(index).swift"), atomically: false, encoding: .utf8)
        }
        return LampProject(id: "tally", name: "Tally \(mark)", exe: "Tally", dir: dir)
    }

    /// The folders sharing made in the temporary folder for this test's app.
    private func workFolders() throws -> Set<String> {
        let fm = FileManager.default
        return Set(try fm.contentsOfDirectory(atPath: fm.temporaryDirectory.path)
            .filter { $0.hasPrefix("forge-share-") }
            .filter { folder in
                let files = (try? fm.subpathsOfDirectory(atPath: fm.temporaryDirectory.appendingPathComponent(folder).path)) ?? []
                return files.contains { $0.contains(mark) }
            })
    }

    func testSharedFileLeavesNoTemporaryFolder() throws {
        let project = try project()
        let file = try Store.sharedFile(of: project, at: root!.appendingPathComponent("Shared/Tally.lampapp"))
        XCTAssertNoThrow(try Sharing.open(file))
        XCTAssertEqual(try workFolders(), [])
    }

    func testFileThatCantBeMadeLeavesNoTemporaryFolder() throws {
        let project = try project(files: Sharing.maxFiles + 1)
        XCTAssertThrowsError(try Store.sharedFile(of: project, at: root!.appendingPathComponent("Shared/Tally.lampapp")))
        XCTAssertEqual(try workFolders(), [])
    }
}
