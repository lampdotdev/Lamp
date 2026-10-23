import XCTest
@testable import Lamp

/// An LG TV answers an SSDP search for five services, each pointing at a description of its own, and the first to
/// answer is usually Netflix's, whose description is nine bytes of "status=ok". The answers and descriptions in
/// Tests/Fixtures/lg-webos-tv are a webOS TV's own, recorded on 2026-10-22 in the order they came, with its
/// address, ids and hardware addresses replaced.
final class LGDiscoveryTests: XCTestCase {
    private let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/lg-webos-tv")
    private let address = "192.168.1.20"

    private func answers() throws -> [DeviceProbe.SSDPAnswer] {
        try String(contentsOf: folder.appendingPathComponent("ssdp.txt"), encoding: .utf8)
            .components(separatedBy: "\n\n").map { DeviceProbe.answer($0, from: address) }
    }

    private func description(port: Int?) -> Data? {
        try? Data(contentsOf: folder.appendingPathComponent("\(port ?? 80).xml"))
    }

    func testTheTVIsFoundThroughItsOwnServiceWhenNetflixAnswersFirst() async throws {
        let answers = try answers()
        XCTAssertEqual(answers.first?.location, "http://192.168.1.20:9080")
        let record = await TVs.lg(at: address, answers: answers) { self.description(port: $0.port) }
        XCTAssertEqual(record?.id, "lg:11111111-2222-4333-8444-000000001904")
        XCTAssertEqual(record?.name, "[LG] webOS TV NANO80ASA")
        XCTAssertEqual(record?.model, "65NANO80ASA.BWCDLKR")
    }

    func testTheTVKeepsItsIDWhenItsOwnServiceMissesAScan() async throws {
        let all = try answers()
        let found = await TVs.lg(at: address, answers: all) { self.description(port: $0.port) }
        let first = try XCTUnwrap(found)
        let others = all.filter { $0.searchTarget != TVs.lgTV && !($0.location ?? "").contains(":1904") }
        let again = await TVs.lg(at: address, answers: others, earlier: [first]) { self.description(port: $0.port) }
        XCTAssertEqual(again?.id, first.id)
    }

    func testATVKeptUnderAnotherServicesIDKeepsThatID() async throws {
        // An earlier Lamp kept whichever description answered first: here the media renderer's.
        let kept = TVs.Record(id: "lg:11111111-2222-4333-8444-000000001601", maker: "LG", name: "[LG] webOS TV NANO80ASA",
                              model: "LG TV", modelID: "1.0", address: address, os: "webOS", osVersion: "", resolution: "")
        let record = await TVs.lg(at: address, answers: try answers(), earlier: [kept]) { self.description(port: $0.port) }
        XCTAssertEqual(record?.id, kept.id)
    }

    func testAnUnknownDeviceIsReadFromTheDescriptionThatNamesIt() async throws {
        let device = await Integrations.described(address, answers: try answers()) { request, _ in
            self.description(port: request.port).map { DeviceHTTP.Answer(status: 200, body: $0) }
        }
        XCTAssertEqual(device?.name, "[LG] webOS TV NANO80ASA")
        XCTAssertEqual(device?.id, "found:192.168.1.20")
    }

    /// The agent's line for a TV app is what Lamp has seen of this TV, and what it hasn't seen (its screen, whether
    /// the app runs there now) is said to be unknown.
    func testTheAgentIsToldWhatLampKnowsOfTheTVAndNoMore() async throws {
        let found = await TVs.lg(at: address, answers: try answers()) { self.description(port: $0.port) }
        let record = try XCTUnwrap(found)
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
