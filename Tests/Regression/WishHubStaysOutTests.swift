import XCTest
@testable import Lamp

/// A wish of one app, which is most wishes and every starter, gets nothing from the wish hub: no rule about it in the
/// agent's prompt, no line about it with the request, none of its code in the app's building blocks (so no size, and
/// nothing that could ask for a permission), no key for the wish's apps' link, and no room at the relay. An app with
/// others in its wish gets all of it.
@MainActor
final class WishHubStaysOutTests: XCTestCase {
    private let kinds: [Platform] = [.mac, .iphone, .universal, .android, .tv]
    private let hubWords = ["LampWish", "Lamp.wish", "wish's room", "wish's apps right now", "/app/wish", "lamp-wish", "x25519"]

    private func project(_ kind: Platform, partOf wish: String? = nil) -> LampProject {
        LampProject(id: wish.map { "\($0).\(kind.rawValue)" } ?? "solo\(kind.rawValue)", name: "Solo", exe: "Solo",
                    dir: URL(fileURLWithPath: "/tmp/solo/\(kind.rawValue)"), platform: kind, partOf: wish)
    }

    func testAnAppOnItsOwnIsToldNothingOfTheHub() {
        for kind in kinds {
            let alone = project(kind)
            let prompt = Agent.systemPrompt(for: alone) + Agent.tryRules
            for word in hubWords { XCTAssertFalse(prompt.contains(word), "\(kind.rawValue)'s prompt names \(word)") }
            XCTAssertEqual(WishNote.line(for: alone, store: .shared), "", "no line about the wish's apps with \(kind.rawValue)'s requests")
        }
    }

    func testAnAppOnItsOwnCarriesNoneOfTheHubsCode() {
        for kind in kinds {
            let alone = project(kind), several = project(kind, partOf: "pair")
            XCTAssertFalse(Template.talksToOtherApps(alone))
            XCTAssertNil(Store.shared.wishKey(for: alone), "no key is made for an app on its own")
            XCTAssertTrue(Template.talksToOtherApps(several))
            switch kind {
            case .android:
                for word in hubWords { XCTAssertFalse(Template.androidSupportKotlin(for: alone).contains(word), word) }
                XCTAssertNil(Template.androidInstallValues(for: alone, onDevice: false, wishKey: Store.shared.wishKey(for: alone))["wishKey"])
                XCTAssertTrue(Template.androidSupportKotlin(for: several).contains("object LampWish"))
            case .tv:
                for word in hubWords { XCTAssertFalse(TVTemplate.lampJS(for: alone).contains(word), word) }
                XCTAssertTrue(TVTemplate.lampJS(for: several).contains("window.Lamp.wish = api"))
            default:
                for word in hubWords + [Template.wishKeyName] { XCTAssertFalse(Template.lampSupportSwift(for: alone).contains(word), "\(kind.rawValue): \(word)") }
                XCTAssertTrue(Template.lampSupportSwift(for: several).contains("final class LampWish"), kind.rawValue)
            }
        }
        // What says whether an app built by an earlier Lamp is out of date leaves the block out, so no app is built again
        // for code it doesn't carry.
        XCTAssertFalse(Template.withoutWish(Template.lampSupportSwift).contains("LampWish"))
        XCTAssertEqual(Template.lampSupportSwift.count - Template.withoutWish(Template.lampSupportSwift).count,
                       Template.lampSupportSwift(for: project(.mac, partOf: "pair")).count - Template.lampSupportSwift(for: project(.mac)).count)
    }

    /// An app of several built with an earlier `LampWish` is built again when it's opened from Lamp, so "out of date"
    /// in its wish's other apps goes once it is; an app on its own is never built again for the block.
    func testOnlyAnAppOfSeveralIsBuiltAgainForTheBlock() {
        let current = BuildStamp.current
        let earlier = BuildStamp(lamp: current.lamp, support: current.support, wish: "0000")
        let unstamped = BuildStamp(lamp: current.lamp, support: current.support)
        for kind: Platform in [.mac, .iphone] {
            XCTAssertFalse(earlier.isOutdated(for: project(kind)), kind.rawValue)
            XCTAssertFalse(unstamped.isOutdated(for: project(kind)), kind.rawValue)
            XCTAssertTrue(earlier.isOutdated(for: project(kind, partOf: "pair")), kind.rawValue)
            XCTAssertTrue(unstamped.isOutdated(for: project(kind, partOf: "pair")), "built before the block was stamped: \(kind.rawValue)")
            XCTAssertFalse(BuildStamp(lamp: current.lamp, support: current.support, wish: BuildStamp.currentWish).isOutdated(for: project(kind, partOf: "pair")))
        }
    }

    func testAnAppOnItsOwnOpensNoRoom() async {
        WishRooms.forgetAll()
        let alone = project(.mac)
        let (status, answer) = await WishRooms.answer(for: alone, wish: alone, apps: [alone], host: "127.0.0.1")
        XCTAssertEqual(status, 200)
        XCTAssertEqual(answer["alone"] as? Bool, true)
        XCTAssertTrue(ControllerRelay.roomKeys.isEmpty, "no room, so nothing starts the relay")
    }
}
