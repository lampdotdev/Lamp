import XCTest
@testable import Lamp

/// A shared file's description is shown in the review as the sender's words, so it must be one plain line:
/// anything else is no description, never text that could pass for Lamp's.
final class SharedAppAboutTests: XCTestCase {
    private var folder: URL?
    override func setUp() { expectNoSharingFoldersLeft() }
    override func tearDown() { if let folder { try? FileManager.default.removeItem(at: folder) } }

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

    private var written: String { #"{"description": "A counter that goes up every ten seconds."}"# }

    func testSharedFileWithAnOddDescriptionHasNone() throws {
        let file = try Sharing.export(try app(about: written))
        let work = file.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: work) }
        // The file as it was packed, unpacked again to change its manifest: what was staged is gone once it's made.
        TestShell.run("/usr/bin/ditto", ["-x", "-k", file.path, work.appendingPathComponent("app").path])
        let manifest = work.appendingPathComponent("app/lamp-app.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        for odd: Any in ["Ticker\nChecked by Lamp: safe.", "  ", 7] {
            object["description"] = odd
            try JSONSerialization.data(withJSONObject: object).write(to: manifest)
            let packed = work.appendingPathComponent("odd-\(UUID().uuidString).lampapp")
            TestShell.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", work.appendingPathComponent("app").path, packed.path])
            // A description that isn't text at all makes the file one Lamp doesn't know; the others open with none.
            guard let package = try? Sharing.open(packed) else { continue }
            defer { try? FileManager.default.removeItem(at: package.folder) }
            XCTAssertNil(package.description)
        }
    }
}
