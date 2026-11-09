import XCTest
@testable import Lamp

/// A folder the person's own coding agent works on (`OutsideWork`) is read as the importer reads it, and kept in step with
/// Lamp's copy through one mapping: a plain site's page, which the import moves into Web/, is captured, its edits land
/// there, and a file taken out of the folder is taken out of the copy. The folder itself is never written.
final class OutsideFolderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ScreenFiles.writeLamps = { project in
            let page = ScreenKit.page(for: project.platform)
            try Template.write(page.says + (ScreenKit.isSite(project) ? ScreenKit.siteLine + "\n" : ""), to: page.marker, for: project)
            try Template.write("// Lamp's script\n", to: TVTemplate.supportFile, for: project)
        }
    }

    override func tearDownWithError() throws {
        ScreenFiles.writeLamps = ScreenKit.write(for:)
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to path: String, in folder: URL) throws {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ path: String, in folder: URL) -> String? {
        try? String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8)
    }

    func testAPlainSiteIsCapturedAndItsEditsLandInWeb() throws {
        let fm = FileManager.default
        let site = root.appendingPathComponent("practice")
        try write("<!doctype html><title>Practice</title><script src=\"js/app.js\"></script>", to: "index.html", in: site)
        try write("console.log('one');\n", to: "js/app.js", in: site)
        try write("body { margin: 0 }\n", to: "css/app.css", in: site)
        XCTAssertEqual(RepoImport.layout(of: site), .site(laidOut: false))
        let untouched = OutsideWork.hashes(of: site)

        // What open_project captures, and the review installs.
        let first = try OutsideWork.capture(site)
        defer { try? fm.removeItem(at: first.package.folder) }
        XCTAssertEqual(first.mapping.files["Web/index.html"]?.source, "index.html")
        XCTAssertEqual(first.mapping.files["Web/js/app.js"]?.source, "js/app.js")
        XCTAssertNotNil(first.mapping.files["APP.md"])
        XCTAssertNil(first.mapping.files["APP.md"]?.source, "the import writes a plain site's APP.md itself")
        var app = try Template.scaffold(name: "Practice", platform: .mac, in: root)
        app.platform = .webApp
        try Template.saveMeta(app)
        try fm.removeItem(at: app.dir.appendingPathComponent("Sources"))
        try Sharing.install(first.package, into: app)

        // The agent edits one file, takes one out, and adds one.
        try write("console.log('two');\n", to: "js/app.js", in: site)
        try fm.removeItem(at: site.appendingPathComponent("css/app.css"))
        try write("export const x = 1;\n", to: "js/new.js", in: site)
        let second = try OutsideWork.capture(site)
        defer { try? fm.removeItem(at: second.package.folder) }
        let written = try OutsideWork.sync(second, into: app, previous: first.mapping.record, metadata: false)

        XCTAssertEqual(written, ["css/app.css", "js/app.js", "js/new.js"], "answered by the folder's own paths")
        XCTAssertEqual(read("Web/js/app.js", in: app.dir), "console.log('two');\n")
        XCTAssertEqual(read("Web/js/new.js", in: app.dir), "export const x = 1;\n")
        XCTAssertFalse(fm.fileExists(atPath: app.dir.appendingPathComponent("Web/css/app.css").path))
        XCTAssertFalse(fm.fileExists(atPath: app.dir.appendingPathComponent("js").path), "nothing lands at the folder's paths")
        XCTAssertEqual(read(TVTemplate.supportFile, in: app.dir), "// Lamp's script\n", "Lamp's own file beside the page stays")

        // Nothing more to write when the folder hasn't changed, and the folder was never written.
        let third = try OutsideWork.capture(site)
        defer { try? fm.removeItem(at: third.package.folder) }
        XCTAssertEqual(try OutsideWork.sync(third, into: app, previous: second.mapping.record, metadata: false), [])
        var now = OutsideWork.hashes(of: site)
        now["css/app.css"] = untouched["css/app.css"]
        now["js/app.js"] = untouched["js/app.js"]
        now["js/new.js"] = nil
        XCTAssertEqual(now, untouched)
    }

    /// A Lamp app's file taken out of the folder is taken out of the copy, and Lamp's own files there stay.
    func testAFileTakenOutOfALampAppGoesFromTheCopy() throws {
        let fm = FileManager.default
        let made = root.appendingPathComponent("made")
        try fm.createDirectory(at: made, withIntermediateDirectories: true)
        let source = try Template.scaffold(name: "Tally", platform: .mac, in: made)
        try Template.writeOwnedFiles(for: source)
        let staged = try GitHubRepo.stage(source, repo: "someone/tally", link: nil)
        defer { try? fm.removeItem(at: staged.folder.deletingLastPathComponent()) }
        let folder = staged.folder
        try write("struct Extra {}\n", to: "Sources/Extra.swift", in: folder)
        XCTAssertEqual(RepoImport.layout(of: folder), .wish)
        let first = try OutsideWork.capture(folder)
        defer { try? fm.removeItem(at: first.package.folder) }
        XCTAssertEqual(first.mapping.files["Sources/Extra.swift"]?.source, "Sources/Extra.swift")
        let app = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        try Sharing.install(first.package, into: app)
        XCTAssertTrue(fm.fileExists(atPath: app.dir.appendingPathComponent("Sources/Extra.swift").path))

        try fm.removeItem(at: folder.appendingPathComponent("Sources/Extra.swift"))
        let second = try OutsideWork.capture(folder)
        defer { try? fm.removeItem(at: second.package.folder) }
        XCTAssertEqual(try OutsideWork.sync(second, into: app, previous: first.mapping.record, metadata: false), ["Sources/Extra.swift"])
        XCTAssertFalse(fm.fileExists(atPath: app.dir.appendingPathComponent("Sources/Extra.swift").path))
        XCTAssertTrue(fm.fileExists(atPath: app.dir.appendingPathComponent("Sources/LampSupport.swift").path))
    }

    /// A folder the importer can't read says what it lacks.
    func testAFolderLampCantReadSaysWhatsMissing() throws {
        let built = root.appendingPathComponent("built")
        try write("<!doctype html>", to: "index.html", in: built)
        try write("{}", to: "package.json", in: built)
        guard case .unknown(let why) = RepoImport.layout(of: built) else { return XCTFail("a site with a build step isn't plain") }
        XCTAssertTrue(why.contains("package.json"), why)

        let empty = root.appendingPathComponent("empty")
        try write("print(1)\n", to: "main.py", in: empty)
        guard case .unknown(let none) = RepoImport.layout(of: empty) else { return XCTFail("nothing to read") }
        XCTAssertTrue(none.contains("lamp-app.json") && none.contains("index.html"), none)
        XCTAssertThrowsError(try OutsideWork.capture(empty))
    }
}
