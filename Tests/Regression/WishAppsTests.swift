import XCTest
@testable import Lamp

/// A wish is its own thing, apart from the apps it's made of: any of Lamp's kinds that can be a part can go together,
/// and the wish remembers which apps it should have and what each one still waits for.
final class WishAppsTests: XCTestCase {
    /// A Mac app with an Android app, an iPhone app with an Android app, a TV app with an Android app: each is one wish of
    /// two apps, in Lamp's order. No app leads: which is at the wish's root is the wish's own affair, not the list's.
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

/// `make_app_for` makes a wish the apps listed by adding and taking away folders: no app is ever written over again as
/// another kind.
final class WishAppsRootTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wish-apps-root-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// "Put it on the TV too" for a Mac wish: the Mac app stays at the root, its code kept, and the TV app goes beside it
    /// in TV/. The TV app used to take the root (it led), which wrote the Mac app over again as a TV app in web code and
    /// scaffolded a fresh Mac app in Mac/.
    func testTVAddedToAMacWishKeepsTheMacApp() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let kinds = try XCTUnwrap(Parts.kinds(for: ["mac", "tv"]))
        XCTAssertEqual(Parts.root(among: kinds, for: wish), .mac)
        XCTAssertEqual(Parts.others(among: kinds, root: .mac), [.tv])
        XCTAssertEqual(Parts.folder(for: .tv), "TV")
    }

    /// The app at the root is changed in place only inside its family: a Mac app that's to be for the iPhone too
    /// becomes the app for both, in the same folder, with its code.
    func testTheRootAppChangesInPlaceInsideItsFamily() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let kinds = try XCTUnwrap(Parts.kinds(for: ["mac", "iphone", "tv"]))
        XCTAssertEqual(Parts.root(among: kinds, for: wish), .universal)
        XCTAssertEqual(Parts.others(among: kinds, root: .universal), [.tv])
    }

    /// A list that leaves the root app's family out is refused once its code is written: a wish keeps the app it began
    /// with, and nothing is written over again as another kind. Its own family is still its to change in place: a Mac
    /// app asked for "tv" and "iphone" becomes the iPhone app, in the same Swift, with the TV app beside it.
    func testAWrittenRootAppIsNeverMadeAnotherKind() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        XCTAssertNil(Parts.root(among: try XCTUnwrap(Parts.kinds(for: ["tv"])), for: wish))
        XCTAssertNil(Parts.root(among: try XCTUnwrap(Parts.kinds(for: ["tv", "android"])), for: wish))
        XCTAssertEqual(Parts.root(among: try XCTUnwrap(Parts.kinds(for: ["tv", "iphone"])), for: wish), .iphone)
    }

    /// A wish still to be told what it's for has nothing written, so its root takes the first kind listed, in Lamp's
    /// order, and the rest go beside it.
    func testAWishWithNothingWrittenTakesTheFirstKindAtItsRoot() throws {
        let draft = LampProject(id: "slides", name: "Slides", exe: "Slides", dir: root.appendingPathComponent("slides"),
                                platform: .mac, undecided: ["tv", "mac"])
        XCTAssertFalse(draft.scaffolded)
        XCTAssertEqual(Parts.root(among: try XCTUnwrap(Parts.kinds(for: ["tv"])), for: draft), .tv)
        XCTAssertEqual(Parts.root(among: try XCTUnwrap(Parts.kinds(for: ["tv", "iphone"])), for: draft), .iphone)
    }

    /// A TV app in TV/, beside the Mac app at the wish's root, takes that app as a player as a TV app at the root takes
    /// its parts: the wish's other apps reach its TV app wherever it is.
    func testATVAppInItsFolderTakesTheWishsOtherAppsAsPlayers() {
        let tv = LampProject(id: "tally.tv", name: "Tally", exe: "Tally", dir: root.appendingPathComponent("tally/TV"),
                             platform: .tv, partOf: "tally")
        XCTAssertTrue(Store.takesPlayers(tv))
        XCTAssertFalse(Store.takesPlayers(LampProject(id: "tally", name: "Tally", exe: "Tally", dir: root.appendingPathComponent("tally"), platform: .tv)))
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
    /// listed with the app at the wish's root, so the list names every app the wish has.
    func testAPartMadeForAWishListsTheRootAppToo() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .tv, in: root)
        XCTAssertEqual(Parts.listing(.mac, madeFor: wish, parts: []), [WishApp(kind: .tv), WishApp(kind: .mac)])
        var waiting = wish
        waiting.apps = [WishApp(kind: .tv), WishApp(kind: .iphone, needs: "this Mac can't build the iPhone app yet.")]
        XCTAssertEqual(Parts.listing(.iphone, madeFor: waiting, parts: []), [WishApp(kind: .tv), WishApp(kind: .iphone)])
    }

    /// A wish waiting for two apps (an iPhone app and an Android app, both toolchains missing) follows each setup on
    /// its own: the setups under way are kept per app and kind, where the app at the root's is kept per app.
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
