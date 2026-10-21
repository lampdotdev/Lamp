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
        let devices = Devices.list(devicectl: Data(listing.utf8), team: "ABCDE12345")
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
        // A watch goes with a set-up iPhone.
        let watch = devices[2]
        XCTAssertEqual(watch.kind, .watch)
        XCTAssertEqual(watch.forAgent, "Apple Watch Series 10, watchOS 26, HealthKit")
        XCTAssertEqual(watch.setup(team: "ABCDE12345"), .ready)
        XCTAssertEqual(Devices.list(devicectl: Data(listing.utf8), team: "")[2].setup(team: ""), .needs("Set up the iPhone it's paired with"))
    }
}
