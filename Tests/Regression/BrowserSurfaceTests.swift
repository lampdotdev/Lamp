import XCTest
@testable import Lamp

@MainActor
final class BrowserSurfaceTests: XCTestCase {
    // Completed actions stay invalid after retry IDs expire or the app restarts.
    func testCompletedActionsAndRestartsInvalidateTheDisplayedRevision() throws {
        let bridge = BrowserSurfacePrototype()
        let app = LampProject(id: "recipes", name: "Recipes", exe: "Recipes", dir: URL(fileURLWithPath: "/tmp/recipes"), instance: "recipe-instance")
        let surface: [String: Any] = ["title": "Recipes", "detail": "", "sections": [], "fields": [],
                                      "actions": [["id": "save", "label": "Save", "readsPage": false]], "busy": false]
        let boot = UUID().uuidString
        func publish(_ boot: String, ack: String? = nil) -> [String: Any] {
            var body: [String: Any] = ["boot": boot, "surface": surface]
            if let ack { body["ack"] = ack }
            return bridge.exchange(body, app: app).1
        }
        func revision() throws -> String {
            try XCTUnwrap(bridge.native(["op": "surface-view", "app": app.id], projects: [app])["revision"] as? String)
        }
        func send(_ id: String, revision: String) -> [String: Any] {
            bridge.native(["op": "surface-action", "app": app.id, "id": id, "revision": revision,
                           "action": "save", "fields": [String: String]()], projects: [app])
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
    func testSelectionActionsRequireSelectionCaptureAndKeepOldPageActionsWorking() throws {
        let app = LampProject(id: "reader", name: "Reader", exe: "Reader", dir: URL(fileURLWithPath: "/tmp/reader"), instance: "reader-instance")
        func exercise(selection: Bool) throws {
            let bridge = BrowserSurfacePrototype(), boot = UUID().uuidString
            var action: [String: Any] = ["id": "read", "label": "Read", "readsPage": !selection]
            if selection { action["readsSelection"] = true } // Old apps omit this field.
            let surface: [String: Any] = ["title": "Reader", "detail": "", "sections": [], "fields": [], "actions": [action], "busy": false]
            let publish: [String: Any] = ["boot": boot, "surface": surface]
            XCTAssertEqual(bridge.exchange(publish, app: app).0, 200)
            let revision = try XCTUnwrap(bridge.native(["op": "surface-view", "app": app.id], projects: [app])["revision"])
            var request: [String: Any] = ["op": "surface-action", "app": app.id, "id": UUID().uuidString,
                                          "revision": revision, "action": "read", "fields": [String: String]()]
            if selection {
                XCTAssertNotNil(bridge.native(request, projects: [app])["error"])
                request["page"] = ["url": "https://example.test/article", "title": "Article", "text": "Unselected article", "scope": "page"]
                XCTAssertNotNil(bridge.native(request, projects: [app])["error"])
            }
            var page = ["url": "https://example.test/article", "title": "Article", "text": "Chosen passage"]
            if selection { page["scope"] = "selection" }
            request["page"] = page
            XCTAssertEqual(bridge.native(request, projects: [app])["accepted"] as? Bool, true)
            let event = try XCTUnwrap(bridge.exchange(publish, app: app).1["event"] as? [String: Any])
            XCTAssertEqual((event["page"] as? [String: String])?["text"], "Chosen passage")
            XCTAssertEqual((event["page"] as? [String: String])?["scope"], selection ? "selection" : "page")
        }
        try exercise(selection: true)
        try exercise(selection: false)
    }

    func testAnActionCannotRequestBothThePageAndTheSelection() {
        let app = LampProject(id: "reader", name: "Reader", exe: "Reader", dir: URL(fileURLWithPath: "/tmp/reader"))
        let surface: [String: Any] = ["title": "Reader", "detail": "", "sections": [], "fields": [],
                                     "actions": [["id": "read", "label": "Read", "readsPage": true, "readsSelection": true]], "busy": false]
        XCTAssertEqual(BrowserSurfacePrototype().exchange(["boot": UUID().uuidString, "surface": surface], app: app).0, 400)
    }

}
