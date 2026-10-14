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
}
