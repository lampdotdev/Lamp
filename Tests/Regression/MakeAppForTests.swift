import XCTest
@testable import Lamp

/// `make_app_for` and `remove_app` are plans over the wish's apps (`AppPlanner`), checked here as they'd be carried out:
/// which app is changed, added, taken away or taken off the list, and into what, with the devices, the family Try On
/// opens it on and the places as they were asked. Taking an app away is `remove_app`'s alone.
final class MakeAppForTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/tmp/make-app-for")
    private var table: [Place] = Places.builtIn

    override func setUpWithError() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for id in ["xbox-one", "roku"] {
            let integration = try JSONDecoder().decode(Integration.self, from: Data(contentsOf: source.appendingPathComponent("Resources/Devices/\(id).json")))
            table.append(try XCTUnwrap(Places.row(for: integration)))
        }
    }

    private func app(_ id: String, _ kind: Platform, folder: String? = nil, places: [Destination]? = nil, integration: String? = nil,
                     family: DeviceFamily = .iphone) -> WishMember {
        var app = LampProject(id: id, name: "Party", exe: "Party", dir: folder.map { dir.appendingPathComponent($0) } ?? dir, platform: kind,
                              family: family, places: places, partOf: folder == nil ? nil : "party")
        app.integration = integration
        return AppKinds.member(of: app, in: table)
    }

    private func make(_ made: Place.Make, _ devices: [String], in members: [WishMember]) throws -> AppPlan {
        try AppPlanner.make(made, devices: devices, in: members, table: table).get()
    }

    private func refused(_ made: Place.Make, _ devices: [String], in members: [WishMember] = []) -> String? {
        guard case .failure(let refusal) = AppPlanner.make(made, devices: devices, in: members, table: table) else { return nil }
        return refusal.reason
    }

    /// A Mac wish with a game beside it: putting the game on the iPhone too changes the game, and only the game.
    func testAnAppLeftOutOfARequestStays() throws {
        let mac = app("party", .mac), game = app("party.game", .game, folder: "Game", places: [.mac])
        guard case .update(let changed, let target) = try make(.web, ["mac", "iphone"], in: [mac, game]) else { return XCTFail() }
        XCTAssertEqual(changed, game)
        XCTAssertEqual(target.kind, .game)
        XCTAssertEqual(target.places, [.mac, .ios])
    }

    /// The Mac app made for the iPhone and its watch too is one app, changed in place.
    func testAnAppOfTheSameCodeChangesInPlace() throws {
        let mac = app("notes", .mac)
        guard case .update(let changed, let target) = try make(.native, ["mac", "iphone", "watch"], in: [mac]) else { return XCTFail() }
        XCTAssertEqual(changed, mac)
        XCTAssertEqual(target.kind, .universal)
        XCTAssertTrue(target.rows.contains("watch"))
    }

    /// The Mac and an Apple TV are one Swift app for both, built for tvOS where Try On opens it: never Mac-only.
    func testTheMacWithAnAppleTVOrVisionProStaysAnAppForBoth() throws {
        let mac = app("notes", .mac)
        for (word, family) in [("apple-tv", DeviceFamily.appletv), ("vision-pro", .vision)] {
            guard case .update(_, let target) = try make(.native, ["mac", word], in: [mac]) else { return XCTFail() }
            XCTAssertEqual(target.kind, .universal)
            XCTAssertEqual(target.family, family)
            XCTAssertTrue(target.kind.target.otherSystems)
        }
    }

    /// An iPad asked for is an iPad: the family Try On opens a game or a screen on, kept apart from the iPhone row it runs as.
    func testTheIPadIsKeptAsAsked() throws {
        let screen = app("board", .screen, places: [.mac])
        guard case .update(_, let target) = try make(.web, ["mac", "ipad"], in: [screen]) else { return XCTFail() }
        XCTAssertEqual(target.kind, .screen)
        XCTAssertEqual(target.places, [.mac, .ios])
        XCTAssertEqual(target.family, .ipad)
        XCTAssertEqual(target.devices.map(\.word), ["mac", "ipad"])
        guard case .add(let added) = try make(.native, ["ipad"], in: []) else { return XCTFail() }
        XCTAssertEqual(added.kind, .iphone)
        XCTAssertEqual(added.family, .ipad)
        // A made app reads back with its family.
        XCTAssertEqual(app("pad", .iphone, family: .ipad).target.devices.map(\.word), ["ipad"])
    }

    /// A device named with a family says which: the iPhone asked for is the iPhone, for an app Try On opened on an iPad
    /// too, and the first so named wins where several are. Only a request naming none keeps the app's family.
    func testTheFamilyIsTheFirstNamedAndKeptOnlyWhenNoneIs() throws {
        let pad = app("pad", .iphone, family: .ipad)
        for (devices, family) in [(["iphone"], DeviceFamily.iphone), (["ipad", "iphone"], .ipad), (["iphone", "ipad"], .iphone),
                                  (["mac", "apple-tv", "iphone"], .appletv)] {
            guard case .update(_, let target) = try make(.native, devices, in: [pad]) else { return XCTFail() }
            XCTAssertEqual(target.family, family, "\(devices)")
        }
        for devices in [["mac"], ["watch"]] {
            guard case .update(_, let target) = try make(.native, devices, in: [pad]) else { return XCTFail() }
            XCTAssertNil(target.family, "\(devices) names no family, so the app keeps its own")
        }
    }

    /// An app waiting to be made keeps what was asked through a failure and a retry: the devices as named, its family,
    /// places and integration, so what's made later is what was asked, not what its kind alone would be.
    func testAWaitingAppKeepsItsWholeTarget() throws {
        for (made, devices) in [(Place.Make.web, ["mac", "ipad"]), (.native, ["ipad", "watch"]), (.web, ["xbox-one"]), (.native, ["vision-pro", "mac"])] {
            guard case .add(let target) = try make(made, devices, in: []) else { return XCTFail() }
            let failed = target.waiting.needing("Xcode")
            let kept = try JSONDecoder().decode([WishApp].self, from: JSONEncoder().encode([failed]))[0]
            XCTAssertEqual(kept.needs, "Xcode")
            let retried = AppKinds.member(waiting: kept.needing(nil), in: table)
            XCTAssertFalse(retried.isMade)
            XCTAssertEqual(retried.target, target, "\(devices)")
        }
    }

    /// The table alone says which kind and family a row is: a row added to it is made and read back by what it says,
    /// with nothing else told about it.
    func testARowAddedToTheTableIsMadeByItsRow() throws {
        table.append(Place(id: "vision-air", name: "Vision Air", words: ["vision-air"], destination: .ios, web: nil,
                           native: .init(code: .apple, reach: "in its simulator"), noWeb: "no web view",
                           wordFamilies: ["vision-air": .vision], input: nil))
        guard case .add(let target) = try make(.native, ["mac", "vision-air"], in: []) else { return XCTFail() }
        XCTAssertEqual(target.kind, .universal)
        XCTAssertEqual(target.family, .vision)
        XCTAssertEqual(AppKinds.member(waiting: target.waiting, in: table).target, target)
    }

    /// A change of make adds the new app beside the old one; whether it takes the old one's place is the person's.
    func testAChangeOfMakeGoesBesideTheOldApp() throws {
        guard case .add(let target) = try make(.web, ["mac"], in: [app("racer", .mac)]) else { return XCTFail() }
        XCTAssertEqual(target.kind, .game)
    }

    /// Web apps are today's kinds by their devices, the wish's own web app keeping its kind; what no kind reaches, and
    /// native apps of two codes, are refused with why.
    func testEachRequestIsOneOfTodaysKindsOrRefusedWithItsReason() throws {
        func kind(_ plan: AppPlan) -> Platform? {
            switch plan {
            case .add(let target), .update(_, let target): target.kind
            default: nil
            }
        }
        XCTAssertEqual(kind(try make(.web, ["mac", "tv"], in: [])), .screen)
        XCTAssertEqual(kind(try make(.web, ["tv"], in: [])), .tv)
        XCTAssertEqual(kind(try make(.web, ["iphone", "android"], in: [])), .game)
        XCTAssertEqual(kind(try make(.native, ["android-tv"], in: [])), .androidTV)
        XCTAssertEqual(kind(try make(.web, ["xbox-one"], in: [])), .device)
        XCTAssertTrue(refused(.web, ["apple-tv"])?.contains("tvOS has no web view") == true)
        XCTAssertNotNil(refused(.web, ["tv", "android"]))
        XCTAssertNotNil(refused(.native, ["mac", "android"]))
        XCTAssertNotNil(refused(.native, ["tv"]))
        XCTAssertNotNil(refused(.web, ["toaster"]))
    }

    /// A device's own app is one of the wish's apps beside the others: a Mac app asked for in a Roku app's wish, or a
    /// Roku app in a Mac app's, is added beside it. Two devices' own apps are two codes, one per wish for now: an Xbox's
    /// web app asked for in a Roku app's wish is refused, never made out of the Roku app.
    func testADevicesOwnAppGoesBesideTheOthersAndIsNeverMadeIntoAnother() throws {
        let roku = app("channel", .device, integration: "roku")
        XCTAssertNotEqual(roku.target.code, AppKinds.code(of: .device, integration: "xbox-one"))
        guard case .add(let mac) = try make(.native, ["mac"], in: [roku]) else { return XCTFail("a Mac app goes beside the Roku app") }
        XCTAssertEqual(mac.kind, .mac)
        guard case .add(let channel) = try make(.native, ["roku"], in: [app("notes", .mac)]) else { return XCTFail("a Roku app goes beside the Mac app") }
        XCTAssertEqual(channel.kind, .device)
        XCTAssertEqual(channel.integration, "roku")
        guard case .update(let same, _) = try make(.native, ["roku"], in: [roku]) else { return XCTFail() }
        XCTAssertEqual(same, roku)
    }

    /// "Put it on our Roku and on the Xbox too": a Roku app and an Xbox app are two apps of one wish, side by side. Asked
    /// for beside each other they're added, in either order, the Roku app is never made into the Xbox's, and asking for
    /// either again changes that one alone. Each is found by its own device, and "device" fits both.
    func testARokuAppAndAnXboxAppGoSideBySide() throws {
        let roku = app("party.roku", .device, folder: "Roku", integration: "roku")
        guard case .add(let xbox) = try make(.web, ["xbox-one"], in: [app("party", .iphone), roku]) else { return XCTFail("the Xbox app goes beside the Roku app") }
        XCTAssertEqual(xbox.kind, .device)
        XCTAssertEqual(xbox.integration, "xbox-one")
        let made = app("party.xbox", .device, folder: "Xbox", integration: "xbox-one")
        XCTAssertEqual(made.target.rows, ["xbox-one"], "a made Xbox app reads back as the Xbox's")
        guard case .add(let channel) = try make(.native, ["roku"], in: [made]) else { return XCTFail("the Roku app goes beside the Xbox app") }
        XCTAssertEqual(channel.integration, "roku")
        guard case .update(let changed, _) = try make(.native, ["roku"], in: [roku, made]) else { return XCTFail() }
        XCTAssertEqual(changed, roku)
        guard case .update(let other, _) = try make(.web, ["xbox-one"], in: [roku, made]) else { return XCTFail() }
        XCTAssertEqual(other, made)
        XCTAssertEqual(AppPlanner.find("xbox-one", in: [roku, made], table: table), .one(made))
        XCTAssertEqual(AppPlanner.find("Roku", in: [roku, made], table: table), .one(roku))
        guard case .several = AppPlanner.find("device", in: [roku, made], table: table) else { return XCTFail("\"device\" is either") }
        let waiting = AppKinds.member(waiting: WishApp(kind: .device, needs: "No Xbox yet", devices: ["xbox-one"], integration: "xbox-one"), in: table)
        guard case .add = try make(.native, ["roku"], in: [waiting]) else { return XCTFail("a Roku app goes beside a waiting Xbox app") }
    }

    /// `remove_app` finds an app by its folder or own word first, then by any device it's on through the table, and
    /// says when a name fits several or none; an app still to be made is taken off the list; the only app stays.
    func testRemoveFindsTheAppThroughTheTable() throws {
        let mac = app("party", .mac), screen = app("party.screen", .screen, folder: "Screen", places: [.mac, .tv])
        let game = app("party.game", .game, folder: "Game", places: [.mac, .android, .device])
        let android = app("party.android", .android, folder: "Android")
        let members = [mac, screen, game, android]
        func found(_ name: String) -> AppPlanner.Found { AppPlanner.find(name, in: members, table: table) }
        XCTAssertEqual(found("tv"), .one(screen))
        XCTAssertEqual(found("xbox-one"), .one(game))
        XCTAssertEqual(found("Screen"), .one(screen))
        XCTAssertEqual(found("android"), .one(android), "the Android app's own word comes before the game that's also on Android")
        XCTAssertEqual(found("iphone"), .none)
        guard case .several(let both) = AppPlanner.find("mac", in: [screen, game], table: table) else { return XCTFail() }
        XCTAssertEqual(both, [screen, game])
        let describe = { (member: WishMember) in member.target.kind.rawValue }
        XCTAssertEqual(try AppPlanner.remove("tv", in: members, table: table, describe: describe).get(), .remove(screen))
        let waiting = AppKinds.member(waiting: WishApp(kind: .iphone, needs: "Xcode"))
        XCTAssertEqual(try AppPlanner.remove("iphone", in: [mac, waiting], table: table, describe: describe).get(), .cancel(waiting))
        guard case .failure = AppPlanner.remove("mac", in: [mac, waiting], table: table, describe: describe) else { return XCTFail("the only made app went") }
    }
}
