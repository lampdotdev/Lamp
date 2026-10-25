import XCTest
@testable import Lamp

/// A wish that asks for several apps is one of several from its first build, before its other apps are made: a Mac app
/// whose Android app waits for Google's tools gets `LampWish`, the wish's key, a room that lists the Android app as not
/// open, the pointer to the `wish-links` skill in its prompt and the skill named with its requests. Apps are counted,
/// not devices: a wish asking for one app for the Mac and the iPhone, like a wish of one app or a starter, gets none of it.
@MainActor
final class WishPlanTests: XCTestCase {
    private let keys = FileManager.default.temporaryDirectory.appendingPathComponent("wish-keys-\(UUID().uuidString)")
    private var keptKeys = WishKeys.folder

    override func setUp() {
        ControllerRelay.executable = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("LampRelay")
        keptKeys = WishKeys.folder
        WishKeys.folder = keys
    }

    override func tearDown() async throws {
        WishRooms.forgetAll()
        WishKeys.folder = keptKeys
        try? FileManager.default.removeItem(at: keys)
    }

    private func wish(_ kind: Platform, asking apps: [WishApp]) -> LampProject {
        var wish = LampProject(id: "score-\(kind.rawValue)-\(apps.count)", name: "Score", exe: "Score",
                               dir: URL(fileURLWithPath: "/tmp/score-plan"), platform: kind)
        wish.apps = apps
        return wish
    }

    func testTheFirstAppOfAWishAskingForTwoIsOneOfSeveralFromItsFirstBuild() async throws {
        let mac = wish(.mac, asking: [WishApp(kind: .mac), WishApp(kind: .android, needs: "This Mac needs Google's tools first.")])
        XCTAssertTrue(Template.talksToOtherApps(mac))
        XCTAssertTrue(Template.lampSupportSwift(for: mac).contains("final class LampWish"), "the block from its first build")
        XCTAssertNotNil(Store.shared.wishKey(for: mac), "and the wish's key, in the copy it's built into")

        // Lamp's room knows the Android app it waits for, by the peer name it will have, not open.
        let (status, answer) = await WishRooms.answer(for: mac, wish: mac, apps: [mac], host: "127.0.0.1")
        XCTAssertEqual(status, 200, "\(answer)")
        XCTAssertNil(answer["alone"], "not alone: \(answer)")
        XCTAssertEqual((answer["apps"] as? [[String: Any]])?.compactMap { $0["peer"] as? String }, ["mac", "android"])
        XCTAssertTrue(WishNote.line(for: mac, store: .shared).contains("The Android app (peer \"android\"): not made yet"))

        // The builder is pointed at the ways its apps can share data, from the first request.
        let prompt = Agent.systemPrompt(for: mac)
        XCTAssertTrue(prompt.contains("`wish-links` skill"), "the pointer in the prompt")
        XCTAssertTrue(Skills.applying(to: mac).contains { $0.name == "wish-links" }, "and the skill named with its requests")
        let shipped = Skills.load(from: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/skills"))
        XCTAssertEqual(Skills.read(["name": "wish-links"], from: shipped).0, 200, "which read_skill answers")
    }

    func testAWishAskingForOneAppGetsNothingWhateverItRunsOn() async {
        for alone in [wish(.mac, asking: []), wish(.mac, asking: [WishApp(kind: .mac)]),
                      wish(.universal, asking: [WishApp(kind: .universal)]), wish(.android, asking: [WishApp(kind: .android)])] {
            XCTAssertFalse(Template.talksToOtherApps(alone), "\(alone.platform.rawValue) with \(alone.apps.count) asked")
            XCTAssertNil(Store.shared.wishKey(for: alone))
            XCTAssertFalse(Agent.systemPrompt(for: alone).contains("wish-links"))
            XCTAssertFalse(Skills.applying(to: alone).contains { $0.name == "wish-links" })
            XCTAssertEqual(WishNote.line(for: alone, store: .shared), "")
            let (_, answer) = await WishRooms.answer(for: alone, wish: alone, apps: [alone], host: "127.0.0.1")
            XCTAssertEqual(answer["alone"] as? Bool, true)
        }
        XCTAssertTrue(ControllerRelay.roomKeys.isEmpty, "no room, so nothing starts the relay")
    }
}
