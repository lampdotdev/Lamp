import XCTest
import AppKit
@testable import Lamp

/// A glass design is read from the app's folder and from files other people share, and its svgs go to AppKit and
/// Icon Composer, so only plain shapes get through; and a copy of an app takes its icon in another hue.
final class GlassIconsTests: XCTestCase {
    private func svg(_ body: String) -> String {
        ##"<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">"## + body + "</svg>"
    }

    private func design(_ body: String) -> GlassDesign {
        GlassDesign(background: "#0A84FF", layers: [GlassDesign.Layer(name: "disc", material: .frosted, svg: svg(body),
                                                                       color: "#FFFFFF", opacity: 0.8, paint: nil)])
    }

    func testPlainShapesAndTheirGradientsPass() {
        let shapes = ##"<defs><radialGradient id="g"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#0A84FF"/></radialGradient></defs><circle cx="512" cy="512" r="300" fill="url(#g)"/>"##
        XCTAssertNil(GlassIcons.problem(in: design(shapes)))
    }

    func testAnythingReachingOutsideIsRefused() {
        for body in [##"<image href="file:///etc/hosts" width="10" height="10"/>"##,
                     ##"<circle r="10" fill="url(https://example.com/x)"/>"##,
                     ##"<use xlink:href="other.svg#a"/>"##,
                     ##"<text x="0" y="0">Hi</text>"##,
                     ##"<style>circle { fill: red }</style>"##,
                     ##"<a href="https://example.com"><circle r="10"/></a>"##] {
            XCTAssertNotNil(GlassIcons.problem(in: design(body)), body)
        }
    }

    func testASharedDesignKeepsOnlyItsOwnPainting() throws {
        var painted = design(##"<circle cx="512" cy="512" r="300"/>"##)
        painted.layers[0].material = .painted
        painted.layers[0].paint = "a sky"
        let key = GlassIcons.paintingKey(painted.layers[0])
        let picture = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            .representation(using: .png, properties: [:])!
        let shared = GlassArt(design: painted, paintings: [key: picture, "extra.png": picture])
        let read = try XCTUnwrap(GlassArt.decoded(try shared.encoded()))
        XCTAssertEqual(Array(read.paintings.keys), [key])
    }

    /// Copied onto the desk, a starter has the icon it shipped with and finds its artwork where an app keeps it, so a
    /// redraw of its icon (a lost preview, a recolor) is the same icon and paints nothing.
    func testAStarterCopiedFindsItsArtwork() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-glass-starters-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let folders = try FileManager.default.contentsOfDirectory(at: repo.appendingPathComponent("Resources/Starters"),
                                                                 includingPropertiesForKeys: nil).filter(\.hasDirectoryPath)
        for folder in folders {
            let starter = try XCTUnwrap(Starters.parse(String(contentsOf: folder.appendingPathComponent("starter.md"), encoding: .utf8),
                                                       folder: folder))
            let project = try Template.draft(name: starter.name, in: work.appendingPathComponent("apps"))
            try Template.fill(project)
            try Starters.copy(starter, into: project)
            let spec = try XCTUnwrap(Icons.load(project), starter.name)
            XCTAssertTrue(Starters.hasShippedIcon(project), starter.name)
            switch Icons.artwork(project, spec: spec) {
            case .glass: XCTAssertFalse(spec.game, "\(starter.name) is a game, painted rather than glass")
            case .picture: XCTAssertTrue(spec.game, "\(starter.name) ships a picture where glass was expected")
            case .waiting, nil: XCTFail("\(starter.name) has no artwork")
            }
        }
    }

    /// A game's painting and a design for glass never stand in for each other, while artwork kept before the game
    /// style existed is still found where it was.
    func testAGameKeepsItsArtworkApart() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-glass-game-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let project = try Template.draft(name: "Cards", in: work)
        var spec = IconSpec(subject: "a playing card", symbol: "suit.spade.fill", background: "green", tint: "#FFFFFF")
        let plain = Icons.artURL(project, spec: spec)
        spec.game = true
        XCTAssertNotEqual(Icons.artURL(project, spec: spec), plain)
        XCTAssertNotEqual(Icons.glassURL(project, spec: spec).deletingPathExtension(), plain.deletingPathExtension())
    }

    func testASubjectOfTwoObjectsIsCaught() {
        XCTAssertEqual(Icons.secondObject(in: "a monstera leaf overlapping a frosted clipboard"), "overlapping")
        XCTAssertNil(Icons.secondObject(in: "a red tomato kitchen timer with a green leafy stem"))
    }

    func testACopyTurnsTheHuesAndKeepsTheWhites() {
        let blue = GlassDesign(background: "#0A84FF", layers: [
            GlassDesign.Layer(name: "ring", material: .glass, svg: svg(##"<circle r="10" fill="#5AB0FF"/>"##), color: "#0060DF",
                              opacity: nil, paint: nil),
            GlassDesign.Layer(name: "dot", material: .solid, svg: svg(##"<circle r="5" fill="#FFFFFF"/>"##), color: "#FFFFFF",
                              opacity: nil, paint: nil),
        ])
        let green = blue.recolored(to: "#28A745")
        XCTAssertEqual(green.background, "#28A745")
        let ring = Icons.color(hex: green.layers[0].color!)!.usingColorSpace(.sRGB)!
        XCTAssertGreaterThan(ring.greenComponent, ring.blueComponent)
        XCTAssertFalse(green.layers[0].svg.contains("#5AB0FF"))
        XCTAssertEqual(green.layers[1].color, "#FFFFFF")
        XCTAssertTrue(green.layers[1].svg.contains("#FFFFFF"))
    }
}
