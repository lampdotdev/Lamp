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

    func testAnUnknownDeviceIsReadFromTheDescriptionThatNamesIt() async throws {
        let device = await Integrations.described(address, answers: try answers()) { request, _ in
            self.description(port: request.port).map { DeviceHTTP.Answer(status: 200, body: $0) }
        }
        XCTAssertEqual(device?.name, "[LG] webOS TV NANO80ASA")
        XCTAssertEqual(device?.id, "found:192.168.1.20")
    }
}
