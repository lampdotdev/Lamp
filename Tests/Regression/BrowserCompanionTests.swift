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
    /// Chrome lights the icon for a fit with path /en-US/ on https://developer.mozilla.org/en-US/, comparing the path
    /// with its last slash and still percent-encoded; the builder's look has to say the same.
    func testAPathIsComparedAsChromeComparesIt() throws {
        let fit = BrowserCompanions.Declaration.Fit(site: "mozilla.org", path: "/en-US/", selector: nil)
        XCTAssertTrue(fit.fitsAddress(try XCTUnwrap(URL(string: "https://developer.mozilla.org/en-US/"))))
        XCTAssertTrue(fit.fitsAddress(try XCTUnwrap(URL(string: "https://developer.mozilla.org/en-US/docs/Web"))))
        XCTAssertFalse(fit.fitsAddress(try XCTUnwrap(URL(string: "https://developer.mozilla.org/en-US"))))
        let encoded = BrowserCompanions.Declaration.Fit(site: nil, path: "/caf%C3%A9/", selector: ".menu")
        XCTAssertTrue(encoded.fitsAddress(try XCTUnwrap(URL(string: "https://example.com/caf%C3%A9/menu"))))
    }

    func testSelectorsWithAnyCombinatorAreRefused() {
        for selector in ["div a", "div\ta", "div\na", "div>a", "a,b", ":not(div a)"] {
            XCTAssertNotNil(BrowserCompanions.Declaration.selectorProblem(selector), selector)
        }
        for selector in [".wprm-recipe-container", "[itemtype*=\"schema.org/Recipe\"]", "[data-x=\"a b\"]", "div.recipe-card"] {
            XCTAssertNil(BrowserCompanions.Declaration.selectorProblem(selector), selector)
        }
    }

    // Two tabs first drawn alike share a revision. A click handled on one must not leave the other's buttons
    // refused for good while its surface stays the same.
    func testAClickOnOneTabLeavesAnotherTabWithTheSameSurfaceWorking() throws {
        let bridge = BrowserCompanions()
        let app = LampProject(id: "box", name: "Box", exe: "Box", dir: URL(fileURLWithPath: "/tmp/box"), instance: "box")
        let boot = UUID().uuidString, main = surface(actions: [["id": "save", "label": "Save", "readsPage": false]])
        func view(_ tab: String) -> String { bridge.native(["op": "surface-view", "app": app.id], tab: tab, projects: [app])["revision"] as? String ?? "" }
        func click(_ tab: String, _ revision: String) -> [String: Any] {
            bridge.native(["op": "surface-action", "app": app.id, "id": UUID().uuidString, "revision": revision, "action": "save",
                           "fields": [String: String]()], tab: tab, projects: [app])
        }
        _ = bridge.exchange(["boot": boot, "surface": main], app: app)
        _ = view("tA"); _ = view("tB")
        _ = bridge.exchange(["boot": boot, "surface": main, "surfaces": ["tA": main, "tB": main]], app: app)
        let a = view("tA"), b = view("tB")
        XCTAssertEqual(a, b, "both tabs were shown the shared revision")
        XCTAssertEqual(click("tA", a)["accepted"] as? Bool, true)
        let event = try XCTUnwrap(bridge.exchange(["boot": boot, "surface": main, "surfaces": ["tA": main, "tB": main]], app: app).1["event"] as? [String: Any])
        for _ in 0..<3 { _ = bridge.exchange(["boot": boot, "surface": main, "surfaces": ["tA": main, "tB": main], "ack": event["id"]!], app: app) }
        XCTAssertNotNil(click("tA", a)["error"], "tab A's old button is spent")
        XCTAssertEqual(click("tB", view("tB"))["accepted"] as? Bool, true, "tab B's buttons still work")
    }

    // Lamp's preview waits while the app works on a click (an AI answer can take a minute). The tab must stay open
    // meanwhile, or the app stops drawing for it and the draft the click prepares is lost.
    func testThePreviewKeepsItsTabOpenWhileAClickIsHandled() async throws {
        let bridge = BrowserCompanions()
        bridge.tabLifetime = 0.5
        let app = LampProject(id: "box", name: "Box", exe: "Box", dir: URL(fileURLWithPath: "/tmp/box"), instance: "box")
        let boot = UUID().uuidString, main = surface(actions: [["id": "read", "label": "Read", "readsPage": false]])
        _ = bridge.exchange(["boot": boot, "surface": main], app: app)
        let revision = try XCTUnwrap(bridge.native(["op": "surface-view", "app": app.id], tab: "preview", projects: [app])["revision"] as? String)
        let id = UUID().uuidString
        XCTAssertEqual(bridge.native(["op": "surface-action", "app": app.id, "id": id, "revision": revision, "action": "read",
                                      "fields": [String: String]()], tab: "preview", projects: [app])["accepted"] as? Bool, true)
        // The app, slower than the tab's lifetime: it keeps publishing, then acknowledges and draws the tab's draft.
        let draft = surface(title: "Review", actions: [["id": "save", "label": "Save", "readsPage": false]])
        let appSide = Task { @MainActor () -> [String] in
            var tabs: [String] = []
            for _ in 0..<6 {
                tabs = bridge.exchange(["boot": boot, "surface": main], app: app).1["tabs"] as? [String] ?? []
                try? await Task.sleep(for: .milliseconds(300))
            }
            _ = bridge.exchange(["boot": boot, "surface": main, "ack": id], app: app)
            _ = bridge.exchange(["boot": boot, "surface": main, "surfaces": ["preview": draft]], app: app)
            return tabs
        }
        let handled = await bridge.awaitHandled(id, in: app, tab: "preview", limit: 10)
        let tabsSeen = await appSide.value
        XCTAssertTrue(handled)
        XCTAssertEqual(tabsSeen, ["preview"], "the app was still told to draw the preview after the tab's lifetime")
        let shown = bridge.native(["op": "surface-view", "app": app.id], tab: "preview", projects: [app])
        XCTAssertEqual((shown["surface"] as? [String: Any])?["title"] as? String, "Review")
    }
}

