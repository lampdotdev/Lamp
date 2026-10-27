import XCTest
@testable import Lamp

/// A wish of several apps is shared whole, a TV app's web files among them, and opens as a wish of the same apps.
final class SharingWishTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        expectNoSharingFoldersLeft()
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-share-wish-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func write(_ text: String, to path: String, in folder: URL) throws {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// A TV wish with an iPhone app in iPhone/, as `make_app_for` leaves it: the part's own meta.json and scaffold.
    private func tvWishWithPhone() throws -> LampProject {
        let wish = try Template.scaffold(name: "Remote", platform: .tv, in: root)
        try write("var tally = 0; fetch('https://example.invalid/scores');\n", to: "Web/app.js", in: wish.dir)
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: wish.dir.appendingPathComponent("Web/logo.png"))
        try write("<html><body>phone</body></html>\n", to: "Phone/index.html", in: wish.dir)
        let phone = LampProject(id: Parts.id(wish: wish.id, folder: "iPhone"), name: wish.name, exe: wish.exe,
                                dir: wish.dir.appendingPathComponent("iPhone"), platform: .iphone, partOf: wish.id)
        try FileManager.default.createDirectory(at: phone.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try Template.saveMeta(phone)
        try Template.fill(phone)
        try Template.writeOwnedFiles(for: phone)
        try write("import SwiftUI\nstruct Pad: View { var body: some View { Text(\"pad\") } }\n", to: "Sources/Pad.swift", in: phone.dir)
        return wish
    }

    /// The file carries the TV app's pages, scripts and pictures (never Lamp's own script) and the iPhone app under
    /// iPhone/, says it's a 10 and names the part; opened, it's a wish of the same two apps.
    func testAWishTravelsWholeWithItsTVAppsWebFiles() throws {
        let wish = try tvWishWithPhone()
        XCTAssertEqual(Parts.load(try XCTUnwrap(Store.readWish(at: wish.dir))).map(\.platform), [.iphone])
        let package = try opened(try exported(wish))
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: package.folder.appendingPathComponent("lamp-app.json"))) as? [String: Any]
        XCTAssertEqual(manifest?["format"] as? Int, 10)
        XCTAssertEqual(manifest?["platform"] as? String, "tv")
        XCTAssertEqual((manifest?["parts"] as? [[String: Any]])?.map { $0["folder"] as? String }, ["iPhone"])
        let carried = Set((FileManager.default.enumerator(atPath: package.folder.path)?.allObjects as? [String]) ?? [])
        XCTAssertTrue(carried.isSuperset(of: ["Web/index.html", "Web/app.js", "Web/logo.png", "Phone/index.html", "iPhone/Sources/Pad.swift", "iPhone/APP.md"]), "\(carried)")
        XCTAssertFalse(carried.contains("Web/lamp.js"))
        XCTAssertFalse(carried.contains("iPhone/Sources/LampSupport.swift"))
        XCTAssertFalse(carried.contains("iPhone/Package.swift"))

        XCTAssertEqual(package.platform, .tv)
        XCTAssertEqual(package.sources.map { package.path(of: $0) }.sorted(), ["Phone/index.html", "Web/app.js", "Web/index.html", "Web/style.css"])
        XCTAssertEqual(package.webData.map { package.path(of: $0) }, ["Web/logo.png"])
        XCTAssertEqual(package.parts.map(\.folder), ["iPhone"])
        let phone = try XCTUnwrap(package.parts.first?.package)
        XCTAssertEqual(phone.platform, .iphone)
        XCTAssertTrue(phone.sources.map { phone.path(of: $0) }.contains("Sources/Pad.swift"))

        // The review reads both apps' code, the part's named by its folder, and the TV page's reach.
        let found = Sharing.inspect(package)
        XCTAssertTrue(found.files.map(\.name).contains("Web/app.js"))
        XCTAssertTrue(found.files.map(\.name).contains("iPhone/Sources/Pad.swift"))
        XCTAssertTrue(found.detected.map(\.label).contains("Connects to the internet"))
        let request = Sharing.reviewRequest(name: package.name, description: nil, notes: nil, files: found.files, web: true,
                                            parts: ["the iPhone app in iPhone/"])
        XCTAssertTrue(request.system.contains("the iPhone app in iPhone/"))
        XCTAssertTrue(request.system.contains("This app is a TV app"))
    }

    /// Opened on another Mac: the TV app's files go into a TV wish's Web/ and Phone/, with Lamp's script written back so
    /// the folder still reads as a TV app, and the iPhone app's code into the part made for it.
    func testAWishOpensAsItsApps() throws {
        let package = try opened(try exported(try tvWishWithPhone()))
        let receiver = try Template.scaffold(name: "Remote 2", platform: .tv, in: root)
        try write("old", to: "Web/old.js", in: receiver.dir)
        try Sharing.install(package, into: receiver)
        XCTAssertEqual(try String(contentsOf: receiver.dir.appendingPathComponent("Web/app.js"), encoding: .utf8), "var tally = 0; fetch('https://example.invalid/scores');\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: receiver.dir.appendingPathComponent("Web/logo.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: receiver.dir.appendingPathComponent("Phone/index.html").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: receiver.dir.appendingPathComponent("Web/old.js").path))
        XCTAssertTrue(TVTemplate.isTV(receiver.dir))
        XCTAssertTrue(receiver.scaffolded)

        let part = try XCTUnwrap(package.parts.first)
        let phone = LampProject(id: Parts.id(wish: receiver.id, folder: part.folder), name: receiver.name, exe: receiver.exe,
                                dir: receiver.dir.appendingPathComponent(part.folder), platform: .iphone, partOf: receiver.id)
        try FileManager.default.createDirectory(at: phone.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try Template.fill(phone)
        try Sharing.install(part.package, into: phone)
        XCTAssertTrue(try String(contentsOf: phone.dir.appendingPathComponent("Sources/Pad.swift"), encoding: .utf8).contains("struct Pad"))
        XCTAssertEqual(Parts.folders(in: receiver.dir), ["iPhone"])
    }

    /// A part this Mac can't make yet keeps its files with the wish, read back as the part it was, and they go into the
    /// part once it's made, over its scaffold.
    func testAPartThatCantBeMadeYetKeepsItsFilesWithTheWish() throws {
        let package = try opened(try exported(try tvWishWithPhone()))
        let receiver = try Template.scaffold(name: "Remote 3", platform: .tv, in: root)
        let part = try XCTUnwrap(package.parts.first)
        try Sharing.keep(part, in: receiver.dir)
        XCTAssertNil(Sharing.kept(in: receiver.dir, for: .android))
        // Found by the part's family, whichever folder the file had it in: an app for both kept from a Mac/ is the Apple part.
        let kept = try XCTUnwrap(Sharing.kept(in: receiver.dir, for: .universal))
        XCTAssertEqual(kept.package.platform, .iphone)
        XCTAssertEqual(kept.package.sources.map { kept.package.path(of: $0) }.sorted(), part.package.sources.map { part.package.path(of: $0) }.sorted())

        let phone = LampProject(id: Parts.id(wish: receiver.id, folder: part.folder), name: receiver.name, exe: receiver.exe,
                                dir: receiver.dir.appendingPathComponent(part.folder), platform: .iphone, partOf: receiver.id)
        try FileManager.default.createDirectory(at: phone.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try Template.fill(phone)
        try Sharing.install(kept.package, into: phone)
        Sharing.forgetKept(in: receiver.dir, for: .iphone)
        XCTAssertTrue(try String(contentsOf: phone.dir.appendingPathComponent("Sources/Pad.swift"), encoding: .utf8).contains("struct Pad"))
        XCTAssertNil(Sharing.kept(in: receiver.dir, for: .iphone))
        XCTAssertFalse(FileManager.default.fileExists(atPath: Sharing.waitingFolder(in: receiver.dir, for: .iphone).path))
    }

    /// Two apps of one family that can't be made yet (a Mac app in Mac/ and an iPhone app in iPhone/, from one file) keep
    /// their files apart, each under the folder kept for it: the second kept never takes the place of the first.
    func testTwoWaitingAppsOfOneFamilyKeepTheirFilesApart() throws {
        let package = try opened(try exported(try tvWishWithPhone()))
        let receiver = try Template.scaffold(name: "Remote 4", platform: .tv, in: root)
        let part = try XCTUnwrap(package.parts.first)
        try Sharing.keep(Sharing.Package.Part(folder: "Mac", package: part.package), in: receiver.dir, slot: "Mac")
        try Sharing.keep(Sharing.Package.Part(folder: "iPhone", package: part.package), in: receiver.dir, slot: "iPhone")
        XCTAssertEqual(Sharing.kept(in: receiver.dir, for: .iphone, slot: "Mac")?.folder, "Mac")
        XCTAssertEqual(Sharing.kept(in: receiver.dir, for: .iphone, slot: "iPhone")?.folder, "iPhone")
        Sharing.forgetKept(in: receiver.dir, for: .iphone, slot: "Mac")
        XCTAssertNil(Sharing.kept(in: receiver.dir, for: .iphone, slot: "Mac"))
        XCTAssertEqual(Sharing.kept(in: receiver.dir, for: .iphone, slot: "iPhone")?.folder, "iPhone")
    }

    /// Files an earlier Lamp kept for a family alone, for an app on a list from before folders were kept, go to the
    /// folder their app is then given: the one they had in their file, so the retry still finds them.
    func testFilesKeptForAFamilyByAnEarlierLampFollowTheirApp() throws {
        let package = try opened(try exported(try tvWishWithPhone()))
        let receiver = try Template.scaffold(name: "Remote 5", platform: .tv, in: root)
        let part = try XCTUnwrap(package.parts.first)
        try Sharing.keep(part, in: receiver.dir)
        let folder = try XCTUnwrap(Sharing.keptFolder(in: receiver.dir, for: .iphone))
        XCTAssertEqual(folder, part.folder)
        Sharing.claimKept(in: receiver.dir, for: .iphone, slot: folder)
        XCTAssertNil(Sharing.kept(in: receiver.dir, for: .iphone))
        XCTAssertEqual(Sharing.kept(in: receiver.dir, for: .iphone, slot: folder)?.package.platform, .iphone)
    }

    /// A part's notes go to the reviewer held to the root's limit, and count against what's sent.
    func testAPartsNotesAreBoundedInTheReview() throws {
        let wish = try tvWishWithPhone()
        try write(String(repeating: "notes ", count: 2000), to: "iPhone/APP.md", in: wish.dir)
        let found = Sharing.inspect(try opened(try exported(wish)))
        let notes = try XCTUnwrap(found.files.first { $0.name == "iPhone/APP.md" })
        XCTAssertEqual(notes.text.count, 4000)
    }

    /// A TV page that loads a script from the internet or runs text as code is said to, as Swift that loads code at
    /// runtime is.
    func testATVPagesHiddenCodeIsSeen() throws {
        let wish = try Template.scaffold(name: "Frame", platform: .tv, in: root)
        try write("<script src=\"https://cdn.example.invalid/x.js\"></script>\n", to: "Web/index.html", in: wish.dir)
        try write("eval(localStorage.getItem('k'));\n", to: "Web/app.js", in: wish.dir)
        let labels = Sharing.inspect(try opened(try exported(wish))).detected.map(\.label)
        XCTAssertTrue(labels.contains("Loads code from the internet (can hide what it does)"), "\(labels)")
        XCTAssertTrue(labels.contains("Loads code at runtime (can hide what it does)"), "\(labels)")
    }

    /// An app on its own keeps the number it had, so a Lamp from before opens it; a wish with a part says 10, which such
    /// a Lamp turns away rather than open as the app at the root alone.
    func testOnlyAWishOfSeveralAppsOrATVAppSaysTheNewNumber() throws {
        let mac = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let plain = try JSONSerialization.jsonObject(with: Data(contentsOf: try opened(try exported(mac)).folder.appendingPathComponent("lamp-app.json"))) as? [String: Any]
        XCTAssertEqual(plain?["format"] as? Int, 2)
        XCTAssertNil(plain?["parts"])
        XCTAssertEqual(Sharing.format(withWidget: false, parts: true), 10)
        XCTAssertEqual(Sharing.format(withWidget: false, platform: .tv), 10)
    }

    /// A manifest naming a part in a folder that isn't one of Lamp's, or twice, brings nothing in from there.
    func testOnlyLampsPartFoldersAreRead() throws {
        let stage = root.appendingPathComponent("stage")
        try write("let a = 1\n", to: "Sources/App.swift", in: stage)
        try write("let b = 1\n", to: "Elsewhere/Sources/App.swift", in: stage)
        try write("let c = 1\n", to: "iPhone/Sources/App.swift", in: stage)
        try write(#"{"format":10,"name":"Tally","exportedAt":"2026-10-01T00:00:00Z","platform":"mac","parts":[{"folder":"Elsewhere","platform":"iphone"},{"folder":"iPhone","platform":"iphone"},{"folder":"iPhone","platform":"mac"}]}"#,
                  to: "lamp-app.json", in: stage)
        let file = root.appendingPathComponent("\(UUID().uuidString).lampapp")
        TestShell.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", stage.path, file.path])
        let package = try opened(file)
        XCTAssertEqual(package.parts.map(\.folder), ["iPhone"])
        XCTAssertEqual(package.parts.first?.package.platform, .iphone)
    }
}
