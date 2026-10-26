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
                guard case .success(let target) = AppKinds.target(make, on: [device], in: Places.builtIn) else {
                    return XCTFail("\(place.name) claims \(make) but no kind builds it")
                }
                XCTAssertTrue(target.kind.target.places.contains(place.destination), "\(target.kind.rawValue) doesn't open on \(place.name)")
            }
        }
        // The Apple TV and Vision Pro are the Apple kinds' own builds for another system.
        for id in ["apple-tv", "vision-pro"] {
            guard case .success(let target) = AppKinds.target(.native, on: [try XCTUnwrap(DeviceWord(id, in: Places.builtIn))], in: Places.builtIn) else { return XCTFail() }
            XCTAssertTrue(target.kind.target.otherSystems)
        }
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
        ]
        for app in apps {
            let member = AppKinds.member(of: app)
            let make: Place.Make = [Platform.game, .screen, .tv].contains(app.platform) ? .web : .native
            guard case .success(let again) = AppKinds.target(make, on: member.target.devices, existing: [member], in: Places.builtIn) else {
                return XCTFail("\(app.platform.rawValue) reads back as devices it can't be made on")
            }
            XCTAssertEqual(again.kind, app.platform)
            XCTAssertEqual(again.code, member.target.code)
        }
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
        XCTAssertTrue(roku.noWeb?.contains("BrightScript") == true)
    }

    func testAnIntegrationCantSupportWhatItHasNoFilesFor() throws {
        let (data, _) = try shipped("roku")
        XCTAssertTrue(IntegrationCheck.problems(data, submitted: false).filter { $0.hasPrefix("supports") }.isEmpty)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["supports"] = ["native", "web"]
        let problems = IntegrationCheck.problems(try JSONSerialization.data(withJSONObject: json), submitted: false)
        XCTAssertEqual(problems.filter { $0.hasPrefix("supports") }.count, 1, "web, which its BrightScript app doesn't make")
        json["supports"] = ["game"]
        XCTAssertFalse(IntegrationCheck.problems(try JSONSerialization.data(withJSONObject: json), submitted: false).filter { $0.hasPrefix("supports") }.isEmpty)
    }
}
