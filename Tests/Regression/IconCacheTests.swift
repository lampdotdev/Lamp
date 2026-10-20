import AppKit
import XCTest
@testable import Lamp

/// Every install asks for the app's icon, and drawing it takes seconds: an icon already drawn from the same design and
/// artwork is kept as it is, and any change to either draws it again.
final class IconCacheTests: XCTestCase {
    private var dir: URL!
    private var app: LampProject!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("icon-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        app = LampProject(id: "cache-\(UUID().uuidString)", name: "Tide Clock", exe: "TideClock", dir: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func written() -> Date? {
        (try? Icons.icnsURL(app).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    func testTheSameIconIsNotDrawnAgain() async throws {
        let spec = IconSpec(subject: "a clock", symbol: "clock", background: "blue", tint: "#0A84FF")
        _ = try await Icons.write(spec, art: nil, for: app)
        let first = try XCTUnwrap(written())
        _ = try await Icons.write(spec, art: nil, for: app)
        XCTAssertEqual(written(), first, "The same design with the same artwork keeps the files already drawn")

        let other = IconSpec(subject: "a clock", symbol: "clock", background: "orange", tint: "#0A84FF")
        _ = try await Icons.write(other, art: nil, for: app)
        let second = try XCTUnwrap(written())
        XCTAssertNotEqual(second, first, "A new design is drawn")

        let art = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.systemRed.setFill(); rect.fill(); return true
        }
        _ = try await Icons.write(other, art: .picture(art), for: app)
        XCTAssertNotEqual(written(), second, "New artwork for the same design is drawn")

        try FileManager.default.removeItem(at: Icons.icnsURL(app))
        _ = try await Icons.write(other, art: .picture(art), for: app)
        XCTAssertNotNil(written(), "A missing file is drawn again")
    }
}
