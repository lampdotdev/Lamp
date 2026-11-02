import XCTest
@testable import Lamp

/// A device Lamp only found on the network may be a neighbor's: it's told apart from the person's own, set up with Lamp,
/// in what the agent and the naming call are told, on the desk, and in which device an app goes on by itself.
@MainActor
final class PossibleDevicesTests: XCTestCase {
    /// A TV that answered the network's scan and was never set up.
    private let foundTV = Device.from(tv: TVs.Record(id: "lg:found-0001", maker: "LG", name: "Upstairs TV", model: "OLED55",
                                                    modelID: "OLED55C1", address: "10.0.0.31", os: "webOS", osVersion: "8.0",
                                                    resolution: "3840x2160"), onNetwork: true, kept: false)
    /// A TV set up with Lamp, away from the network just now.
    private let keptTV = Device.from(tv: TVs.Record(id: "lg:kept-0001", maker: "LG", name: "Den TV", model: "NANO80",
                                                   modelID: "NANO80UPA", address: "10.0.0.32", os: "webOS", osVersion: "7.0",
                                                   resolution: "3840x2160"), onNetwork: false, kept: true)

    private func roku(_ serial: String, kept: Bool, address: String) -> Device {
        if kept {
            return Integrations.device(from: Integrations.Kept(id: "roku:\(serial)", integration: "roku", name: "Roku \(serial)", model: "Roku Ultra",
                                                               modelID: "4850X", os: "Roku OS", osVersion: "14.0", address: address, passed: ["developer-mode"]),
                                       onNetwork: true)
        }
        var device = Device(id: "roku:\(serial)", kind: .other, maker: "Roku", model: "Roku Ultra", modelID: "4850X", name: "Roku \(serial)",
                            os: "Roku OS", osVersion: "14.0", reach: .network)
        device.integration = "roku"
        device.address = address
        return device
    }

    private func rokuApp(chosen: String? = nil) -> LampProject {
        var project = LampProject(id: "roku-app", name: "Channel", exe: "Channel", dir: URL(fileURLWithPath: "/tmp/roku-app"))
        project.integration = "roku"
        project.device = chosen
        return project
    }

    // MARK: Which device an app goes on by itself

    func testTheOnlyDeviceFoundIsNotTakenForThePersonsOwn() {
        XCTAssertNil(DeviceApps.device(for: rokuApp(), among: [roku("FOUND", kept: false, address: "10.0.0.41")]))
    }

    func testTheOnlyDeviceSetUpIsChosenBesideOnesOnlyFound() {
        let mine = roku("MINE", kept: true, address: "10.0.0.42")
        XCTAssertEqual(DeviceApps.device(for: rokuApp(), among: [roku("FOUND", kept: false, address: "10.0.0.41"), mine])?.id, mine.id)
    }

    func testAChoiceSinceForgottenAndGoneFallsToTheOneSetUp() {
        let mine = roku("MINE", kept: true, address: "10.0.0.42")
        XCTAssertEqual(DeviceApps.device(for: rokuApp(chosen: "roku:FORGOTTEN"), among: [mine])?.id, mine.id)
    }

    // MARK: What the agent is told

    func testTheDevicesLineCallsOnlyThoseSetUpThePersons() {
        let text = Places.known([foundTV, keptTV])
        let theirs = text.components(separatedBy: "not set up with Lamp").first ?? text
        XCTAssertTrue(theirs.contains("Den TV"), text)
        XCTAssertFalse(theirs.contains("Upstairs TV"), text)
        // Still told, with what it can run.
        XCTAssertTrue(text.contains("Upstairs TV (Samsung / LG TV)"), text)
    }

    func testTheTVLineNeverCallsAFoundTVThePersons() {
        let text = DeviceNote.tv(previewOpen: false, chosen: nil, tvs: [foundTV, keptTV], onTV: [:], current: "")
        XCTAssertTrue(text.contains("The person's Den TV"), text)
        XCTAssertFalse(text.contains("The person's Upstairs TV"), text)
        XCTAssertTrue(text.contains("Upstairs TV"), text)
    }

