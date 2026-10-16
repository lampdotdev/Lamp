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

    /// Artwork that arrives during a turn reaches the .icns only when the turn ends, so a file shared then must
    /// carry the icon drawn from its design, not the one in the .icns.
    func testTheIconIsDrawnFromTheDesignNotAnOlderIcns() async throws {
        let project = try project(icon: false)
        let spec = IconSpec(subject: "a wave", symbol: "water.waves", background: "blue", tint: "#0A84FF")
        try JSONEncoder().encode(spec).write(to: Icons.specURL(project))
        try writeIcns(of: .systemRed, to: Icons.icnsURL(project))

        for icon in [Sharing.drawnIcon(of: project), await Sharing.sharedIcon(of: project)] {
            let file = try Sharing.export(project, icon: icon)
            let image = try XCTUnwrap(LampFile(contentsOf: file)?.icon)
            let middle = try XCTUnwrap(NSBitmapImageRep(cgImage: image).colorAt(x: image.width / 2, y: image.height / 5))
            XCTAssertLessThan(middle.redComponent, middle.blueComponent, "the .icns's red, not the design's blue")
        }
    }

    private func writeIcns(of color: NSColor, to url: URL) throws {
        let fm = FileManager.default
        let set = root!.appendingPathComponent("stale.iconset")
        try fm.createDirectory(at: set, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent("icon_512x512@2x.png"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", set.path, "-o", url.path]
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try process.run()
        process.waitUntilExit()
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