@MainActor
final class BrowserLookTests: XCTestCase {
    // Whatever colors an app picks, from pale yellow to near black, on its own background or Lamp's tint, the text
    // the sidebar draws with them reads at 4.5:1 in light and dark.
    func testEveryAppColorStaysReadable() throws {
        let accents = ["#ffd60a", "#ffffff", "#000000", "#34c759", "#5ac8fa", "#ff2d55", "#3d5736", "#8e8e93"]
        let backgrounds: [String?] = [nil, "#ffffff", "#fff8e1", "#101418", "#2b1d3a"]
        for accent in accents {
            for background in backgrounds {
                let look = BrowserLook.Requested(accent: .init(light: accent, dark: accent),
                                                 background: background.map { .init(light: $0, dark: $0) })
                let drawn = BrowserLook.drawn(look)
                for palette in [drawn.light, drawn.dark] {
                    let where_ = "\(accent) on \(background ?? "tint")"
                    XCTAssertGreaterThanOrEqual(palette.ink.contrast(palette.background), 4.5, where_)
                    XCTAssertGreaterThanOrEqual(palette.muted.contrast(palette.background), 4.5, where_)
                    XCTAssertGreaterThanOrEqual(palette.accent.contrast(palette.background), 4.5, where_)
                    XCTAssertGreaterThanOrEqual(palette.onFill.contrast(palette.fill), 4.5, where_)
                }
            }
        }
    }

    // The extension sets only finished colors: a look that isn't plain colors and a known design never gets there.
    func testALookThatIsntPlainColorsIsRefused() {
        let app = LampProject(id: "notes", name: "Notes", exe: "Notes", dir: URL(fileURLWithPath: "/tmp/notes"), instance: "notes-instance")
        func publish(_ look: [String: Any]) -> Int {
            let surface: [String: Any] = ["title": "Notes", "detail": "", "sections": [], "fields": [], "actions": [], "busy": false, "look": look]
            return BrowserCompanions().exchange(["boot": UUID().uuidString, "surface": surface], app: app).0
        }
        XCTAssertEqual(publish(["accent": ["light": "#ff9500", "dark": "#ff9f0a"], "design": "rounded"]), 200)
        XCTAssertEqual(publish(["accent": ["light": "red;}body{background:url(https://x)", "dark": "#ff9f0a"]]), 400)
        XCTAssertEqual(publish(["accent": ["light": "#ff9500", "dark": "#ff9f0a"], "design": "Comic Sans\"}"]), 400)
    }
}
