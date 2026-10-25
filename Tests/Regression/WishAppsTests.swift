import XCTest
@testable import Lamp

/// A wish is its own thing, apart from the apps it's made of: any of Lamp's kinds that can be a part can go together,
/// and the wish remembers which apps it should have and what each one still waits for.
final class WishAppsTests: XCTestCase {
    /// A Mac app with an Android app, an iPhone app with an Android app, a TV app with an Android app: each is one wish of
    /// two apps, in Lamp's order. No app leads.
    func testAnAndroidAppCanGoWithAnyOtherKind() throws {
        XCTAssertEqual(Parts.kinds(for: ["mac", "android"]), [.mac, .android])
        XCTAssertEqual(Parts.kinds(for: ["iphone", "android"]), [.iphone, .android])
        XCTAssertEqual(Parts.kinds(for: ["tv", "android"]), [.android, .tv])
    }

    /// Three devices of three families are three apps: Apple's devices as one app for both.
    func testAWishCanBeThreeApps() throws {
        XCTAssertEqual(Parts.kinds(for: ["tv", "mac", "iphone", "android"]), [.universal, .android, .tv])
    }

    /// An Android app alone is still one app, and a device whose integration declares its apps still stands alone.
    func testOneKindAloneIsOneApp() throws {
        XCTAssertEqual(Parts.kinds(for: ["android"]), [.android])
        XCTAssertNil(Parts.kinds(for: ["android", "nothing-lamp-makes"]))
    }
}

/// `make_app_for` makes a wish the apps listed, every app of it treated alike: kept, changed in place inside its family,
/// added in a folder of its own, or taken away, the app in the wish's own folder as much as any other.
final class WishAppsRootTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wish-apps-root-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// "Put it on the TV too" for a Mac wish: the Mac app stays, its code kept, and the TV app goes beside it in TV/.
    func testTVAddedToAMacWishKeepsTheMacApp() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let plan = Parts.plan(try XCTUnwrap(Parts.kinds(for: ["mac", "tv"])), for: [wish])
        XCTAssertEqual(plan, Parts.Plan(keep: [wish.id: .mac], add: [.tv], remove: []))
        XCTAssertEqual(Parts.folder(for: .tv), "TV")
    }

    /// An app is changed in place only inside its family: a Mac app that's to be for the iPhone too becomes the app for
    /// both, in the same folder, with its code.
    func testAnAppChangesInPlaceInsideItsFamily() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let plan = Parts.plan(try XCTUnwrap(Parts.kinds(for: ["mac", "iphone", "tv"])), for: [wish])
        XCTAssertEqual(plan, Parts.Plan(keep: [wish.id: .universal], add: [.tv], remove: []))
    }

    /// "I want it on my TV, not my Mac" for a Mac wish: the Mac app the wish began with goes like any other, and the TV
    /// app is made in TV/. The wish itself (its folder, name, chat and history) stays.
    func testTheFirstAppIsReplacedLikeAnyOther() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        XCTAssertEqual(Parts.plan(try XCTUnwrap(Parts.kinds(for: ["tv"])), for: [wish]), Parts.Plan(keep: [:], add: [.tv], remove: [wish.id]))
        let tv = LampProject(id: "tally.tv", name: "Tally", exe: "Tally", dir: wish.dir.appendingPathComponent("TV"), platform: .tv, partOf: wish.id)
        // With a TV app beside it, dropping the Mac app takes only it away.
        XCTAssertEqual(Parts.plan(try XCTUnwrap(Parts.kinds(for: ["tv"])), for: [wish, tv]), Parts.Plan(keep: [tv.id: .tv], add: [], remove: [wish.id]))
    }

    /// A TV app in TV/, beside the Mac app in the wish's own folder, takes players as a TV app with other apps does: its
    /// game is open for the wish's other apps wherever it is. A TV app on its own without a phone page takes none.
    func testATVAppInItsFolderTakesTheWishsOtherAppsAsPlayers() {
        let tv = LampProject(id: "tally.tv", name: "Tally", exe: "Tally", dir: root.appendingPathComponent("tally/TV"),
                             platform: .tv, partOf: "tally")
        XCTAssertTrue(Store.takesPlayers(tv))
        XCTAssertFalse(Store.takesPlayers(LampProject(id: "slides", name: "Slides", exe: "Slides", dir: root.appendingPathComponent("slides"), platform: .tv)))
    }
}

