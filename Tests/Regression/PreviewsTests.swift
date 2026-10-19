import XCTest
import AppKit
@testable import Lamp

/// Lamp writes the copies of pictures the agent is shown unconfined, so it never writes through a link the
/// agent left in the app's folder.
@MainActor
final class PreviewsTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func makeProject() throws -> (LampProject, URL) {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-previews-test-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("harness", isDirectory: true)
        try fm.createDirectory(at: dir.appendingPathComponent(".lamp/runtime"), withIntermediateDirectories: true)
        return (LampProject(id: "harness", name: "Harness", exe: "Harness", dir: dir), root)
    }

    private func writePNG(_ url: URL, width: Int, height: Int) throws {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.orange.setFill(); rect.fill(); return true
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    func testNothingIsWrittenThroughALinkOutOfTheAppsFolder() throws {
        let (project, root) = try makeProject()
        let fm = FileManager.default
        let elsewhere = root.appendingPathComponent("elsewhere", isDirectory: true)
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: project.dir.appendingPathComponent(".lamp/runtime/previews"), withDestinationURL: elsewhere)
        let screenshot = project.dir.appendingPathComponent(".lamp/runtime/screenshot.png")
        try writePNG(screenshot, width: 300, height: 200)
        XCTAssertEqual(Previews.forAgent(screenshot, in: project), screenshot, "the full picture is given rather than a copy written elsewhere")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: elsewhere.path), [])

        // A linked ancestor with the folder missing: nothing is made through the link.
        try fm.removeItem(at: project.dir.appendingPathComponent(".lamp/runtime/previews"))
        try fm.removeItem(at: project.dir.appendingPathComponent(".lamp/runtime"))
        try fm.createSymbolicLink(at: project.dir.appendingPathComponent(".lamp/runtime"), withDestinationURL: elsewhere)
        let outsideShot = elsewhere.appendingPathComponent("screenshot.png")
        try writePNG(outsideShot, width: 300, height: 200)
        // And the picture there, reached through the link, isn't the app's to hand over.
        XCTAssertNil(Previews.forAgent(project.dir.appendingPathComponent(".lamp/runtime/screenshot.png"), in: project))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: elsewhere.path), ["screenshot.png"])
        try fm.removeItem(at: project.dir.appendingPathComponent(".lamp/runtime"))
        try fm.removeItem(at: outsideShot)
        try fm.createDirectory(at: project.dir.appendingPathComponent(".lamp/runtime/previews"), withIntermediateDirectories: true)
        try writePNG(screenshot, width: 300, height: 200)

        // A link in the file's place is replaced, not written through.
        try fm.removeItem(at: project.dir.appendingPathComponent(".lamp/runtime/previews"))
        try fm.createDirectory(at: project.dir.appendingPathComponent(".lamp/runtime/previews"), withIntermediateDirectories: true)
        let secret = root.appendingPathComponent("secret.txt")
        try "keep".write(to: secret, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: project.dir.appendingPathComponent(".lamp/runtime/previews/screenshot.jpg"), withDestinationURL: secret)
        XCTAssertEqual(Previews.forAgent(screenshot, in: project), screenshot)
        XCTAssertEqual(try String(contentsOf: secret, encoding: .utf8), "keep")
    }
}
