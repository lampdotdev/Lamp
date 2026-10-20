import XCTest
@testable import Lamp

/// Lamp builds, signs and installs an iPhone app on the person's own phone chosen under Try On, with a free Apple
/// account. The prompts say so, and the first iPhone look says what Try On is set to and what the device list holds.
@MainActor
final class PhoneTryOnNoteTests: XCTestCase {
    private let phone = Devices.Device(udid: "00008110-TEST", name: "Test iPhone", model: "iPhone 16",
                                       connected: true, paired: true, developerMode: true)

    func testThePromptsSayTheAppCanGoOnTheChosenPhone() {
        for prompt in [Agent.iPhonePrompt(for: .iphone), Agent.universalPrompt(for: .iphone)] {
            XCTAssertFalse(prompt.contains("can't be put on a real device"))
            XCTAssertTrue(prompt.contains("install the app on the person's own iPhone or iPad, the one chosen under Try On"))
            XCTAssertTrue(prompt.contains("with a free Apple account"))
        }
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
