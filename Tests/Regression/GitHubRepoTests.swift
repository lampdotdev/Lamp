import XCTest
@testable import Lamp

/// What goes on GitHub: the shared wish unpacked, with what builds it, the shared file, a README and never Lamp's
/// own records or a key. And what comes back: the tree opens in Lamp as the file does, its credits naming the repository.
final class GitHubRepoTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-github-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testTheStagedRepositoryBuildsOnItsOwnAndOpensInLamp() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        try Template.writeOwnedFiles(for: wish)
        let staged = try GitHubRepo.stage(wish, repo: "someone/tally", link: URL(string: "https://lamp.dev/w/AyTkit4xCc"))
        defer { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        let fm = FileManager.default
        func has(_ path: String) -> Bool { fm.fileExists(atPath: staged.folder.appendingPathComponent(path).path) }

        // The code and what builds it, so `./build.sh` works with no Lamp.
        for path in ["Sources/App.swift", "Sources/LampSupport.swift", "Package.swift", "build.sh", "APP.md", "lamp-app.json", Credits.file, ".gitignore"] {
            XCTAssertTrue(has(path), path)
        }
        // The shared file beside it, and the README pointing at the Share Link and at it.
        XCTAssertTrue(has("tally.lampapp"))
        let readme = try String(contentsOf: staged.folder.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(readme.contains("https://lamp.dev/w/AyTkit4xCc"))
        XCTAssertTrue(readme.contains("[tally.lampapp](tally.lampapp)"))
        XCTAssertTrue(readme.contains("./build.sh"))
        // Nothing of Lamp's records.
        XCTAssertFalse(has(".lamp"))
        XCTAssertFalse(has(".git"))
        XCTAssertEqual(staged.open.link?.absoluteString, "https://lamp.dev/w/AyTkit4xCc")
        XCTAssertTrue(readme.contains("https://github.com/someone/tally"))

        // The tree opens as the shared file does: only the sender's code is read (Lamp's own file beside it isn't), and
        // the chain ends with this wish, named where it lives.
        let package = try Sharing.open(staged.folder)
        defer { try? fm.removeItem(at: package.folder) }
        XCTAssertEqual(package.name, "Tally")
        XCTAssertTrue(package.sources.contains { $0.lastPathComponent == "App.swift" })
        XCTAssertFalse(package.sources.contains { $0.lastPathComponent == "LampSupport.swift" })
        XCTAssertEqual(package.credits?.remixOf.last?.url, "https://github.com/someone/tally")
        XCTAssertFalse(fm.fileExists(atPath: package.folder.appendingPathComponent("tally.lampapp").path))
        // The file inside says the same.
        let file = try Sharing.open(staged.folder.appendingPathComponent("tally.lampapp"))
        defer { try? fm.removeItem(at: file.folder) }
        XCTAssertEqual(file.credits?.remixOf.last?.url, "https://github.com/someone/tally")
        // Opened here as the same wish and shared on as a file, it still says where it lives; put on another repository,
        // it lives there now.
        let link = Credits.Remix(name: "Tally", wish: file.credits?.remixOf.last?.wish)
        XCTAssertEqual(file.credits?.remixed(from: link).remixOf.last?.url, "https://github.com/someone/tally")
        var moved = link
        moved.url = "https://github.com/else/tally"
        XCTAssertEqual(file.credits?.remixed(from: moved).remixOf.last?.url, "https://github.com/else/tally")
    }

    func testARepositoryAddressIsReadAsGitTakesIt() {
        XCTAssertEqual(RepoImport.source(from: "https://github.com/someone/tally"), RepoImport.Source(owner: "someone", name: "tally"))
        XCTAssertEqual(RepoImport.source(from: " github.com/someone/tally.git/ "), RepoImport.Source(owner: "someone", name: "tally"))
        XCTAssertEqual(RepoImport.source(from: "git@github.com:someone/tally.git"), RepoImport.Source(owner: "someone", name: "tally"))
        XCTAssertEqual(RepoImport.source(from: "ssh://git@github.com/someone/tally.git"), RepoImport.Source(owner: "someone", name: "tally"))
        XCTAssertEqual(RepoImport.source(from: "https://github.com/someone/tally/tree/feature/x")?.ref, "feature/x")
        XCTAssertEqual(RepoImport.source(from: "https://github.com/someone/tally/commit/199f010cf9b35eb58ec934d95eba1ab977c880c1")?.ref,
                       "199f010cf9b35eb58ec934d95eba1ab977c880c1")
        for bad in ["https://example.com/someone/tally", "https://github.com/someone", "https://github.com/someone/tally/tree/--upload-pack=x",
                    "https://github.com/someone/tally/tree/../x", "https://github.com/someone/tally/blob/main/README.md", "not an address"] {
            XCTAssertNil(RepoImport.source(from: bad), bad)
        }
    }

    func testAShareAlikeUpstreamLeavesNoLicenseToChoose() {
        var credits = Credits()
        XCTAssertTrue(GitHubRepo.canOfferLicense(credits))
        credits.upstream = [Credits.Source(name: "Engine", license: "GPL-3.0-or-later")]
        XCTAssertFalse(GitHubRepo.canOfferLicense(credits))
        credits.upstream = [Credits.Source(name: "Map", license: "ODbL-1.0")]
        XCTAssertTrue(GitHubRepo.canOfferLicense(credits), "data under its own share-alike licence stays credited, the code can still be MIT")
        XCTAssertTrue(GitHubRepo.mitLicense(holder: "someone").contains("Copyright (c)"))
    }
}
