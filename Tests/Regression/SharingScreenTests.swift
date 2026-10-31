import XCTest
@testable import Lamp

/// A web app, and a screen made before, travel as their page and the Swift beside it, never Lamp's files around them, as a
/// shared file and as a repository put on GitHub; opened, each is the kind it was. Home HQ, the screen among Lamp's
/// starters, stands in for both: its page, its Native.swift and its credits with the licenses they name.
final class SharingScreenTests: XCTestCase {
    private var root: URL!
    private var starter: URL { get throws { try StarterTrees.tree("homehq") } }

    override func setUpWithError() throws {
        expectNoSharingFoldersLeft()
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-share-screen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Lamp's files around the page come from Lamp's resources, which a test run doesn't have: the stand-in writes what
        // marks the kind, as the real one does last.
        ScreenFiles.writeLamps = { project in
            let page = ScreenKit.page(for: project.platform)
            try Template.write(page.says, to: page.marker, for: project)
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

    /// Home HQ as a web app of `platform`, with stand-ins for every file Lamp writes around its page.
    private func homeHQ(_ platform: Platform, name: String = "Home HQ") throws -> LampProject {
        let fm = FileManager.default
        var project = try Template.scaffold(name: name, platform: .mac, in: root)
        project.platform = platform
        try Template.saveMeta(project)
        // A Mac app's Swift, and the page scaffold's, make way for Home HQ's.
        try fm.removeItem(at: project.dir.appendingPathComponent("Sources"))
        try fm.createDirectory(at: project.dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try? fm.removeItem(at: project.dir.appendingPathComponent("Web"))
        try fm.copyItem(at: starter.appendingPathComponent("Web"), to: project.dir.appendingPathComponent("Web"))
        try fm.copyItem(at: starter.appendingPathComponent("Sources/Native.swift"), to: project.dir.appendingPathComponent("Sources/Native.swift"))
        try fm.copyItem(at: starter.appendingPathComponent(Credits.file), to: project.dir.appendingPathComponent(Credits.file))
        let page = ScreenKit.page(for: platform)
        try write("// Lamp's script\n", to: TVTemplate.supportFile, in: project.dir)
        try write("// Lamp's app around the page\n", to: page.swift, in: project.dir)
        try write("// Lamp's bridge\n", to: "Sources/LampPage.swift", in: project.dir)
        try write("// Lamp's blocks\n", to: "Sources/LampSupport.swift", in: project.dir)
        try write(page.says, to: page.marker, in: project.dir)
        return project
    }

    /// The file carries the page and Native.swift as code, the fonts and the licenses as data, says 12 and which kind it
    /// is; the copy another Mac makes is that kind, with the file's page in place of its own.
    func testAScreenAndAWebAppTravelAsTheirPage() throws {
        let fm = FileManager.default
        for platform in [Platform.screen, .webApp] {
            let page = ScreenKit.page(for: platform)
            let sender = try homeHQ(platform)
            XCTAssertNil(sender.platform.target.recipe.shareRefusal)
            let package = try opened(try exported(sender))
            let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: package.folder.appendingPathComponent("lamp-app.json"))) as? [String: Any]
            XCTAssertEqual(manifest?["format"] as? Int, 12)
            XCTAssertEqual(manifest?["platform"] as? String, platform.rawValue)
            XCTAssertEqual(package.platform, platform)
            let code = Set(package.sources.map(package.path(of:)))
            XCTAssertTrue(code.isSuperset(of: ["Web/index.html", "Web/js/app.js", "Web/css/base.css", "Sources/Native.swift"]), "\(code)")
            for lamps in [TVTemplate.supportFile, page.swift, "Sources/LampPage.swift", "Sources/LampSupport.swift"] {
                XCTAssertFalse(code.contains(lamps), "\(lamps) is Lamp's, written by the Mac that opens the file")
                XCTAssertFalse(fm.fileExists(atPath: package.folder.appendingPathComponent(lamps).path), lamps)
            }
            XCTAssertFalse(fm.fileExists(atPath: package.folder.appendingPathComponent(page.marker).path), "the kind is the manifest's word")
            let data = Set(package.webData.map(package.path(of:)))
            XCTAssertTrue(data.contains("Web/fonts/archivo.woff2") && data.contains("Web/LICENSE-photo-frame-dashboard"), "\(data)")
            XCTAssertEqual(package.licences.map(package.path(of:)), ["Web/LICENSE-photo-frame-dashboard"])
            XCTAssertEqual(package.credits?.basedOn, "Based on photo-frame-dashboard by Wes Bos")

            // The review reads the page and the Swift beside it, and is told what a page is.
            let found = Sharing.inspect(package)
            // Home HQ's page is more than one request holds: it goes in several, the Swift beside the page first.
            XCTAssertEqual(found.files.first?.name, "Sources/Native.swift")
            XCTAssertTrue(found.files.map(\.name).contains("Web/index.html") && !found.truncated, "\(found.files.map(\.name))")
            XCTAssertGreaterThan(found.batches.count, 1)
            XCTAssertTrue(found.detected.map(\.label).contains("Connects to geocoding-api.open-meteo.com"), "\(found.detected.map(\.label))")
            let request = Sharing.reviewRequest(name: package.name, description: nil, notes: nil, files: found.files, page: true)
            XCTAssertTrue(request.system.contains("This app is a page"))
            XCTAssertFalse(request.system.contains("This app is a TV app"))

            // Opened on another Mac: the file's page and Swift in place of the app's, and the folder still the kind it was.
            let receiver = try homeHQ(platform, name: "Copy")
            try write("old", to: "Web/old.js", in: receiver.dir)
            try write("enum Old {}\n", to: "Sources/Old.swift", in: receiver.dir)
            try Sharing.install(package, into: receiver)
            XCTAssertEqual(try Data(contentsOf: receiver.dir.appendingPathComponent("Web/index.html")),
                           try Data(contentsOf: starter.appendingPathComponent("Web/index.html")))
            XCTAssertEqual(try Data(contentsOf: receiver.dir.appendingPathComponent("Sources/Native.swift")),
                           try Data(contentsOf: starter.appendingPathComponent("Sources/Native.swift")))
            XCTAssertFalse(fm.fileExists(atPath: receiver.dir.appendingPathComponent("Web/old.js").path))
            XCTAssertFalse(fm.fileExists(atPath: receiver.dir.appendingPathComponent("Sources/Old.swift").path))
            XCTAssertTrue(fm.fileExists(atPath: receiver.dir.appendingPathComponent(page.swift).path), "Lamp's own stay")
            XCTAssertTrue(platform.target.recipe.isMade(receiver.dir))
            try fm.removeItem(at: sender.dir)
            try fm.removeItem(at: receiver.dir)
        }
        XCTAssertEqual(Sharing.format(withWidget: false, platform: .screen), 12)
        XCTAssertEqual(Sharing.format(withWidget: false, platform: .webApp), 12)
        XCTAssertEqual(Sharing.format(withWidget: false, platform: .tv), 10)
    }

    /// The Little House as its sender has it: its page with a copy of three.js beside it, its Native.swift, and Lamp's
    /// files around the page, the phone controllers' kit among them. The review reads all of the sender's own code and
    /// none of Lamp's: not the kit, which the Mac that opens the file writes itself, nor three.js where it is Lamp's copy
    /// byte for byte; a copy changed in any way is the sender's code, read in full and checked like the rest.
    func testTheLittleHouseIsReviewedInFullAndWithoutLampsFiles() throws {
        let fm = FileManager.default
        let house = try StarterTrees.tree("thelittlehouse")
        let three = StarterTrees.folder.deletingLastPathComponent().appendingPathComponent("WebLibraries/three")
        let shipped = try fm.subpathsOfDirectory(atPath: three.path).compactMap { try? String(contentsOf: three.appendingPathComponent($0), encoding: .utf8) }
        XCTAssertFalse(shipped.isEmpty)
        let known = Sharing.knownLibraries
        // As Lamp knows them: the version it ships and those it shipped before, which a starter's copy may be.
        let earlier = (try? String(contentsOf: three.deletingLastPathComponent().appendingPathComponent("earlier.txt"), encoding: .utf8))?
            .split(whereSeparator: \.isNewline).map(String.init) ?? []
        Sharing.knownLibraries = Set(shipped.map(Sharing.fingerprint)).union(earlier)
        defer { Sharing.knownLibraries = known }

        func inspected(_ change: ((URL) throws -> Void)? = nil) throws -> Sharing.Inspection {
            let sender = try homeHQ(.webApp, name: "The Little House \(UUID().uuidString.prefix(4))")
            defer { try? fm.removeItem(at: sender.dir) }
            try? fm.removeItem(at: sender.dir.appendingPathComponent(Credits.file))
            for path in ["Web", "Sources/Native.swift", "Sources/LampControllerKit.swift"] {
                try? fm.removeItem(at: sender.dir.appendingPathComponent(path))
                try fm.copyItem(at: house.appendingPathComponent(path), to: sender.dir.appendingPathComponent(path))
            }
            try change?(sender.dir)
            let package = try opened(try exported(sender))
            XCTAssertFalse(package.sources.map(package.path(of:)).contains("Sources/LampControllerKit.swift"), "Lamp's, written by the Mac that opens the file")
            return Sharing.inspect(package)
        }

        let found = try inspected()
        let names = found.files.map(\.name)
        XCTAssertFalse(found.truncated)
        XCTAssertEqual(found.batches.count, 1)
        XCTAssertTrue(Set(names).isSuperset(of: ["Sources/Native.swift", "Web/app.js", "Web/style.css", "Web/house.js", "Web/index.html"]), "\(names)")
        XCTAssertFalse(names.contains { $0.hasPrefix("Web/three/") || $0.hasPrefix("Sources/Lamp") }, "\(names)")
        XCTAssertFalse(found.detected.contains { $0.level > .ordinary }, "\(found.detected.map(\.label))")

        // The same three.js with one line added is the sender's code, sent whole and checked.
        let changed = try inspected { dir in
            let module = dir.appendingPathComponent("Web/three/three.module.js")
            try (String(contentsOf: module, encoding: .utf8) + "\neval(atob(location.hash.slice(1)));\n").write(to: module, atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(changed.files.contains { $0.name.hasPrefix("Web/three/three.module.js") })
        XCTAssertTrue(changed.detected.contains { $0.label == "Loads code at runtime (can hide what it does)" }, "\(changed.detected.map(\.label))")
        XCTAssertFalse(changed.truncated)
    }

    /// Put on GitHub, a screen's repository holds its page and Native.swift with Lamp's files around them, so it builds as
    /// it is; opened from there, only the sender's code is read, and Lamp's files are the ones an update leaves out.
    func testAScreensRepositoryBuildsOnItsOwnAndOpensAsAScreen() throws {
        let fm = FileManager.default
        let screen = try homeHQ(.screen)
        let staged = try GitHubRepo.stage(screen, repo: "someone/homehq", link: nil)
        defer { try? fm.removeItem(at: staged.folder.deletingLastPathComponent()) }
        func has(_ path: String) -> Bool { fm.fileExists(atPath: staged.folder.appendingPathComponent(path).path) }
        for path in ["Web/index.html", "Web/js/app.js", "Sources/Native.swift", "Web/LICENSE-photo-frame-dashboard",
                     TVTemplate.supportFile, ScreenKit.screenPage.swift, "Sources/LampPage.swift", "Sources/LampSupport.swift",
                     "build.sh", "Package.swift", ScreenKit.marker, "lamp-app.json", Credits.file, "README.md"] {
            XCTAssertTrue(has(path), path)
        }
        XCTAssertFalse(has(ScreenKit.webAppPage.swift))
        XCTAssertFalse(has(".lamp"))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: staged.folder.path).contains { $0.hasSuffix(".lampapp") })

        let package = try Sharing.open(staged.folder)
        defer { try? fm.removeItem(at: package.folder) }
        XCTAssertEqual(package.platform, .screen)
        let code = Set(package.sources.map(package.path(of:)))
        XCTAssertTrue(code.contains("Web/index.html") && code.contains("Sources/Native.swift"), "\(code)")
        for lamps in [TVTemplate.supportFile, ScreenKit.screenPage.swift, "Sources/LampPage.swift", "Sources/LampSupport.swift"] {
            XCTAssertFalse(code.contains(lamps), lamps)
            XCTAssertTrue(Upstream.isLeftOut(lamps, in: screen), lamps)
        }
        XCTAssertFalse(Upstream.isLeftOut("Web/index.html", in: screen) || Upstream.isLeftOut("Sources/Native.swift", in: screen))
        XCTAssertTrue(Upstream.isLeftOut(ScreenKit.marker, in: screen))
    }
}
