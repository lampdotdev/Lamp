import XCTest
@testable import Lamp

/// Try On's list of simulators by name, and the choice an app keeps.
@MainActor
final class SimulatorChoiceTests: XCTestCase {
    private let listing = """
    {"devices": {
      "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
        {"name": "iPhone 17 Pro", "udid": "A", "state": "Shutdown"},
        {"name": "iPad Air 11-inch (M3)", "udid": "B", "state": "Shutdown"},
        {"name": "iPhone 16e", "udid": "C", "state": "Booted"},
        {"name": "Apple Watch Series 11", "udid": "W", "state": "Shutdown"}
      ],
      "com.apple.CoreSimulator.SimRuntime.iOS-18-6": [
        {"name": "iPhone 17 Pro", "udid": "D", "state": "Shutdown"}
      ],
      "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
        {"name": "iPhone 17 Pro", "udid": "F", "state": "Shutdown"}
      ],
      "com.apple.CoreSimulator.SimRuntime.iOS-16-4": [
        {"name": "iPhone 14", "udid": "E", "state": "Shutdown"}
      ]
    }}
    """

    func testIPhonesThenIPadsEachOnceWithTheIOSWhenANameRepeats() {
        let choices = Simulator.choices(listing: listing)
        XCTAssertEqual(choices.map(\.udid), ["C", "A", "D", "F", "B"], "iPhones first, by name, newest iOS first by the whole version; no watch, nothing too old")
        XCTAssertEqual(choices.map(\.label), ["iPhone 16e", "iPhone 17 Pro (iOS 26.0)", "iPhone 17 Pro (iOS 18.6)", "iPhone 17 Pro (iOS 18.5)", "iPad Air 11-inch (M3)"])
        XCTAssertEqual(choices.last?.family, .ipad)
    }

    func testTheChoiceIsKeptWithTheApp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-simulator-choice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var project = try Template.draft(name: "Island", platform: .iphone, in: root)
        project.simulator = "A"
        try Template.saveMeta(project)
        let meta = try JSONDecoder().decode(ProjectMeta.self, from: Data(contentsOf: project.dir.appendingPathComponent(".lamp/meta.json")))
        XCTAssertEqual(meta.simulator, "A")
        var mac = project; mac.platform = .mac
        try Template.saveMeta(mac)
        XCTAssertNil(try JSONDecoder().decode(ProjectMeta.self, from: Data(contentsOf: project.dir.appendingPathComponent(".lamp/meta.json"))).simulator)
    }
}