/// A wish whose first app was taken away, its apps all in folders of their own: still the wish, read back from its
/// files, and never given an app in its own folder again by Lamp's own writes.
final class WishWithoutItsFirstAppTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wish-apps-folders-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// A Mac wish whose Mac app was replaced by a TV app in TV/: its folder holds the wish's files and TV/ only.
    private func replacedWish() throws -> LampProject {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let tv = LampProject(id: "tally.tv", name: "Tally", exe: "Tally", dir: wish.dir.appendingPathComponent("TV"),
                             instance: wish.instance + ".TV", platform: .tv, partOf: wish.id)
        try FileManager.default.createDirectory(at: tv.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try Template.saveMeta(tv)
        try Template.fill(tv)
        let kept: Set<String> = [".lamp", ".git", ".gitignore", "icon.json", AppDescription.file, Attachments.folder, "TV"]
        for name in try FileManager.default.contentsOfDirectory(atPath: wish.dir.path) where !kept.contains(name) {
            try FileManager.default.removeItem(at: wish.dir.appendingPathComponent(name))
        }
        return try XCTUnwrap(Store.readWish(at: wish.dir))
    }

    func testItIsStillTheWishWithItsAppInAFolder() throws {
        let wish = try replacedWish()
        XCTAssertFalse(wish.holdsApp)
        XCTAssertTrue(wish.scaffolded, "it's no draft to be made again")
        XCTAssertEqual(Parts.load(wish).map(\.platform), [.tv])
        XCTAssertEqual(Parts.made(in: wish, parts: Parts.load(wish)), [.tv])
        XCTAssertFalse(Template.isScaffold(wish))
    }

    func testLampsOwnFilesNeverPutAnAppBackInItsFolder() throws {
        let wish = try replacedWish()
        try Template.writeOwnedFiles(for: wish)
        try Template.fill(wish)
        XCTAssertFalse(FileManager.default.fileExists(atPath: wish.dir.appendingPathComponent("Package.swift").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: wish.dir.appendingPathComponent("Sources").path))
        XCTAssertFalse(Runtime.sourcesChanged(wish))
        // A copy of it, made before its apps are listed, isn't taken for an app either.
        let copy = LampProject(id: wish.id, name: wish.name, exe: wish.exe, dir: wish.dir, platform: .mac)
        XCTAssertFalse(copy.holdsApp)
    }

    /// One app is one app, wherever it is: a wish left with only its TV app gets nothing for talking to other apps.
    func testOneAppInAFolderIsAWishOfOneApp() throws {
        let wish = try replacedWish()
        XCTAssertFalse(Template.talksToOtherApps(wish))
        XCTAssertFalse(Template.talksToOtherApps(try XCTUnwrap(Parts.load(wish).first)))
    }
}

/// What a wish keeps of the apps it should have, in its own meta.json, so a quit or a failure between asking and making
/// them loses nothing.
final class WishAppsKeptTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wish-apps-kept-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// A wish for a Mac app and an Android app, this Mac not yet able to build the Android app: the wish's meta.json says
    /// it should have one and why it isn't made yet, and reads back the same.
    func testAWishRemembersTheAppsItShouldHaveAndWhatEachWaitsFor() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        var wanted = wish
        wanted.apps = [WishApp(kind: .mac), WishApp(kind: .android, needs: "this Mac can't build it for Android.")]
        try Template.saveMeta(wanted)
        let read = try XCTUnwrap(Store.readWish(at: wish.dir))
        XCTAssertEqual(read.apps, wanted.apps)
        XCTAssertEqual(Parts.waiting(in: read, parts: []).map(\.kind), [.android])
    }

    /// A meta.json from before wishes listed their apps reads as a wish of the one app it is.
    func testAWishFromBeforeHasTheAppItIs() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let read = try XCTUnwrap(Store.readWish(at: wish.dir))
        XCTAssertEqual(read.apps, [])
        XCTAssertEqual(Parts.wanted(in: read, parts: []), [WishApp(kind: .mac)])
        XCTAssertEqual(Parts.waiting(in: read, parts: []), [])
    }

    /// An app that's made (its part found in the wish's folder) no longer waits, whatever the list said of it; and a wanted
    /// iPhone app is made once Apple's folder holds an app for both, since Apple's devices are one part between them.
    func testAnAppThatIsMadeNoLongerWaits() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .tv, in: root)
        var wanted = wish
        wanted.apps = [WishApp(kind: .tv), WishApp(kind: .iphone, needs: "this Mac can't build the iPhone app yet.")]
        let apple = LampProject(id: "tally.apple", name: "Tally", exe: "Tally", dir: wish.dir.appendingPathComponent("Apple"),
                                platform: .universal, partOf: wish.id)
        XCTAssertEqual(Parts.waiting(in: wanted, parts: [apple]), [])
        XCTAssertEqual(Parts.waiting(in: wanted, parts: []).map(\.kind), [.iphone])
    }

    /// A part made for a wish whose list is empty (a wish from before the list, or one opened from a shared file) is
    /// listed with the app in the wish's own folder, so the list names every app the wish has.
    func testAPartMadeForAWishListsTheRootAppToo() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .tv, in: root)
        XCTAssertEqual(Parts.listing(.mac, madeFor: wish, parts: []), [WishApp(kind: .tv), WishApp(kind: .mac)])
        var waiting = wish
        waiting.apps = [WishApp(kind: .tv), WishApp(kind: .iphone, needs: "this Mac can't build the iPhone app yet.")]
        XCTAssertEqual(Parts.listing(.iphone, madeFor: waiting, parts: []), [WishApp(kind: .tv), WishApp(kind: .iphone)])
    }

    /// A wish waiting for two apps (an iPhone app and an Android app, both toolchains missing) follows each setup on
    /// its own: the setups under way are kept per app and kind, where the one in the wish's own folder is kept per app.
    func testEachWaitingAppsSetupIsFollowedOnItsOwn() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .tv, in: root)
        XCTAssertNotEqual(IPhoneSetupLine.key(wish, wanted: .iphone, part: true), IPhoneSetupLine.key(wish, wanted: .android, part: true))
        XCTAssertEqual(IPhoneSetupLine.key(wish, wanted: .iphone, part: false), wish.id)
    }

    /// An Android app in Android/ is one of the wish's parts, found from its files as the others are.
    func testAnAndroidPartIsFoundInItsFolder() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let android = wish.dir.appendingPathComponent("Android")
        try FileManager.default.createDirectory(at: android.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try "rootProject.name = \"Tally\"\n".write(to: android.appendingPathComponent("settings.gradle.kts"), atomically: true, encoding: .utf8)
        let read = try XCTUnwrap(Store.readWish(at: wish.dir))
        XCTAssertEqual(read.partFolders, ["Android"])
        XCTAssertEqual(Parts.load(read).map(\.platform), [.android])
        XCTAssertEqual(Parts.load(read).map(\.id), ["\(wish.id).android"])
    }
}
