import XCTest
import AppKit
@testable import Lamp

/// The copies of pictures the agent is shown: a screenshot keeps its pixels (use_app's points are pixels in it),
/// art is shrunk, and Lamp, writing unconfined, never writes through a link the agent left in the app's folder.
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
        try fm.createDirectory(at: dir.appendingPathComponent("Assets"), withIntermediateDirectories: true)
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

    private func size(of url: URL) throws -> (Int, Int) {
        let rep = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    func testAScreenshotKeepsItsPixelsAndArtIsShrunk() throws {
        let (project, _) = try makeProject()
        let screenshot = project.dir.appendingPathComponent(".lamp/runtime/screenshot.png")
        try writePNG(screenshot, width: 1400, height: 900)
        let preview = Previews.forAgent(screenshot, in: project)
        XCTAssertEqual(preview.path, project.dir.appendingPathComponent(".lamp/runtime/previews/screenshot.jpg").path)
        XCTAssertEqual(Previews.mimeType(of: preview.path), "image/jpeg")
        let (w, h) = try size(of: preview)
        XCTAssertEqual(w, 1400); XCTAssertEqual(h, 900)

        let art = project.dir.appendingPathComponent("Assets/star.png")
        try writePNG(art, width: 2048, height: 1024)
        let artPreview = Previews.forAgent(art, in: project)
        XCTAssertEqual(artPreview.lastPathComponent, "art-star.jpg")
        let (aw, ah) = try size(of: artPreview)
        XCTAssertEqual(aw, 1280); XCTAssertEqual(ah, 640)
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
