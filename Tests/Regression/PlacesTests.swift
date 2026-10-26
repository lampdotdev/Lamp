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

    func testEveryMakeARowClaimsHasAKindThatBuildsItThere() {
        for place in Places.builtIn {
            for make in Place.Make.allCases where place.runs(make) {
                let kinds = Places.kinds(make: make, devices: [place.id])
                XCTAssertFalse(kinds.isEmpty, "\(place.name) claims \(make) but no kind builds it")
                for kind in kinds {
                    XCTAssertTrue(kind.target.places.contains(place.destination), "\(kind.rawValue) doesn't open on \(place.name)")
                }
            }
        }
        // The Apple TV and Vision Pro are the Apple kinds' own builds for another system.
        for id in ["apple-tv", "vision-pro"] {
            XCTAssertTrue(Places.kinds(make: .native, devices: [id]).allSatisfy(\.target.otherSystems))
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

    func testEveryStoredKindReadsAsAMakeAndDevicesThatLeadBackToIt() {
        let samples: [(Platform, Set<String>)] = [(.mac, []), (.iphone, []), (.iphone, ["watch"]), (.universal, []), (.android, []),
                                                  (.androidTV, []), (.tv, []), (.game, []), (.game, ["iphone", "android"]),
                                                  (.screen, []), (.screen, ["ipad", "tv"])]
        for (kind, places) in samples {
            let model = Places.model(of: kind, places: places)
            XCTAssertTrue(Places.kinds(make: model.make, devices: model.devices).contains(kind),
                          "\(kind.rawValue) \(places.sorted()) reads as \(model.make) on \(model.devices.sorted()), which leads elsewhere")
        }
        XCTAssertEqual(Places.model(of: .game, places: ["ipad"]).devices, ["mac", "iphone"])
        XCTAssertEqual(Places.kinds(make: .native, devices: ["mac", "iphone"]), [.universal])
        XCTAssertEqual(Places.kinds(make: .web, devices: ["mac", "tv"]), [.screen], "a game isn't shown on a TV")
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
