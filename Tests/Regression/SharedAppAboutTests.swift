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

    /// A made-up app with code, as Lamp keeps one, in a folder of its own.
    private func app(description: String?) throws -> LampProject {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-about-\(UUID().uuidString)")
        folder = root
        var project = LampProject(id: "ticker", name: "Ticker", exe: "Ticker", dir: root.appendingPathComponent("ticker"))
        project.description = description
        try fm.createDirectory(at: project.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try fm.createDirectory(at: project.dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try Data("import SwiftUI\n".utf8).write(to: project.dir.appendingPathComponent("Sources/App.swift"))
        // The agent's notes, which read like this and are never what a person is shown.
        try Data("# Ticker\n\n## What it does\n- Each change is shared with the widget (`LampWidget.share(TickerSummary, as: \"summary\")`).\n".utf8)
            .write(to: project.dir.appendingPathComponent("APP.md"))
        try Template.saveMeta(project)
        return project
    }

    private let words = "A counter that goes up every ten seconds."

    /// The description is a field of the app: it goes into the shared file as it is and comes out the same.
    func testDescriptionTravelsWithTheSharedApp() throws {
        let file = try Sharing.export(try app(description: words))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let package = try Sharing.open(file)
        defer { try? FileManager.default.removeItem(at: package.folder) }
        XCTAssertEqual(package.description, words)
    }

    /// An app nobody described says nothing, whatever its notes hold.
    func testAppWithoutADescriptionSharesNone() throws {
        let file = try Sharing.export(try app(description: nil))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let package = try Sharing.open(file)
        defer { try? FileManager.default.removeItem(at: package.folder) }
        XCTAssertNil(package.description)
    }

    /// The copy made by opening a shared app keeps the description, so it's there when the copy is shared on.
    func testOpenedCopyKeepsTheDescription() throws {
        let copy = try app(description: nil)
        let unpacked = copy.dir.deletingLastPathComponent().appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let shared = Sharing.Package(name: "Ticker", description: words, folder: unpacked, sources: [], attachments: [], fileCount: 0)
        try Sharing.install(shared, into: copy)
        let meta = try JSONDecoder().decode(ProjectMeta.self, from: Data(contentsOf: copy.dir.appendingPathComponent(".lamp/meta.json")))
        XCTAssertEqual(meta.description, words)
        XCTAssertEqual(meta.name, "Ticker")
    }

    /// An update from a file with no description leaves none: the old words were about the old code.
    func testUpdateFromAFileWithoutADescriptionClearsIt() throws {
        let copy = try app(description: words)
        let unpacked = copy.dir.deletingLastPathComponent().appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let shared = Sharing.Package(name: "Ticker", folder: unpacked, sources: [], attachments: [], fileCount: 0)
        try Sharing.install(shared, into: copy, replacing: true)
        let meta = try JSONDecoder().decode(ProjectMeta.self, from: Data(contentsOf: copy.dir.appendingPathComponent(".lamp/meta.json")))
        XCTAssertNil(meta.description)
    }

    /// Lamp writes the description with the name, from what the person asked for. It's kept as the model
    /// gave it, on one line; none, or the prompt's own example handed back, is no description.
    @MainActor func testDescriptionComesWithTheName() {
        let asked = "a counter that goes up every ten seconds"
        XCTAssertEqual(AppName.description(["description": words], asked: asked), words)
        XCTAssertEqual(AppName.description(["description": " A counter that\ngoes up. "], asked: asked), "A counter that goes up.")
        XCTAssertNil(AppName.description(["name": "Ticker"], asked: asked))
        XCTAssertNil(AppName.description(["description": "  "], asked: asked))
        XCTAssertNil(AppName.description(["description": AppName.exampleDescription], asked: asked))
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
