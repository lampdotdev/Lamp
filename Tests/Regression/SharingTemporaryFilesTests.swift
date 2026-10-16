import XCTest
@testable import Lamp

/// Sharing an app makes its file in a temporary folder of its own. Whether the file is shared, copied or exported,
/// or can't be made at all, that folder goes, so sharing again and again leaves nothing behind.
final class SharingTemporaryFilesTests: XCTestCase {
    private var root: URL?
    /// In every name the test's app gives its files, so only its own folders are counted while other runs share.
    private let mark = UUID().uuidString
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func project(files: Int = 1, mark: String? = nil, assetBytes: Int = 0) throws -> LampProject {
        let fm = FileManager.default
        let mark = mark ?? self.mark
        let root = root ?? fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-sharing-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent(mark)
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        for index in 0..<files {
            try "let count\(index) = 0".write(to: dir.appendingPathComponent("Sources/\(mark)-\(index).swift"), atomically: false, encoding: .utf8)
        }
        if assetBytes > 0 {
            try fm.createDirectory(at: dir.appendingPathComponent(Sharing.Assets.folder), withIntermediateDirectories: true)
            var bytes = Data(count: assetBytes)
            bytes.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, assetBytes, $0.baseAddress!) }
            try bytes.write(to: dir.appendingPathComponent("\(Sharing.Assets.folder)/sound.bin"))
        }
        return LampProject(id: mark, name: "Tally", exe: "Tally", dir: dir)
    }

    /// The folders sharing made in the temporary folder for an app of this test's, looking only past `skipping`.
    private func workFolders(mark: String? = nil, skipping: Set<String> = []) throws -> Set<String> {
        let fm = FileManager.default
        let mark = mark ?? self.mark
        return Set(try fm.contentsOfDirectory(atPath: fm.temporaryDirectory.path)
            .filter { $0.hasPrefix("forge-share-") && !skipping.contains($0) }
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

    /// Two shares going to the same file at once, the first slow to make: the file left is the second's, which
    /// read the app last, and neither fails.
    func testOverlappingSharesLeaveTheLaterOne() throws {
        let first = UUID().uuidString, second = UUID().uuidString
        let slow = try project(mark: first, assetBytes: 40_000_000)
        let quick = try project(mark: second)
        let destination = root!.appendingPathComponent("Shared/Tally.lampapp")
        // Folders already there aren't the first share's, and looking through them all takes longer than it does.
        let earlier = Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path))
        let done = expectation(description: "first share")
        var firstResult: Result<URL, Error>?
        DispatchQueue.global().async {
            firstResult = Result { try Store.sharedFile(of: slow, at: destination) }
            done.fulfill()
        }
        // The second is asked for once the first has begun.
        let start = Date()
        while try workFolders(mark: first, skipping: earlier).isEmpty, firstResult == nil, Date().timeIntervalSince(start) < 10 { usleep(1000) }
        XCTAssertNoThrow(try Store.sharedFile(of: quick, at: destination))
        wait(for: [done], timeout: 60)
        XCTAssertNoThrow(try firstResult?.get())
        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        listing.arguments = ["-1", destination.path]
        let pipe = Pipe()
        listing.standardOutput = pipe
        try listing.run()
        let entries = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        listing.waitUntilExit()
        XCTAssertTrue(entries.contains(second), entries)
    }
}
