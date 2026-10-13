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

    func testTheProjectsPlistsCarryTheContainer() throws {
        let project = try app(.universal)
        try Template.fill(project)
        try #"{"icloud": true}"#.write(to: project.dir.appendingPathComponent("capabilities.json"), atomically: true, encoding: .utf8)
        try Template.writeDeviceProject(for: project, team: "ABCDE12345")
        func text(_ path: String) throws -> String { try String(contentsOf: project.dir.appendingPathComponent(".lamp/device/" + path), encoding: .utf8) }
        let container = "iCloud." + project.bundleID
        XCTAssertTrue(try text("App.entitlements").contains(container))
        XCTAssertTrue(try text("Info.plist").contains("<key>LampICloudContainer</key><string>\(container)</string>"))
        XCTAssertTrue(try text("Info-macOS.plist").contains("<key>LampICloudContainer</key><string>\(container)</string>"))
        XCTAssertTrue(try text("App-macOS.entitlements").contains("com.apple.developer.aps-environment"))
        XCTAssertTrue(try text("Info.plist").contains("<key>UIBackgroundModes</key><array><string>remote-notification</string></array>"))
        XCTAssertTrue(try text("\(project.exe).xcodeproj/project.pbxproj").contains("\"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]\" = \"App-macOS.entitlements\""))
        // Taken back when no longer declared.
        try FileManager.default.removeItem(at: project.dir.appendingPathComponent("capabilities.json"))
        try Template.writeDeviceProject(for: project, team: "ABCDE12345")
        XCTAssertFalse(try text("Info.plist").contains("LampICloudContainer"))
        XCTAssertFalse(try text("App.entitlements").contains("icloud"))
    }

    func testTheAgentIsToldForAppsWithAnIPhoneHalfOnly() throws {
        let both = try app(.universal)
        XCTAssertTrue(Agent.systemPrompt(for: both).contains("LampSync.collection("))
        var phone = both; phone.platform = .iphone
        XCTAssertTrue(Agent.systemPrompt(for: phone).contains("LampSync.collection("))
        var mac = both; mac.platform = .mac
        XCTAssertFalse(Agent.systemPrompt(for: mac).contains("LampSync"))
    }
}
