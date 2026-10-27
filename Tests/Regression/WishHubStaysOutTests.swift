import XCTest
@testable import Lamp

/// Every app carries `LampWish`, since any app may be open on several devices at once (two iPhones, a screen on an iPad
/// and a TV) and its copies share values through it: an app on its own has the block in its building blocks (and a key
/// and a room, `WishHubTests`). What's for a wish of several apps stays out of an app on its own: the rule about them in the agent's prompt
/// and the line about them with each request.
@MainActor
final class WishHubStaysOutTests: XCTestCase {
    private let kinds: [Platform] = [.mac, .iphone, .universal, .android, .tv, .game, .webApp, .screen]

    private func project(_ kind: Platform, partOf wish: String? = nil) -> LampProject {
        LampProject(id: wish.map { "\($0).\(kind.rawValue)" } ?? "solo\(kind.rawValue)", name: "Solo", exe: "Solo",
                    dir: URL(fileURLWithPath: "/tmp/solo/\(kind.rawValue)"), platform: kind, partOf: wish)
    }

    func testAnAppOnItsOwnIsToldNothingOfTheWishsOtherApps() {
        for kind in kinds {
            let alone = project(kind)
            let prompt = Agent.systemPrompt(for: alone) + Agent.tryRules
            XCTAssertFalse(prompt.contains(Agent.Rules.wishTalk.trimmingCharacters(in: .whitespacesAndNewlines)), "\(kind.rawValue)'s prompt has the rule for a wish of several")
            XCTAssertEqual(WishNote.line(for: alone, store: .shared), "", "no line about the wish's apps with \(kind.rawValue)'s requests")
        }
    }

    func testAnAppOnItsOwnCarriesTheBlockForItsCopies() {
        for kind in kinds {
            let alone = project(kind)
            XCTAssertFalse(Template.talksToOtherApps(alone))
            XCTAssertTrue(Template.carriesWish(alone), kind.rawValue)
            switch kind {
            case .android: XCTAssertTrue(Template.androidSupportKotlin(for: alone).contains("object LampWish"))
            case .tv: XCTAssertTrue(TVTemplate.lampJS(for: alone).contains("window.Lamp.wish = api"))
            case .game: XCTAssertTrue(GameKit.lampJS(for: alone).contains("window.Lamp.wish = api"))
            default: XCTAssertTrue(Template.lampSupportSwift(for: alone).contains("final class LampWish"), kind.rawValue)
            }
        }
    }

    /// An app built with an earlier `LampWish`, or before every app carried it, is built again when it's opened from Lamp.
    func testAnAppBuiltWithAnEarlierBlockIsBuiltAgain() {
        let current = BuildStamp.current
        let earlier = BuildStamp(lamp: current.lamp, support: current.support, wish: "0000")
        let unstamped = BuildStamp(lamp: current.lamp, support: current.support)
        for kind: Platform in [.mac, .iphone] {
            for app in [project(kind), project(kind, partOf: "pair")] {
                XCTAssertTrue(earlier.isOutdated(for: app), app.id)
                XCTAssertTrue(unstamped.isOutdated(for: app), "built before the block was stamped: \(app.id)")
                XCTAssertFalse(BuildStamp(lamp: current.lamp, support: current.support, wish: BuildStamp.currentWish).isOutdated(for: app))
            }
        }
    }
}
