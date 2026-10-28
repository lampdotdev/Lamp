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

    /// Two TVs answering with one serial at two addresses (left as adb lists them), one of them at an old choice's address.
    private func ambiguous() throws -> (devices: [Device], old: String) {
        let other = "192.168.1.77:41000"
        let listing = try fixture("devices").replacingOccurrences(of: address, with: other)
        let devices = AndroidTVs.merge(Adb.listed(listing).map { Device.from(adb: $0.serial, state: $0.state, properties: properties) },
                                       services: AndroidTVs.services(try fixture("mdns")), kept: []).devices
        return (devices, other)
    }

    /// An old address-and-port choice isn't used because an unrecorded TV answers there: the person chooses it again.
    func testAnOldAddressOnAnUnrecordedTVNeedsChoosingAgain() throws {
        let (devices, old) = try ambiguous()
        guard case .confirm = AndroidTVs.choice(old, among: devices, confirmed: []) else { return XCTFail("used without asking") }
        guard case .use = AndroidTVs.choice(old, among: devices, confirmed: [old]) else { return XCTFail("chosen again, still refused") }
    }

    /// Stop with nothing of Lamp's watching closes the app only where the choice can be used: never at an old address
    /// another TV may have taken.
    func testStopDoesNotGoToAnUnconfirmedOldAddress() throws {
        let record = try kept()
        let devices = look(try fixture("devices"), try fixture("mdns"), [mdnsName: properties, address: properties], kept: [record])
        XCTAssertNil(AndroidTVs.stopTarget("192.168.1.50:5555", among: devices, confirmed: []))
        XCTAssertNil(AndroidTVs.stopTarget(address, among: devices, confirmed: []))
        XCTAssertEqual(AndroidTVs.stopTarget(record.id, among: devices, confirmed: []), mdnsName)
    }

    /// After pairing over Wireless debugging, the TV's old 5555 connection isn't taken for ready.
    @MainActor func testAPairedTVIsntReadyOnTheOldPort() throws {
        let old = "192.168.1.50:5555"
        let devices = look("List of devices attached\n\(old)   device product:jarvis\n", try fixture("mdns"), [old: properties], kept: [])
        XCTAssertNil(AndroidWiFi.ready(at: "192.168.1.50", among: devices, services: AndroidTVs.services(try fixture("mdns")), tls: true))
        XCTAssertNotNil(AndroidWiFi.ready(at: "192.168.1.50", among: devices, services: AndroidTVs.services(try fixture("mdns")), tls: false))
    }

    /// adb's answer when the TV's connection is gone (its port changed) says nothing of the app: it isn't taken for the
    /// app having quit.
    func testALostConnectionIsntAnAppThatQuit() {
        let lost = Subprocess.Result(status: 1, output: "", errors: "adb: device '\(address)' not found", timedOut: false)
        XCTAssertEqual(Adb.process(of: "dev.lamp.app", on: address, said: lost), .unreachable)
        let quit = Subprocess.Result(status: 1, output: "", errors: "", timedOut: false)
        XCTAssertEqual(Adb.process(of: "dev.lamp.app", on: address, said: quit), .gone)
    }

    /// A TV at an old choice's address whose description couldn't be read (no answer about its leanback feature) isn't
    /// taken for a phone, which would be used as chosen: it's asked about like any TV there.
    func testADeviceThatDidntSayWhatItIsIsAskedAbout() throws {
        let old = "192.168.1.77:41000"
        let devices = look("List of devices attached\n\(old)   device product:jarvis\n", "", [old: [:]], kept: [])
        guard case .confirm = AndroidTVs.choice(old, among: devices, confirmed: []) else { return XCTFail("used without asking") }
        let phone = look("List of devices attached\n\(old)   device product:pixel\n", "", [old: ["leanback": "false", "ro.serialno": "PHONE0123456"]], kept: [])
        guard case .use = AndroidTVs.choice(old, among: phone, confirmed: []) else { return XCTFail("a phone that said so is used as chosen") }
    }

    /// A TV kept from its Fire‑style old port, then paired over Wireless debugging (with the window closed before its
    /// encrypted connection showed), isn't reached on 5555 while the pairing is recent, nor after, once it's marked by
    /// its serial.
    func testAPairingOutlivesTheWindow() throws {
        let old = "192.168.1.50:5555"
        let read = Adb.listed("List of devices attached\n\(old)   device product:jarvis\n").map { Device.from(adb: $0.serial, state: $0.state, properties: properties) }
        let legacy = try XCTUnwrap(AndroidTVs.merge(read, services: [], kept: []).kept.first)
        XCTAssertEqual(legacy.transport, .legacy)
        let after = AndroidTVs.merge(read, services: [], kept: [legacy], pairedAt: ["192.168.1.50"])
        XCTAssertTrue(try XCTUnwrap(after.devices.first { $0.id == legacy.id }).isAway)
        // Tied to the TV by the serial it read as it paired, the mark lasts beyond the address's hint.
        let marked = AndroidTVs.promoted([legacy], serial: "SERIAL0123456")
        XCTAssertEqual(marked.first?.transport, .tls)
        XCTAssertTrue(try XCTUnwrap(AndroidTVs.merge(read, services: [], kept: marked).devices.first { $0.id == legacy.id }).isAway)
    }

    /// A pairing at an address is no lasting mark on a different device that has that address later: a Fire TV with
    /// another serial there keeps its old port for good, and is kept from it only while the pairing is recent.
    func testAPairingDoesntMarkAnotherDeviceAtItsAddress() throws {
        let old = "192.168.1.50:5555"
        let fire = ["ro.product.manufacturer": "Amazon", "ro.product.model": "AFTMM", "ro.serialno": "FIRETV0000001", "leanback": "true"]
        let read = Adb.listed("List of devices attached\n\(old)   device product:mantis\n").map { Device.from(adb: $0.serial, state: $0.state, properties: fire) }
        let legacy = try XCTUnwrap(AndroidTVs.merge(read, services: [], kept: []).kept.first)
        let recent = AndroidTVs.merge(read, services: [], kept: [legacy], pairedAt: ["192.168.1.50"])
        XCTAssertEqual(recent.kept.first?.transport, .legacy)
        let later = AndroidTVs.merge(read, services: [], kept: recent.kept)
        XCTAssertEqual(later.devices.first?.adb, old)
        XCTAssertFalse(try XCTUnwrap(later.devices.first).isAway)
    }

    /// A kept TV that's paired over Wireless debugging and away puts no rule on the address it last had: a different
    /// device there now (a Fire TV with another serial) can be connected on its old port once no pairing there is
    /// recent. The TV itself, answering there, keeps its rule.
    func testAnAwayTVPutsNoRuleOnItsLastAddress() throws {
        let tv = try kept()
        let fire = ["ro.product.manufacturer": "Amazon", "ro.product.model": "AFTMM", "ro.serialno": "FIRETV0000001", "leanback": "true"]
        let other = "192.168.1.50:5555"
        let read = Adb.listed("List of devices attached\n\(other)   device product:mantis\n").map { Device.from(adb: $0.serial, state: $0.state, properties: fire) }
        let devices = AndroidTVs.merge(read, services: [], kept: [tv]).devices
        XCTAssertTrue(try XCTUnwrap(devices.first { $0.id == tv.id }).isAway)
        XCTAssertFalse(AndroidTVs.requiresTLS("192.168.1.50", among: devices, pairedAt: []))
        XCTAssertTrue(AndroidTVs.requiresTLS("192.168.1.50", among: devices, pairedAt: ["192.168.1.50"]))
        let here = look(try fixture("devices"), try fixture("mdns"), [mdnsName: properties, address: properties], kept: [tv])
        XCTAssertTrue(AndroidTVs.requiresTLS("192.168.1.50", among: here, pairedAt: []))
    }

    /// A kept TV listed by its mDNS name in a look where adb's search answered nothing has no known address: the one it
    /// last had isn't taken for where it is now.
    func testAnUnresolvedMDNSNameGivesNoAddress() throws {
        var tv = try kept()
        tv.address = "192.168.1.50"
        let devices = look("List of devices attached\n\(mdnsName) device product:jarvis\n", "", [mdnsName: properties], kept: [tv])
        let live = try XCTUnwrap(devices.first { $0.id == tv.id })
        XCTAssertEqual(live.adbState, "device")
        XCTAssertNil(live.address)
        XCTAssertFalse(AndroidTVs.requiresTLS("192.168.1.50", among: devices, pairedAt: []))
    }
}
