import XCTest
import AppKit
@testable import Lamp
import LampFileLook

/// How a shared app looks before anyone opens it: Quick Look and the picture sent with it read the name and icon
/// out of the very file Lamp writes, without unpacking it.
final class SharedFileLookTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func project(icon: Bool) throws -> LampProject {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-look-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("tidenotes")
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "let tides = 2".write(to: dir.appendingPathComponent("Sources/ContentView.swift"), atomically: true, encoding: .utf8)
        let project = LampProject(id: "tidenotes", name: "Tide Notes", exe: "TideNotes", dir: dir)
        if icon {
            // The desk's icon, as Lamp writes it beside the app: a 256 px PNG.
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor.systemPink.setFill()
            NSBezierPath(roundedRect: NSRect(x: 20, y: 20, width: 216, height: 216), xRadius: 48, yRadius: 48).fill()
            NSGraphicsContext.restoreGraphicsState()
            try fm.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
            try rep.representation(using: .png, properties: [:])!.write(to: Icons.previewURL(project))
        }
        return project
    }

    func testTheSharedFileCarriesItsNameAndIcon() throws {
        let file = try Sharing.export(try project(icon: true))
        let look = try XCTUnwrap(LampFile(contentsOf: file))
        XCTAssertEqual(look.name, "Tide Notes")
        XCTAssertEqual(look.icon?.width, 256)
    }

    /// A file from before files carried their icon still shows its name, with Lamp's own icon.
    func testAFileWithoutAnIconStillShowsItsName() throws {
        let file = try Sharing.export(try project(icon: false))
        let look = try XCTUnwrap(LampFile(contentsOf: file))
        XCTAssertEqual(look.name, "Tide Notes")
        XCTAssertNil(look.icon)
        XCTAssertNotNil(Store.sharePicture(for: file))
    }

    func testThePictureIsWrittenBesideTheFile() throws {
        let file = try Sharing.export(try project(icon: true))
        let picture = try XCTUnwrap(Store.sharePicture(for: file))
        XCTAssertEqual(picture.lastPathComponent, "Tide Notes.png")
        let image = try XCTUnwrap(NSImage(contentsOf: picture)?.representations.first)
        XCTAssertEqual(image.pixelsWide, 2400)
        XCTAssertEqual(image.pixelsHigh, 1260)
    }

    func testAnythingElseIsNotALampFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-look-\(UUID().uuidString)")
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("Fake.lampapp")
        try Data("not a zip".utf8).write(to: file)
        XCTAssertNil(LampFile(contentsOf: file))
    }
}
