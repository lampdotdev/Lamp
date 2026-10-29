import XCTest
@testable import Lamp

/// A game on an iPhone or iPad serves its own phone page, so the page has to be in what's built for it: the
/// simulator's bundle (written into the app's own folder) and the copy of the app's files Xcode builds a device's app
/// from (in Lamp's folder), with the device project naming it as a resource. The page is made in the temporary folder
/// first, so putting it in place copies from one folder into another.
final class GamePhonesIOSTests: XCTestCase {
    private var work: URL!
    private var game: LampProject!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-game-phones-ios-\(UUID().uuidString)")
        let dir = work.appendingPathComponent("padgame")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        var game = LampProject(id: "padgame-\(UUID().uuidString.prefix(8))", name: "Pad Game", exe: "PadGame", dir: dir)
        game.platform = .game
        game.places = [.mac, .ios]
        self.game = game
        // The page as a build publishes it (`TVs.stagePhone`).
        let published = TVs.phoneFolder(for: game)
        try FileManager.default.createDirectory(at: published, withIntermediateDirectories: true)
        try Data("<title>Pad</title>".utf8).write(to: published.appendingPathComponent("index.html"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
        if let game { try? FileManager.default.removeItem(at: TVs.stagingFolder(for: game)) }
    }

    func testTheSimulatorsBundleGetsThePhonePage() throws {
        XCTAssertTrue(GamePhones.bundlesOnIOS(game))
        let app = game.dir.appendingPathComponent("build/iOS/PadGame.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try GamePhones.write(game, to: app.appendingPathComponent(GamePhones.iosFolder), in: game.dir)
        let phone = app.appendingPathComponent("Phone")
        XCTAssertEqual(try String(contentsOf: phone.appendingPathComponent("index.html"), encoding: .utf8), "<title>Pad</title>")
        XCTAssertTrue(FileManager.default.fileExists(atPath: phone.appendingPathComponent("lamp-controller.js").path))
    }

    func testADevicesBuildGetsThePhonePageAndItsProjectNamesIt() throws {
        // Where `Devices.stage` copies the app's files for Xcode, in Lamp's folder.
        let files = work.appendingPathComponent("Phone Builds/padgame/app")
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        try GamePhones.write(game, to: files.appendingPathComponent(GamePhones.iosFolder), in: files)
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.appendingPathComponent("Phone/index.html").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.appendingPathComponent("Phone/lamp-controller.js").path))

        let project = Template.withPhoneFolder(Template.devicePbxproj)
        XCTAssertTrue(project.contains("/* Phone in Resources */ = {isa = PBXBuildFile;"))
        XCTAssertTrue(project.contains("name = Phone; path = ../../Phone;"))
        XCTAssertTrue(project.contains("files = (A00000000000000000000001 /* Assets in Resources */, E00000000000000000000003 /* Phone in Resources */,"))
    }
}
