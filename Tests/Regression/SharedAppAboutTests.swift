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

    /// A description is a line under the app's name. One that runs long is refused with the reason, for the
    /// agent to write again, and never cut short.
    func testALongDescriptionIsRefusedNotCut() throws {
        XCTAssertNil(Store.descriptionRefusal(words))
        XCTAssertNil(Store.descriptionRefusal(String(repeating: "a", count: Store.descriptionLimit)))
        let long = "A simple counter that goes up by one every ten seconds while its window is open, and picks up where it left off next time."
        let refusal = try XCTUnwrap(Store.descriptionRefusal(long))
        XCTAssertTrue(refusal.contains("\(long.count)") && refusal.contains("\(Store.descriptionLimit)"))
        XCTAssertNotNil(Store.descriptionRefusal(""))
        XCTAssertNotNil(Store.descriptionRefusal("A counter.\nIt counts."))
        // The tool tells the agent the same limit Lamp holds it to.
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/lamp-tools.json")
        let tools = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        let tool = try XCTUnwrap(tools.first { $0["name"] as? String == "describe_app" })
        XCTAssertTrue((tool["description"] as? String ?? "").contains("At most \(Store.descriptionLimit) characters"))
    }

    /// Every engine is given the tool that sets it, and an app without one is told so with the request.
    func testAgentIsGivenTheToolAndToldWhenThereIsNoDescription() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/lamp-tools.json")
        let tools = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        XCTAssertTrue(tools.contains { $0["name"] as? String == "describe_app" })
        XCTAssertTrue(Agent.tryRules.contains("`describe_app`"))
        XCTAssertTrue(Agent.undescribed(try app(description: nil)).contains("describe_app"))
        XCTAssertEqual(Agent.undescribed(try app(description: words)), "")
        XCTAssertEqual(ToolCall("describe_app").action, .describe)
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
