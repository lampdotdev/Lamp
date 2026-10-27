import XCTest
@testable import Lamp

/// A wish that has an app gets another only from a call that asks for one (`another`): a call that names no app is
/// refused, so a change of mind changes the app it has. Each runs `make_app_for` as the agent calls it, on a Store over
/// a folder of its own.
@MainActor
final class MoreAppsTests: XCTestCase {
    private var root: URL!
    private var wishes: [LampProject] = []

    override func setUpWithError() throws {
        // Under the home folder, as Lamp keeps its wishes: a wish's folder is written only where no link leads on the way.
        root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-app-additions-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A Mac wish whose own folder holds its app, with a Store over it.
    private func macWish() throws -> (Store, LampProject) {
        let wish = try Template.scaffold(name: "Water", platform: .mac, in: root)
        wishes.append(wish)
        let store = Store(testingAt: root)
        return (store, try XCTUnwrap(store.current(wish)))
    }

    private func call(_ store: Store, _ wish: LampProject, _ extra: [String: Any] = [:]) async -> (Int, String) {
        let (status, answer) = await store.agentKind(["made": "native", "devices": ["mac"]].merging(extra) { $1 }, for: wish)
        return (status, answer["text"] as? String ?? answer["error"] as? String ?? "")
    }

    private func folders(_ wish: LampProject) -> [String] { Parts.folders(in: wish.dir) }

    /// "Actually never mind, make it a timer instead": with no `app`, nothing is added, and the reply says how to change
    /// the app the wish has; with `app` it's that app changed, and the wish still has one.
    func testAChangeOfMindNeverAddsAnApp() async throws {
        let (store, wish) = try macWish()
        let (status, text) = await call(store, wish)
        XCTAssertEqual(status, 400)
        XCTAssertTrue(text.contains("`app`") && text.contains("Nothing changed"), text)
        XCTAssertTrue(text.contains("`ask`"), "the refusal says to ask the person before adding: \(text)")
        XCTAssertEqual(folders(wish), [])
        let (changed, said) = await call(store, wish, ["app": "."])
        XCTAssertEqual(changed, 200)
        XCTAssertTrue(said.contains("nothing was added"), said)
        XCTAssertEqual(folders(wish), [])
        XCTAssertEqual(store.apps(of: try XCTUnwrap(store.current(wish))).count, 1)
    }

    /// "I want a second Mac app": `another` adds exactly one app, in a folder of its own, the wish's app staying as it
    /// is. The same call again in the same request is that app, never a third; a new request asking again adds one more.
    func testAnotherAppIsAddedOncePerRequest() async throws {
        let (store, wish) = try macWish()
        let (added, said) = await call(store, wish, ["another": true])
        XCTAssertEqual(added, 200, said)
        XCTAssertEqual(folders(wish), ["Mac2"])
        XCTAssertNil(store.logs[wish.id]?.last { $0.ask != nil }, "Lamp puts up no card of its own")
        let (again, repeated) = await call(store, wish, ["another": true])
        XCTAssertEqual(again, 200)
        XCTAssertTrue(repeated.hasPrefix("Already done"), repeated)
        XCTAssertEqual(folders(wish), ["Mac2"])
        // Another app for other devices in the same request is one more.
        _ = await call(store, wish, ["another": true, "devices": ["mac", "iphone"]])
        XCTAssertEqual(Set(folders(wish)), ["Mac2", "Apple2"])

        store.requestBegins(for: wish)
        _ = await call(store, wish, ["another": true])
        XCTAssertEqual(folders(wish).count, 3, "\(folders(wish))")
    }

    /// What isn't a plain choice is refused before anything is written: a blank, unknown or malformed `app`, `app` with
    /// `another`, and a malformed `another`.
    func testMalformedCallsChangeNothing() async throws {
        let (store, wish) = try macWish()
        for extra: [String: Any] in [["app": ""], ["app": "  "], ["app": "Mac9"], ["app": 5], ["app": ".", "another": true], ["another": "yes"]] {
            let (status, text) = await call(store, wish, extra)
            XCTAssertEqual(status, 400, "\(extra): \(text)")
            XCTAssertTrue(text.contains("Nothing changed"), text)
        }
        XCTAssertEqual(folders(wish), [])
        XCTAssertEqual(store.logs[wish.id]?.contains { $0.ask != nil } ?? false, false)
    }

    /// An app still to be made from a list an earlier Lamp kept, with no folder of its own, can be changed by the folder
    /// it will be made in, which the refusal names; changing it gives it that folder on the list.
    func testAnOlderWaitingAppCanBeNamed() async throws {
        let (store, made) = try macWish()
        var wish = made
        wish.apps = [WishApp(kind: .mac, folder: "."), WishApp(kind: .android, needs: "Android Studio")]
        try Template.saveMeta(wish)
        let fresh = Store(testingAt: root)
        let current = try XCTUnwrap(fresh.current(wish))
        let (refused, said) = await fresh.agentKind(["made": "native", "devices": ["android"]], for: current)
        XCTAssertEqual(refused, 400)
        XCTAssertTrue(said["error"].map { "\($0)".contains("\"Android\"") } == true, "\(said)")
        let (status, answer) = await fresh.agentKind(["made": "native", "devices": ["android"], "app": "Android"], for: current)
        XCTAssertEqual(status, 200, "\(answer)")
        XCTAssertEqual(try XCTUnwrap(fresh.current(wish)).apps.map(\.folder), [".", "Android"])
        _ = store
    }

    /// An older waiting app changed into another kind is that app changed: its entry takes the new kind, and no app of
    /// the old one stays to be made.
    func testAnOlderWaitingAppChangedIntoAnotherKindReplacesIt() async throws {
        let (_, made) = try macWish()
        var wish = made
        wish.apps = [WishApp(kind: .mac, folder: "."), WishApp(kind: .android, needs: "Android Studio")]
        try Template.saveMeta(wish)
        let store = Store(testingAt: root)
        let (status, answer) = await store.agentKind(["made": "web", "devices": ["mac", "ipad"], "app": "Android"], for: try XCTUnwrap(store.current(wish)))
        XCTAssertEqual(status, 200, "\(answer)")
        let apps = try XCTUnwrap(store.current(wish)).apps
        XCTAssertEqual(apps.map(\.folder), [".", "Android"])
        XCTAssertFalse(apps.contains { $0.kind == .android }, "\(apps)")
    }

    /// Cancelling one of two waiting apps of a family, one from an earlier Lamp's list, takes away that one alone.
    func testCancellingOneWaitingAppLeavesTheOther() async throws {
        let (_, made) = try macWish()
        var wish = made
        wish.apps = [WishApp(kind: .mac, folder: "."), WishApp(kind: .android, needs: "Android Studio"),
                     WishApp(kind: .android, needs: "Android Studio", folder: "Android2")]
        try Template.saveMeta(wish)
        let store = Store(testingAt: root)
        let (status, answer) = await store.agentRemove(["app": "Android2"], for: try XCTUnwrap(store.current(wish)))
        XCTAssertEqual(status, 200, "\(answer)")
        XCTAssertEqual(try XCTUnwrap(store.current(wish)).apps.map(\.folder), [".", "Android"])
    }

    /// Shared files an earlier Lamp kept for an older waiting app's family go with it when it's given its folder, even
    /// when the folder they had is taken now (iPhone/ there, so iPhone2/).
    func testAnOlderWaitingAppsKeptFilesFollowItsNewFolder() async throws {
        var wish = try Template.scaffold(name: "Remote", platform: .tv, in: root)
        wishes.append(wish)
        wish.apps = [WishApp(kind: .tv, folder: "."), WishApp(kind: .iphone, needs: "Xcode")]
        try Template.saveMeta(wish)
        try FileManager.default.createDirectory(at: wish.dir.appendingPathComponent("iPhone"), withIntermediateDirectories: true)
        let family = Sharing.waitingFolder(in: wish.dir, for: .iphone)
        try FileManager.default.createDirectory(at: family, withIntermediateDirectories: true)
        try #"{"platform":"iphone","folder":"iPhone"}"#.write(to: family.appendingPathComponent("lamp-part.json"), atomically: true, encoding: .utf8)
        let store = Store(testingAt: root)
        guard case .ready(let given) = store.givingWaitingAppsFolders(try XCTUnwrap(store.current(wish))) else { return XCTFail() }
        XCTAssertEqual(given.apps.map(\.folder), [".", "iPhone2"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: family.path))
        XCTAssertEqual(Sharing.keptFolder(in: wish.dir, for: .iphone, slot: "iPhone2"), "iPhone")
    }

    /// The same, stopped part way: with the files' note naming their slot and the list saved, but the files not moved
    /// yet, they're still found from that slot; with only the note written, the slot it names is the one given again.
    func testAnOlderWaitingAppsKeptFilesAreFoundAfterAStopPartWay() async throws {
        var wish = try Template.scaffold(name: "Remote", platform: .tv, in: root)
        wishes.append(wish)
        try FileManager.default.createDirectory(at: wish.dir.appendingPathComponent("iPhone"), withIntermediateDirectories: true)
        let family = Sharing.waitingFolder(in: wish.dir, for: .iphone)
        try FileManager.default.createDirectory(at: family, withIntermediateDirectories: true)
        try #"{"platform":"iphone","folder":"iPhone"}"#.write(to: family.appendingPathComponent("lamp-part.json"), atomically: true, encoding: .utf8)
        // Stopped after the note: the list still has no folder.
        XCTAssertEqual(Sharing.markKept(in: wish.dir, for: .iphone, slot: "iPhone7"), .marked)
        wish.apps = [WishApp(kind: .tv, folder: "."), WishApp(kind: .iphone, needs: "Xcode")]
        try Template.saveMeta(wish)
        // Stopped after the list too: the files are where they were, found from the slot all the same.
        XCTAssertEqual(Sharing.keptFolder(in: wish.dir, for: .iphone, slot: "iPhone7"), "iPhone")
        let store = Store(testingAt: root)
        guard case .ready(let given) = store.givingWaitingAppsFolders(try XCTUnwrap(store.current(wish))) else { return XCTFail() }
        XCTAssertEqual(given.apps.map(\.folder), [".", "iPhone7"])
        XCTAssertEqual(Sharing.keptFolder(in: wish.dir, for: .iphone, slot: "iPhone7"), "iPhone")
        XCTAssertFalse(FileManager.default.fileExists(atPath: family.path))
    }

    /// Kept files whose note can't be written to name their slot stop it: the list keeps the app with no folder, so the
    /// files are still found as they were.
    func testAnOlderWaitingAppKeepsNoFolderWhenItsFilesCantBeNoted() async throws {
        var wish = try Template.scaffold(name: "Remote", platform: .tv, in: root)
        wishes.append(wish)
        try FileManager.default.createDirectory(at: wish.dir.appendingPathComponent("iPhone"), withIntermediateDirectories: true)
        let family = Sharing.waitingFolder(in: wish.dir, for: .iphone)
        try FileManager.default.createDirectory(at: family, withIntermediateDirectories: true)
        try #"{"platform":"iphone","folder":"iPhone"}"#.write(to: family.appendingPathComponent("lamp-part.json"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: family.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: family.path) }
        wish.apps = [WishApp(kind: .tv, folder: "."), WishApp(kind: .iphone)]
        try Template.saveMeta(wish)
        let store = Store(testingAt: root)
        XCTAssertEqual(store.givingWaitingAppsFolders(try XCTUnwrap(store.current(wish))), .failed)
        // Nor does anything else act on the wish's apps meanwhile: Lamp's own retry makes nothing, and make_app_for refuses.
        await store.makeWaitingParts(of: try XCTUnwrap(store.current(wish)))
        XCTAssertEqual(Parts.folders(in: wish.dir), [])
        let (status, _) = await store.agentKind(["made": "native", "devices": ["iphone"], "app": "iPhone"], for: try XCTUnwrap(store.current(wish)))
        XCTAssertEqual(status, 500)
        let given = try XCTUnwrap(store.current(wish))
        XCTAssertEqual(given.apps.map(\.folder), [".", nil])
        XCTAssertEqual(given.apps.map(\.kind), [.tv, .iphone])
        XCTAssertEqual(try XCTUnwrap(Store.readWish(at: wish.dir)).apps.map(\.folder), [".", nil])
        XCTAssertEqual(Sharing.keptFolder(in: wish.dir, for: .iphone), "iPhone")
    }

    /// The planner alone: a wish with no app gets its first, and an app still to be made counts as one the wish has.
    func testAWaitingAppCountsAsAnApp() throws {
        let waiting = AppKinds.member(waiting: WishApp(kind: .mac, needs: "Xcode", folder: "Mac"))
        guard case .success(.first) = AppPlanner.decide(app: nil, another: nil, in: []) else { return XCTFail() }
        guard case .failure = AppPlanner.decide(app: nil, another: nil, in: [waiting]) else { return XCTFail("a waiting app is an app") }
        guard case .success(.another) = AppPlanner.decide(app: nil, another: true, in: [waiting]) else { return XCTFail() }
        guard case .success(.change(let member)) = AppPlanner.decide(app: "mac", another: false, in: [waiting]) else { return XCTFail() }
        XCTAssertEqual(member.slot, "Mac")
    }
}
