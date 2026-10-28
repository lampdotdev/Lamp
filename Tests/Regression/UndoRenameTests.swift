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

    /// Lamp's own files carry the app's name. Undo of a rename saved them under the name it was leaving, and the build
    /// after it wrote them under the name it gave back: the app was left unsaved, so the next Undo only discarded that
    /// and rebuilt, and Undo never got past the rename (Roomote's review of #615).
    func testUndoOfARenameLeavesNothingUnsavedForTheNextBuild() async throws {
        let app = try escape.app()
        try Template.writeOwnedFiles(for: app.project)
        let made = await Versions.save(app.project, message: "Make it")
        XCTAssertTrue(made)
        // The rename, as Lamp saves it: its own files under the new name.
        let renamed = app.project.named("Heads or Tails")
        try Template.writeOwnedFiles(for: renamed)
        let saved = await Versions.save(renamed, message: "Rename to Heads or Tails",
                                        trailer: Versions.nameTrailers(from: "Coin Flip", to: "Heads or Tails"), allowEmpty: true)
        XCTAssertTrue(saved)
        var unsaved = await Versions.hasUnsavedChanges(renamed)
        XCTAssertFalse(unsaved, "the rename's own build finds its files as saved")

        let versions = await Versions.list(renamed)
        let (undoing, target) = try XCTUnwrap(Versions.undoTarget(in: versions))
        let undone = await Versions.restore(renamed, to: target, message: "Undid “\(undoing.label)”",
                                            trailer: "Lamp-Undid: \(undoing.id)", renaming: ("Heads or Tails", "Coin Flip"))
        XCTAssertTrue(undone)
        // What the build after Undo writes, under the name given back.
        try Template.writeOwnedFiles(for: renamed.named("Coin Flip"))
        unsaved = await Versions.hasUnsavedChanges(renamed)
        XCTAssertFalse(unsaved, "the build after Undo finds Lamp's files as the Undo saved them")
    }

    /// "TV instead" for a Mac wish, then Undo: the restore wrote the Mac app's own files while the wish's list still had
    /// the TV app, so with the link code for it. The TV app was then forgotten, the next build wrote them without that
    /// code, and every Undo after only discarded the difference, which the build made again.
    func testUndoPastAReplacedFirstAppLeavesNothingUnsaved() async throws {
        let app = try escape.app()
        var wish = app.project
        try FileManager.default.createDirectory(at: wish.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try Template.saveMeta(wish)
        try Template.fill(wish)
        let made = await Versions.save(wish, message: "Make it")
        XCTAssertTrue(made)
        // The Mac app replaced by a TV app in TV/, as `make_app_for` leaves it.
        let tv = LampProject(id: Parts.id(wish: wish.id, folder: "TV"), name: wish.name, exe: wish.exe, dir: wish.dir.appendingPathComponent("TV"),
                             platform: .tv, partOf: wish.id)
        try FileManager.default.createDirectory(at: tv.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try Template.saveMeta(tv)
        try Template.fill(tv)
        for name in ["Sources", "Package.swift", "build.sh", "APP.md", "Assets"] { try? FileManager.default.removeItem(at: wish.dir.appendingPathComponent(name)) }
        wish.apps = [WishApp(kind: .tv)]
        try Template.saveMeta(wish)
        wish = try XCTUnwrap(Store.readWish(at: wish.dir))
        let replaced = await Versions.save(wish, message: "TV instead")
        XCTAssertTrue(replaced)

        let versions = await Versions.list(wish)
        let (undoing, target) = try XCTUnwrap(Versions.undoTarget(in: versions))
        let undone = await Versions.restore(wish, to: target, message: "Undid “\(undoing.label)”", trailer: "Lamp-Undid: \(undoing.id)")
        XCTAssertTrue(undone)
        // The TV app is forgotten (off the list, `Store.forget`), and the Mac app's next build writes Lamp's files.
        var after = try XCTUnwrap(Store.readWish(at: wish.dir))
        after.apps = after.apps.filter { $0.kind != .tv }
        try Template.saveMeta(after)
        try Template.writeOwnedFiles(for: after)
        let unsaved = await Versions.hasUnsavedChanges(after)
        XCTAssertFalse(unsaved, "the build after Undo finds Lamp's files as the Undo saved them")
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
