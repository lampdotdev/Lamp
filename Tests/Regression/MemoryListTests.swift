import XCTest
@testable import Lamp

/// Settings → Memory lists the notes that hold something, not a row for everything there could be notes on.
final class MemoryListTests: XCTestCase {
    private func app(_ name: String, untitled: Bool = false) -> LampProject {
        LampProject(id: name.lowercased(), name: name, exe: name, dir: URL(fileURLWithPath: "/tmp/\(name)"), untitled: untitled)
    }

    func testNothingSavedListsNothing() {
        let apps = (1...9).map { app("App\($0)") }
        let rows = MemorySettings.rows(apps: apps) { _ in false }
        XCTAssertTrue(rows.saved.isEmpty)
        XCTAssertEqual(rows.empty.map(\.title), ["About you"] + apps.map { "About \($0.name)" })
    }

    func testOnlyWhatHoldsNotesIsListedAndTheRestCanBeAdded() {
        let rows = MemorySettings.rows(apps: [app("Pong"), app("Mirror")]) { $0.id == "" || $0.id == "mirror" }
        XCTAssertEqual(rows.saved.map(\.title), ["About you", "About Mirror"])
        XCTAssertEqual(rows.empty.map(\.title), ["About Pong"])
    }

    func testAnAppWithNoNameYetIsNotOfferedNotes() {
        let rows = MemorySettings.rows(apps: [app("Untitled", untitled: true)]) { _ in false }
        XCTAssertEqual(rows.empty.map(\.title), ["About you"])
    }
}
