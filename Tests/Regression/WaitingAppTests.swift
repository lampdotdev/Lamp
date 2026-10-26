import XCTest
@testable import Lamp

/// An app the wish waits for is made later by the path an app made at once takes: an iPhone app asked for with its
/// watch, put off, is told to add its watch app when it's made, and that stays to be told until a request carrying it
/// has reached the agent.
@MainActor
final class WaitingAppTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        // Under the home folder, where Lamp writes a wish's folders: the temporary folder's way there is a link.
        root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-waiting-app-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAWaitingIPhoneAppIsToldToAddItsWatchApp() async throws {
        // Made here only when this Mac can build iPhone apps; otherwise its check would open the setup steps.
        guard await Task.detached(operation: { PhoneTools.checked(family: .iphone).issue }).value == nil else {
            throw XCTSkip("this Mac can't build iPhone apps")
        }
        var wish = try Template.scaffold(name: "Steps", platform: .android, in: root)
        guard case .add(let target) = try AppPlanner.make(.native, devices: ["iphone", "watch"],
                                                          in: [AppKinds.member(of: wish, in: Places.builtIn)], table: Places.builtIn).get()
        else { return XCTFail("an iPhone app beside an Android one is a new app") }
        wish.apps = [WishApp(kind: .android), target.waiting]
        try Template.saveMeta(wish)
        let store = Store(testingAt: root)
        let listed = try XCTUnwrap(store.projects.first { $0.id == wish.id })
        await store.makeWaitingParts(of: listed)
        XCTAssertTrue(store.projects.contains { $0.partOf == wish.id && $0.platform == .iphone })
        func told() -> String { Parts.madeNote(for: listed, apps: store.apps(of: listed)).text }
        XCTAssertTrue(told().contains("apple-watch skill"), told())
        XCTAssertTrue(told().contains(Parts.pack(for: .iphone).prefix(80)), "its rules go with it, as for an app made at once")

        // The request that carried it never reached the agent (its engine wouldn't start): it's still to be told, at
        // the next request and after Lamp starts again.
        let request = LogLine(kind: .user, text: "Count my steps.")
        store.logs[wish.id] = [request, LogLine(kind: .error, text: "The engine couldn't start.")]
        store.told(listed, request: request.id, made: Parts.madeNote(for: listed, apps: store.apps(of: listed)).sent)
        XCTAssertTrue(Store(testingAt: root).projects.contains { $0.id == wish.id })
        XCTAssertTrue(told().contains("apple-watch skill"), "kept until the agent has had it")

        // Once a request with it reached the agent, it's told.
        store.logs[wish.id] = [request, LogLine(kind: .agent, text: "Adding the watch app.")]
        store.told(listed, request: request.id, made: Parts.madeNote(for: listed, apps: store.apps(of: listed)).sent)
        XCTAssertEqual(told(), "")
    }

    /// Made, not yet told (its engine never started), and then gone with a version restored without it: what was to be
    /// said about it isn't said, while what's still true of another app is.
    func testANoteAboutAnAppNoLongerThereIsntSent() async throws {
        guard await Task.detached(operation: { PhoneTools.checked(family: .iphone).issue }).value == nil else {
            throw XCTSkip("this Mac can't build iPhone apps")
        }
        var wish = try Template.scaffold(name: "Steps", platform: .android, in: root)
        guard case .add(let target) = try AppPlanner.make(.native, devices: ["iphone", "watch"],
                                                          in: [AppKinds.member(of: wish, in: Places.builtIn)], table: Places.builtIn).get()
        else { return XCTFail("an iPhone app beside an Android one is a new app") }
        wish.apps = [WishApp(kind: .android), target.waiting]
        try Template.saveMeta(wish)
        let store = Store(testingAt: root)
        let listed = try XCTUnwrap(store.projects.first { $0.id == wish.id })
        await store.makeWaitingParts(of: listed)
        let phone = try XCTUnwrap(store.parts(of: listed).first { $0.platform == .iphone })
        XCTAssertTrue(Parts.madeNote(for: listed, apps: store.apps(of: listed)).text.contains("apple-watch skill"))
        // A note about the wish's Android app, still as it was made.
        Parts.rememberMade(["Keep the Android app's layout."], about: listed, in: listed)

        // The restore leaves `.lamp/` as it is and takes iPhone/ away.
        try FileManager.default.removeItem(at: phone.dir)
        store.reload()
        let note = Parts.madeNote(for: listed, apps: store.apps(of: listed)).text
        XCTAssertFalse(note.contains("apple-watch skill"), note)
        XCTAssertTrue(note.contains("Keep the Android app's layout."), "a note whose app is still there is kept")
    }

    /// Not yet told (its engine never started), then the person picks the iPad and their own phone under Try On: the
    /// app is still the one it was made as, so the note still goes. And a request reaching the agent counts as telling
    /// only the notes it carried, not one Lamp kept after it was sent.
    func testANoteOutlivesATryOnChoiceAndOnlyWhatWasSentIsTold() async throws {
        guard await Task.detached(operation: { PhoneTools.checked(family: .iphone).issue }).value == nil else {
            throw XCTSkip("this Mac can't build iPhone apps")
        }
        var wish = try Template.scaffold(name: "Steps", platform: .android, in: root)
        guard case .add(let target) = try AppPlanner.make(.native, devices: ["iphone", "watch"],
                                                          in: [AppKinds.member(of: wish, in: Places.builtIn)], table: Places.builtIn).get()
        else { return XCTFail("an iPhone app beside an Android one is a new app") }
        wish.apps = [WishApp(kind: .android), target.waiting]
        try Template.saveMeta(wish)
        let store = Store(testingAt: root)
        let listed = try XCTUnwrap(store.projects.first { $0.id == wish.id })
        await store.makeWaitingParts(of: listed)
        func note() -> (text: String, sent: [Parts.Made]) { Parts.madeNote(for: listed, apps: store.apps(of: listed)) }

        var phone = try XCTUnwrap(store.parts(of: listed).first { $0.platform == .iphone })
        phone.family = .ipad
        phone.device = "00008110-test"
        try Template.saveMeta(phone)
        store.reload()
        XCTAssertEqual(store.parts(of: listed).first { $0.platform == .iphone }?.family, .ipad)
        let sent = note()
        XCTAssertTrue(sent.text.contains("apple-watch skill"), "where Try On opens it changes nothing the note says")

        // Lamp keeps another note while the request is out; the request reaches the agent.
        Parts.rememberMade(["Keep the Android app's layout."], about: listed, in: listed)
        let request = LogLine(kind: .user, text: "Count my steps.")
        store.logs[wish.id] = [request, LogLine(kind: .agent, text: "Adding the watch app.")]
        store.told(listed, request: request.id, made: sent.sent)
        XCTAssertFalse(note().text.contains("apple-watch skill"))
        XCTAssertTrue(note().text.contains("Keep the Android app's layout."), "a note the request didn't carry is still to be told")
    }
}
