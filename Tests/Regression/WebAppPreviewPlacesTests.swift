import XCTest
@testable import Lamp

/// A web app at home on the Mac is looked at in the TV preview, but it isn't a TV app: its preview isn't called a TV's,
/// and its agent isn't sent to look at it as a TV, a frame and a phone before it finishes. Pointed at a TV, it is one.
@MainActor
final class WebAppPreviewPlacesTests: XCTestCase {
    private func webApp(_ places: [Destination], chosen: Destination = .mac) -> LampProject {
        LampProject(id: "kitchen-board", name: "Kitchen Board", exe: "KitchenBoard", dir: URL(fileURLWithPath: "/tmp/kitchen-board"),
                    platform: .webApp, chosen: chosen, places: places)
    }

    func testAMacWebAppsPreviewIsJustThePreview() {
        let mac = webApp([.mac])
        XCTAssertNil(Store.previewDevice(mac))
        XCTAssertEqual(TVPreview.title(of: mac.name, device: Store.previewDevice(mac)), "Kitchen Board Preview")
        XCTAssertFalse(Store.notTheDevice(Store.previewDevice(mac)).contains("TV"))
    }

    func testPointedAtATVItsPreviewIsTheTVs() {
        let tv = webApp([.mac, .tv], chosen: .tv)
        XCTAssertEqual(Store.previewDevice(tv), "TV")
        XCTAssertEqual(TVPreview.title(of: tv.name, device: Store.previewDevice(tv)), "Kitchen Board on TV")
        XCTAssertEqual(Store.previewDevice(webApp([.mac, .androidTV], chosen: .androidTV)), "TV")
    }

    func testTheShapesLookedAtAreThoseOfItsPlaces() {
        let mac = Agent.screenPrompt(for: webApp([.mac]))
        XCTAssertTrue(mac.contains("\"1280x800\" (a Mac window)"))
        for other in ["1920x1080", "820x1180", "390x844"] { XCTAssertFalse(mac.contains(other), other) }

        let tv = Agent.screenPrompt(for: webApp([.mac, .tv]))
        XCTAssertTrue(tv.contains("\"1920x1080\" (a TV)"))
        XCTAssertFalse(tv.contains("390x844"))

        let phone = Agent.screenPrompt(for: webApp([.mac, .ios, .android]))
        XCTAssertTrue(phone.contains("\"390x844\" (an iPhone or an Android phone)"))
        XCTAssertFalse(phone.contains("1920x1080"))
    }

    /// An app made into a web app (`make_app_for`) is told the web app's own design rule, not a TV app's.
    func testAnAppMadeIntoAMacWebAppIsntToldToDesignForATV() {
        let rules = Target.webApp.guidance.changeRules(webApp([.mac]))
        XCTAssertFalse(rules.contains("1920×1080"), "a Mac web app isn't laid out at a TV's size")
        XCTAssertTrue(rules.contains("\"1280x800\" (a Mac window)"))
        XCTAssertFalse(rules.contains("390x844"))
    }
}
