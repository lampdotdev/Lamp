import XCTest
@testable import Lamp

/// What an app's `.lampignore` (or its page's own) keeps to this computer stays out of a shared file's History/ as it
/// does out of the app it carries: files added, changed or removed after an earlier share, in an app at the wish's
/// root, in an app in a folder of its own, and in one a shared file puts at its root. Each test shares a made-up wish
/// as Lamp does with mixing on and reads the finished file.
@MainActor
final class SharedHistoryIgnoreTests: XCTestCase {
    private var roots: [URL] = []

    override func setUp() { expectNoSharingFoldersLeft() }

    override func tearDown() {
        unsetenv("GIT_CONFIG_GLOBAL")
        for root in roots { try? FileManager.default.removeItem(at: root) }
    }

    /// Under the home folder, as Lamp's own git runs confined to it, with git's Mac-wide settings an empty file.
    private func newRoot() throws -> URL {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-history-ignore-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        let settings = fm.temporaryDirectory.appendingPathComponent("lamp-test-git-settings-\(UUID().uuidString)")
        roots.append(settings)
        try "".write(to: settings, atomically: true, encoding: .utf8)
        setenv("GIT_CONFIG_GLOBAL", settings.path, 1)
        return root
    }

    /// Writes files (nil removes one) in the wish, and saves them as a version.
    private func save(_ wish: URL, _ message: String, _ files: [String: String?]) throws {
        for (path, content) in files {
            let url = wish.appendingPathComponent(path)
            if let content {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: url, atomically: true, encoding: .utf8)
            } else {
                try FileManager.default.removeItem(at: url)
            }
        }
        let git = (try? FileManager.default.attributesOfItem(atPath: wish.appendingPathComponent(".git").path)) == nil ? "git init -q -b main && " : ""
        let made = TestShell.run("/bin/bash", ["-c", git + "git add -A && git -c user.name=Lamp -c user.email=lamp@localhost commit -qm \(Sandbox.quoted(message))"], in: wish)
        XCTAssertEqual(made.status, 0, made.output)
    }

    /// A web app in `folder` of the wish: its mark and its page.
    private func webApp(_ folder: String) -> [String: String?] {
        [folder + "/" + ScreenKit.webAppPage.marker: ScreenKit.webAppPage.says, folder + "/Web/index.html": "<p>first</p>\n"]
    }

    /// Shares the wish with its history, as with mixing on, and unpacks the file: every file in it by its path, and
    /// History/history.json read as the Mac that opens it reads it.
    private func shared(_ wish: URL) throws -> (files: Set<String>, history: MixHistory?) {
        let project = try XCTUnwrap(Store.readWish(at: wish))
        let file = try Sharing.export(project, withHistory: true)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-history-ignore-unpacked-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let unpacked = TestShell.run("/usr/bin/ditto", ["-x", "-k", file.path, out.path], in: FileManager.default.temporaryDirectory)
        XCTAssertEqual(unpacked.status, 0, unpacked.output)
        var files: Set<String> = []
        for case let url as URL in FileManager.default.enumerator(at: out, includingPropertiesForKeys: [.isRegularFileKey]) ?? FileManager.DirectoryEnumerator()
        where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            files.insert(Sharing.relativePath(of: url, in: out))
        }
        return (files, MixHistory.read(in: out))
    }

    /// A Mac app at the wish's root and a web app in a folder of its own, each with its own `.lampignore`, and the web
    /// app's page with one of its own too.
    func testIgnoredFilesStayOutOfTheHistoryOfAnAppAndAnotherInItsFolder() throws {
        let root = try newRoot()
        let wish = try Template.scaffold(name: "Board \(UUID().uuidString.prefix(8))", platform: .mac, in: root).dir
        var first: [String: String?] = webApp("WebApp")
        first[".lampignore"] = "/Assets/local.csv\n"
        first["Assets/local.csv"] = "name,value\nExample,1\n"
        first["Assets/notes.txt"] = "first\n"
        first["WebApp/.lampignore"] = "/Web/big/\n"
        first["WebApp/Web/big/old.bin"] = "made-up bytes\n"
        first["WebApp/Web/.lampignore"] = "*.csv\n"
        first["WebApp/Web/scores.csv"] = "name,score\nExample,1\n"
        try save(wish, "First", first)
        // The first share is where the run starts.
        XCTAssertEqual(try shared(wish).history?.versions.count, 0)

        try save(wish, "Only kept here", ["Assets/local.csv": "name,value\nExample,2\n", "WebApp/Web/added.csv": "a\n",
                                          "WebApp/Web/big/old.bin": nil])
        try save(wish, "Both", ["Assets/notes.txt": "second\n", "Assets/local.csv": "name,value\nExample,3\n",
                                "WebApp/Web/index.html": "<p>second</p>\n", "WebApp/Web/scores.csv": "name,score\nExample,2\n"])
        let (files, history) = try shared(wish)
        let run = try XCTUnwrap(history)
        XCTAssertEqual(run.versions.map(\.title), ["Only kept here", "Both"])
        XCTAssertEqual(run.versions.first?.changed, [], "a version that changed only ignored files goes with none of them")
        XCTAssertEqual(run.versions.first?.removed, [])
        XCTAssertEqual(Set(run.versions.last?.changed ?? []), ["Assets/notes.txt", "WebApp/Web/index.html"])
        XCTAssertEqual(run.versions.last?.removed, [])
        let folder = try XCTUnwrap(run.versions.last?.folder)
        XCTAssertEqual(Set(files.filter { $0.hasPrefix(MixHistory.folder + "/") }),
                       [MixHistory.folder + "/" + MixHistory.file, "History/\(folder)/Assets/notes.txt", "History/\(folder)/WebApp/Web/index.html"])
        XCTAssertTrue(files.isSuperset(of: ["Assets/notes.txt", "WebApp/Web/index.html"]))
        XCTAssertFalse(files.contains { $0.hasSuffix(".csv") || $0.contains("big/") }, "\(files.sorted())")
    }

    /// A wish whose apps are all in folders of their own: the one the file puts at its root is asked by its own rules
    /// from its folder, and the wish's own files by the wish folder's.
    func testIgnoredFilesStayOutOfTheHistoryOfTheAppAFilePutsAtItsRoot() throws {
        let root = try newRoot()
        let wish = try Template.draft(name: "Shelf \(UUID().uuidString.prefix(8))", in: root).dir
        var first: [String: String?] = webApp("WebApp")
        first[Parts.wishOnly] = Parts.wishOnlyText
        first[".lampignore"] = "/Plans.md\n"
        first["Plans.md"] = "made-up plans\n"
        first["WebApp/.lampignore"] = "/Web/data.csv\n"
        first["WebApp/Web/data.csv"] = "name,value\nExample,1\n"
        first["WebApp/Web/.lampignore"] = "drafts/\n"
        first["WebApp/Web/drafts/one.html"] = "<p>draft</p>\n"
        try save(wish, "First", first)
        XCTAssertEqual(try shared(wish).history?.versions.count, 0)

        try save(wish, "Only kept here", ["Plans.md": "more made-up plans\n", "WebApp/Web/data.csv": "name,value\nExample,2\n",
                                          "WebApp/Web/drafts/one.html": nil, "WebApp/Web/drafts/two.html": "<p>two</p>\n"])
        try save(wish, "Both", ["WebApp/Web/index.html": "<p>second</p>\n", "WebApp/Web/data.csv": "name,value\nExample,3\n"])
        let (files, history) = try shared(wish)
        let run = try XCTUnwrap(history)
        XCTAssertEqual(run.versions.map(\.title), ["Only kept here", "Both"])
        XCTAssertEqual(run.versions.first?.changed, [], "a version that changed only ignored files goes with none of them")
        XCTAssertEqual(run.versions.first?.removed, [])
        XCTAssertEqual(run.versions.last?.changed, ["WebApp/Web/index.html"])
        XCTAssertEqual(run.versions.last?.removed, [])
        let folder = try XCTUnwrap(run.versions.last?.folder)
        XCTAssertEqual(Set(files.filter { $0.hasPrefix(MixHistory.folder + "/") }),
                       [MixHistory.folder + "/" + MixHistory.file, "History/\(folder)/WebApp/Web/index.html"])
        XCTAssertTrue(files.contains("Web/index.html"), "the app goes at the file's root")
        XCTAssertFalse(files.contains { $0.hasSuffix("data.csv") || $0.contains("drafts/") || $0.hasSuffix("Plans.md") }, "\(files.sorted())")
    }
}
