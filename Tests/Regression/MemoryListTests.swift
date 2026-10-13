import XCTest
@testable import Lamp

/// Settings → Memory lists the notes that hold something, not a row for everything there could be notes on.
final class MemoryListTests: XCTestCase {
    private typealias Row = MemorySettings.Row

    private func app(_ name: String, untitled: Bool = false) -> LampProject {
        LampProject(id: name.lowercased(), name: name, exe: name, dir: URL(fileURLWithPath: "/tmp/\(name)"), untitled: untitled)
    }

    /// The pane's listing where the sets of notes with these ids hold something.
    private func listing(_ apps: [LampProject], holding: Set<String> = []) -> MemorySettings.Listing? {
        MemorySettings.listing(on: true, apps: apps) { row in
            holding.contains(row.id) ? Memory.Notes(summary: "What \(row.title) covers", text: "Notes") : Memory.Notes()
        }
    }

    func testNothingSavedListsNothing() {
        let apps = (1...9).map { app("App\($0)") }
        let listing = listing(apps)
        XCTAssertEqual(listing?.saved, [])
        XCTAssertEqual(listing?.empty.map(\.title), ["About you"] + apps.map { "About \($0.name)" })
    }

    func testOnlyWhatHoldsNotesIsListedAndTheRestCanBeAdded() {
        let listing = listing([app("Pong"), app("Mirror")], holding: ["", "mirror"])
        XCTAssertEqual(listing?.saved.map(\.row.title), ["About you", "About Mirror"])
        XCTAssertEqual(listing?.saved.map(\.summary), ["What About you covers", "What About Mirror covers"])
        XCTAssertEqual(listing?.empty.map(\.title), ["About Pong"])
    }

    func testAnAppWithNoNameYetIsNotOfferedNotes() {
        XCTAssertEqual(listing([app("Untitled", untitled: true)])?.empty.map(\.title), ["About you"])
    }

    // Switched off, nothing reads the notes, and that goes for the pane too.
    func testSwitchedOffNoNotesAreRead() {
        var reads = 0
        let listing = MemorySettings.listing(on: false, apps: [app("Pong"), app("Mirror")]) { _ in
            reads += 1
            return Memory.Notes()
        }
        XCTAssertNil(listing)
        XCTAssertEqual(reads, 0)
    }

    func testEachSetOfNotesIsReadOnce() {
        var reads: [String] = []
        _ = MemorySettings.listing(on: true, apps: [app("Pong"), app("Mirror")]) { row in
            reads.append(row.id)
            return row.id == "pong" ? Memory.Notes(summary: "S", text: "T") : Memory.Notes()
        }
        XCTAssertEqual(reads, ["", "pong", "mirror"])
    }

    // A menu is for choosing among several: with one place left for notes, it's a button naming it.
    func testOnePlaceLeftIsAButtonAndSeveralAreAMenu() {
        XCTAssertEqual(listing([app("Pong")])?.adding, .several([Row(id: "", title: "About you"), Row(id: "pong", title: "About Pong")]))
        XCTAssertEqual(listing([app("Pong")], holding: [""])?.adding, .one(Row(id: "pong", title: "About Pong")))
        XCTAssertEqual(listing([], holding: [])?.adding, .one(Row(id: "", title: "About you")))
        XCTAssertEqual(listing([app("Pong")], holding: ["", "pong"])?.adding, .nothing)
        XCTAssertEqual(MemorySettings.addLabel(Row(id: "pong", title: "About Pong")), "Add Notes About Pong…")
        XCTAssertEqual(MemorySettings.addLabel(Row(id: "", title: "About you")), "Add Notes About You…")
    }
}
