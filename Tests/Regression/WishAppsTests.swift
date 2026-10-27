import XCTest
@testable import Lamp

/// A game and a screen are apps of a wish like any other: listed with other apps, each is an app of its own, and the
/// devices it can be on stay its places unless "app" follows one.
final class WishGameAppsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wish-game-apps-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// With a game and a Mac app, "mac" for `look_at_app` and `use_app` is the Mac app, though the game runs on the
    /// Mac too and comes first; "game" is the game.
    func testAPartIsNamedByItsOwnWordFirst() throws {
        let wish = LampProject(id: "party", name: "Party", exe: "Party", dir: root.appendingPathComponent("party"), platform: .game)
        let mac = LampProject(id: "party.mac", name: "Party", exe: "Party", dir: wish.dir.appendingPathComponent("Mac"), platform: .mac, partOf: wish.id)
        XCTAssertEqual(Parts.pick("mac", among: [wish, mac])?.id, mac.id)
        XCTAssertEqual(Parts.pick("game", among: [wish, mac])?.id, wish.id)
    }

    /// A Mac wish with a game in Game/, as `make_app_for` leaves it. `gameMeta` is the game's meta.json, or nil for none
    /// (a restore brings back a part's files, never its `.lamp/`).
    private func partyWithGame(gameMeta: String?) throws -> LampProject {
        let wish = try Template.scaffold(name: "Party", platform: .mac, in: root)
        let dir = wish.dir.appendingPathComponent(Parts.folder(for: .game))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let gameMeta {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
            try gameMeta.write(to: dir.appendingPathComponent(".lamp/meta.json"), atomically: true, encoding: .utf8)
        }
        try "A game made with Lamp.\n".write(to: dir.appendingPathComponent(GameKit.marker), atomically: true, encoding: .utf8)
        return try XCTUnwrap(Store.readWish(at: wish.dir))
    }

    /// A game made beside other apps is found in its folder, with the places its own meta.json keeps, and is installed
    /// apart from the wish's Mac app, which has the wish's name: in the apps folder's Games/. Where stays where it was
    /// once the Mac app is taken away.
    func testAGameInAFolderOfItsOwnIsOneOfTheWishsApps() throws {
        let wish = try partyWithGame(gameMeta: #"{"name":"Party","exe":"Party","platform":"game","places":["mac","ios"]}"#)
        XCTAssertEqual(wish.partFolders, ["Game"])
        let parts = Parts.load(wish)
        XCTAssertEqual(parts.map(\.platform), [.game])
        XCTAssertEqual(parts.first?.openPlaces, [.mac, .ios])
        XCTAssertEqual(wish.installedURL.lastPathComponent, "Party.app")
        XCTAssertNotEqual(parts.first?.installedURL, wish.installedURL)
        for name in ["Sources", "Package.swift", "build.sh", "APP.md"] { try? FileManager.default.removeItem(at: wish.dir.appendingPathComponent(name)) }
        let alone = try XCTUnwrap(Store.readWish(at: wish.dir))
        XCTAssertFalse(alone.holdsApp)
        XCTAssertEqual(Parts.load(alone).first?.installedURL, parts.first?.installedURL)
    }

    /// Duplicate copies each app's meta.json as it is: the copy's game was installed where the original's is, so building
    /// either replaced the other.
    func testADuplicatedWishsGameIsInstalledApartFromTheOriginals() throws {
        // Whatever the game's meta.json says of where it's installed is copied with it, and isn't where it goes.
        let wish = try partyWithGame(gameMeta: #"{"name":"Party","exe":"Party","platform":"game","installName":"Party Game"}"#)
        let copyDir = root.appendingPathComponent("partycopy")
        try FileManager.default.copyItem(at: wish.dir, to: copyDir)
        try Template.saveMeta(LampProject(id: "partycopy", name: "Party copy", exe: "PartyCopy", dir: copyDir, platform: .mac))
        let copy = try XCTUnwrap(Store.readWish(at: copyDir))
        let original = try XCTUnwrap(Parts.load(wish).first), copied = try XCTUnwrap(Parts.load(copy).first)
        XCTAssertNotEqual(copied.installedURL, original.installedURL)
        XCTAssertNotEqual(copied.installedURL, copy.installedURL)
    }

    /// A restore brings a part's files back without its meta.json: the game read nothing of where it was installed, and
    /// went where the wish's Mac app is.
    func testARestoredGameIsInstalledApartFromTheMacApp() throws {
        let wish = try partyWithGame(gameMeta: nil)
        let game = try XCTUnwrap(Parts.load(wish).first)
        XCTAssertEqual(game.platform, .game)
        XCTAssertNotEqual(game.installedURL, wish.installedURL)
    }
}

/// A wish's apps are all treated alike, the one in the wish's own folder as much as any other.
final class WishAppsRootTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wish-apps-root-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

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

    /// "Make it playable on my iPad and on our Roku too": a Roku app is one of the wish's apps, but it can't join the
    /// wish's room yet, so the iPhone app beside it gets no link to it, and the Roku app gets `LampWish` saying it's away.
    func testARokuAppIsAnAppOfTheWishOutsideItsRoom() throws {
        var wish = try Template.scaffold(name: "Tally", platform: .iphone, in: root)
        wish.apps = [WishApp(kind: .iphone), WishApp(kind: .device, integration: "roku")]
        try Template.saveMeta(wish)
        XCTAssertTrue(Template.hasOtherApps(wish))
        XCTAssertFalse(Template.talksToOtherApps(wish), "nothing to reach")
        let roku = LampProject(id: wish.id + ".roku", name: "Tally", exe: "Tally", dir: wish.dir.appendingPathComponent("Roku"),
                               platform: .device, integration: "roku", partOf: wish.id)
        XCTAssertFalse(Template.talksToOtherApps(roku))
        XCTAssertTrue(Template.hasOtherApps(roku))
    }

    /// A device's app is found by its own mark, whatever its folder is called (its integration may have been renamed
    /// since), and a version keeps which device it was for.
    func testADevicesAppIsFoundByItsMarkAndVersionsKeepItsDevice() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .iphone, in: root)
        for folder in ["Roku", "OldName"] {
            let dir = wish.dir.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "roku\n".write(to: dir.appendingPathComponent(DeviceApps.marker), atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(Set(Parts.folders(in: wish.dir)), ["Roku", "OldName"], "both, while one replaces the other")
        let apps = [WishApp(kind: .iphone), WishApp(kind: .device, integration: "roku")]
        XCTAssertEqual(Versions.apps(from: apps.map(Versions.trailerWord).joined(separator: " ")), apps)
    }

    /// A Roku app made and an Xbox app still waiting, then both made: each is its own entry on the wish's list, so the made
    /// Roku app never makes the Xbox's look made and taking one off the list leaves the other; each has its own folder,
    /// its own rules and its own word in look_at_app and use_app, and "device" is asked about rather than read as the first.
    func testARokuAppAndAnXboxAppAreEachTheirOwn() throws {
        var wish = try Template.scaffold(name: "Tally", platform: .iphone, in: root)
        wish.apps = [WishApp(kind: .iphone), WishApp(kind: .device, integration: "roku"),
                     WishApp(kind: .device, needs: "No Xbox yet", devices: ["xbox-one"], integration: "xbox-one")]
        try Template.saveMeta(wish)
        func mark(_ folder: String, _ integration: String) throws {
            let dir = wish.dir.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "\(integration)\n".write(to: dir.appendingPathComponent(DeviceApps.marker), atomically: true, encoding: .utf8)
        }
        try mark("Roku", "roku")
        let one = try XCTUnwrap(Store.readWish(at: wish.dir))
        let roku = try XCTUnwrap(Parts.load(one).first)
        XCTAssertEqual(Parts.waiting(in: one, parts: [roku]).map(\.integration), ["xbox-one"], "the made Roku app isn't the Xbox app")
        XCTAssertEqual(Parts.waiting(in: one, parts: [roku]).first?.needs, "No Xbox yet")
        XCTAssertEqual(Parts.wanted(in: one, parts: [roku]).count, 3)
        XCTAssertEqual(Parts.listing(.device, integration: "xbox-one", madeFor: one, parts: [roku]).map(\.integration), [nil, "roku", "xbox-one"])
        XCTAssertEqual(one.apps.filter { !Parts.lists($0, roku) }.map(\.integration), [nil, "xbox-one"], "taking the Roku app away leaves the Xbox's")
        // A list from before kept no integration: its device entry is the Roku app it was for.
        var old = one
        old.apps = [WishApp(kind: .iphone), WishApp(kind: .device)]
        XCTAssertEqual(Parts.waiting(in: old, parts: [roku]), [])

        // A new device's app never goes into another's folder, whatever the case of its name.
        XCTAssertEqual(DeviceApps.freeFolder("Xbox", for: "xbox-one", in: wish.dir), "Xbox")
        XCTAssertEqual(DeviceApps.freeFolder("Roku", for: "roku", in: wish.dir), "Roku")
        XCTAssertEqual(DeviceApps.freeFolder("Roku", for: "xbox-one", in: wish.dir), "Roku2")
        XCTAssertEqual(DeviceApps.freeFolder("ROKU", for: "roku", in: wish.dir), "ROKU2")

        try mark("Xbox", "xbox-one")
        let both = try XCTUnwrap(Store.readWish(at: wish.dir))
        let parts = Parts.load(both)
        XCTAssertEqual(Set(parts.map(\.id)), [Parts.id(wish: both.id, folder: "Roku"), Parts.id(wish: both.id, folder: "Xbox")])
        XCTAssertEqual(Set(parts.compactMap(\.integration)), ["roku", "xbox-one"])
        XCTAssertEqual(Parts.waiting(in: both, parts: parts), [])
        XCTAssertEqual(Set(parts.map(Parts.skill(of:))), ["target-device-roku", "target-device-xbox"])
        let skills = Parts.packs(for: parts)
        XCTAssertTrue(try XCTUnwrap(skills["target-device-xbox"]).body.contains("Xbox/"))
        XCTAssertFalse(try XCTUnwrap(skills["target-device-xbox"]).body.contains("Roku/"))
        XCTAssertTrue(try XCTUnwrap(skills["target-device-roku"]).body.contains("Roku/"))
        XCTAssertTrue(try XCTUnwrap(skills["target-device"]).body.contains("target-device-xbox"), "the kind's skill says which is whose")
        XCTAssertEqual(Set(Skills.applying(to: both, parts: parts).map(\.name)).intersection(skills.keys), ["target-device-roku", "target-device-xbox"])
        XCTAssertEqual(Parts.picks("device", among: [both] + parts).count, 2)
        XCTAssertEqual(Parts.pick("xbox", among: [both] + parts)?.integration, "xbox-one")
        XCTAssertEqual(Parts.pick("roku", among: [both] + parts)?.integration, "roku")
    }

    /// A Roku app taken away keeps its folder: another device's app whose name comes to the same folder is made in one of
    /// its own, so it never takes the Roku app's id or what it saved, and Undo, which puts the wish's files back as they
    /// were, brings the Roku app back into its own folder, beside the other, each with its own id. The Roku's own app,
    /// asked for again, is made where it was.
    func testADeviceAppTakenAwayKeepsItsFolderForUndo() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .iphone, in: root)
        func mark(_ folder: String, _ integration: String) throws {
            let dir = wish.dir.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "\(integration)\n".write(to: dir.appendingPathComponent(DeviceApps.marker), atomically: true, encoding: .utf8)
        }
        try mark("Roku", "roku")
        let roku = try XCTUnwrap(Parts.load(try XCTUnwrap(Store.readWish(at: wish.dir))).first)
        RemovedApp.record(roku, in: wish.dir)
        try FileManager.default.removeItem(at: roku.dir)

        // Another integration whose name gives "Roku", in any case.
        XCTAssertEqual(DeviceApps.freeFolder("Roku", for: "xbox-one", in: wish.dir), "Roku2")
        XCTAssertEqual(DeviceApps.freeFolder("roku", for: "xbox-one", in: wish.dir), "roku2")
        XCTAssertEqual(DeviceApps.freeFolder("Roku", for: "roku", in: wish.dir), "Roku", "the Roku's own app is made where it was")

        try mark("Roku2", "xbox-one")
        try mark("Roku", "roku")   // Undo
        let parts = Parts.load(try XCTUnwrap(Store.readWish(at: wish.dir)))
        XCTAssertEqual(parts.first { $0.integration == "roku" }?.id, roku.id)
        XCTAssertEqual(parts.first { $0.integration == "roku" }?.instance, roku.instance)
        XCTAssertEqual(Set(parts.map(\.id)).count, 2)
    }

    /// A wish of a Roku app and an Xbox app alone has other apps: each is told it's one of several.
    func testARokuAppBesideAnXboxAppHasAnother() throws {
        var wish = try Template.scaffold(name: "Tally", platform: .iphone, in: root)
        wish.apps = [WishApp(kind: .device, integration: "roku"), WishApp(kind: .device, integration: "xbox-one")]
        for name in ["Sources", "Package.swift", "build.sh", "APP.md"] { try? FileManager.default.removeItem(at: wish.dir.appendingPathComponent(name)) }
        try Template.saveMeta(wish)
        let roku = LampProject(id: wish.id + ".roku", name: "Tally", exe: "Tally", dir: wish.dir.appendingPathComponent("Roku"),
                               platform: .device, integration: "roku", partOf: wish.id)
        XCTAssertTrue(Template.hasOtherApps(roku))
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
