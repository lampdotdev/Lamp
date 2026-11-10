import XCTest
@testable import Lamp

/// An LG TV answers an SSDP search for several services, each with an id of its own, and lamp's command line reads it
/// under its own service's id when that answered (cli/tests/network.test.mjs, on a webOS TV's recorded answers). Which
/// TV a reading is to Lamp is Lamp's: one kept or seen under another of its ids keeps that id.
final class LGDiscoveryTests: XCTestCase {
    private let address = "192.168.1.20"

    private func reading(_ id: String, udns: [String]) -> TVs.Record {
        TVs.Record(id: "lg:\(id)", maker: "LG", name: "[LG] webOS TV NANO80ASA", model: "65NANO80ASA.BWCDLKR", modelID: "65NANO80ASA",
                   address: address, os: "webOS", osVersion: "", resolution: "", udns: udns)
    }

    func testATVSeenUnderAnyOfItsIDsKeepsTheIDItHad() {
        let own = "11111111-2222-4333-8444-000000001904", renderer = "11111111-2222-4333-8444-000000001601", other = "11111111-2222-4333-8444-000000002043"
        // Its own service missed this search: it's read under another of its services' ids, and is still the TV seen before.
        let first = TVs.adopt(reading(own, udns: [own, renderer, other]), earlier: [])
        XCTAssertEqual(first.id, "lg:\(own)")
        XCTAssertEqual(TVs.adopt(reading(renderer, udns: [renderer, other]), earlier: [first]).id, first.id)
        // An earlier Lamp kept whichever description answered first: here the media renderer's.
        let kept = TVs.Record(id: "lg:\(renderer)", maker: "LG", name: "[LG] webOS TV NANO80ASA", model: "LG TV", modelID: "1.0", address: address,
                              os: "webOS", osVersion: "", resolution: "")
        XCTAssertEqual(TVs.adopt(reading(own, udns: [own, renderer]), earlier: [kept]).id, kept.id)
        XCTAssertEqual(TVs.adopt(reading(own, udns: [own]), earlier: [kept]).id, "lg:\(own)", "a TV that shares none of its ids is another")
    }

    /// The agent's line for a TV app is what Lamp has seen of this TV, and what it hasn't seen (its screen, whether
    /// the app runs there now) is said to be unknown.
    func testTheAgentIsToldWhatLampKnowsOfTheTVAndNoMore() throws {
        let record = reading("11111111-2222-4333-8444-000000001904", udns: [])
        let tv = Device.from(tv: record, onNetwork: true, kept: false)
        let put = Date(timeIntervalSince1970: 1_800_000_000)
        let line = DeviceNote.tv(previewOpen: true, chosen: tv.udid, tvs: [tv],
                                 onTV: [tv.udid: Runtime.OnTV(at: put, fingerprint: "old")], current: "new")
        XCTAssertTrue(line.contains("The TV preview, a window on this Mac with a remote's keys, is open now"))
        XCTAssertTrue(line.contains("webOS version unknown, screen size unknown"))
        XCTAssertTrue(line.contains("is chosen under Try On"))
        XCTAssertTrue(line.contains("Lamp finds it on the network now"))
        XCTAssertTrue(line.contains("at \(put.formatted(date: .abbreviated, time: .shortened)), and the code has changed since"))
        XCTAssertTrue(line.contains("Whether the app is running on a TV now, and how it looks or runs there, Lamp doesn't know."))
        // Only the preview, with no TV chosen or found, has nothing to say of a TV.
        let alone = DeviceNote.tv(previewOpen: false, chosen: nil, tvs: [], onTV: [:], current: "")
        XCTAssertEqual(alone, "The TV preview, a window on this Mac with a remote's keys, is closed now; look_at_app and use_app reach only the preview. Try On points at the preview, so Play opens the app there. No TV of the person's has been found on the network.")
    }
}
