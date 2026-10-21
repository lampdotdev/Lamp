import XCTest
@testable import Lamp

/// The gallery draws the light on an app being changed with Lamp's own copy of its layers (TransitionLook.swift),
/// and the apps draw it with the one in their support code: the two must be the same text, or the gallery shows
/// something no app does.
final class TransitionLookTests: XCTestCase {
    func testTheGallerysLookIsTheAppsLook() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/Lamp/TransitionLook.swift")
        let lamps = try block(in: String(contentsOf: file, encoding: .utf8))
        let apps = try block(in: Template.lampSupportSwift)
        XCTAssertFalse(lamps.isEmpty)
        XCTAssertEqual(lamps, apps, "Run scripts/sync-transition-look.sh to copy TransitionLook.swift into Template.swift.")
    }

    /// The lines between the markers, without their indentation, which differs by one level.
    private func block(in text: String) throws -> [String] {
        let lines = text.components(separatedBy: "\n")
        let start = try XCTUnwrap(lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "// TransitionLook" })
        let end = try XCTUnwrap(lines[start...].firstIndex { $0.trimmingCharacters(in: .whitespaces) == "// end TransitionLook" })
        return lines[(start + 1)..<end].map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