    func testNetworkDevicesPutsFoundOnesApartAndKeepsWhatLampCanDoWithThem() {
        let rokuFound = roku("FOUND", kept: false, address: "10.0.0.41")
        var tvHere = keptTV
        tvHere.connected = true
        let text = NetworkDevices.describe([foundTV, tvHere, rokuFound], integrations: [])
        let theirs = text.components(separatedBy: "not set up with Lamp").first ?? text
        XCTAssertTrue(theirs.contains("Den TV"), text)
        XCTAssertFalse(theirs.contains("Upstairs TV"), text)
        XCTAssertFalse(theirs.contains("Roku FOUND"), text)
        // A Roku is controlled without being set up; a found TV is still one Lamp puts apps on.
        XCTAssertTrue(text.contains("controls it with `LampRoku`"), text)
        XCTAssertTrue(text.contains("Lamp puts TV apps on it once it's set up"), text)
    }

    // MARK: Naming a wish

    func testTheNamingCallReadsMyTVAsTheOneSetUp() {
        let text = AppName.seen([foundTV, keptTV])
        let theirs = text.components(separatedBy: "not set up with Lamp").first ?? text
        XCTAssertTrue(theirs.contains("Den TV"), text)
        XCTAssertFalse(theirs.contains("Upstairs TV"), text)
        XCTAssertTrue(text.contains("Upstairs TV"), text)
    }

    // MARK: The desk's devices

    func testYourDevicesKeepsFoundOnesOutOfThePersons() {
        let rokuFound = roku("FOUND", kept: false, address: "10.0.0.41"), rokuMine = roku("MINE", kept: true, address: "10.0.0.42")
        let list = HomeNetwork.List(devices: [foundTV, keptTV, rokuFound, rokuMine], hosts: [])
        XCTAssertEqual(Set(list.works.map(\.id)), [keptTV.id, rokuMine.id])
    }

    /// A device only found offers Set Up… on the desk: its first setup step is for the setup window. One set up with
    /// Lamp and ready offers none; Forget and Reconnect are for the ones Lamp set up itself.
    func testAFoundDeviceOffersSetUp() {
        let rokuFound = roku("FOUND", kept: false, address: "10.0.0.41")
        XCTAssertTrue(DeskDevices.offersSetUp(foundTV, team: ""))
        XCTAssertTrue(DeskDevices.offersSetUp(rokuFound, team: ""))
        XCTAssertFalse(DeskDevices.offersSetUp(Device(id: Device.macID, kind: .mac, maker: "Apple", model: "Mac", modelID: "", name: "This Mac",
                                                      os: "macOS", osVersion: "27", reach: .thisMac), team: ""))
    }

    /// A found device an app can already control, a Sonos speaker, offers Set Up… like every other found device.
    func testAFoundDeviceAnAppControlsOffersSetUpLikeTheRest() {
        let sonos = Device(id: "net:10.0.0.51", kind: .other, maker: "Sonos", model: "One", modelID: "S18", name: "Kitchen",
                           os: "", osVersion: "", reach: .network)
        let list = HomeNetwork.List(devices: [sonos], hosts: [])
        XCTAssertEqual(list.possible.map(\.id), [sonos.id])
        XCTAssertNotNil(list.controls[sonos.id])
        XCTAssertTrue(DeskDevices.offersSetUp(sonos, team: ""))
    }

    /// A TV chosen under Try On and forgotten since keeps a way into its setup beside its ticked row.
    func testAChosenDeviceSinceForgottenKeepsItsSetup() {
        XCTAssertNotNil(TryOnMenu.setUpAgain(foundTV, id: "tvsetup:\(foundTV.udid)", chosen: true))
        XCTAssertNil(TryOnMenu.setUpAgain(foundTV, id: "tvsetup:\(foundTV.udid)", chosen: false))
    }

    /// An away device's last address doesn't make whatever answers there now the person's.
    func testTheDeviceCardGoesByWhatAnswersAtTheAddressNow() {
        var newcomer = foundTV
        newcomer.address = keptTV.address
        XCTAssertFalse(DevicePermissions.setUp(at: "10.0.0.32", among: [keptTV, newcomer]))
        var keptHere = keptTV
        keptHere.connected = true
        XCTAssertTrue(DevicePermissions.setUp(at: "10.0.0.32", among: [keptHere]))
    }
}
