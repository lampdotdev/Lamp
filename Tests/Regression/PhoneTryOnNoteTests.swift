import XCTest
@testable import Lamp

/// Lamp builds, signs and installs an iPhone app on the person's own phone chosen under Try On, with a free Apple
/// account. The prompts say so, and an iPhone preview result once per turn notes the Try On selection and Lamp's
/// device lookup.
@MainActor
final class PhoneTryOnNoteTests: XCTestCase {
    private let phone = Device(id: "00008110-TEST", kind: .iphone, maker: "Apple", model: "iPhone 16", modelID: "iPhone17,3",
                               name: "Test iPhone", os: "iOS", osVersion: "18.6", reach: .cable)

    func testThePromptsSayTheAppCanGoOnTheChosenPhone() {
        for prompt in [Agent.iPhonePrompt(for: .iphone), Agent.universalPrompt(for: .iphone)] {
            XCTAssertFalse(prompt.contains("can't be put on a real device"))
            XCTAssertTrue(prompt.contains("install the app on the person's own iPhone or iPad, the one chosen under Try On"))
            XCTAssertTrue(prompt.contains("with a free Apple account"))
        }
    }

    /// What Apple won't sign for a free team is named at the build, and nothing is said for a paid one.
    func testAFreeTeamIsToldWhatItCantSign() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-free-team-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try #"{"healthkit": true, "nfc": true, "siri": true}"#.write(to: dir.appendingPathComponent("capabilities.json"), atomically: true, encoding: .utf8)
        let app = LampProject(id: "tags", name: "Tags", exe: "Tags", dir: dir, platform: .iphone)
        XCTAssertEqual(TeamLimits.refused(in: app), ["NFC", "Siri"])
        XCTAssertEqual(TeamLimits.problem(for: app, on: "Test iPhone", team: "ABCDE12345", free: ["ABCDE12345"]),
                       "Tags uses NFC and Siri, which Apple allows only with a paid Apple Developer membership. Your Apple account is a free one, so Lamp can't put the app on Test iPhone. Choose a simulator under Try On to keep working, or ask Lamp to take them out.")
        XCTAssertNil(TeamLimits.problem(for: app, on: "Test iPhone", team: "ABCDE12345", free: []))
    }

    func testAChosenPhoneThatsListedIsWhereTryOnIsSet() {
        let note = Devices.tryOnNote(chosen: phone.udid, among: [phone])
        XCTAssertTrue(note.contains("Try On is set to the person's Test iPhone"))
        XCTAssertTrue(note.contains("Play builds, signs and installs the app there"))
    }

    func testAnEmptyListMeansTheSimulatorAndHowToConnectOne() {
        let note = Devices.tryOnNote(chosen: nil, among: [])
        XCTAssertTrue(note.contains("Try On is set to the simulator"))
        XCTAssertTrue(note.contains("device list returned no iPhone or iPad"))
        XCTAssertTrue(note.contains("connect and unlock it, choose it under Try On and press Play"))
    }

    func testAChosenPhoneTheListDidntReturnIsSaidSo() {
        let note = Devices.tryOnNote(chosen: phone.udid, among: [])
        XCTAssertTrue(note.contains("device list didn't return"))
        XCTAssertTrue(note.contains("connect and unlock it, then press Play"))
    }
}
