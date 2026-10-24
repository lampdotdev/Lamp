import XCTest
@testable import Lamp

/// A wish of one app, which is most wishes and every starter, gets nothing from the wish hub: no rule about it in the
/// agent's prompt, no line about it with the request, none of its code in the app's building blocks (so no size, and
/// nothing that could ask for a permission), and no room at the relay. An app with others in its wish gets all of it.
@MainActor
final class WishHubStaysOutTests: XCTestCase {
    private let kinds: [Platform] = [.mac, .iphone, .universal, .android, .tv]
    private let hubWords = ["LampWish", "Lamp.wish", "wish's room", "wish's apps right now", "/app/wish"]

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
            XCTAssertTrue(Template.talksToOtherApps(several))
            switch kind {
            case .android:
                XCTAssertFalse(Template.androidSupportKotlin(for: alone).contains("LampWish"))
                XCTAssertTrue(Template.androidSupportKotlin(for: several).contains("object LampWish"))
            case .tv:
                XCTAssertFalse(TVTemplate.lampJS(for: alone).contains("Lamp.wish"))
                XCTAssertTrue(TVTemplate.lampJS(for: several).contains("window.Lamp.wish = api"))
            default:
                XCTAssertFalse(Template.lampSupportSwift(for: alone).contains("LampWish"), kind.rawValue)
                XCTAssertTrue(Template.lampSupportSwift(for: several).contains("final class LampWish"), kind.rawValue)
            }
        }
        // What says whether an app built by an earlier Lamp is out of date leaves the block out, so no app is built again
        // for code it doesn't carry.
        XCTAssertFalse(Template.withoutWish(Template.lampSupportSwift).contains("LampWish"))
        XCTAssertEqual(Template.lampSupportSwift.count - Template.withoutWish(Template.lampSupportSwift).count,
                       Template.lampSupportSwift(for: project(.mac, partOf: "pair")).count - Template.lampSupportSwift(for: project(.mac)).count)
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
