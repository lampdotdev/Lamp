import XCTest
@testable import Lamp

/// Lamp puts an iPhone app on the person's own phone when it's chosen under Try On, free Apple account or not.
/// An agent once told someone it couldn't; it should say where the app goes, or ask for a phone to be connected.
@MainActor
final class PhoneTryOnNoteTests: XCTestCase {
    private let phone = Devices.Device(udid: "00008110-TEST", name: "Test iPhone", model: "iPhone 16",
                                       connected: true, paired: true, developerMode: true)

    func testThePromptsNeverSayAPhoneCantHaveTheApp() {
        for prompt in [Agent.iPhonePrompt(for: .iphone), Agent.universalPrompt(for: .iphone)] {
            XCTAssertFalse(prompt.contains("can't be put on a real device"))
            XCTAssertTrue(prompt.contains("even with a free Apple account"))
        }
    }

    func testAChosenPhoneThatsThereGetsTheApp() {
        let note = Devices.tryOnNote(chosen: phone.udid, among: [phone])
        XCTAssertTrue(note.contains("Test iPhone"))
        XCTAssertTrue(note.contains("puts the app on it"))
    }

    func testNoPhoneMeansTheSimulatorAndAnAskToConnectOne() {
        let note = Devices.tryOnNote(chosen: nil, among: [])
        XCTAssertTrue(note.contains("in the simulator"))
        XCTAssertTrue(note.contains("doesn't see their iPhone or iPad connected"))
        XCTAssertTrue(note.contains("plug it in"))
    }

    func testAChosenPhoneThatsGoneIsAskedFor() {
        let note = Devices.tryOnNote(chosen: phone.udid, among: [])
        XCTAssertTrue(note.contains("doesn't see it now"))
        XCTAssertTrue(note.contains("connect it"))
    }
}
