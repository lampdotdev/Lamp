import XCTest
@testable import Lamp

/// The table of what each device can run holds only what Lamp can build: every make a row claims has a kind of app that
/// builds it there, every make it doesn't claim is refused with the row's reason, and every kind Lamp stores reads as a
/// make and devices that lead back to it.
final class PlacesTests: XCTestCase {
    private func shipped(_ id: String) throws -> (data: Data, integration: Integration) {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: source.appendingPathComponent("Resources/Devices/\(id).json"))
        return (data, try JSONDecoder().decode(Integration.self, from: data))
    }

    func testEveryMakeARowClaimsHasAKindThatBuildsItThere() throws {
        for place in Places.builtIn {
            for make in Place.Make.allCases where place.runs(make) {
                let device = try XCTUnwrap(DeviceWord(place.words[0], in: Places.builtIn))
                guard case .success(let target) = AppKinds.target(make, kind: .app, on: [device], in: Places.builtIn) else {
                    return XCTFail("\(place.name) claims \(make) but no kind builds it")
                }
                XCTAssertTrue(target.kind.target.places.contains(place.destination), "\(target.kind.rawValue) doesn't open on \(place.name)")
            }
        }
        // The Apple TV and Vision Pro are the Apple kinds' own builds for another system.
        for id in ["apple-tv", "vision-pro"] {
            guard case .success(let target) = AppKinds.target(.native, kind: .app, on: [try XCTUnwrap(DeviceWord(id, in: Places.builtIn))], in: Places.builtIn) else { return XCTFail() }
            XCTAssertTrue(target.kind.target.otherSystems)
        }
    }

    /// Designing for a TV is offered by the rows that are TVs, built in or an integration's (the Roku's JSON), once
    /// however many of them an app is on; a row that isn't a TV offers nothing for it.
    func testTheTVRowsOfferTheirDesignSkill() throws {
        let roku = try XCTUnwrap(Places.row(for: try shipped("roku").integration))
        let table = Places.builtIn + [roku]
        XCTAssertEqual(Places.skills(rows: ["tv", "android-tv", "apple-tv", "roku"], in: table), ["tv-design"])
        for rows: Set<String> in [["mac"], ["iphone", "android"], ["watch"], ["vision-pro"]] {
            XCTAssertEqual(Places.skills(rows: rows, in: table), [], "\(rows) isn't a TV")
        }
        XCTAssertEqual(Set(table.filter { !$0.skills.isEmpty }.map(\.id)), ["apple-tv", "android-tv", "tv", "roku"])
    }

    func testEveryMakeARowDoesntClaimIsRefusedWithItsReason() {
        for place in Places.builtIn {
            for make in Place.Make.allCases {
                let refusal = Places.refusal(make: make, devices: [place.id])
                if place.runs(make) {
                    XCTAssertNil(refusal, "\(place.name) runs \(make)")
                } else {
                    let said = try? XCTUnwrap(refusal, "\(place.name) doesn't run \(make)")
                    XCTAssertTrue(said?.contains(place.name) == true)
                    XCTAssertTrue(said?.contains((make == .web ? place.noWeb : place.noNative) ?? "-") == true, "the row's reason is said")
                }
            }
        }
        XCTAssertNotNil(Places.refusal(make: .web, devices: ["iphone", "apple-tv"]), "one device that can't is enough")
        XCTAssertNil(Places.refusal(make: .web, devices: ["iphone", "mac"]))
    }

    /// Where Lamp only lacks a host or a recipe (a native Samsung or LG TV app, a page on Vision Pro, a native app for a
    /// device whose integration doesn't say what it runs), the refusal says Lamp can't build it yet, never that the
    /// device can't run it; a device that really can't (an Apple TV's page) is still said so.
    func testLampsOwnGapsAreRefusedAsLampsNotTheDevices() throws {
        let tv = Places.refusal(make: .native, devices: ["tv"]) ?? ""
        XCTAssertTrue(tv.hasPrefix("Lamp can't build a native app for Samsung / LG TV yet"), tv)
        XCTAssertFalse(tv.contains("can't run"), tv)
        let vision = Places.refusal(make: .web, devices: ["vision-pro"]) ?? ""
        XCTAssertTrue(vision.hasPrefix("Lamp can't build a web app for Vision Pro yet"), vision)
        XCTAssertTrue(Places.refusal(make: .web, devices: ["apple-tv"])?.hasPrefix("Apple TV can't run a web app") == true)
        let table = try ["xbox-one", "roku"].compactMap { Places.row(for: try shipped($0).integration) }
        let xbox = Places.refusal(make: .native, devices: ["xbox-one"], in: table) ?? ""
        XCTAssertTrue(xbox.hasPrefix("Lamp can't build a native app for"), xbox)
        let roku = Places.refusal(make: .web, devices: ["roku"], in: table) ?? ""
        XCTAssertTrue(roku.contains("can't run a web app") && roku.contains("TypeScript on Roku's own SDK"), "a Roku's own limit stays its own: \(roku)")
    }

    /// Every stored kind reads back as devices that, asked for again as it's made, plan the same kind: nothing changes.
    func testEveryStoredKindReadsBackAsItself() throws {
        let dir = URL(fileURLWithPath: "/tmp/places-kinds")
        let apps: [LampProject] = [
            LampProject(id: "a", name: "A", exe: "A", dir: dir, platform: .mac),
            LampProject(id: "b", name: "B", exe: "B", dir: dir, platform: .iphone),
            LampProject(id: "c", name: "C", exe: "C", dir: dir, platform: .universal),
            LampProject(id: "d", name: "D", exe: "D", dir: dir, platform: .android),
            LampProject(id: "e", name: "E", exe: "E", dir: dir, platform: .androidTV),
            LampProject(id: "f", name: "F", exe: "F", dir: dir, platform: .tv),
            LampProject(id: "g", name: "G", exe: "G", dir: dir, platform: .game, places: [.mac, .ios, .android]),
            LampProject(id: "h", name: "H", exe: "H", dir: dir, platform: .screen, places: [.mac, .tv]),
            LampProject(id: "i", name: "I", exe: "I", dir: dir, platform: .webApp, places: [.mac, .android]),
        ]
        for app in apps {
            let member = AppKinds.member(of: app)
            let make: Place.Make = [Platform.game, .webApp, .screen, .tv].contains(app.platform) ? .web : .native
            guard case .success(let again) = AppKinds.target(make, kind: AppIntent.of(app.platform), on: member.target.devices, keeping: member.target.kind, in: Places.builtIn) else {
                return XCTFail("\(app.platform.rawValue) reads back as devices it can't be made on")
            }
            XCTAssertEqual(again.kind, app.platform)
            XCTAssertEqual(again.code, member.target.code)
        }
    }

    /// A page goes wherever one of Lamp's web hosts is, whatever kind of page it is, Android TV among them, and a device
    /// with none is refused with why: it needs a native version.
    func testAPageGoesWhereverAHostIs() throws {
        XCTAssertEqual(Places.pagePlaces, [.mac, .ios, .android, .androidTV, .tv, .device])
        XCTAssertEqual(Platform.game.target.places, Places.pagePlaces)
        XCTAssertEqual(Platform.screen.target.places, Places.pagePlaces)
        XCTAssertEqual(Places.named("android-tv")?.web?.host, Places.named("android")?.web?.host, "one Android host for phones and TVs")
        let devices = ["mac", "android-tv", "android", "ipad"].compactMap { DeviceWord($0, in: Places.builtIn) }
        guard case .success(let page) = AppKinds.target(.web, kind: .game, on: devices, in: Places.builtIn) else { return XCTFail("a page on Android TV") }
        XCTAssertTrue(page.kind.addsPlaces && page.places?.contains(.androidTV) == true)
        let appleTV = ["mac", "apple-tv"].compactMap { DeviceWord($0, in: Places.builtIn) }
        guard case .failure(let refusal) = AppKinds.target(.web, kind: .app, on: appleTV, in: Places.builtIn) else { return XCTFail("a page on an Apple TV") }
        XCTAssertTrue(refusal.reason.contains("needs a native version"), refusal.reason)
    }

    /// Which make a game and an app on each device get when the person names none: a game web wherever Lamp has a host
    /// for a page, native on a Roku, an Apple TV, an Apple Watch and Vision Pro; an app native on one Mac, iPhone or
    /// Android device, web on a TV or a console; one app across several devices web where every one takes a page. Each
    /// default is a make its row runs, and the table the agent reads says them.
    func testEachDeviceHasTheDefaultsAskedFor() throws {
        let table = try Places.builtIn + ["xbox-one", "roku"].compactMap { Places.row(for: try shipped($0).integration) }
        let expected: [String: (game: Place.Make, app: Place.Make)] = [
            "mac": (.web, .native), "iphone": (.web, .native), "android": (.web, .native),
            "tv": (.web, .web), "android-tv": (.web, .web), "xbox-one": (.web, .web),
            "apple-tv": (.native, .native), "roku": (.native, .native), "watch": (.native, .native), "vision-pro": (.native, .native),
        ]
        XCTAssertEqual(Set(table.map(\.id)), Set(expected.keys))
        for place in table {
            let want = try XCTUnwrap(expected[place.id])
            XCTAssertEqual(place.defaultMake(.game), want.game, "a game on \(place.name)")
            XCTAssertEqual(place.defaultMake(.app), want.app, "an app on \(place.name)")
            XCTAssertTrue(place.runs(place.gameDefault) && place.runs(place.appDefault), "\(place.name)'s defaults are makes it runs")
        }
        XCTAssertEqual(Places.defaultMake(.app, devices: ["mac", "iphone", "android"], in: table), .web, "one app across several")
        XCTAssertEqual(Places.defaultMake(.game, devices: ["mac", "tv", "xbox-one"], in: table), .web)
        XCTAssertEqual(Places.defaultMake(.app, devices: ["mac", "apple-tv"], in: table), .native, "native on both")
        XCTAssertNil(Places.defaultMake(.app, devices: ["tv", "apple-tv"], in: table), "no make they share")
        XCTAssertEqual(Places.defaultMake(.app, devices: ["iphone"], in: table), .native)
        XCTAssertTrue(Places.forAgent.contains("This Mac [\"mac\"]: ") && Places.forAgent.contains("by default a game web, an app native"))
        XCTAssertTrue(Places.forAgent.contains("by default a game native, an app native"))
    }

    func testAnIntegrationsRowIsWhatItSupports() throws {
        let xbox = try XCTUnwrap(Places.row(for: try shipped("xbox-one").integration))
        XCTAssertTrue(xbox.runs(.web))
        XCTAssertFalse(xbox.runs(.native), "the Xbox's C++ games are kept as they are; nothing new is made that way")
        XCTAssertEqual(xbox.destination, .device)
        XCTAssertTrue(Platform.game.target.places.contains(.device))
        let roku = try XCTUnwrap(Places.row(for: try shipped("roku").integration))
        XCTAssertEqual(roku.native?.code, .integration)
        XCTAssertFalse(roku.runs(.web))
        // A page asked of it is refused with what a Roku runs, in the integration's own words, never Lamp's.
        XCTAssertTrue(roku.noWeb?.contains("Roku's own SDK") == true)
    }

    /// Every row with no web host is one a page can't go to, each said with its own reason, whichever device it is: none
    /// is singled out by name, and a gap of Lamp's own is told apart from what the device itself can't do.
    func testEveryRowWithNoHostIsOneAPageCantGoTo() throws {
        let roku = try XCTUnwrap(Places.row(for: try shipped("roku").integration))
        let table = Places.builtIn + [roku]
        let none = Places.noPage(in: table)
        XCTAssertEqual(none.map(\.id), table.filter { !$0.runs(.web) }.map(\.id))
        XCTAssertEqual(Set(none.map(\.id)), ["watch", "apple-tv", "vision-pro", "roku"])
        for place in none { XCTAssertNotNil(place.noWeb, "\(place.name) says why") }
        XCTAssertEqual(none.filter(\.noHostYet).map(\.id), ["vision-pro"], "only Vision Pro's is Lamp's own gap")
    }

    /// A page for several devices goes onto an integration only through the integration Lamp packages pages for: another
    /// integration's device that runs web apps isn't taken for an Xbox.
    func testAPageForSeveralDevicesIsntSentToAnotherIntegrationsHost() throws {
        let xbox = try XCTUnwrap(Places.row(for: try shipped("xbox-one").integration))
        let frame = Place(id: "test-frame", name: "Test Frame", words: ["test-frame"], destination: .device,
                          web: .init(host: .integration, reach: "Lamp installs it"), native: nil, input: .generic)
        let table = Places.builtIn + [xbox, frame]
        let both = ["mac", "test-frame"].compactMap { DeviceWord($0, in: table) }
        guard case .failure(let refusal) = AppKinds.target(.web, kind: .app, on: both, in: table) else {
            return XCTFail("a page for the Mac and Test Frame was made as one for the Xbox")
        }
        XCTAssertTrue(refusal.reason.contains("Test Frame"), refusal.reason)
        // Alone, it's the integration's own web app; with the Xbox, a page that goes there.
        guard case .success(let own) = AppKinds.target(.web, kind: .app, on: [try XCTUnwrap(DeviceWord("test-frame", in: table))], in: table) else { return XCTFail() }
        XCTAssertEqual(own.integration, "test-frame")
        guard case .success(let page) = AppKinds.target(.web, kind: .game, on: ["mac", "xbox-one"].compactMap { DeviceWord($0, in: table) }, in: table) else { return XCTFail() }
        XCTAssertEqual(page.places, [.mac, .device])
    }

    func testAnIntegrationCantSupportWhatItHasNoFilesFor() throws {
        let (data, _) = try shipped("roku")
        XCTAssertTrue(IntegrationCheck.problems(data, submitted: false).filter { $0.hasPrefix("supports") }.isEmpty)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["supports"] = ["native", "web"]
        let problems = IntegrationCheck.problems(try JSONSerialization.data(withJSONObject: json), submitted: false)
        XCTAssertEqual(problems.filter { $0.hasPrefix("supports") }.count, 1, "web, which its Roku app doesn't make")
        json["supports"] = ["game"]
        XCTAssertFalse(IntegrationCheck.problems(try JSONSerialization.data(withJSONObject: json), submitted: false).filter { $0.hasPrefix("supports") }.isEmpty)
    }
}
