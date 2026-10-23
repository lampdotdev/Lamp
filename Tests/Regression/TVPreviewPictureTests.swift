import AppKit
import XCTest
@testable import Lamp

/// The agent judges movement from two pictures of the TV preview, and the time between them is more than a `use_app`
/// wait: its own thinking between the calls counts too. So each picture says when it was taken and how long after the one
/// before. A picture is 960 pixels across, the size `use_app`'s points are in, and where it's taken from the window, the
/// window's rounded corners are black like a TV's edge, not the clear corners of the capture.
@MainActor
final class TVPreviewPictureTests: XCTestCase {
    func testEachPictureSaysWhenItWasTakenAndTheCornersAreBlack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tv-picture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("app"), staged = root.appendingPathComponent("web")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try "<html><body style=\"margin:0;width:1920px;height:1080px;background:#fff\"></body></html>"
            .write(to: staged.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let project = LampProject(id: "tv-preview-picture", name: "Blank", exe: "Blank", dir: dir)
        defer { TVPreview.close(project) }
        let problem = await TVPreview.show(project, staged: staged, inFront: false)
        XCTAssertNil(problem)

        let firstTaken = await TVPreview.picture(project)
        try await Task.sleep(for: .milliseconds(1500))
        let secondTaken = await TVPreview.picture(project)
        let first = try XCTUnwrap(firstTaken), second = try XCTUnwrap(secondTaken)

        XCTAssertNil(first.since)
        let since = try XCTUnwrap(second.since)
        XCTAssertEqual(since, second.at.timeIntervalSince(first.at), accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(since, 1.5)

        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let at = Date(timeIntervalSince1970: 1_792_714_627.43)   // 00:17:07.4 UTC
        XCTAssertEqual(TVPreview.takenNote(.init(png: Data(), moving: true, at: at, since: nil), timeZone: utc),
                       "This picture was taken at 00:17:07.4 by this Mac's clock, the first since the app was opened in the preview.")
        XCTAssertEqual(TVPreview.takenNote(.init(png: Data(), moving: true, at: at, since: 3.41), timeZone: utc),
                       "This picture was taken at 00:17:07.4 by this Mac's clock, 3.4 s after the previous one.")

        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: second.png))
        XCTAssertEqual(bitmap.pixelsWide, 960)
        XCTAssertEqual(bitmap.pixelsHigh, 540)
        let middle = try XCTUnwrap(bitmap.colorAt(x: 480, y: 270)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(middle.brightnessComponent, 0.9, "the page is white")
        // Only a capture of the window has rounded corners; WebKit's snapshot is square.
        if second.moving {
            for (x, y) in [(0, 539), (959, 539)] {
                let corner = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                XCTAssertLessThan(corner.brightnessComponent, 0.1, "corner \(x),\(y)")
                XCTAssertEqual(corner.alphaComponent, 1, accuracy: 0.01, "corner \(x),\(y)")
            }
        }
    }
}
