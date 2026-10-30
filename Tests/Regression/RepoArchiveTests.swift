import XCTest
@testable import Lamp

/// A repository fetched with no git: GitHub's archive, which must be refused whole, before anything is written, for
/// anything but plain folders and files. Tests/Fixtures/github-archive holds a real answer, recorded on 2026-10-30:
/// octocat/Hello-World at its default branch, from codeload.github.com. The refused archives are made here, byte by byte,
/// as an attacker's repository or server would make them.
final class RepoArchiveTests: XCTestCase {
    private let commit = "7fd1a60b01f91b314f59955a4e4d4e80d8edf11d"
    private var top: String { "Hello-World-\(commit)/" }
    private let source = RepoImport.Source(owner: "octocat", name: "Hello-World")
    private var folder: URL!
    private let realAsk = RepoArchive.ask

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-archive-\(UUID().uuidString)")
    }

    override func tearDown() {
        RepoArchive.ask = realAsk
        try? FileManager.default.removeItem(at: folder)
    }

    private var recorded: Data {
        get throws {
            try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Fixtures/github-archive/Hello-World-7fd1a60.tar.gz"))
        }
    }

    // MARK: A tar, by hand

    private func block(_ name: String, type: Character = "0", size: Int = 0, link: String = "", magic: String = "ustar\0") -> Data {
        var header = Data(repeating: 0, count: 512)
        func put(_ text: String, at offset: Int) { header.replaceSubrange(offset..<(offset + text.utf8.count), with: Data(text.utf8)) }
        put(name, at: 0)
        put("0000644\0", at: 100)
        put(String(format: "%011o\0", size), at: 124)
        put(String(type), at: 156)
        put(link, at: 157)
        put(magic, at: 257)
        put("        ", at: 148)
        let sum = header.reduce(0) { $0 + Int($1) }
        put(String(format: "%06o\0 ", sum), at: 148)
        return header
    }

    private func file(_ name: String, _ text: String = "hi", type: Character = "0") -> Data {
        let body = Data(text.utf8)
        return block(name, type: type, size: body.count) + body + Data(repeating: 0, count: (512 - body.count % 512) % 512)
    }

    private func pax(_ key: String, _ value: String, type: Character = "x", then entry: Data) -> Data {
        var length = key.utf8.count + value.utf8.count + 3
        length += String(length).count
        if String(length).count + key.utf8.count + value.utf8.count + 3 != length { length += 1 }
        return file("pax", "\(length) \(key)=\(value)\n", type: type) + entry
    }

    private func tar(_ entries: Data...) -> Data {
        block(top, type: "5") + entries.reduce(Data(), +) + Data(repeating: 0, count: 1024)
    }

    private func refuses(_ archive: Data, _ line: UInt = #line) {
        XCTAssertThrowsError(try RepoArchive.read(tar: archive, commit: commit), line: line) {
            XCTAssertTrue($0 is Sharing.ImportError, line: line)
        }
    }

    // MARK: What's fine

    func testARealArchiveIsReadAndWritten() async throws {
        let archive = try recorded
        RepoArchive.ask = { request, _ in
            request.url?.host == "api.github.com" ? (200, Data(("7fd1a60b01f91b314f59955a4e4d4e80d8edf11d\n").utf8)) : (200, archive)
        }
        let fetched = try await RepoArchive.fetch(source, into: folder)
        XCTAssertEqual(fetched.commit, commit)
        XCTAssertEqual(fetched.url, "https://github.com/octocat/Hello-World")
        XCTAssertEqual(try String(contentsOf: fetched.tree.appendingPathComponent("README"), encoding: .utf8), "Hello World!\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fetched.tree.appendingPathComponent(".git").path))
        let attributes = try FileManager.default.attributesOfItem(atPath: folder.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
        let file = try FileManager.default.attributesOfItem(atPath: fetched.tree.appendingPathComponent("README").path)
        XCTAssertEqual(file[.posixPermissions] as? Int, 0o600)
    }

    func testFoldersAndALongPathAreFine() throws {
        let long = String(repeating: "a", count: 150)
        let entries = try RepoArchive.read(tar: tar(block(top + "Sources/", type: "5"), file(top + "Sources/App.swift"),
                                                    pax("path", top + long + ".swift", then: file("short"))), commit: commit)
        XCTAssertEqual(entries.map(\.path), ["Sources", "Sources/App.swift", long + ".swift"])
    }

    // MARK: Paths

    func testPathsThatLeaveTheTreeAreRefused() {
        refuses(tar(file(top + "../outside")))
        refuses(tar(file(top + "a/../../outside")))
        refuses(tar(file(top + "./a")))
        refuses(tar(file("/etc/outside")))
        refuses(tar(file("../outside")))
        refuses(tar(file("Other-\(commit)/a")))
        refuses(tar(pax("path", "../../outside", then: file(top + "fine"))))
        refuses(tar(pax("path", "/tmp/outside", then: file(top + "fine"))))
        refuses(tar(file(top + "a\\..\\b")))
        refuses(tar(file(top + "a//b")))
    }

    // MARK: Kinds

    func testLinksAndSpecialFilesAreRefused() {
        refuses(tar(block(top + "link", type: "2", link: "/etc/passwd")))
        refuses(tar(block(top + "link", type: "1", link: top + "a")))
        for special: Character in ["3", "4", "6", "7", "L", "K", "S"] { refuses(tar(block(top + "odd", type: special))) }
    }

    /// A header can't change what the fields mean to anything reading on from it.
    func testExtendedHeadersOtherThanAPathAreRefused() {
        refuses(tar(pax("size", "0", then: file(top + "a"))))
        refuses(tar(pax("linkpath", "/etc/passwd", then: file(top + "a"))))
        refuses(tar(pax("path", "../x", type: "g", then: file(top + "a"))))
    }

    // MARK: Conflicts

    func testNamesTheDiskWouldTakeForOneAreRefused() {
        refuses(tar(file(top + "a"), file(top + "a")))
        refuses(tar(file(top + "App.swift"), file(top + "app.swift")))
        refuses(tar(file(top + "caf\u{e9}"), file(top + "cafe\u{301}")))
        refuses(tar(file(top + "a"), file(top + "a/b")))
        refuses(tar(file(top + "a/b"), file(top + "a")))
        refuses(tar(file(top + "a"), block(top + "a/", type: "5")))
    }

    /// Two spellings of a folder are one folder on the disk, which would put their files together.
    func testAFolderSpelledTwoWaysIsRefused() throws {
        refuses(tar(file(top + "Sources/a"), file(top + "sources/b")))
        refuses(tar(block(top + "Sources/", type: "5"), block(top + "sources/", type: "5")))
        refuses(tar(block(top + "Sources/", type: "5"), file(top + "sources/b")))
        refuses(tar(file(top + "a/Deep/x"), file(top + "A/deep/y")))
        refuses(tar(file(top + "caf\u{e9}/a"), file(top + "cafe\u{301}/b")))
        XCTAssertEqual(try RepoArchive.read(tar: tar(file(top + "Sources/a"), file(top + "Sources/b")), commit: commit).map(\.path), ["Sources/a", "Sources/b"])
    }

    // MARK: Which commit

    func testAnArchiveOfAnotherCommitIsRefused() {
        let other = String(repeating: "b", count: 40)
        XCTAssertThrowsError(try RepoArchive.read(tar: block("Hello-World-\(other)/", type: "5") + file("Hello-World-\(other)/a")
                                                    + Data(repeating: 0, count: 1024), commit: commit))
        refuses(pax("comment", other, type: "g", then: tar()))
    }

    func testABranchIsSettledToACommitFirstAndACommitNamedMustBeTheOneGiven() async throws {
        final class Asked: @unchecked Sendable { var urls: [String] = [] }
        let asked = Asked()
        RepoArchive.ask = { [commit] request, _ in
            asked.urls.append(request.url?.absoluteString ?? "")
            return (200, Data(commit.utf8))
        }
        var branch = source
        branch.ref = "feature/one"
        let settled = try await RepoArchive.resolve(branch)
        XCTAssertEqual(settled, commit)
        XCTAssertEqual(asked.urls, ["https://api.github.com/repos/octocat/Hello-World/commits/feature/one"])

        var other = source
        other.ref = String(repeating: "b", count: 40)
        await assertThrows { try await RepoArchive.resolve(other) }
        RepoArchive.ask = { _, _ in (200, Data("not a commit".utf8)) }
        await assertThrows { try await RepoArchive.resolve(self.source) }
        RepoArchive.ask = { _, _ in (404, Data()) }
        await assertThrows { try await RepoArchive.resolve(self.source) }
    }

    private func assertThrows(_ body: () async throws -> String, _ line: UInt = #line) async {
        do { _ = try await body(); XCTFail("should throw", line: line) } catch {}
    }

    // MARK: Limits

    func testTooManyFilesAreRefusedBeforeAnythingIsWritten() async throws {
        let many = (0...RepoArchive.maxFiles).reduce(into: Data()) { all, index in all += file(top + "f\(index)") }
        let packed = try gzip(tar(many))
        RepoArchive.ask = { request, _ in request.url?.host == "api.github.com" ? (200, Data("7fd1a60b01f91b314f59955a4e4d4e80d8edf11d".utf8)) : (200, packed) }
        let target = folder.appendingPathComponent("fetched")
        await assertThrows { try await RepoArchive.fetch(self.source, into: target).commit }
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testASizeThatRunsPastTheArchiveOrIsTooLargeIsRefused() {
        refuses(tar(block(top + "a", size: 4096)))
        refuses(tar(block(top + "a", size: RepoArchive.maxFileBytes + 1)))
    }

    func testAnArchiveThatUnpacksPastTheLimitIsStopped() throws {
        let bomb = Data(repeating: 0, count: 8 << 20)
        let packed = try gzip(bomb)
        XCTAssertLessThan(packed.count, bomb.count / 100)
        XCTAssertThrowsError(try RepoArchive.gunzip(packed, limit: 1 << 20))
        XCTAssertEqual(try RepoArchive.gunzip(packed, limit: 9 << 20), bomb)
    }

    func testACutOrPaddedArchiveIsRefused() throws {
        let archive = try recorded
        XCTAssertThrowsError(try RepoArchive.gunzip(archive.dropLast(20), limit: 1 << 20))
        XCTAssertThrowsError(try RepoArchive.gunzip(archive + Data([1, 2, 3]), limit: 1 << 20))
        XCTAssertThrowsError(try RepoArchive.gunzip(Data("not an archive at all".utf8), limit: 1 << 20))
        refuses(Data(repeating: 1, count: 512))
        refuses(block(top, type: "5"))
    }

    private func gzip(_ data: Data) throws -> Data {
        let raw = folder.appendingPathComponent("raw")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: raw)
        TestShell.run("/usr/bin/gzip", ["-k", raw.path])
        return try Data(contentsOf: raw.appendingPathExtension("gz"))
    }

    // MARK: What's said of it

    /// The credits name what Lamp asked for, whatever the repository's files claim, with no `.git` standing in for it.
    func testTheCreditsNameWhatWasFetched() throws {
        let tree = folder.appendingPathComponent("Tally")
        try FileManager.default.createDirectory(at: tree.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try Data(#"{"format": 2, "name": "Tally", "exportedAt": "2026-10-01T00:00:00Z"}"#.utf8).write(to: tree.appendingPathComponent("lamp-app.json"))
        try Data("let a = 1\n".utf8).write(to: tree.appendingPathComponent("Sources/App.swift"))
        // A claim the repository could make for itself, which nothing reads.
        try Data(#"{"url":"https://github.com/someone/else","commit":"bbbb"}"#.utf8).write(to: tree.appendingPathComponent(WaitingImport.fetchedFile))
        let url = "https://github.com/octocat/tally"
        let package = try RepoImport.open(folder: tree, fetched: RepoArchive.Fetched(tree: tree, url: url, commit: commit))
        defer { try? FileManager.default.removeItem(at: package.folder) }
        XCTAssertEqual(package.credits?.remixOf.last?.url, url)
        XCTAssertEqual(package.credits?.remixOf.last?.commit, commit)
        XCTAssertNil(WaitingImport.fetched(beside: tree), "a record in the tree isn't one Lamp kept")
    }

    /// The same files fetched from another repository or at another commit are another fetch: each is credited to its own.
    func testTwoFetchesOfTheSameFilesAreKeptApart() throws {
        let suite = "lamp-archive-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func tree(_ name: String) throws -> URL {
            let tree = folder.appendingPathComponent("\(name)/Tally")
            try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: tree.appendingPathComponent("lamp-app.json"))
            return tree
        }
        let waiting = WaitingImport(defaults: defaults, folder: folder.appendingPathComponent("Waiting"))
        let original = "https://github.com/octocat/tally", fork = "https://github.com/someone/tally"
        let other = String(repeating: "b", count: 40)
        let first = try tree("a"), second = try tree("b"), third = try tree("c"), again = try tree("d")
        XCTAssertTrue(waiting.keep(first, fetched: RepoArchive.Fetched(tree: first, url: original, commit: commit)))
        XCTAssertTrue(waiting.keep(second, fetched: RepoArchive.Fetched(tree: second, url: fork, commit: commit)))
        XCTAssertTrue(waiting.keep(third, fetched: RepoArchive.Fetched(tree: third, url: original, commit: other)))
        XCTAssertTrue(waiting.keep(again, fetched: RepoArchive.Fetched(tree: again, url: original, commit: commit)))
        XCTAssertEqual(waiting.count, 3, "the same fetch again is kept once")
        let kept = try (0..<3).map { _ in try XCTUnwrap(WaitingImport.fetched(beside: try XCTUnwrap(waiting.take(after: SetupCheck(), welcomeOver: true)))) }
        XCTAssertEqual(kept.map(\.url), [original, fork, original])
        XCTAssertEqual(kept.map(\.commit), [commit, commit, other])
    }

    /// Through the wait for the welcome, what was fetched stays with Lamp's copy, in Lamp's own folder.
    func testWhatWasFetchedIsKeptBesideTheCopy() throws {
        let suite = "lamp-archive-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tree = folder.appendingPathComponent("tree/Tally")
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: tree.appendingPathComponent("lamp-app.json"))
        let waiting = WaitingImport(defaults: defaults, folder: folder.appendingPathComponent("Waiting"))
        let url = "https://github.com/octocat/tally"
        XCTAssertTrue(waiting.keep(tree, fetched: RepoArchive.Fetched(tree: tree, url: url, commit: commit)))
        let kept = try XCTUnwrap(waiting.take(after: SetupCheck(), welcomeOver: true))
        let again = try XCTUnwrap(WaitingImport.fetched(beside: kept))
        XCTAssertEqual(again.url, url)
        XCTAssertEqual(again.commit, commit)
        XCTAssertEqual(again.tree, kept)

        // A record that names nothing plainly is no record.
        let record = kept.deletingLastPathComponent().appendingPathComponent(WaitingImport.fetchedFile)
        try Data(#"{"tree":"file:///x","url":"https://example.com/a/b","commit":"zz"}"#.utf8).write(to: record)
        XCTAssertNil(WaitingImport.fetched(beside: kept))
    }
}
