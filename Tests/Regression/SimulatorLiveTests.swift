import XCTest
@testable import Lamp

/// The driver against a real simulator window, for checking by hand what unit tests can't: it taps and
/// reads another app's window on this Mac's screen, so it only runs when asked.
///
///     LAMP_LIVE_UDID=<booted simulator> LAMP_LIVE_ACTIONS='[{"action":"click","x":100,"y":200}]' \
///         swift test --filter SimulatorLiveTests
///
/// It prints what `use_app` would answer: why the screen can't be used, or what each action did and the
/// screen as text afterwards. Without LAMP_LIVE_ACTIONS it only reads.
final class SimulatorLiveTests: XCTestCase {
    func testDriveTheSimulatorWindow() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let udid = environment["LAMP_LIVE_UDID"] else { throw XCTSkip("Set LAMP_LIVE_UDID to a booted simulator to run this.") }
        let began = Date()
        let found = await Simulator.Driver.screen(of: udid, owner: "live")
        print(String(format: "LIVE found in %.2f s", Date().timeIntervalSince(began)))
        guard case .success(let screen) = found else {
            if case .failure(let trouble) = found { print("LIVE trouble \(trouble): " + trouble.message(viewer: Simulator.viewerName(), device: "iPhone")) }
            return
        }
        print("LIVE screen \(screen.rect) zoom \(screen.zoom) in \(screen.viewer)")
        if let json = environment["LAMP_LIVE_ACTIONS"]?.data(using: .utf8) {
            let actions = try JSONDecoder().decode([Simulator.Driver.Action].self, from: json)
            let picture = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-live-\(udid).png")
            _ = await Simulator.screenshot(on: udid, to: picture)
            print("LIVE report\n" + (await Simulator.Driver.perform(actions, on: screen, picture: picture) { true }))
        }
        let reading = Date()
        let text = await Simulator.Driver.screenText(on: screen)
        print(String(format: "LIVE text in %.2f s\n", Date().timeIntervalSince(reading)) + (text ?? "(none)"))
    }
}
