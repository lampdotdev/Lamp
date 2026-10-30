import XCTest
@testable import Lamp

final class DeskDevicesTests: XCTestCase {
    func testLabelsLeaveOutAddressesAndSerials() {
        var speaker = Device(id: "found:192.168.1.5", kind: .other, maker: "Sonos, Inc.", model: "SYMFONISK Bookshelf", modelID: "",
                             name: "192.168.1.5 - SYMFONISK Bookshelf - RINCON_38420B99FAFA01400", os: "", osVersion: "", reach: .network)
        XCTAssertEqual(DeskDevices.label(speaker), "SYMFONISK Bookshelf")
        speaker = Device(id: "found:192.168.1.6", kind: .other, maker: "Sonos, Inc.", model: "Play:1", modelID: "",
                         name: "192.168.1.6 - Play:1 - RINCON_7828CA96A6DE01400", os: "", osVersion: "", reach: .network)
        XCTAssertEqual(DeskDevices.label(speaker), "Sonos Play:1")
        XCTAssertEqual(speaker.symbol, "hifispeaker")
    }

    /// An Android TV or the emulator isn't called a phone in the wish it starts.
    func testAndroidWordsKeepWhatItIs() {
        var device = Device(id: "1", kind: .android, maker: "Google", model: "Chromecast", modelID: "", name: "Chromecast",
                            os: "Android", osVersion: "14", reach: .network)
        device.features = ["tv"]
        XCTAssertEqual(DeskDevices.words(for: device), "Android TV")
        device = Device(id: "2", kind: .androidEmulator, maker: "Google", model: "sdk", modelID: "", name: "Emulator",
                        os: "Android", osVersion: "14", reach: .thisMac)
        XCTAssertEqual(DeskDevices.words(for: device), "Android emulator")
    }

    func testNamesKeepTheRoom() {
        XCTAssertEqual(DeskDevices.names("192.168.1.5 - Kitchen - RINCON_38420B99FAFA01400"), ["Kitchen"])
    }
}
