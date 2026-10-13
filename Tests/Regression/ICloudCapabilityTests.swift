import XCTest
@testable import Lamp

/// `icloud` in capabilities.json: the CloudKit entitlements and the container's name in Info.plist, for apps
/// Apple signs for a team, and nothing for a Mac app on its own.
@MainActor
final class ICloudCapabilityTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

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
        let entitlements = capabilities.entitlementsPlist(for: both)
        XCTAssertTrue(entitlements.contains("<key>com.apple.developer.icloud-container-identifiers</key><array><string>iCloud.\(both.bundleID)</string></array>"))
        XCTAssertTrue(entitlements.contains("<key>com.apple.developer.icloud-services</key><array><string>CloudKit</string></array>"))
        XCTAssertEqual(capabilities.icloudPlistLine(for: both), "  <key>LampICloudContainer</key><string>iCloud.\(both.bundleID)</string>")
        var phone = both; phone.platform = .iphone
        XCTAssertEqual(capabilities.container(for: phone), "iCloud." + phone.bundleID)
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
