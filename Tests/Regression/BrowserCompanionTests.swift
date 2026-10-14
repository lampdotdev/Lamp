import XCTest
@testable import Lamp

@MainActor
final class BrowserCompanionTests: XCTestCase {
    private func surface(title: String = "Recipes", fields: [[String: Any]] = [], actions: [[String: Any]]) -> [String: Any] {
        ["title": title, "detail": "", "sections": [], "fields": fields, "actions": actions, "busy": false]
    }

    // Completed actions stay invalid after retry IDs expire or the app restarts.
    func testCompletedActionsAndRestartsInvalidateTheDisplayedRevision() throws {
        let bridge = BrowserCompanions()
        let app = LampProject(id: "recipes", name: "Recipes", exe: "Recipes", dir: URL(fileURLWithPath: "/tmp/recipes"), instance: "recipe-instance")
        let shown = surface(actions: [["id": "save", "label": "Save", "readsPage": false]])
        let boot = UUID().uuidString, tab = "t1"
        func publish(_ boot: String, ack: String? = nil) -> [String: Any] {
            var body: [String: Any] = ["boot": boot, "surface": shown]
            if let ack { body["ack"] = ack }
            return bridge.exchange(body, app: app).1
        }
        func revision() throws -> String {
            try XCTUnwrap(bridge.native(["op": "surface-view", "app": app.id], tab: tab, projects: [app])["revision"] as? String)
        }
        func send(_ id: String, revision: String) -> [String: Any] {
            bridge.native(["op": "surface-action", "app": app.id, "id": id, "revision": revision,
                           "action": "save", "fields": [String: String]()], tab: tab, projects: [app])
        }
        _ = publish(boot)
        let original = try revision(), first = UUID().uuidString
        XCTAssertEqual(send(first, revision: original)["accepted"] as? Bool, true)
        _ = publish(boot, ack: first)
        for _ in 0..<64 {
            let id = UUID().uuidString
            XCTAssertEqual(send(id, revision: try revision())["accepted"] as? Bool, true)
            _ = publish(boot, ack: id)
        }
        XCTAssertNotNil(send(first, revision: original)["error"])
        XCTAssertNil(publish(boot)["event"])
        let beforeRestart = try revision(), newBoot = UUID().uuidString
        _ = publish(newBoot)
        XCTAssertNotEqual(try revision(), beforeRestart)
        XCTAssertNotNil(send(UUID().uuidString, revision: beforeRestart)["error"])
        XCTAssertNil(publish(newBoot)["event"])
    }

    func testSelectionActionsRequireSelectionCaptureAndPageActionsWork() throws {
        let app = LampProject(id: "reader", name: "Reader", exe: "Reader", dir: URL(fileURLWithPath: "/tmp/reader"), instance: "reader-instance")
        func exercise(selection: Bool) throws {
            let bridge = BrowserCompanions(), boot = UUID().uuidString
            var action: [String: Any] = ["id": "read", "label": "Read", "readsPage": !selection]
            if selection { action["readsSelection"] = true }
            let publish: [String: Any] = ["boot": boot, "surface": surface(title: "Reader", actions: [action])]
            XCTAssertEqual(bridge.exchange(publish, app: app).0, 200)
            let revision = try XCTUnwrap(bridge.native(["op": "surface-view", "app": app.id], tab: "t1", projects: [app])["revision"])
            var request: [String: Any] = ["op": "surface-action", "app": app.id, "id": UUID().uuidString,
                                          "revision": revision, "action": "read", "fields": [String: String]()]
            if selection {
                XCTAssertNotNil(bridge.native(request, tab: "t1", projects: [app])["error"])
                request["page"] = ["url": "https://example.test/article", "title": "Article", "text": "Unselected article", "scope": "page"]
                XCTAssertNotNil(bridge.native(request, tab: "t1", projects: [app])["error"])
            }
            var page = ["url": "https://example.test/article", "title": "Article", "text": "Chosen passage"]
            if selection { page["scope"] = "selection" }
            request["page"] = page
            XCTAssertEqual(bridge.native(request, tab: "t1", projects: [app])["accepted"] as? Bool, true)
            let event = try XCTUnwrap(bridge.exchange(publish, app: app).1["event"] as? [String: Any])
            XCTAssertEqual((event["page"] as? [String: Any])?["text"] as? String, "Chosen passage")
            XCTAssertEqual((event["page"] as? [String: Any])?["scope"] as? String, selection ? "selection" : "page")
        }
        try exercise(selection: true)
        try exercise(selection: false)
    }

    func testAnActionCannotRequestBothThePageAndTheSelection() {
        let app = LampProject(id: "reader", name: "Reader", exe: "Reader", dir: URL(fileURLWithPath: "/tmp/reader"))
        let both = surface(title: "Reader", actions: [["id": "read", "label": "Read", "readsPage": true, "readsSelection": true]])
        XCTAssertEqual(BrowserCompanions().exchange(["boot": UUID().uuidString, "surface": both], app: app).0, 400)
    }

