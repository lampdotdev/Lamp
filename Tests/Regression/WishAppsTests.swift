import XCTest
@testable import Lamp

/// A wish is its own thing, apart from the apps it's made of: any of Lamp's kinds that can be a part can go together,
/// and the wish remembers which apps it should have and what each one still waits for.
final class WishAppsTests: XCTestCase {
    /// A Mac app with an Android app, an iPhone app with an Android app, a TV app with an Android app: each is one wish of
    /// two apps. No kind has to lead: the first in Lamp's order is the app at the wish's root, a TV app before the rest.
    func testAnAndroidAppCanGoWithAnyOtherKind() throws {
        let macAndAndroid = try XCTUnwrap(Parts.kinds(for: ["mac", "android"]))
        XCTAssertEqual(macAndAndroid.main, .mac)
        XCTAssertEqual(macAndAndroid.parts, [.android])
        let bothPhones = try XCTUnwrap(Parts.kinds(for: ["iphone", "android"]))
        XCTAssertEqual(bothPhones.main, .iphone)
        XCTAssertEqual(bothPhones.parts, [.android])
        let tvAndAndroid = try XCTUnwrap(Parts.kinds(for: ["tv", "android"]))
        XCTAssertEqual(tvAndAndroid.main, .tv)
        XCTAssertEqual(tvAndAndroid.parts, [.android])
    }

    /// Three devices of three families are three apps: the TV app at the root, Apple's devices as one app for both.
    func testAWishCanBeThreeApps() throws {
        let three = try XCTUnwrap(Parts.kinds(for: ["tv", "mac", "iphone", "android"]))
        XCTAssertEqual(three.main, .tv)
        XCTAssertEqual(three.parts, [.universal, .android])
    }

    /// An Android app alone is still one app, and a device whose integration declares its apps still stands alone.
    func testOneKindAloneIsOneApp() throws {
        let alone = try XCTUnwrap(Parts.kinds(for: ["android"]))
        XCTAssertEqual(alone.main, .android)
        XCTAssertEqual(alone.parts, [])
        XCTAssertNil(Parts.kinds(for: ["android", "nothing-lamp-makes"]))
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
