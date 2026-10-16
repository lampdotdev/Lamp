import XCTest
@testable import Lamp

/// Sharing an app makes its file in a temporary folder of its own. Whether the file is shared, copied or exported,
/// or can't be made at all, that folder goes, so sharing again and again leaves nothing behind.
final class SharingTemporaryFilesTests: XCTestCase {
    private var root: URL?
    /// In every name the test's app gives its files, so only its own folders are counted while other runs share.
    private let mark = UUID().uuidString
    /// Files the test locked, unlocked again before its folder goes.
    private var locked: [URL] = []
    /// A small disk the test attached, detached when it's done.
    private var disk: URL?
    override func tearDown() {
        for file in locked { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file.path) }
        if let disk { _ = try? run("/usr/bin/hdiutil", ["detach", disk.path, "-force"]) }
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: tool, code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output]) }
        return output
    }

    /// A file of the app's locked in Finder, as a person can lock any file.
    private func lock(_ file: URL) throws {
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: file.path)
        locked.append(file)
    }

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
        let entries = try run("/usr/bin/zipinfo", ["-1", destination.path])
        XCTAssertTrue(entries.contains(second), entries)
    }

    /// A file the person locked in Finder is shared like any other, and the copy made of it goes with the rest,
    /// whether the share is made or refused. The person's own file stays locked.
    func testLockedFileLeavesNoTemporaryFolder() throws {
        let made = try project()
        let source = made.dir.appendingPathComponent("Sources/\(mark)-0.swift")
        try lock(source)
        XCTAssertNoThrow(try Store.sharedFile(of: made, at: root!.appendingPathComponent("Shared/Tally.lampapp")))
        XCTAssertEqual(try workFolders(), [])
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: source.path)[.immutable] as? Bool, true)
    }

    func testLockedFileInAShareThatCantBeMadeLeavesNoTemporaryFolder() throws {
        let refused = try project(files: Sharing.maxFiles + 1)
        try lock(refused.dir.appendingPathComponent("Sources/\(mark)-0.swift"))
        XCTAssertThrowsError(try Store.sharedFile(of: refused, at: root!.appendingPathComponent("Shared/Tally.lampapp")))
        XCTAssertEqual(try workFolders(), [])
    }

    /// The file already handed on (pasted, in a picker) is there the whole time a later share replaces it.
    func testHandedOnFileIsNeverMissing() throws {
        let made = try project()
        let destination = try Store.sharedFile(of: made, at: root!.appendingPathComponent("Shared/Tally.lampapp"))
        let counts = NSLock()
        var reads = 0, missing = 0, stop = false
        let reader = DispatchGroup()
        reader.enter()
        DispatchQueue.global().async {
            while !counts.withLock({ stop }) {
                let found = (try? Data(contentsOf: destination)) != nil
                counts.withLock { if found { reads += 1 } else { missing += 1 } }
            }
            reader.leave()
        }
        for _ in 0..<40 { _ = try Store.sharedFile(of: made, at: destination) }
        counts.withLock { stop = true }
        reader.wait()
        XCTAssertGreaterThan(reads, 0)
        XCTAssertEqual(missing, 0)
    }

    /// Exporting over a file on a disk with too little room for the new one leaves the old one as it was.
    func testExportThatDoesntFitKeepsTheOldFile() throws {
        let image = root ?? FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-sharing-\(UUID().uuidString)")
        root = image
        try FileManager.default.createDirectory(at: image, withIntermediateDirectories: true)
        let volume = image.appendingPathComponent("disk")
        try run("/usr/bin/hdiutil", ["create", "-size", "16m", "-fs", "HFS+", "-volname", "Small", image.appendingPathComponent("small.dmg").path])
        try run("/usr/bin/hdiutil", ["attach", image.appendingPathComponent("small.dmg").path, "-mountpoint", volume.path, "-nobrowse"])
        disk = volume
        let destination = volume.appendingPathComponent("Tally.lampapp")
        _ = try Store.sharedFile(of: try project(mark: UUID().uuidString), at: destination)
        let old = try Data(contentsOf: destination)
        let free = (try FileManager.default.attributesOfFileSystem(forPath: volume.path)[.systemFreeSize] as? NSNumber)?.intValue ?? 0
        try Data(count: max(0, free - 1_000_000)).write(to: volume.appendingPathComponent("filler"))
        XCTAssertThrowsError(try Store.sharedFile(of: try project(mark: UUID().uuidString, assetBytes: 8_000_000), at: destination))
        XCTAssertEqual(try? Data(contentsOf: destination), old)
    }
}
