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
        XCTAssertTrue(rules.contains("for each place the request's device line names"))
    }
}

/// Places set by `make_app_for` after an app is given its kind, and Try On moved while a preview stays open: the agent's
/// shapes and the preview's name follow where the app is now, not where it was when they were first written.
@MainActor
final class WebAppPlacesChangeTests: XCTestCase {
    private func webApp(_ places: [Destination]?, chosen: Destination = .mac, dir: URL = URL(fileURLWithPath: "/tmp/kitchen-board")) -> LampProject {
        LampProject(id: "kitchen-board-change", name: "Kitchen Board", exe: "KitchenBoard", dir: dir, platform: .webApp, chosen: chosen, places: places)
    }

    /// An app made into a web app for the Mac and the iPhone: its kind's rules are written while it has only its kind's start
    /// (the Mac), so they mustn't name only the Mac's shapes; what's said once its places are set names the iPhone's and iPad's.
    func testAnAppMadeIntoAWebAppForTheIPhoneIsToldTheIPhonesShapes() {
        let rules = Target.webApp.guidance.changeRules(webApp(nil))
        XCTAssertFalse(rules.contains("and only those: \"1280x800\""), "written before its places are set")
        XCTAssertTrue(rules.contains("820x1180"))
        let placed = Agent.Rules.screenPlaced(webApp([.mac, .ios]))
        XCTAssertTrue(placed.contains("\"820x1180\" (an iPad upright)"))
        XCTAssertTrue(placed.contains("\"390x844\" (an iPhone)"))
        XCTAssertTrue(placed.contains("\"1280x800\" (a Mac window)"))
    }

    func testAnOpenPreviewsTitleFollowsTryOn() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("web-preview-title-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("app"), staged = root.appendingPathComponent("web")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try "<html><body></body></html>".write(to: staged.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let onTV = webApp([.mac, .tv], chosen: .tv, dir: dir), onMac = webApp([.mac, .tv], chosen: .mac, dir: dir)
        defer { TVPreview.close(onTV) }
        let problem = await TVPreview.show(onTV, staged: staged, inFront: false, device: Store.previewDevice(onTV))
        XCTAssertNil(problem)
        XCTAssertEqual(TVPreview.window(onTV)?.title, "Kitchen Board on TV")

        TVPreview.follow([onMac])
        XCTAssertEqual(TVPreview.window(onMac)?.title, "Kitchen Board Preview")
        TVPreview.follow([onTV])
        XCTAssertEqual(TVPreview.window(onTV)?.title, "Kitchen Board on TV")
    }
}
