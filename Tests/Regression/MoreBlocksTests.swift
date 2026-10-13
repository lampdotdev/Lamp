import XCTest
@testable import Lamp

/// Photos, Location, Weather, Music and Home: the entitlements each needs, where they go by kind of app,
/// and what the agent is told.
@MainActor
final class MoreBlocksTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func app(_ platform: Platform) throws -> LampProject {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-blocks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        return try Template.draft(name: "Day Book", platform: platform, in: root)
    }

    func testWeatherIsSignedForOnBothHalvesAndHomeOnTheIPhoneOnly() throws {
        var capabilities = Template.Capabilities()
        capabilities.weather = true
        capabilities.homekit = true
        XCTAssertEqual(capabilities.checked.weather, true)
        XCTAssertEqual(capabilities.checked.homekit, true)
        let both = try app(.universal)
        XCTAssertTrue(capabilities.weather(for: both))
        XCTAssertTrue(capabilities.entitlementsPlist(for: both, platform: .ios).contains("<key>com.apple.developer.weatherkit</key><true/>"))
        XCTAssertTrue(capabilities.entitlementsPlist(for: both, platform: .mac).contains("<key>com.apple.developer.weatherkit</key><true/>"))
        XCTAssertTrue(capabilities.entitlementsPlist(for: both, platform: .ios).contains("<key>com.apple.developer.homekit</key><true/>"))
        XCTAssertFalse(capabilities.entitlementsPlist(for: both, platform: .mac).contains("homekit"), "a Mac has no home to control")
        // A Mac app on its own carries Lamp's signature, which can claim neither.
        var mac = both; mac.platform = .mac
        XCTAssertFalse(capabilities.weather(for: mac))
        XCTAssertFalse(capabilities.entitlementsPlist(for: mac, platform: .mac).contains("weatherkit"))
        XCTAssertFalse(capabilities.entitlementsPlist(for: mac, platform: .mac).contains("homekit"))
    }

    func testEveryBlockHasItsReasonInThePlists() throws {
        let ios = Template.iosUsageDescriptions.map(\.key)
        for key in ["NSPhotoLibraryUsageDescription", "NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription", "NSAppleMusicUsageDescription", "NSHomeKitUsageDescription"] {
            XCTAssertTrue(ios.contains(key), key)
        }
        let mac = Template.macUsageDescriptions.map(\.key)
        for key in ["NSPhotoLibraryUsageDescription", "NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription", "NSAppleMusicUsageDescription"] {
            XCTAssertTrue(mac.contains(key), key)
        }
    }

    func testTheAgentIsToldWhatEachKindOfAppHas() throws {
        let both = try app(.universal)
        let universal = Agent.systemPrompt(for: both)
        var phone = both; phone.platform = .iphone
        var mac = both; mac.platform = .mac
        let iPhone = Agent.systemPrompt(for: phone), macOnly = Agent.systemPrompt(for: mac)
        for block in ["LampPhotos", "LampLocation", "LampWeather", "LampMusic"] {
            XCTAssertTrue(universal.contains("`\(block)`"), block)
            XCTAssertTrue(iPhone.contains("`\(block)`"), block)
            XCTAssertTrue(macOnly.contains("`\(block)`"), block)
        }
        XCTAssertTrue(iPhone.contains("`LampHome`"))
        XCTAssertTrue(universal.contains("`LampHome` only under"))
        XCTAssertFalse(macOnly.contains("LampHome"))
        XCTAssertTrue(iPhone.contains("\"weather\": true, \"homekit\": true"))
    }
}
