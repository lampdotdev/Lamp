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

    /// A plain site is converted in place by adding Lamp's manifest beside its page, and nothing else changes: it then
    /// reads as a laid-out site whose edits land where they did.
    func testAPlainSiteTakesLampsManifestInPlace() throws {
        let fm = FileManager.default
        let site = root.appendingPathComponent("practice")
        try write("<!doctype html><title>Practice</title>", to: "index.html", in: site)
        try write("console.log('one');\n", to: "js/app.js", in: site)
        let before = OutsideWork.hashes(of: site)
        let capture = try OutsideWork.capture(site)
        defer { try? fm.removeItem(at: capture.package.folder) }
        let conversion = OutsideWork.conversion(for: capture, in: site)
        XCTAssertEqual(conversion.disruptive, [])
        XCTAssertEqual(Set(conversion.added.keys), [StaticSite.folder + "/lamp-app.json", StaticSite.folder + "/APP.md"])

        XCTAssertEqual(try OutsideWork.convert(conversion, in: site).path, site.path, "worked on in place")
        XCTAssertEqual(RepoImport.layout(of: site), .site(laidOut: true))
        var after = OutsideWork.hashes(of: site)
        for path in conversion.added.keys { after[path] = nil }
        XCTAssertEqual(after, before, "only the manifest was added")

        let again = try OutsideWork.capture(site)
        defer { try? fm.removeItem(at: again.package.folder) }
        XCTAssertEqual(Set(again.mapping.files.keys), Set(capture.mapping.files.keys))
        XCTAssertEqual(again.mapping.files["Web/js/app.js"]?.source, "js/app.js")
        XCTAssertEqual(again.mapping.files["APP.md"]?.source, StaticSite.folder + "/APP.md")
        XCTAssertEqual(again.package.name, "Practice")
        XCTAssertEqual(OutsideWork.conversion(for: again, in: site), OutsideWork.Conversion(), "nothing more to add")
    }

    /// When adding the manifest would replace one of the folder's own files, Lamp works in a copy beside it and leaves the
    /// original exactly as it was.
    func testAConversionThatWouldReplaceAFileIsMadeInACopy() throws {
        let fm = FileManager.default
        let site = root.appendingPathComponent("practice")
        try write("<!doctype html><title>Practice</title>", to: "index.html", in: site)
        try write("notes of mine\n", to: StaticSite.folder, in: site)
        let before = OutsideWork.hashes(of: site)
        let capture = try OutsideWork.capture(site)
        defer { try? fm.removeItem(at: capture.package.folder) }
        let conversion = OutsideWork.conversion(for: capture, in: site)
        XCTAssertFalse(conversion.disruptive.isEmpty)

        let copy = try OutsideWork.convert(conversion, in: site)
        XCTAssertEqual(copy.path, root.appendingPathComponent("practice-lamp").path)
        XCTAssertEqual(OutsideWork.hashes(of: site), before, "the original is unchanged")
        XCTAssertEqual(RepoImport.layout(of: site), .site(laidOut: false))
        XCTAssertEqual(RepoImport.layout(of: copy), .site(laidOut: true))
        XCTAssertEqual(read(StaticSite.folder + "-before-lamp", in: copy), "notes of mine\n", "the copy keeps the file it moved aside")
        XCTAssertEqual(try OutsideWork.convert(conversion, in: site).path, root.appendingPathComponent("practice-lamp-2").path, "never over an earlier copy")
    }

    /// The folder given may be a git worktree checkout: it's acted on where it is, and a copy of it leaves the worktree's
    /// .git file out, so the copy never claims the same checkout. The notice names the copy, why, and the folder unchanged.
    func testAWorktreeIsCopiedWithoutClaimingItsCheckout() throws {
        let fm = FileManager.default
        func git(_ args: String..., in folder: URL) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", folder.path] + args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, args.joined(separator: " "))
        }
        // A worktree with no commit (an orphan branch), so the test makes none.
        let main = root.appendingPathComponent("main")
        try fm.createDirectory(at: main, withIntermediateDirectories: true)
        try git("init", "-q", in: main)
        let worktree = root.appendingPathComponent("practice-wt")
        try git("worktree", "add", "-q", "--orphan", "-b", "site", worktree.path, in: main)
        try write("<!doctype html><title>Practice</title>", to: "index.html", in: worktree)
        try write("notes of mine\n", to: StaticSite.folder, in: worktree)
        XCTAssertTrue(OutsideWork.isLinkedCheckout(worktree))

        let before = OutsideWork.hashes(of: worktree)
        XCTAssertNil(before[".git"], "git's own file is never the app's")
        let capture = try OutsideWork.capture(worktree)
        defer { try? fm.removeItem(at: capture.package.folder) }
        let conversion = OutsideWork.conversion(for: capture, in: worktree)
        let copy = try OutsideWork.convert(conversion, in: worktree)
        XCTAssertEqual(copy.path, root.appendingPathComponent("practice-wt-lamp").path)
        XCTAssertFalse(fm.fileExists(atPath: copy.appendingPathComponent(".git").path))
        XCTAssertEqual(OutsideWork.hashes(of: worktree), before)
        XCTAssertTrue(fm.fileExists(atPath: worktree.appendingPathComponent(".git").path))

        let notice = OutsideWork.copyNotice(copy: copy.path, original: worktree.path, because: conversion.disruptive, withoutGit: true)
        XCTAssertTrue(notice.contains("at \(copy.path), because "), notice)
        XCTAssertTrue(notice.contains("\(worktree.path), is unchanged"), notice)
        XCTAssertTrue(notice.contains("Add folder"), notice)
        // The desktop apps' steps first and the command line last, each naming the copy by its absolute path.
        let steps = OutsideWork.switchSteps(copy.path).split(separator: "\n").map(String.init)
        XCTAssertEqual(steps.count, 3)
        XCTAssertTrue(steps[0].hasPrefix("- Claude Code desktop app") && steps[1].hasPrefix("- ChatGPT desktop app"), steps.joined(separator: "\n"))
        XCTAssertTrue(steps[2].contains("--add-dir \(copy.path)"), steps[2])
        XCTAssertTrue(steps.allSatisfy { $0.contains(copy.path) })
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
