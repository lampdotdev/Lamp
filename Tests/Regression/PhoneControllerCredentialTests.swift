import XCTest
@testable import Lamp

/// The phone controllers' credentials: each holder gets into its own app's session as what it is, for as long as it's
/// given, and nothing else gets in.
final class PhoneControllerCredentialTests: XCTestCase {
    private let app = "padgame"

    func testACredentialGetsItsHolderInAsWhatItIs() {
        for kind in ControllerCredential.Kind.allCases {
            let token = ControllerCredential.issue(kind: kind, app: app, player: kind == .controller ? 3 : nil)
            XCTAssertEqual(ControllerCredential.check(token, kinds: [kind], app: app)?.kind, kind)
        }
        let controller = ControllerCredential.issue(kind: .controller, app: app, player: 3)
        XCTAssertEqual(ControllerCredential.check(controller, kinds: [.controller], app: app)?.player, 3)
    }

    func testAPhonesCredentialIsNeverAHostsAndAHostsIsNeverAPhones() {
        let join = ControllerCredential.issue(kind: .join, app: app)
        let controller = ControllerCredential.issue(kind: .controller, app: app, player: 1)
        let host = ControllerCredential.issue(kind: .host, app: app)
        XCTAssertNil(ControllerCredential.check(join, kinds: [.host], app: app))
        XCTAssertNil(ControllerCredential.check(controller, kinds: [.host], app: app))
        XCTAssertNil(ControllerCredential.check(host, kinds: [.join, .controller], app: app))
    }

    func testACredentialOpensNoOtherApp() {
        for kind in ControllerCredential.Kind.allCases {
            XCTAssertNil(ControllerCredential.check(ControllerCredential.issue(kind: kind, app: app), kinds: [kind], app: "otherapp"))
        }
    }

    func testAPhonesCredentialsRunOutInMinutes() {
        let now = Date()
        let join = ControllerCredential.issue(kind: .join, app: app, now: now)
        let controller = ControllerCredential.issue(kind: .controller, app: app, player: 1, now: now)
        XCTAssertNotNil(ControllerCredential.check(join, kinds: [.join], app: app, now: now.addingTimeInterval(14 * 60)))
        XCTAssertNil(ControllerCredential.check(join, kinds: [.join], app: app, now: now.addingTimeInterval(16 * 60)))
        XCTAssertNotNil(ControllerCredential.check(controller, kinds: [.controller], app: app, now: now.addingTimeInterval(60)))
        XCTAssertNil(ControllerCredential.check(controller, kinds: [.controller], app: app, now: now.addingTimeInterval(3 * 60)))
    }

    func testEndingASessionMakesItsCredentialsWorthless() {
        let other = "endedgame"
        let join = ControllerCredential.issue(kind: .join, app: other)
        let host = ControllerCredential.issue(kind: .host, app: other)
        ControllerCredential.forget(other)
        XCTAssertNil(ControllerCredential.check(join, kinds: [.join], app: other))
        XCTAssertNil(ControllerCredential.check(host, kinds: [.host], app: other))
        XCTAssertNotNil(ControllerCredential.check(ControllerCredential.issue(kind: .join, app: other), kinds: [.join], app: other))
    }

    func testAChangedCutOrForeignCredentialGetsNowhere() {
        let token = ControllerCredential.issue(kind: .controller, app: app, player: 1)
        let parts = token.split(separator: ".").map(String.init)
        var payload = (try? JSONSerialization.jsonObject(with: Data(urlSafeBase64: parts[0])!)) as! [String: Any]
        payload["k"] = "host"
        let asHost = (try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])).urlSafeBase64
        XCTAssertNil(ControllerCredential.check(asHost + "." + parts[1], kinds: [.host], app: app), "kind rewritten")
        let flipped = (parts[1].first == "A" ? "B" : "A") + String(parts[1].dropFirst())
        XCTAssertNil(ControllerCredential.check(parts[0] + "." + flipped, kinds: [.controller], app: app), "signature changed")
        XCTAssertNil(ControllerCredential.check(parts[0], kinds: [.controller], app: app), "no signature")
        XCTAssertNil(ControllerCredential.check(token + ".x", kinds: [.controller], app: app), "extra part")
        XCTAssertNil(ControllerCredential.check(nil, kinds: [.controller], app: app), "none")
        XCTAssertNil(ControllerCredential.check(String(repeating: "x", count: 5000), kinds: [.controller], app: app), "too long")
    }

    func testEveryCredentialIsNew() {
        let now = Date()
        XCTAssertNotEqual(ControllerCredential.issue(kind: .join, app: app, now: now), ControllerCredential.issue(kind: .join, app: app, now: now))
    }
}
