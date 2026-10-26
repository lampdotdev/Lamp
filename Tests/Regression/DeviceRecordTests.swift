import XCTest
@testable import Lamp

/// The record Lamp keeps of a device is read off the device itself: Xcode's list for a phone or watch, with the
/// exact model and software, and what sets it apart. Watches are kept, and the agent's line has the shape the
/// device list and Try On go by.
final class DeviceRecordTests: XCTestCase {
    private let listing = """
    {"result": {"devices": [
      {"hardwareProperties": {"deviceType": "iPhone", "marketingName": "iPhone 16 Pro Max", "platform": "iOS", "productType": "iPhone17,2", "reality": "physical", "udid": "PHONE"},
       "deviceProperties": {"name": "Celsius", "osVersionNumber": "27.0", "developerModeStatus": "enabled"},
       "connectionProperties": {"pairingState": "paired", "tunnelState": "disconnected", "transportType": "localNetwork"}},
      {"hardwareProperties": {"deviceType": "appleWatch", "marketingName": "Apple Watch Series 10", "platform": "watchOS", "productType": "Watch7,8", "reality": "physical", "udid": "WATCH"},
       "deviceProperties": {"name": "Watch", "osVersionNumber": "26.1"},
       "connectionProperties": {"pairingState": "paired", "tunnelState": "disconnected"}},
      {"hardwareProperties": {"deviceType": "iPhone", "marketingName": "iPhone 16e", "platform": "iOS", "productType": "iPhone17,5", "reality": "physical", "udid": "NEW"},
       "deviceProperties": {"name": "New phone", "osVersionNumber": "26.0"},
       "connectionProperties": {"pairingState": "unpaired", "tunnelState": "disconnected", "transportType": "wired"}},
      {"hardwareProperties": {"deviceType": "iPhone", "marketingName": "iPhone 16", "platform": "iOS", "productType": "iPhone17,3", "reality": "simulated", "udid": "SIM"},
       "deviceProperties": {"name": "iPhone 16", "osVersionNumber": "18.6"}, "connectionProperties": {"pairingState": "paired"}}
    ]}}
    """

    func testPhonesAndWatchesAreReadExactly() {
        let devices = Devices.list(devicectl: Data(listing.utf8))
        XCTAssertEqual(devices.map(\.id), ["PHONE", "NEW", "WATCH"])
        let phone = devices[0]
        XCTAssertEqual(phone.forAgent, "iPhone 16 Pro Max, iOS 27, Dynamic Island, NFC, HealthKit")
        XCTAssertEqual(phone.modelID, "iPhone17,2")
        XCTAssertEqual(phone.reach, .network)
        XCTAssertEqual(phone.setup(team: "ABCDE12345"), .ready)
        XCTAssertEqual(phone.setup(team: ""), .needs("Choose your Apple team"))
        // The 16e has no Dynamic Island, and an unpaired phone's next step is pairing.
        let new = devices[1]
        XCTAssertFalse(new.features.contains("Dynamic Island"))
        XCTAssertEqual(new.reach, .cable)
        XCTAssertEqual(new.setup(team: "ABCDE12345"), .needs("Pair it with this Mac"))
        // A watch goes with a paired iPhone with Developer Mode on, and needs the team as the phone does.
        let watch = devices[2]
        XCTAssertEqual(watch.kind, .watch)
        XCTAssertEqual(watch.forAgent, "Apple Watch Series 10, watchOS 26, HealthKit")
        XCTAssertEqual(watch.setup(team: "ABCDE12345"), .ready)
        XCTAssertEqual(watch.setup(team: ""), .needs("Choose your Apple team"))
        // An iPad is no companion: without the iPhone the watch's next step is its iPhone.
        let withoutPhone = listing.replacingOccurrences(of: "\"deviceType\": \"iPhone\", \"marketingName\": \"iPhone 16 Pro Max\"", with: "\"deviceType\": \"iPad\", \"marketingName\": \"iPad Pro\"")
        let pad = Devices.list(devicectl: Data(withoutPhone.utf8))
        XCTAssertEqual(pad.first { $0.kind == .watch }?.setup(team: "ABCDE12345"), .needs("Set up the iPhone it's paired with"))
    }

    /// An Xbox's description says Xbox One on every console; Device Portal names the console, and that's its model and
    /// what a game played on it is budgeted for. An Xbox not read yet is budgeted as the slowest, an Xbox One.
    /// Only a wish for a phone, a TV or a device has Lamp look, which is what makes macOS ask about the local network:
    /// one for this Mac, or a game played only there, never does.
    func testOnlyAWishForAPhoneTVOrDeviceLooks() {
        func wish(_ kinds: [Platform], places: [Platform: [Destination]] = [:], integration: String? = nil) -> AppName.Suggestion {
            var suggestion = AppName.Suggestion(name: "A", sketch: [], kinds: kinds)
            suggestion.places = places
            suggestion.integration = integration
            return suggestion
        }
        XCTAssertFalse(wish([.mac]).forDevice)
        XCTAssertFalse(wish([.mac]).forPhone)
        XCTAssertTrue(wish([.iphone]).forPhone)
        XCTAssertFalse(wish([.game], places: [.game: [.mac, .ios]]).forDevice)
        XCTAssertTrue(wish([.tv]).forDevice)
        XCTAssertTrue(wish([.game], places: [.game: [.mac, .device]]).forDevice)
        XCTAssertTrue(wish([.device], integration: "roku").forDevice)
        var other = wish([.mac])
        other.forOtherDevice = true
        XCTAssertTrue(other.forDevice)
    }

    func testAnXboxIsTheConsoleDevicePortalNames() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let xbox = try JSONDecoder().decode(Integration.self, from: Data(contentsOf: source.appendingPathComponent("Resources/Devices/xbox-one.json")))
        var kept = Integrations.Kept(id: "xbox-one:uuid:1", integration: "xbox-one", name: "Xbox", model: "Xbox One", modelID: "",
                                     os: "Xbox OS", osVersion: "10.0", address: "192.168.1.20")
        XCTAssertNil(Integrations.readModel(of: kept, by: xbox))
        kept.reads["device-portal"] = "Xbox Series X"
        XCTAssertEqual(Integrations.readModel(of: kept, by: xbox), "Xbox Series X")

        let game = LampProject(id: "racer", name: "Racer", exe: "Racer", dir: URL(fileURLWithPath: "/tmp/racer"), platform: .game,
                               device: kept.id, places: [.mac, .device], engine: "web")
        let line = Agent.Rules.gamePlaces(game, xbox: Integrations.readModel(of: kept, by: xbox))
        XCTAssertTrue(line.contains("Its budget is the person's Xbox Series X's"), line)
        XCTAssertFalse(line.contains("Xbox One"), line)
        XCTAssertTrue(Agent.Rules.gamePlaces(game, xbox: nil).contains("Its budget is an Xbox One's"))
        // With an iPhone too, the iPhone is the slower place.
        var both = game
        both.places = [.mac, .ios, .device]
        XCTAssertTrue(Agent.Rules.gamePlaces(both, xbox: "Xbox Series X").contains("Its budget is an iPhone's"))
    }
}
