import XCTest
@testable import Lamp

/// An app of a wish is its folder: its id, instance, name among the wish's apps, installed copy and skill come from it,
/// so a wish can have two apps of one kind (two Mac apps, two Roku apps), each found, addressed and changed on its own.
@MainActor
final class WishFolderIdentityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        // Under the home folder, as Lamp keeps its wishes: a wish's folder is written only where no link leads on the way.
        root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-wish-folders-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func part(_ folder: String, _ kind: Platform, of wish: LampProject, integration: String? = nil) throws -> LampProject {
        var part = LampProject(id: Parts.id(wish: wish.id, folder: folder), name: wish.name, exe: wish.exe, dir: wish.dir.appendingPathComponent(folder),
                               instance: Parts.instance(wish: wish, folder: folder), platform: kind, partOf: wish.id)
        part.integration = integration
        try FileManager.default.createDirectory(at: part.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try Template.saveMeta(part)
        // A device's app is its marker, naming its integration, beside the code its integration writes.
        if let integration { try integration.write(to: part.dir.appendingPathComponent(DeviceApps.marker), atomically: true, encoding: .utf8) }
        else { try Template.fill(part) }
        return part
    }

    /// "Make me another Mac app in this wish": a wish whose own folder holds a Mac app gets a second and a third, each in
    /// a folder of its own, with its own id, instance, name among the wish's apps and installed copy, and both are still
    /// there when Lamp starts again.
    func testTwoMoreMacAppsAreTwoAppsEachByItsFolder() async throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let store = Store(testingAt: root)
        let (first, problem, _) = await store.addPart(.mac, to: try XCTUnwrap(store.current(wish)))
        XCTAssertNil(problem)
        let (second, problem2, _) = await store.addPart(.mac, to: try XCTUnwrap(store.current(wish)))
        XCTAssertNil(problem2)
        let a = try XCTUnwrap(first), b = try XCTUnwrap(second)
        // The Mac app in the wish's own folder is installed under the wish's name, so neither new one is given Mac/.
        XCTAssertEqual([a, b].map(\.dir.lastPathComponent), ["Mac2", "Mac3"])
        XCTAssertEqual(Set([wish.id, a.id, b.id]).count, 3)
        XCTAssertEqual(Set([wish.instance, a.instance, b.instance]).count, 3)
        XCTAssertEqual(Set([wish, a, b].map(\.installedURL)).count, 3)
        XCTAssertEqual(Set([wish, a, b].map(\.bundleID)).count, 3)
        let now = try XCTUnwrap(store.current(wish))
        XCTAssertEqual(Set([wish, a, b].map { WishRooms.peer($0, in: now) }).count, 3)
        XCTAssertEqual(now.apps.map(\.folder), [".", "Mac2", "Mac3"])
        XCTAssertEqual(Parts.waiting(in: now, parts: store.parts(of: now)), [])

        let relaunched = Store(testingAt: root)
        let again = try XCTUnwrap(relaunched.current(wish))
        XCTAssertEqual(relaunched.parts(of: again).map(\.id).sorted(), [a.id, b.id].sorted())
        XCTAssertEqual(relaunched.parts(of: again).map(\.platform), [.mac, .mac])
        // A Lamp from before would find neither, so the wish says a layout it leaves alone.
        XCTAssertFalse(Parts.readByEarlierLamp(wish.dir))
        XCTAssertEqual(NewerWish.savedLayout(at: wish.dir), NewerWish.layout)
    }

    /// An app already made keeps the id, folder and installed place it always had: a Mac app in Mac/ beside a TV app in
    /// the wish's own folder is still "tally.mac", installed under the wish's name, and the wish is one a Lamp from before reads.
    func testAnAppInItsKindsOwnFolderKeepsEverythingItHad() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .tv, in: root)
        let mac = try part("Mac", .mac, of: wish)
        XCTAssertEqual(Parts.folders(in: wish.dir), ["Mac"])
        XCTAssertEqual(Parts.load(try XCTUnwrap(Store.readWish(at: wish.dir))).map(\.id), ["\(wish.id).mac"])
        XCTAssertEqual(mac.installedURL.lastPathComponent, "Tally.app")
        XCTAssertTrue(Parts.readByEarlierLamp(wish.dir))
        XCTAssertEqual(Template.layout(of: try XCTUnwrap(Store.readWish(at: wish.dir))), nil)
    }

    /// A folder that's there already is never given to a new app, whatever's in it: a Roku app's Roku/, and Roku2/ holding
    /// files of no app at all, are both passed over, and so is a folder whose name differs only in case.
    func testANewAppNeverGoesIntoAFolderThatIsThere() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .tv, in: root)
        _ = try part("Roku", .device, of: wish, integration: "roku")
        let loose = wish.dir.appendingPathComponent("Roku2")
        try FileManager.default.createDirectory(at: loose, withIntermediateDirectories: true)
        try "notes".write(to: loose.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: wish.dir.appendingPathComponent("mac"), withIntermediateDirectories: true)
        let read = try XCTUnwrap(Store.readWish(at: wish.dir))
        XCTAssertEqual(Parts.newFolder("Roku", in: read), "Roku3")
        XCTAssertEqual(Parts.newFolder("Mac", in: read), "Mac2")
        XCTAssertEqual(try String(contentsOf: loose.appendingPathComponent("notes.txt"), encoding: .utf8), "notes")
    }

    /// An app taken away keeps its folder (`RemovedApp`): a new app of the same kind asked for afterwards goes in another,
    /// so it has none of the old one's id or data, and Undo brings the old one back into its own.
    func testAFolderAnAppWasTakenAwayFromStaysItsOwn() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .tv, in: root)
        let mac = try part("Mac", .mac, of: wish)
        RemovedApp.record(mac, in: wish.dir)
        try FileManager.default.removeItem(at: mac.dir)
        let read = try XCTUnwrap(Store.readWish(at: wish.dir))
        XCTAssertEqual(Parts.newFolder("Mac", in: read), "Mac2")
        // Nor one kept for an app still to be made.
        var waiting = read
        waiting.apps = [WishApp(kind: .mac, needs: "Xcode", folder: "Mac2")]
        XCTAssertEqual(Parts.newFolder("Mac", in: waiting), "Mac3")
    }

    /// A word for `part` names an app by its folder before anything else: of a Roku app in Roku/ and another in Roku2/,
    /// "roku" is the one in Roku/ and "roku2" the other, and each is offered by a word that reaches it alone. "mac", which
    /// two Mac apps share, is asked about rather than read as the first, each then offered by a word of its own.
    func testAFolderNamesOneAppAndAWordForSeveralIsAsked() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let roku = try part("Roku", .device, of: wish, integration: "roku")
        let other = try part("Roku2", .device, of: wish, integration: "roku")
        let mac = try part("Mac2", .mac, of: wish)
        let apps = [wish, roku, other, mac]
        XCTAssertEqual(Parts.picks("roku", among: apps).map(\.id), [roku.id])
        XCTAssertEqual(Parts.picks("roku2", among: apps).map(\.id), [other.id])
        XCTAssertEqual(Parts.address(of: roku, among: apps), "roku")
        XCTAssertEqual(Parts.address(of: other, among: apps), "roku2")
        XCTAssertNil(Parts.pick("mac", among: apps))
        XCTAssertEqual(Set(Parts.picks("mac", among: apps).map(\.id)), [wish.id, mac.id])
        XCTAssertEqual(Parts.address(of: wish, among: apps), ".")
        XCTAssertEqual(Parts.address(of: mac, among: apps), "mac2")
        XCTAssertEqual(Parts.pick(".", among: apps)?.id, wish.id)
        // And the chat's menu of apps tells two apps of a kind apart.
        XCTAssertNotEqual(Parts.menu(of: roku).name, Parts.menu(of: other).name)
        XCTAssertEqual(Parts.menu(of: mac).name, "Mac App 2")
    }

    /// Each of two apps of a kind has its rules as a skill of its own, about its own folder.
    func testEachAppOfAKindHasItsOwnSkill() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .tv, in: root)
        let mac = try part("Mac", .mac, of: wish), other = try part("Mac2", .mac, of: wish)
        let skills = Parts.packs(for: [mac, other])
        XCTAssertEqual(Parts.skill(of: mac), "target-mac")
        XCTAssertEqual(Parts.skill(of: other), "target-mac-mac2")
        XCTAssertTrue(try XCTUnwrap(skills["target-mac"]).body.contains("Mac/"))
        XCTAssertTrue(try XCTUnwrap(skills["target-mac-mac2"]).body.contains("Mac2/"))
        XCTAssertEqual(Skills.applying(to: wish, parts: [mac, other]).map(\.name).filter { $0.hasPrefix("target-") }, ["target-mac", "target-mac-mac2"])
    }

    /// Two Mac apps asked for while this Mac can't build them wait each in the folder kept for it: one made leaves the
    /// other waiting, and the versions' list keeps both apart.
    func testTwoWaitingAppsOfAKindAreEachTheirOwn() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .tv, in: root)
        var asked = wish
        asked.apps = [WishApp(kind: .tv, folder: "."), WishApp(kind: .mac, needs: "Xcode", folder: "Mac"), WishApp(kind: .mac, needs: "Xcode", folder: "Mac2")]
        XCTAssertEqual(Parts.waiting(in: asked, parts: []).map(\.folder), ["Mac", "Mac2"])
        let made = try part("Mac2", .mac, of: wish)
        XCTAssertEqual(Parts.waiting(in: asked, parts: [made]).map(\.folder), ["Mac"])
        XCTAssertEqual(Parts.folder(waiting: asked.apps[1], in: wish.dir), "Mac")

        let trailer = asked.apps.map(Versions.trailerWord).joined(separator: " ")
        XCTAssertEqual(trailer, "tv mac mac@Mac2", "an app in its kind's own folder is said as a Lamp from before says it")
        XCTAssertEqual(Versions.apps(from: trailer)?.map(\.folder), [nil, nil, "Mac2"])
    }

    /// `make_app_for` with `another` is one more app only of a code the wish has none of: a third Mac app beside two is
    /// refused, as is a call with neither; with `app` it changes that app and no other, the one in Mac2/ included. An
    /// `app` that names no app, or a path, changes nothing.
    func testMakeAppForChangesOnlyTheAppItNames() throws {
        let mac = AppKinds.member(of: LampProject(id: "tally", name: "Tally", exe: "Tally", dir: root, platform: .mac))
        let other = AppKinds.member(of: LampProject(id: "tally.mac2", name: "Tally", exe: "Tally", dir: root.appendingPathComponent("Mac2"),
                                                     platform: .mac, partOf: "tally"))
        XCTAssertThrowsError(try AppPlanner.make(.native, kind: .app, devices: ["mac"], another: true, in: [mac, other]).get(), "two apps of one code")
        XCTAssertThrowsError(try AppPlanner.make(.native, kind: .app, devices: ["mac"], in: [mac, other]).get(), "naming no app, a wish that has one gets none")
        guard case .another(let added) = try AppPlanner.make(.native, kind: .app, devices: ["android"], another: true, in: [mac, other]).get() else { return XCTFail() }
        XCTAssertEqual(added.kind, .android)
        guard case .update(let changed, let target) = try AppPlanner.make(.native, kind: .app, devices: ["mac", "iphone"], app: "mac2", in: [mac, other]).get()
        else { return XCTFail() }
        XCTAssertEqual(changed, other)
        XCTAssertEqual(target.kind, .universal)
        guard case .update(let rootApp, _) = try AppPlanner.make(.native, kind: .app, devices: ["mac"], app: ".", in: [mac, other]).get() else { return XCTFail() }
        XCTAssertEqual(rootApp, mac)
        for selector in ["Mac3", "../Mac2", "mac", "/tmp"] {
            guard case .failure = AppPlanner.make(.native, kind: .app, devices: ["mac"], app: selector, in: [mac, other]) else { return XCTFail(selector) }
        }
        let waiting = AppKinds.member(waiting: WishApp(kind: .mac, needs: "Xcode", folder: "Mac3"))
        guard case .update(let pending, _) = try AppPlanner.make(.native, kind: .app, devices: ["mac", "ipad"], app: "Mac3", in: [mac, waiting]).get()
        else { return XCTFail() }
        XCTAssertEqual(pending.slot, "Mac3")
    }

    /// A wish whose Mac apps in Mac2/ and Mac3/ are still to be made says a layout an earlier Lamp leaves alone, as it
    /// does once they're made: that Lamp would read the list by code and fold them into one.
    func testWaitingAppsAnEarlierLampWouldFoldMarkTheWishNewer() throws {
        var wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        XCTAssertNil(Template.layout(of: wish))
        wish.apps = [WishApp(kind: .mac, folder: "."), WishApp(kind: .mac, needs: "Xcode", folder: "Mac2"),
                     WishApp(kind: .mac, needs: "Xcode", folder: "Mac3")]
        XCTAssertEqual(Template.layout(of: wish), NewerWish.layout)
        // An app waiting in its kind's own folder beside apps of other families is one an earlier Lamp reads.
        wish.apps = [WishApp(kind: .mac, folder: "."), WishApp(kind: .android, needs: "Android Studio", folder: "Android")]
        XCTAssertNil(Template.layout(of: wish))
        // Two device apps, which an earlier Lamp lists by family as one.
        wish.apps = [WishApp(kind: .mac, folder: "."), WishApp(kind: .device, needs: "a TV", integration: "roku", folder: "Roku"),
                     WishApp(kind: .device, needs: "a TV", integration: "roku", folder: "Roku2")]
        XCTAssertEqual(Template.layout(of: wish), NewerWish.layout)
        // One device app waiting for a folder other than its device's own, which an earlier Lamp would make it in.
        wish.apps = [WishApp(kind: .mac, folder: "."),
                     WishApp(kind: .device, needs: "a TV", integration: "roku", folder: Parts.folder(for: .device, integration: "roku") + "2")]
        XCTAssertEqual(Template.layout(of: wish), NewerWish.layout)
        wish.apps = [WishApp(kind: .mac, folder: "."),
                     WishApp(kind: .device, needs: "a TV", integration: "roku", folder: Parts.folder(for: .device, integration: "roku"))]
        XCTAssertNil(Template.layout(of: wish))
    }

    /// The app in the wish's own folder made a Mac app beside a Mac app in Mac/ would be "mac" and installed under the
    /// wish's name twice: `make_app_for` refuses it, and nothing else of the wish clashes.
    func testChangingAnAppIntoOneThatSharesAnothersNameIsRefused() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .tv, in: root)
        let mac = try part("Mac", .mac, of: wish), other = try part("Mac2", .mac, of: wish)
        let apps = [wish, mac, other]
        XCTAssertEqual(Parts.clash(changing: wish, to: .mac, integration: nil, places: nil, among: apps, in: wish)?.id, mac.id)
        XCTAssertNil(Parts.clash(changing: wish, to: .android, integration: nil, places: nil, among: apps, in: wish))
        XCTAssertNil(Parts.clash(changing: other, to: .universal, integration: nil, places: nil, among: apps, in: wish))
        // An app still to be made in Mac/ is the app it will be.
        var waiting = wish
        waiting.apps = [WishApp(kind: .tv, folder: "."), WishApp(kind: .mac, needs: "Xcode", folder: "Mac")]
        XCTAssertEqual(Parts.clash(changing: waiting, to: .mac, integration: nil, places: nil, among: [waiting], in: waiting)?.dir.lastPathComponent, "Mac")
    }

    /// Only folders of the wish's own are its apps': a link to another folder holding an app, and the source folders of
    /// the app in the wish's own folder, are never one.
    func testALinkOrTheWishsOwnSourcesAreNoApp() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .tv, in: root)
        let elsewhere = try Template.scaffold(name: "Other", platform: .mac, in: root)
        try FileManager.default.createSymbolicLink(at: wish.dir.appendingPathComponent("Mac9"), withDestinationURL: elsewhere.dir)
        XCTAssertEqual(Parts.folders(in: wish.dir), [])
        XCTAssertTrue(Parts.isFolderName("Mac2"))
        for name in ["Mac 2", "Mac.2", "../Mac", "", "2Mac"] { XCTAssertFalse(Parts.isFolderName(name), name) }
    }
}
