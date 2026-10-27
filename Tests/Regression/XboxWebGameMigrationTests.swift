import XCTest
@testable import Lamp

/// A game made as the Xbox's web app, before games were a kind of their own, is read as a game at home on the Mac with
/// the Xbox one of its places, once, with a line in its chat; an Xbox app that isn't a game stays the Xbox's.
@MainActor
final class XboxWebGameMigrationTests: XCTestCase {
    private var root: URL!

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func oldXboxWish(_ id: String, game: Bool) throws -> URL {
        let dir = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Web"), withIntermediateDirectories: true)
        try #"{"name":"\#(id)","exe":"\#(id)","platform":"device","integration":"xbox-one","device":"xbox-one:console"}"#
            .write(to: dir.appendingPathComponent(".lamp/meta.json"), atomically: true, encoding: .utf8)
        try "xbox-one\n".write(to: dir.appendingPathComponent(DeviceApps.marker), atomically: true, encoding: .utf8)
        try "<script type=\"importmap\">{\"imports\":{\"three\":\"./three/three.module.js\"}}</script>"
            .write(to: dir.appendingPathComponent("Web/index.html"), atomically: true, encoding: .utf8)
        try #"{"symbol":"flame.fill","game":\#(game)}"#.write(to: dir.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
        return dir
    }

    func testAnOldXboxWebGameBecomesAGameAtHomeOnTheMac() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-xbox-game-\(UUID().uuidString)")
        let gameDir = try oldXboxWish("City", game: true)
        let appDir = try oldXboxWish("Menus", game: false)

        let game = try XCTUnwrap(Store.readWish(at: gameDir))
        XCTAssertEqual(game.platform, .game)
        XCTAssertEqual(game.openPlaces, [.mac, .device])
        XCTAssertEqual(game.destination, .mac)
        XCTAssertEqual(game.device, "xbox-one:console", "the console it's on stays the one chosen for the Xbox")
        XCTAssertEqual(game.integration, GameKit.xbox, "installed on the Xbox as its web app, as a game")
        XCTAssertEqual(GameKit.engine(game), .web)
        XCTAssertTrue(Store.placesToAdd(game).contains(.ios))
        XCTAssertEqual(Targets.kind(of: gameDir), .game, "a restored version reads as a game too")
        XCTAssertTrue(GameKit.ownsLoop(game), "its page has no game() to script, so it's looked at in the page preview")

        // Once: read again, it's the game it was saved as, and its chat says so a single time.
        XCTAssertEqual(Store.readWish(at: gameDir)?.platform, .game)
        let chat = try XCTUnwrap(LogLine.readChat(gameDir.appendingPathComponent(".lamp/chat.json"))).lines
        XCTAssertEqual(chat.count, 1)
        XCTAssertTrue(chat[0].text.contains("is a game now"), chat[0].text)

        // Try On has the Mac, the Xbox and the places to add, not the device app's menu.
        let store = Store(testingAt: root)
        let menu = try XCTUnwrap(TryOnMenu.make(for: try XCTUnwrap(store.projects.first { $0.id == game.id }), store: store))
        let ids = menu.sections.flatMap(\.items).map(\.id)
        XCTAssertTrue(ids.contains("mac") && ids.contains("add:ios"), "\(ids)")

        let app = try XCTUnwrap(Store.readWish(at: appDir))
        XCTAssertEqual(app.platform, .device, "an Xbox app that isn't a game stays the Xbox's")
        // Its menu still reaches another device.
        let appMenu = try XCTUnwrap(TryOnMenu.make(for: try XCTUnwrap(store.projects.first { $0.id == app.id }), store: store))
        XCTAssertTrue(appMenu.sections.flatMap(\.items).contains { $0.id == TryOnMenu.another.id })
    }
}
