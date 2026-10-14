import XCTest
@testable import Lamp

/// `icloud` in capabilities.json: the CloudKit entitlements and the container's name in Info.plist, for apps
/// Apple signs for a team, and nothing for a Mac app on its own.
@MainActor
final class ICloudCapabilityTests: XCTestCase {
    private var root: URL?
    private var team: Any?

    override func setUp() {
        team = UserDefaults.standard.object(forKey: "appleTeam")
        UserDefaults.standard.set("ABCDE12345", forKey: "appleTeam")
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
        UserDefaults.standard.set(team, forKey: "appleTeam")
    }

    private func app(_ platform: Platform) throws -> LampProject {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-icloud-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        return try Template.draft(name: "Cloud Notes", platform: platform, in: root)
    }

    func testAnAppWithAnIPhoneHalfGetsAContainerAndAMacAppDoesNot() throws {
        var capabilities = Template.Capabilities()
        capabilities.icloud = true
        XCTAssertEqual(capabilities.checked.icloud, true)
        let both = try app(.universal)
        XCTAssertEqual(capabilities.container(for: both), "iCloud." + both.bundleID)
        XCTAssertTrue(both.bundleID.hasSuffix(".abcde12345"), "the container carries the team")
        let entitlements = capabilities.entitlementsPlist(for: both, platform: .ios)
        XCTAssertTrue(entitlements.contains("<key>com.apple.developer.icloud-container-identifiers</key><array><string>iCloud.\(both.bundleID)</string></array>"))
        XCTAssertTrue(entitlements.contains("<key>com.apple.developer.icloud-services</key><array><string>CloudKit</string></array>"))
        // Push, so the engine hears of changes made elsewhere: spelled for each platform.
        XCTAssertTrue(entitlements.contains("<key>aps-environment</key><string>development</string>"))
        XCTAssertTrue(capabilities.entitlementsPlist(for: both, platform: .mac).contains("<key>com.apple.developer.aps-environment</key><string>development</string>"))
        XCTAssertFalse(capabilities.entitlementsPlist(for: both, platform: .mac).contains("<key>aps-environment</key>"))
        XCTAssertEqual(capabilities.lists["UIBackgroundModes"], ["remote-notification"])
        XCTAssertEqual(capabilities.icloudPlistLine(for: both), "  <key>LampICloudContainer</key><string>iCloud.\(both.bundleID)</string>")
        // An iPhone app's container carries the team too, though its simulator bundle doesn't: containers are global.
        var phone = both; phone.platform = .iphone
        XCTAssertEqual(capabilities.container(for: phone), "iCloud." + phone.deviceBundleID(team: "ABCDE12345"))
        XCTAssertNotEqual(capabilities.container(for: phone), "iCloud." + phone.bundleID)
        var mac = both; mac.platform = .mac
        XCTAssertNil(capabilities.container(for: mac))
        XCTAssertFalse(capabilities.entitlementsPlist(for: mac).contains("icloud"))
        XCTAssertEqual(capabilities.icloudPlistLine(for: mac), "")
        XCTAssertNil(Template.Capabilities().container(for: both))
    }
}
