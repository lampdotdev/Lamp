import XCTest
@testable import Lamp

/// A Google TV as adb sees it over Wi‑Fi. Tests/Fixtures/google-tv are its own answers, recorded on 2026-10-28 from
/// Lamp's adb server with the TV already paired (its serial, address and mDNS suffix replaced): adb lists it twice,
/// under the name its own search connected and the address a manual `adb connect` added, and the TV offers its
/// encrypted connection and the old 5555 one at once. What it said of itself (`getprop`) is in `properties`.
final class AndroidTVTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/google-tv/\(name).txt")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private let properties: [String: String] = [
        "ro.product.manufacturer": "onn", "ro.product.model": "onn. Streaming Device 4K pro", "ro.product.device": "SNA",
        "ro.build.version.release": "14", "ro.build.version.sdk": "34", "ro.serialno": "SERIAL0123456", "leanback": "true",
    ]
    private let mdnsName = "adb-SERIAL0123456-Ab12Cd._adb-tls-connect._tcp"
    private let address = "192.168.1.50:33935"

    /// The TV's encrypted connection is the one Lamp connects to, not the old port it offers beside it.
    func testServicesKeepTheEncryptedConnectionPort() throws {
        let found = Adb.services(from: try fixture("mdns"))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.connectPort, 33935)
    }

    /// Two selectors for one TV (the same serial at the same address) are one device, reached by adb's own name for it.
    func testOneTVListedTwiceIsOneDevice() throws {
        let devices = Adb.devices(listing: try fixture("devices"), services: try fixture("mdns"),
                                  properties: [mdnsName: properties, address: properties])
        XCTAssertEqual(devices.count, 1, devices.map(\.id).joined(separator: ", "))
        XCTAssertEqual(devices.first?.adb, mdnsName)
    }

    /// The record met in the first look, and what a later look makes of it.
    private func kept() throws -> AndroidTVs.Record {
        let read = Adb.listed(try fixture("devices")).map { Device.from(adb: $0.serial, state: $0.state, properties: properties) }
        let first = AndroidTVs.merge(read, services: AndroidTVs.services(try fixture("mdns")), kept: []).kept
        XCTAssertEqual(first.first?.transport, .tls)
        return try XCTUnwrap(first.first)
    }

    private func look(_ listing: String, _ mdns: String, _ properties: [String: [String: String]], kept: [AndroidTVs.Record]) -> [Device] {
        let read = Adb.listed(listing).map { Device.from(adb: $0.serial, state: $0.state, properties: properties[$0.serial] ?? [:]) }
        return AndroidTVs.merge(read, services: AndroidTVs.services(mdns), kept: kept).devices
    }

    /// Wireless debugging turned off and on again gives the TV a new port: the saved record is still the TV, reached at it.
    func testTheRecordFollowsANewPort() throws {
        let record = try kept()
        let moved = "192.168.1.50:40211"
        let devices = look("List of devices attached\n\(moved)   device product:jarvis\n",
                           "List of discovered mdns services\nadb-SERIAL0123456-Ab12Cd\t_adb-tls-connect._tcp\t\(moved)\n",
                           [moved: properties], kept: [record])
        XCTAssertEqual(devices.map(\.id), [record.id])
        XCTAssertEqual(devices.first?.adb, moved)
        XCTAssertEqual(devices.first?.adbState, "device")
    }

    /// A TV paired over Wireless debugging is never reached over the old port it also offers: with only that one
    /// listed, it's away and says what to turn back on.
    func testATLSPairedTVIsNeverReachedOnTheOldPort() throws {
        let record = try kept()
        let old = "192.168.1.50:5555"
        let devices = look("List of devices attached\n\(old)   device product:jarvis\n", try fixture("mdns"), [old: properties], kept: [record])
        let tv = try XCTUnwrap(devices.first { $0.id == record.id })
        XCTAssertNotEqual(tv.adb, old)
        XCTAssertTrue(tv.isAway)
        XCTAssertEqual(tv.setup(), .needs("Turn on Wireless debugging on it"))
    }

    /// Two rows reading the same serial at different addresses aren't taken for one TV: both stay as adb listed them,
    /// and no record is made.
    func testTheSameSerialAtTwoAddressesStaysTwoRows() throws {
        let other = "192.168.1.77:41000"
        let listing = try fixture("devices").replacingOccurrences(of: address, with: other)
        let result = AndroidTVs.merge(Adb.listed(listing).map { Device.from(adb: $0.serial, state: $0.state, properties: properties) },
                                      services: AndroidTVs.services(try fixture("mdns")), kept: [])
        XCTAssertEqual(Set(result.devices.map(\.id)), [other, mdnsName])
        XCTAssertTrue(result.kept.isEmpty)
    }

    /// An old choice is adopted only when it's adb's mDNS name for the TV and carries the serial the TV reads; an
    /// address and port is the person's to confirm.
    func testOldChoicesAreAdoptedOnlyByTheirSerial() throws {
        let record = try kept()
        let tv = try XCTUnwrap(look(try fixture("devices"), try fixture("mdns"), [mdnsName: properties, address: properties], kept: [record]).first)
        XCTAssertTrue(AndroidTVs.adopts(mdnsName, as: tv))
        XCTAssertFalse(AndroidTVs.adopts(address, as: tv))
        var another = tv
        another.serialNumber = "SERIAL9999999"
        XCTAssertFalse(AndroidTVs.adopts(mdnsName, as: another))
    }
}