    // Drafts are kept per tab: what the app prepared for one tab is shown only there, a click carries its tab,
    // and a button drawn on one tab can't act on what another tab shows.
    func testEachTabShowsItsOwnDraftAndClicksCarryTheirTab() throws {
        let bridge = BrowserCompanions()
        let app = LampProject(id: "box", name: "Recipe Box", exe: "RecipeBox", dir: URL(fileURLWithPath: "/tmp/box"), instance: "box")
        let boot = UUID().uuidString
        let save: [[String: Any]] = [["id": "save", "label": "Save", "readsPage": false]]
        let empty = surface(title: "Recipe Box", actions: save)
        let draftA = surface(title: "Recipe Box", fields: [["id": "name", "label": "Name", "value": "Lemon chickpeas"]], actions: save)
        func view(_ tab: String) -> [String: Any] { bridge.native(["op": "surface-view", "app": app.id], tab: tab, projects: [app]) }
        XCTAssertEqual(bridge.exchange(["boot": boot, "surface": empty], app: app).0, 200)
        _ = view("tA"); _ = view("tB")
        let tabs = try XCTUnwrap(bridge.exchange(["boot": boot, "surface": empty], app: app).1["tabs"] as? [String])
        XCTAssertEqual(Set(tabs), ["tA", "tB"])
        _ = bridge.exchange(["boot": boot, "surface": empty, "surfaces": ["tA": draftA, "tB": empty]], app: app)
        let a = view("tA"), b = view("tB")
        XCTAssertEqual(((a["surface"] as? [String: Any])?["fields"] as? [[String: Any]])?.first?["value"] as? String, "Lemon chickpeas")
        XCTAssertEqual(((b["surface"] as? [String: Any])?["fields"] as? [[String: Any]])?.count, 0)
        XCTAssertNotEqual(a["revision"] as? String, b["revision"] as? String)
        let fromB = bridge.native(["op": "surface-action", "app": app.id, "id": UUID().uuidString, "revision": a["revision"]!,
                                   "action": "save", "fields": ["name": "Lemon chickpeas"]], tab: "tB", projects: [app])
        XCTAssertNotNil(fromB["error"], "tab B used tab A's buttons")
        let fromA = bridge.native(["op": "surface-action", "app": app.id, "id": UUID().uuidString, "revision": a["revision"]!,
                                   "action": "save", "fields": ["name": "Lemon chickpeas"]], tab: "tA", projects: [app])
        XCTAssertEqual(fromA["accepted"] as? Bool, true)
        let event = try XCTUnwrap(bridge.exchange(["boot": boot, "surface": empty, "surfaces": ["tA": draftA, "tB": empty]], app: app).1["event"] as? [String: Any])
        XCTAssertEqual(event["tab"] as? String, "tA")
    }

    // The same tab in two Chrome profiles is two sidebars.
    func testTabKeysDifferByProfile() {
        let run = UUID().uuidString
        let one = BrowserCompanions.tabKey(profile: UUID().uuidString, run: run, tab: 12), other = BrowserCompanions.tabKey(profile: UUID().uuidString, run: run, tab: 12)
        XCTAssertNotNil(one); XCTAssertNotEqual(one, other)
        XCTAssertNil(BrowserCompanions.tabKey(profile: "p", run: run, tab: "x"))
    }

    // Found by an independent attack on the bridge: a button drawn before a click acted again once the app's next
    // update left its tab out (the app draws only the tabs open most recently).
    func testASpentButtonStaysSpentWhenTheAppStopsDrawingItsTab() throws {
        let bridge = BrowserCompanions()
        let app = LampProject(id: "box", name: "Box", exe: "Box", dir: URL(fileURLWithPath: "/tmp/box"), instance: "box")
        let boot = UUID().uuidString, main = surface(actions: [["id": "save", "label": "Save", "readsPage": false]])
        func view() -> String { bridge.native(["op": "surface-view", "app": app.id], tab: "t17", projects: [app])["revision"] as? String ?? "" }
        func click(_ revision: String) -> [String: Any] {
            bridge.native(["op": "surface-action", "app": app.id, "id": UUID().uuidString, "revision": revision, "action": "save",
                           "fields": [String: String]()], tab: "t17", projects: [app])
        }
        _ = bridge.exchange(["boot": boot, "surface": main], app: app)
        let drawn = view()
        XCTAssertEqual(click(drawn)["accepted"] as? Bool, true)
        let first = try XCTUnwrap(bridge.exchange(["boot": boot, "surface": main], app: app).1["event"] as? [String: Any])
        _ = bridge.exchange(["boot": boot, "surface": main, "ack": first["id"]!], app: app)
        XCTAssertNotNil(click(drawn)["error"])
        _ = bridge.exchange(["boot": boot, "surface": main], app: app)
        XCTAssertNotNil(click(drawn)["error"], "the button drawn before the first click acted again")
        XCTAssertEqual(click(view())["accepted"] as? Bool, true, "the tab's fresh buttons still work")
    }

    // Chrome takes one compound selector per fit; any whitespace in CSS is a descendant combinator.
    func testSelectorsWithAnyCombinatorAreRefused() {
        for selector in ["div a", "div\ta", "div\na", "div>a", "a,b", ":not(div a)"] {
            XCTAssertNotNil(BrowserCompanions.Declaration.selectorProblem(selector), selector)
        }
        for selector in [".wprm-recipe-container", "[itemtype*=\"schema.org/Recipe\"]", "[data-x=\"a b\"]", "div.recipe-card"] {
            XCTAssertNil(BrowserCompanions.Declaration.selectorProblem(selector), selector)
        }
    }
}
