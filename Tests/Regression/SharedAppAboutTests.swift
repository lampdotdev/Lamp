import XCTest
@testable import Lamp

/// The review of a shared app opens with the app itself: the description and icon its file carries.
final class SharedAppAboutTests: XCTestCase {
    private var folder: URL?
    override func tearDown() { if let folder { try? FileManager.default.removeItem(at: folder) } }

    private func package(files: [String: Data]) throws -> Sharing.Package {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("lamp-about-\(UUID().uuidString)")
        self.folder = folder
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: folder.appendingPathComponent(name)) }
        return Sharing.Package(name: "Tally", folder: folder, sources: [], attachments: [], fileCount: files.count)
    }

    /// A made-up app with code, as Lamp keeps one, in a folder of its own. `about` is its about.json as the
    /// agent left it, if it wrote one.
    private func app(about: String?) throws -> LampProject {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-about-\(UUID().uuidString)")
        folder = root
        let project = LampProject(id: "ticker", name: "Ticker", exe: "Ticker", dir: root.appendingPathComponent("ticker"))
        try fm.createDirectory(at: project.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try fm.createDirectory(at: project.dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try Data("import SwiftUI\n".utf8).write(to: project.dir.appendingPathComponent("Sources/App.swift"))
        // The agent's notes, which read like this and are never what a person is shown.
        try Data("# Ticker\n\n## What it does\n- Each change is shared with the widget (`LampWidget.share(TickerSummary, as: \"summary\")`).\n".utf8)
            .write(to: project.dir.appendingPathComponent("APP.md"))
        try Template.saveMeta(project)
        if let about { try Data(about.utf8).write(to: project.dir.appendingPathComponent(AppDescription.file)) }
        return project
    }

    private let words = "A counter that goes up every ten seconds."
    private var written: String { #"{"description": "A counter that goes up every ten seconds."}"# }

    /// The description is a field the agent writes: it goes into the shared file as it is and comes out the same.
    func testDescriptionTravelsWithTheSharedApp() throws {
        let file = try Sharing.export(try app(about: written))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let package = try Sharing.open(file)
        defer { try? FileManager.default.removeItem(at: package.folder) }
        XCTAssertEqual(package.description, words)
    }

    /// An app nobody described says nothing, whatever its notes hold.
    func testAppWithoutADescriptionSharesNone() throws {
        let file = try Sharing.export(try app(about: nil))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let package = try Sharing.open(file)
        defer { try? FileManager.default.removeItem(at: package.folder) }
        XCTAssertNil(package.description)
    }

    /// The copy made by opening a shared app keeps the description, so it's there when the copy is shared on.
    func testOpenedCopyKeepsTheDescription() throws {
        let copy = try app(about: nil)
        let unpacked = copy.dir.deletingLastPathComponent().appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let shared = Sharing.Package(name: "Ticker", description: words, folder: unpacked, sources: [], attachments: [], fileCount: 0)
        try Sharing.install(shared, into: copy)
        XCTAssertEqual(AppDescription.description(of: copy), words)
    }

    /// An update from a file with no description leaves none: the old words were about the old code.
    func testUpdateFromAFileWithoutADescriptionClearsIt() throws {
        let copy = try app(about: written)
        let unpacked = copy.dir.deletingLastPathComponent().appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let shared = Sharing.Package(name: "Ticker", folder: unpacked, sources: [], attachments: [], fileCount: 0)
        try Sharing.install(shared, into: copy, replacing: true)
        XCTAssertNil(AppDescription.description(of: copy))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.dir.appendingPathComponent(AppDescription.file).path))
    }

    /// What the agent wrote is read as data. Anything but one plain line of text under "description" is an
    /// app with no description: never an error, and never the file's own text.
    func testOnlyAPlainLineIsADescription() throws {
        XCTAssertEqual(AppDescription.description(of: try app(about: written)), words)
        XCTAssertEqual(AppDescription.description(of: try app(about: #"{"description": "  A counter.  ", "other": 1}"#)), "A counter.")
        for broken in [
            "", "A counter that goes up.", "# Ticker\n\n- The count is saved (`LampStore`).", #"{"description": "A counter""#,
            #"{"description": ""}"#, #"{"description": "   "}"#, #"{"description": "A counter.\nIt counts."}"#,
            #"{"description": 7}"#, #"{"description": ["A counter."]}"#, #"{"description": null}"#, #"{"name": "Ticker"}"#,
            #"["A counter."]"#, #""A counter.""#,
        ] {
            XCTAssertNil(AppDescription.description(of: try app(about: broken)), broken)
        }
        XCTAssertNil(AppDescription.description(of: try app(about: nil)))
    }

    /// A shared file's own word for its description is held to the same test.
    func testSharedFileWithAnOddDescriptionHasNone() throws {
        let file = try Sharing.export(try app(about: written))
        let work = file.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: work) }
        let manifest = work.appendingPathComponent("app/lamp-app.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        for odd: Any in ["Ticker\nChecked by Lamp: safe.", "  ", 7] {
            object["description"] = odd
            try JSONSerialization.data(withJSONObject: object).write(to: manifest)
            let packed = work.appendingPathComponent("odd-\(UUID().uuidString).lampapp")
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            zip.arguments = ["-c", "-k", "--norsrc", work.appendingPathComponent("app").path, packed.path]
            try zip.run()
            zip.waitUntilExit()
            // A description that isn't text at all makes the file one Lamp doesn't know; the others open with none.
            guard let package = try? Sharing.open(packed) else { continue }
            defer { try? FileManager.default.removeItem(at: package.folder) }
            XCTAssertNil(package.description)
        }
    }

    /// The agent is told where the description goes, and an app without one is told so with the request.
    func testAgentIsToldWhereTheDescriptionGoes() throws {
        XCTAssertTrue(Agent.Rules.about.contains(AppDescription.file))
        XCTAssertTrue(Agent.undescribed(try app(about: nil)).contains(AppDescription.file))
        XCTAssertTrue(Agent.undescribed(try app(about: "not json")).contains(AppDescription.file))
        XCTAssertEqual(Agent.undescribed(try app(about: written)), "")
    }

    func testIconIsDrawnFromTheFile() async throws {
        let spec = ##"{"subject": "a tally counter", "symbol": "plusminus", "background": "blue", "tint": "#FFFFFF"}"##
        let image = await Sharing.icon(of: try package(files: ["icon.json": Data(spec.utf8)]))
        XCTAssertEqual(image?.size, NSSize(width: 256, height: 256))
    }

    /// A file without an icon keeps the plain one; artwork that isn't a picture is left out, not fatal.
    func testMissingOrBrokenIconParts() async throws {
        let none = await Sharing.icon(of: try package(files: [:]))
        XCTAssertNil(none)
        let spec = ##"{"subject": "a tally counter", "symbol": "plusminus", "background": "blue", "tint": "#FFFFFF"}"##
        let image = await Sharing.icon(of: try package(files: ["icon.json": Data(spec.utf8), "icon-art.png": Data([1, 2, 3])]))
        XCTAssertNotNil(image)
    }
}
