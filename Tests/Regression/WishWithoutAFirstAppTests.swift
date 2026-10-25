import XCTest
@testable import Lamp

/// What a wish whose apps are all in folders of their own keeps through sharing, going back to a version, and a Lamp from
/// before such wishes: each app's name among the wish's apps, the list of apps the version had, and being left alone.
final class WishWithoutAFirstAppTests: XCTestCase {
    private var roots: [URL] = []

    override func setUpWithError() throws { expectNoSharingFoldersLeft() }

    override func tearDown() {
        unsetenv("GIT_CONFIG_GLOBAL")
        for root in roots { try? FileManager.default.removeItem(at: root) }
    }

    /// Under the home folder, as Lamp's own git runs confined to it, with git's Mac-wide settings an empty file.
    private func newRoot() throws -> URL {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-wish-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        let settings = fm.temporaryDirectory.appendingPathComponent("lamp-test-git-settings-\(UUID().uuidString)")
        roots.append(settings)
        try "".write(to: settings, atomically: true, encoding: .utf8)
        setenv("GIT_CONFIG_GLOBAL", settings.path, 1)
        return root
    }

    /// A part of `wish` of this kind in this folder, as `make_app_for` leaves one.
    @discardableResult
    private func part(_ kind: Platform, in folder: String, of wish: LampProject) throws -> LampProject {
        let part = LampProject(id: Parts.id(wish: wish.id, folder: folder), name: wish.name, exe: wish.exe,
                               dir: wish.dir.appendingPathComponent(folder), instance: Parts.instance(wish: wish, folder: folder),
                               platform: kind, partOf: wish.id)
        try FileManager.default.createDirectory(at: part.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try Template.saveMeta(part)
        try Template.fill(part)
        return part
    }

    /// A Mac wish whose Mac app was taken away: only the wish's own files are left in its folder, beside its parts'. The
    /// app's files are moved into `aside`, when given, so a test can bring them back as a version would.
    private func takeAwayTheFirstApp(of wish: LampProject, aside: URL? = nil) throws -> LampProject {
        let fm = FileManager.default
        let kept = Parts.folders.union([".lamp", ".git", ".gitignore", "icon.json", AppDescription.file, Attachments.folder])
        if let aside { try fm.createDirectory(at: aside, withIntermediateDirectories: true) }
        for name in try fm.contentsOfDirectory(atPath: wish.dir.path) where !kept.contains(name) {
            if let aside { try fm.moveItem(at: wish.dir.appendingPathComponent(name), to: aside.appendingPathComponent(name)) }
            else { try fm.removeItem(at: wish.dir.appendingPathComponent(name)) }
        }
        return try XCTUnwrap(Store.readWish(at: wish.dir))
    }

    // MARK: Sharing

    /// A TV app in TV/ and an iPhone app made for the Mac too, still in iPhone/, the Mac app the wish began with gone. The
    /// TV app's code talks to "iphone". The file carries the app at its root by its kind, so the iPhone app there would be
    /// "apple" to the TV app on the Mac that opens it: the TV app goes at the root, and the iPhone app keeps its folder.
    func testEachAppKeepsItsNameAmongTheWishsAppsInASharedFile() throws {
        let made = try Template.scaffold(name: "Remote", platform: .mac, in: try newRoot())
        try part(.tv, in: "TV", of: made)
        try part(.universal, in: "iPhone", of: made)
        let wish = try takeAwayTheFirstApp(of: made)
        XCTAssertFalse(wish.holdsApp)
        let before = Set(Parts.load(wish).map { $0.dir.lastPathComponent.lowercased() })
        XCTAssertEqual(before, ["tv", "iphone"])

        let package = try opened(try exported(wish))
        // As the Mac that opens it names them (`WishRooms.peer`): the app at the root by its kind's folder, each other
        // by the folder the file gives it.
        let after = Set([Parts.folder(for: package.platform).lowercased()] + package.parts.map { $0.folder.lowercased() })
        XCTAssertEqual(after, before)
        XCTAssertEqual(package.platform, .tv)
        XCTAssertEqual(package.parts.map(\.folder), ["iPhone"])
        XCTAssertEqual(package.parts.map(\.package.platform), [.universal])
    }

    /// The same part kept for a Mac that can't build it yet is made in its folder later, not in the one its kind gets
    /// when new; a folder of another family, which a file could say, isn't taken.
    func testAPartKeptForLaterKeepsItsFolder() throws {
        let made = try Template.scaffold(name: "Remote", platform: .mac, in: try newRoot())
        try part(.tv, in: "TV", of: made)
        try part(.universal, in: "iPhone", of: made)
        let package = try opened(try exported(try takeAwayTheFirstApp(of: made)))
        let phone = try XCTUnwrap(package.parts.first)

        let receiver = try Template.scaffold(name: "Remote 2", platform: .tv, in: try newRoot())
        try Sharing.keep(phone, in: receiver.dir)
        XCTAssertEqual(Sharing.kept(in: receiver.dir, for: .universal)?.folder, "iPhone")
        XCTAssertTrue(Parts.folder("iPhone", canHold: .universal))
        XCTAssertTrue(Parts.folder("Mac", canHold: .universal))
        XCTAssertFalse(Parts.folder("TV", canHold: .universal))
        XCTAssertFalse(Parts.folder("Sources", canHold: .universal))
    }

    // MARK: A Lamp from before

    /// Lamp 0.19 leaves alone a wish whose meta.json says a layout above 1 (`NewerWish`), and reads every other one as its
    /// own: a wish with no app in its own folder would be an empty draft to it, and its first message would write a new
    /// app there. Such a wish says 2 from the moment its first app goes, and stops saying it once one is back.
    func testAWishWithoutItsFirstAppIsLeftAloneByALampFromBefore() throws {
        let root = try newRoot()
        let made = try Template.scaffold(name: "Remote", platform: .mac, in: root)
        try part(.tv, in: "TV", of: made)
        XCTAssertNil(NewerWish.savedLayout(at: made.dir), "a wish that holds its app is read by any Lamp")

        let aside = root.appendingPathComponent("taken-away")
        let wish = try takeAwayTheFirstApp(of: made, aside: aside)
        XCTAssertEqual(NewerWish.savedLayout(at: wish.dir), 2)
        XCTAssertGreaterThan(try XCTUnwrap(NewerWish.savedLayout(at: wish.dir)), 1, "what Lamp 0.19 leaves alone")
        XCTAssertNotNil(Store.readWish(at: wish.dir), "this Lamp still reads it")
        XCTAssertNil(NewerWish.read(at: wish.dir))
        try Template.saveMeta(wish)
        XCTAssertEqual(NewerWish.savedLayout(at: wish.dir), 2, "every save of it says so")

        // The app back in the wish's folder (an Undo): a Lamp from before reads it again.
        for name in try FileManager.default.contentsOfDirectory(atPath: aside.path) {
            try FileManager.default.moveItem(at: aside.appendingPathComponent(name), to: made.dir.appendingPathComponent(name))
        }
        XCTAssertTrue(try XCTUnwrap(Store.readWish(at: made.dir)).holdsApp)
        XCTAssertNil(NewerWish.savedLayout(at: made.dir))
    }

    // MARK: Going back to a version

    /// A Mac wish asked to be on Android too while this Mac can't build Android apps: the Android app waits on the wish's
    /// list. Going back to the version before that takes it off the list with the rest of the change, so the next turn
    /// doesn't make it, and the Mac app's building blocks are written for an app on its own again.
    func testGoingBackToAVersionBringsBackItsListOfApps() async throws {
        var wish = try Template.scaffold(name: "Tally", platform: .mac, in: try newRoot())
        wish.apps = [WishApp(kind: .mac)]
        try Template.saveMeta(wish)
        try Template.writeOwnedFiles(for: wish)
        let initialised = TestShell.run("/bin/bash", ["-c", "git init -q -b main"], in: wish.dir)
        XCTAssertEqual(initialised.status, 0, initialised.output)
        let first = await Versions.commitAll("-qm \"$LAMP_PROMPT\"", in: wish.dir, env: ["LAMP_PROMPT": "Make a tally"])
        XCTAssertEqual(first, .saved)

        wish.apps = [WishApp(kind: .mac), WishApp(kind: .android, needs: "This Mac can't build Android apps yet.")]
        try Template.saveMeta(wish)
        try Template.writeOwnedFiles(for: wish)
        try "// counts up\n".write(to: wish.dir.appendingPathComponent("Sources/Count.swift"), atomically: true, encoding: .utf8)
        let second = await Versions.commitAll("-qm \"$LAMP_PROMPT\"", in: wish.dir, env: ["LAMP_PROMPT": "Put it on my Android phone too"])
        XCTAssertEqual(second, .saved)
        let support = wish.dir.appendingPathComponent("Sources/LampSupport.swift")
        XCTAssertTrue(try String(contentsOf: support, encoding: .utf8).contains("MARK: - The wish's other apps"))

        let versions = await Versions.list(wish)
        XCTAssertEqual(versions.map(\.apps), [[.mac, .android], [.mac]])
        let target = try XCTUnwrap(versions.last)
        let restored = await Versions.restore(wish, to: target, message: "Undid “Put it on my Android phone too”")
        XCTAssertTrue(restored)

        XCTAssertEqual(try XCTUnwrap(Store.readWish(at: wish.dir)).apps, [WishApp(kind: .mac)])
        XCTAssertFalse(try String(contentsOf: support, encoding: .utf8).contains("MARK: - The wish's other apps"))
        let unsaved = await Versions.hasUnsavedChanges(wish)
        XCTAssertFalse(unsaved, "the restore's own version holds everything it wrote")
        // And the Undo's own version carries the list it brought back.
        let after = await Versions.list(wish)
        XCTAssertEqual(after.first?.apps, [.mac])
    }
}
