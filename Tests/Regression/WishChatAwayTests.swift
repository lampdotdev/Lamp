import XCTest
@testable import Lamp

/// A wish whose one app is a web app in a folder of its own, set to play on an Android TV: clicked on the desk, it is
/// used and its chat is shown, since once the app is running on the TV using it opens nothing on the Mac. Its web app
/// says it has a window wherever it plays, so where it plays is read from where Try On points.
@MainActor
final class WishChatAwayTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wish-chat-away-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// The wish's folder holds only the wish; its web app in WebApp/ has the places and Try On choice `make_app_for` and
    /// the Try On menu leave in its meta.json.
    private func clockWish(target: String, device: String?) throws -> (Store, LampProject) {
        let draft = try Template.draft(name: "Clock", in: root)
        let folder = draft.dir.appendingPathComponent("WebApp")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try ScreenKit.webAppPage.says.write(to: folder.appendingPathComponent(ScreenKit.webAppPage.marker), atomically: true, encoding: .utf8)
        var meta: [String: Any] = ["name": "Clock", "exe": "Clock", "platform": "web-app", "places": ["mac", "android-tv"], "target": target]
        if let device { meta["device"] = device }
        try JSONSerialization.data(withJSONObject: meta).write(to: folder.appendingPathComponent(".lamp/meta.json"))
        try "\(Parts.wishOnlyText)".write(to: draft.dir.appendingPathComponent(Parts.wishOnly), atomically: true, encoding: .utf8)
        let store = Store(testingAt: root)
        let wish = try XCTUnwrap(store.projects.first { $0.id == draft.id })
        XCTAssertFalse(wish.holdsApp)
        return (store, wish)
    }

    func testAWishWhoseWebAppPlaysOnAnAndroidTVShowsItsChat() throws {
        let (store, wish) = try clockWish(target: "android-tv", device: "android-tv:00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(store.apps(of: wish).map(\.destination), [.androidTV])
        // Why the place alone can't tell: a web app says it has a window wherever it plays.
        XCTAssertEqual(WishPlace.of(wish), .window)
        XCTAssertTrue(Store.playsAwayFromMac(store.apps(of: wish)))
    }

    func testAWishWhoseWebAppPlaysOnTheMacOpensBesideItsWindow() throws {
        let (store, wish) = try clockWish(target: "mac", device: nil)
        XCTAssertEqual(store.apps(of: wish).map(\.destination), [.mac])
        XCTAssertFalse(Store.playsAwayFromMac(store.apps(of: wish)))
    }
}
