import XCTest
@testable import Lamp

/// A game's page is told the device it's on by the copy of the page Lamp makes for that device, from the device's row
/// in the table of devices: every way a copy is made resolves its own row, a copy made without one stops, and the
/// rows' and integrations' input is checked against Lamp's one list of controllers.
final class GamePageTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func shipped(_ id: String) throws -> (data: Data, integration: Integration) {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: source.appendingPathComponent("Resources/Devices/\(id).json"))
        return (data, try JSONDecoder().decode(Integration.self, from: data))
    }

    /// A game under the home folder, as a real one is, with Lamp's runtime in its page.
    private func game(chosen: Destination = .mac, family: DeviceFamily = .iphone) throws -> LampProject {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-game-page-test-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("Apps/hopper")
        try fm.createDirectory(at: dir.appendingPathComponent("Web"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "import SwiftUI".write(to: dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        try "<script type=module src=game.js></script>".write(to: dir.appendingPathComponent("Web/index.html"), atomically: true, encoding: .utf8)
        try "// runtime".write(to: dir.appendingPathComponent("Web/lamp-game.js"), atomically: true, encoding: .utf8)
        return LampProject(id: "hopper", name: "Hopper", exe: "Hopper", dir: dir, platform: .game, family: family,
                           chosen: chosen, places: [.mac, .ios, .android])
    }

    func testEachPlaceAGameIsBuiltForIsItsOwnRow() throws {
        XCTAssertEqual(try GamePage.place(for: game(chosen: .mac)).id, "mac")
        XCTAssertEqual(try GamePage.place(for: game(chosen: .ios, family: .ipad)).id, "iphone")
        XCTAssertEqual(try GamePage.place(for: game(chosen: .android)).id, "android")
        XCTAssertEqual(try GamePage.place(for: game(chosen: .ios), at: .mac).id, "mac", "the preview is played on this Mac")
        // Each row says which it is, so a copy carrying another device's facts is told apart even where they agree.
        let mac = try GamePage.descriptor(for: GamePage.place(for: game(chosen: .mac)))
        let phone = try GamePage.descriptor(for: GamePage.place(for: game(chosen: .ios)))
        XCTAssertNotEqual(mac, phone)
        XCTAssertTrue(phone.contains(#""Enter":"Return""#))
        XCTAssertTrue(try GamePage.descriptor(for: GamePage.place(for: game(chosen: .android))).contains(#"export default {"keys":{}};"#))
    }

    func testARealPhonesCopyOfThePageIsToldItsThePhone() async throws {
        let project = try game(chosen: .ios, family: .iphone)
        let source = try await Devices.stage(project, team: "ABCDE12345", in: try XCTUnwrap(root).appendingPathComponent("Phone Builds/hopper"))
        let told = try String(contentsOf: source.appendingPathComponent("Web/lamp-device.js"), encoding: .utf8)
        XCTAssertEqual(told, try GamePage.descriptor(for: XCTUnwrap(Places.builtIn.first { $0.id == "iphone" })))
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.dir.appendingPathComponent("Web/lamp-device.js").path),
                       "the app's own page holds no device")
    }

    func testTheXboxStartsOnItsControllerAndNamesEveryControllerByItsLayout() throws {
        let xbox = try XCTUnwrap(Places.row(for: try shipped("xbox-one").integration))
        XCTAssertEqual(xbox.input, Place.Input(controller: "xbox", layout: "xbox"))
        XCTAssertTrue(try GamePage.descriptor(for: xbox).contains(#"export default {"controller":"xbox","keys":{},"layout":"xbox"};"#))
    }

    func testARowThatDoesntSayItsInputHasNoGamePage() throws {
        var (data, _) = try shipped("xbox-one")
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["input"] = nil
        data = try JSONSerialization.data(withJSONObject: json)
        let row = try XCTUnwrap(Places.row(for: try JSONDecoder().decode(Integration.self, from: data)))
        XCTAssertThrowsError(try GamePage.descriptor(for: row))
        json["input"] = [String: Any]()
        let generic = try XCTUnwrap(Places.row(for: try JSONDecoder().decode(Integration.self, from: JSONSerialization.data(withJSONObject: json))))
        XCTAssertEqual(generic.input, .generic, "{} is a web view with a PC keyboard and no controller of its own")
    }

    func testAnInputNamesOnlyAControllerLampHasALayoutFor() throws {
        let (data, _) = try shipped("xbox-one")
        XCTAssertTrue(IntegrationCheck.problems(data, submitted: false).filter { $0.hasPrefix("input") }.isEmpty)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["input"] = ["controller": "xbox", "layout": "gamecube"]
        XCTAssertEqual(IntegrationCheck.problems(try JSONSerialization.data(withJSONObject: json), submitted: false).filter { $0.hasPrefix("input") }.count, 1)
        XCTAssertEqual(Set(Controllers.ids), ["xbox", "playstation", "switch"])
        XCTAssertTrue(Controllers.pageJS.contains(#""base":"xbox""#))
    }

    /// An integration's package step runs on Lamp's copy of the app: the device is written there, never in the app's
    /// own page, what builds leave behind isn't copied, and a copy whose runtime lost its device is refused.
    func testAnIntegrationsPackageIsMadeFromACopyToldItsDevice() async throws {
        let project = try game(chosen: .mac)
        try FileManager.default.createDirectory(at: project.dir.appendingPathComponent("build"), withIntermediateDirectories: true)
        try "old".write(to: project.dir.appendingPathComponent("build/app.zip"), atomically: true, encoding: .utf8)
        let xbox = try XCTUnwrap(Places.row(for: try shipped("xbox-one").integration))
        let source = try await DeviceApps.packageSource(project, in: try XCTUnwrap(root).appendingPathComponent("Device Builds/hopper"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("Web/lamp-game.js").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.appendingPathComponent("build").path))
        try GamePage.stage(source.appendingPathComponent("Web"), in: source, for: xbox)
        XCTAssertNoThrow(try GamePage.check(source, for: xbox))
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.dir.appendingPathComponent("Web/lamp-device.js").path))
        try "export default {};".write(to: source.appendingPathComponent("Web/lamp-device.js"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try GamePage.check(source, for: xbox), "another device's facts")
        try FileManager.default.removeItem(at: source.appendingPathComponent("Web/lamp-device.js"))
        XCTAssertThrowsError(try GamePage.check(source, for: xbox), "none at all")
    }

    /// A link in the app's folder can't take Lamp's write anywhere: the copy that holds one is refused, and staging a
    /// copy that kept one reads and writes nothing through it.
    func testALinkInTheAppCantCarryTheDeviceElsewhere() async throws {
        let project = try game(chosen: .mac)
        let other = try XCTUnwrap(root).appendingPathComponent("Apps/other/Web")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try "// runtime".write(to: other.appendingPathComponent("lamp-game.js"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: project.dir.appendingPathComponent("Web"))
        try FileManager.default.createSymbolicLink(at: project.dir.appendingPathComponent("Web"), withDestinationURL: other)
        let xbox = try XCTUnwrap(Places.row(for: try shipped("xbox-one").integration))
        let builds = try XCTUnwrap(root).appendingPathComponent("Device Builds/hopper")
        do {
            let source = try await DeviceApps.packageSource(project, in: builds)
            try GamePage.stage(source.appendingPathComponent("Web"), in: source, for: xbox)
            XCTFail("a copy holding a link was staged")
        } catch {}
        // And should a copy keep one, nothing is read or written through it.
        let kept = builds.appendingPathComponent("kept")
        try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: kept.appendingPathComponent("Web"), withDestinationURL: other)
        try? GamePage.stage(kept.appendingPathComponent("Web"), in: kept, for: xbox)
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.appendingPathComponent("lamp-device.js").path), "another game's folder was written")
    }

    /// An old package that came along in the copy is taken away before the step, so one that makes nothing fails.
    func testAnOldPackageInTheCopyIsTakenAway() throws {
        _ = try game()
        let source = try XCTUnwrap(root).appendingPathComponent("copy")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "old".write(to: source.appendingPathComponent("app.zip"), atomically: true, encoding: .utf8)
        let output = DeviceApps.freshOutput("app.zip", in: source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    /// Where Lamp can read the package (a ZIP), the device must be in it beside the runtime, as staged.
    func testAPackageWithoutTheDeviceBesideTheRuntimeIsRefused() throws {
        let xbox = try XCTUnwrap(Places.row(for: try shipped("xbox-one").integration))
        let runtime = (path: "lamp-game.js", data: Data("// runtime".utf8))
        XCTAssertThrowsError(try GamePage.check(payload: [runtime], for: xbox))
        XCTAssertThrowsError(try GamePage.check(payload: [runtime, ("lamp-device.js", Data("export default {};".utf8))], for: xbox))
        XCTAssertNoThrow(try GamePage.check(payload: [runtime, ("lamp-device.js", Data(try GamePage.descriptor(for: xbox).utf8))], for: xbox))
        XCTAssertNoThrow(try GamePage.check(payload: [("index.html", Data())], for: xbox), "a page that isn't a game's needs no device")
    }

    /// An iOS app built for an Apple TV or a Vision Pro is that device's, whose row shows no page: never the iPhone's.
    func testTheFamilyPicksTheRowBeforeAskingForAPage() throws {
        XCTAssertThrowsError(try GamePage.place(for: game(chosen: .ios, family: .appletv))) { error in
            XCTAssertTrue(error.localizedDescription.contains("Apple TV"), error.localizedDescription)
        }
        XCTAssertThrowsError(try GamePage.place(for: game(chosen: .ios, family: .vision)))
    }

    /// What the page is told is part of what the game is built from, so a change to the device's row builds it again.
    func testWhatThePageIsToldIsPartOfTheBuildsInputs() throws {
        let mac = try game(chosen: .mac), android = try game(chosen: .android)
        let inputs = { (project: LampProject) in project.platform.target.recipe.inputs(project) ?? "" }
        XCTAssertTrue(inputs(mac).hasSuffix(try GamePage.descriptor(for: GamePage.place(for: mac))))
        XCTAssertNotEqual(inputs(mac), inputs(android))
    }

    /// build.sh's one step for its copies: the page with the device it was handed, and no copy of a game's page without one.
    func testBuildShWritesTheDeviceItIsHandedAndStopsWithoutOne() throws {
        let project = try game(chosen: .android)
        let out = project.dir.appendingPathComponent("build/android-assets/Web")
        func run(_ env: [String: String]) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "set -euo pipefail\n" + GameKit.stagePageSh + "stage_page build/android-assets/Web"]
            process.currentDirectoryURL = project.dir
            process.environment = ["PATH": "/usr/bin:/bin"].merging(env) { $1 }
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
        let handed = try GamePage.buildEnvironment(for: project)
        XCTAssertEqual(try run(handed), 0)
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("lamp-device.js"), encoding: .utf8), handed["LAMP_PAGE_DEVICE"])
        XCTAssertNotEqual(try run([:]), 0, "a game's page isn't copied without the device it's for")
    }
}
