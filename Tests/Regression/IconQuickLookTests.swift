import AppKit
import XCTest
@testable import Lamp

/// Clicking the icon in the chat's title bar shows it in Quick Look, which goes on showing what it once read at a
/// path. Each time the icon changes, Quick Look must be handed a new file holding the new icon.
final class IconQuickLookTests: XCTestCase {
    private var dir: URL!
    private var app: LampProject!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("icon-quicklook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        app = LampProject(id: "ql-\(UUID().uuidString)", name: "Tide Clock", exe: "TideClock", dir: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Forge/Icons/\(app.id)")
        try? FileManager.default.removeItem(at: cache)
    }

    func testEachIconChangeIsANewFileWithTheNewIcon() async throws {
        let first = IconSpec(subject: "a clock", symbol: "clock", background: "blue", tint: "#0A84FF")
        Icons.save(first, for: app)
        _ = try await Icons.write(first, art: nil, for: app)
        let shownFirst = try await shown()
        XCTAssertEqual(shownFirst.lastPathComponent, "Tide Clock.png")
        let again = try await shown()
        XCTAssertEqual(again, shownFirst, "An unchanged icon is the same file")

        // A turn redesigns the icon: the new design is saved, the .icns isn't written until the turn ends.
        let second = IconSpec(subject: "a wave", symbol: "water.waves", background: "orange", tint: "#FF9F0A")
        Icons.save(second, for: app)
        let shownSecond = try await shown()
        XCTAssertNotEqual(shownSecond, shownFirst)
        XCTAssertFalse(FileManager.default.fileExists(atPath: shownFirst.path), "Earlier previews are cleared")
        XCTAssertNotEqual(try pixels(shownSecond), try pixels(Icons.icnsURL(app)),
                          "The preview is the new design, not the .icns still holding the old one")

        // Artwork arrives for the same design, and later a picture the person chose replaces it at the same path.
        let art = Icons.artURL(app, spec: second)
        try FileManager.default.createDirectory(at: art.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png(.systemRed).write(to: art)
        let shownArt = try await shown()
        XCTAssertNotEqual(shownArt, shownSecond)
        try png(.systemGreen).write(to: art)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: art.path)
        let artPixel = try pixels(shownArt)
        let shownChosen = try await shown()
        XCTAssertNotEqual(shownChosen, shownArt)
        XCTAssertNotEqual(try pixels(shownChosen), artPixel)
    }

    private func shown() async throws -> URL {
        let url = await Icons.largePreview(app)
        return try XCTUnwrap(url)
    }

    private func png(_ color: NSColor) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    /// A pixel inside the tile, a little above its middle.
    private func pixels(_ url: URL) throws -> NSColor? {
        let rep = try XCTUnwrap(NSImage(contentsOf: url)?.representations.compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide < $1.pixelsWide })
        return rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 3)
    }
}
