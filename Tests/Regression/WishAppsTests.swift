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

/// A game and a screen are apps of a wish like any other: listed with other apps, each is an app of its own, and the
/// devices it can be on stay its places unless "app" follows one.
final class WishGameAppsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wish-game-apps-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// "Make a fun TV party game" for a Mac wish: Lamp said it couldn't make a game as a part of another wish. Asked
    /// for the game alone, the game replaces the Mac app, in a folder of its own; asked for both, the Mac app stays.
    func testAGameReplacesTheMacAppOrGoesBesideIt() throws {
        let wish = try Template.scaffold(name: "Party", platform: .mac, in: root)
        let alone = try XCTUnwrap(Parts.asked(["game"]))
        XCTAssertEqual(alone, Parts.Asked(kinds: [.game], places: [.game: []]))
        XCTAssertEqual(Parts.plan(alone.kinds, for: [wish]), Parts.Plan(keep: [:], add: [.game], remove: [wish.id]))
        let both = try XCTUnwrap(Parts.asked(["game", "mac"]))
        XCTAssertEqual(both.kinds, [.mac, .game])
        XCTAssertEqual(Parts.plan(both.kinds, for: [wish]), Parts.Plan(keep: [wish.id: .mac], add: [.game], remove: []))
        XCTAssertTrue(Parts.partKinds.contains(.game))
        XCTAssertTrue(Parts.partKinds.contains(.screen))
    }

    /// Every word of `devices` is an app; where the game is played or the screen shown is `places`, apart. So the
    /// phones' own apps beside a game are "iphone" and "android" in `devices`, and the game played on an Xbox too is
    /// "xbox-one" in `places`.
    func testDevicesAreAppsAndPlacesAreGivenApart() throws {
        XCTAssertEqual(Parts.asked(["game", "iphone", "android"], places: ["xbox-one"]),
                       Parts.Asked(kinds: [.iphone, .android, .game], places: [.game: ["xbox-one"]]))
        XCTAssertEqual(Parts.asked(["game"], places: ["iphone", "android"]), Parts.Asked(kinds: [.game], places: [.game: ["iphone", "android"]]))
        XCTAssertEqual(Parts.asked(["screen"], places: ["tv"]), Parts.Asked(kinds: [.screen], places: [.screen: ["tv"]]))
        XCTAssertEqual(Parts.kinds(for: ["game", "tv"]), [.tv, .game])
        XCTAssertEqual(Parts.kinds(for: ["screen", "tv"]), [.tv, .screen])
        // Places are only a game's or a screen's, and only where it can be.
        XCTAssertNil(Parts.asked(["mac"], places: ["iphone"]))
        XCTAssertNil(Parts.asked(["game"], places: ["tv"]))
    }

    /// With a game and a Mac app, "mac" for `look_at_app` and `use_app` is the Mac app, though the game runs on the
    /// Mac too and comes first; "game" is the game.
    func testAPartIsNamedByItsOwnWordFirst() throws {
        let wish = LampProject(id: "party", name: "Party", exe: "Party", dir: root.appendingPathComponent("party"), platform: .game)
        let mac = LampProject(id: "party.mac", name: "Party", exe: "Party", dir: wish.dir.appendingPathComponent("Mac"), platform: .mac, partOf: wish.id)
        XCTAssertEqual(Parts.pick("mac", among: [wish, mac])?.id, mac.id)
        XCTAssertEqual(Parts.pick("game", among: [wish, mac])?.id, wish.id)
    }

    /// A game made beside other apps is found in its folder, with the places its own meta.json keeps.
    func testAGameInAFolderOfItsOwnIsOneOfTheWishsApps() throws {
        let wish = try Template.scaffold(name: "Party", platform: .mac, in: root)
        let dir = wish.dir.appendingPathComponent(Parts.folder(for: .game))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        var game = LampProject(id: Parts.id(wish: wish.id, folder: "Game"), name: "Party", exe: "Party", dir: dir, platform: .game, partOf: wish.id)
        game.places = [.mac, .ios]
        // Made beside the Mac app, it was given a name of its own to be installed under.
        game.installName = "Party Game"
        try Template.saveMeta(game)
        try "A game made with Lamp.\n".write(to: dir.appendingPathComponent(GameKit.marker), atomically: true, encoding: .utf8)
        let read = try XCTUnwrap(Store.readWish(at: wish.dir))
        XCTAssertEqual(read.partFolders, ["Game"])
        let parts = Parts.load(read)
        XCTAssertEqual(parts.map(\.platform), [.game])
        XCTAssertEqual(parts.first?.openPlaces, [.mac, .ios])
        // Both have a Mac copy, so they can't both be installed under the wish's name: each would replace the other.
        XCTAssertEqual(read.installedURL.lastPathComponent, "Party.app")
        XCTAssertEqual(parts.first?.installedURL.lastPathComponent, "Party Game.app")
        // The Mac app taken away, the game is where it was installed: its install name is its own, not the wish's
        // apps' order of the moment, so nothing installed is left behind under an old name.
        for name in ["Sources", "Package.swift", "build.sh", "APP.md"] { try? FileManager.default.removeItem(at: wish.dir.appendingPathComponent(name)) }
        let alone = try XCTUnwrap(Store.readWish(at: wish.dir))
        XCTAssertFalse(alone.holdsApp)
        XCTAssertEqual(Parts.load(alone).first?.installedURL.lastPathComponent, "Party Game.app")
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

    /// "Just the TV" for a wish of a Mac app, a TV app and an Android app: the Mac app and the Android app both go, since
    /// the TV app stays. Only when nothing stays or is added does one app the request leaves out stay, so the wish keeps one.
    func testEveryAppLeftOutGoesWhileAnotherStays() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let tv = LampProject(id: "tally.tv", name: "Tally", exe: "Tally", dir: wish.dir.appendingPathComponent("TV"), platform: .tv, partOf: wish.id)
        let android = LampProject(id: "tally.android", name: "Tally", exe: "Tally", dir: wish.dir.appendingPathComponent("Android"), platform: .android, partOf: wish.id)
        let apps = [wish, tv, android]
        let plan = Parts.plan(try XCTUnwrap(Parts.kinds(for: ["tv"])), for: apps)
        XCTAssertEqual(plan.remove, [wish.id, android.id])
        XCTAssertEqual(Parts.staying(of: plan.remove, survivors: apps.count - plan.remove.count), [])
        // "Android only" on a Mac wish this Mac can't build Android apps for yet: the Mac app stays until it can.
        XCTAssertEqual(Parts.staying(of: [wish.id], survivors: 0), [wish.id])
        XCTAssertEqual(Parts.staying(of: [wish.id, tv.id], survivors: 0), [wish.id])
    }

    /// An iPhone app asked for "iphone" and "watch": its kind is already right, but the answer says to add the watch
    /// app, so it isn't dropped as saying nothing new. Nor is one saying to take the watch app away.
    func testAWatchToAddOrTakeAwayIsNeverDropped() {
        XCTAssertTrue(Parts.saysNothingNew("It's already made for iPhone and iPad."))
        XCTAssertFalse(Parts.saysNothingNew("It's already made for iPhone and iPad.\n\nThen add its Apple Watch app in Watch/: open the apple-watch skill with `read_skill` first, and follow it."))
        XCTAssertFalse(Parts.saysNothingNew("It's already made for iPhone and iPad.\n\nThen take its Apple Watch app away: delete the files in Watch/ with delete_file."))
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

    /// A wish whose one app is in a folder of its own gets no code for reaching other apps, so its prompt says nothing
    /// of them either: it had the TV app's rules for talking to the wish's phones and Macs.
    func testTheOnlyAppIsToldNothingOfOtherApps() throws {
        let wish = try replacedWish()
        let prompt = Agent.wishPrompt(for: wish, parts: Parts.load(wish))
        XCTAssertTrue(prompt.contains("the part of the wish in TV/"))
        XCTAssertFalse(prompt.contains("wish-links"), "the rules for reaching the wish's other apps")
        XCTAssertFalse(prompt.contains("LampController"))
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
