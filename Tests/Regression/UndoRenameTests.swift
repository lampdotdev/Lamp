import XCTest
@testable import Lamp

/// A wish's name is kept in Lamp's own folder, which versions don't hold, so Undo of a rename put back its files and
/// left it with the new name. The versions that change the name carry it, and going back to one brings it back.
final class UndoRenameTests: XCTestCase {
    private let escape = HistoryEscapeTests()
    override func tearDown() { escape.tearDown() }

    /// A real history: a change, a rename that changed no file, and Undo of it.
    func testUndoOfARenameGivesTheOldNameBack() async throws {
        let app = try escape.app()
        try "two\n".write(to: app.project.dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        let changed = await Versions.save(app.project, message: "Make it two")
        XCTAssertTrue(changed)
        let renamed = await Versions.save(app.project, message: "Rename to Heads or Tails",
                                          trailer: Versions.nameTrailers(from: "Coin Flip", to: "Heads or Tails"), allowEmpty: true)
        XCTAssertTrue(renamed, "a rename is a version even when no file named the app")

        var versions = await Versions.list(app.project)
        let (undoing, target) = try XCTUnwrap(Versions.undoTarget(in: versions))
        XCTAssertEqual(undoing.message, "Rename to Heads or Tails")
        XCTAssertEqual(Versions.name(at: target, in: versions), "Coin Flip")
        let undone = await Versions.restore(app.project, to: target, message: "Undid “\(undoing.label)”",
                                            trailer: "Lamp-Undid: \(undoing.id)", renaming: ("Heads or Tails", "Coin Flip"))
        XCTAssertTrue(undone, "the files are as they were, and the name still changes")

        versions = await Versions.list(app.project)
        XCTAssertEqual(Versions.name(at: try XCTUnwrap(versions.first), in: versions), "Coin Flip")
        // Going back to the rename itself, from there, is "Heads or Tails" again; to the first version, "Coin Flip".
        let rename = try XCTUnwrap(versions.first { $0.message == "Rename to Heads or Tails" })
        XCTAssertEqual(Versions.name(at: rename, in: versions), "Heads or Tails")
        XCTAssertEqual(Versions.name(at: try XCTUnwrap(versions.last), in: versions), "Coin Flip")
        // Undo again goes on back past the rename, to a version that had the old name.
        let (_, earlier) = try XCTUnwrap(Versions.undoTarget(in: versions))
        XCTAssertEqual(Versions.name(at: earlier, in: versions), "Coin Flip")
    }

    /// A name may hold what a shell reads inside quotes; it's saved as it is.
    func testANameIsSavedAsWritten() async throws {
        let app = try escape.app()
        let saved = await Versions.save(app.project, message: "Rename to $HOME `id`",
                                        trailer: Versions.nameTrailers(from: "Coin Flip", to: "$HOME `id`"), allowEmpty: true)
        XCTAssertTrue(saved)
        let versions = await Versions.list(app.project)
        XCTAssertEqual(versions.first?.renamedTo, "$HOME `id`")
        XCTAssertEqual(versions.first?.renamedFrom, "Coin Flip")
        XCTAssertEqual(versions.first?.message, "Rename to $HOME `id`")
    }

    /// An app renamed by a Lamp from before versions carried the name has no record of the old one: it keeps its name.
    func testARenameFromBeforeLeavesTheNameAlone() async throws {
        let app = try escape.app()
        let saved = await Versions.save(app.project, message: "Rename to Heads or Tails", allowEmpty: true)
        XCTAssertTrue(saved)
        let versions = await Versions.list(app.project)
        XCTAssertEqual(versions.first?.renamedTo, "Heads or Tails")
        XCTAssertNil(Versions.name(at: try XCTUnwrap(versions.last), in: versions))
    }
}
