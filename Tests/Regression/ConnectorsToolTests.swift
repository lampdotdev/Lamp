import XCTest
@testable import Lamp

/// The builder may name a service the way it's written rather than by its id ("home-assistant", "intervals.icu").
final class ConnectorsToolTests: XCTestCase {
    func testAServiceIsFoundByItsNameAsWritten() {
        let app = LampProject(id: "dashboard", name: "Dashboard", exe: "Dashboard", dir: URL(fileURLWithPath: "/tmp/dashboard"))
        for asked in ["home-assistant", "Home Assistant", "homeassistant", "intervals.icu", "open-meteo", "Open Food Facts"] {
            let text = Connectors.answer(["service": asked], for: app).1["text"] as? String ?? ""
            XCTAssertFalse(text.hasPrefix("No connector"), "\(asked): \(text.prefix(80))")
        }
    }
}
