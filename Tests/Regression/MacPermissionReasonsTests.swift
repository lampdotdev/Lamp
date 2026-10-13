import XCTest
@testable import Lamp

/// macOS kills a Mac app that asks for the photo library, to add to it, or for Bluetooth when its Info.plist
/// doesn't say why. Every Mac app carries those reasons, wherever Lamp writes its Info.plist.
@MainActor
final class MacPermissionReasonsTests: XCTestCase {
    private var root: URL?
    private var team: Any?

    override func setUp() {
        team = UserDefaults.standard.object(forKey: "appleTeam")
        UserDefaults.standard.removeObject(forKey: "appleTeam")
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
        UserDefaults.standard.set(team, forKey: "appleTeam")
    }

    /// The keys macOS named when it refused each request and ended the app.
    private static let refusedWithout = ["NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription", "NSBluetoothAlwaysUsageDescription"]

    private func app(_ platform: Platform) throws -> LampProject {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-reasons-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        let project = try Template.draft(name: "Ann's Album", platform: platform, in: root)
        try Template.fill(project)
        return project
    }

    /// What the script's heredoc writes, read as the property list macOS will read.
    private func plist(in text: String) throws -> [String: Any] {
        let start = try XCTUnwrap(text.range(of: "<?xml")), end = try XCTUnwrap(text.range(of: "</plist>", range: start.upperBound..<text.endIndex))
        let data = Data(text[start.lowerBound..<end.upperBound].utf8)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testAMacAppSaysWhyItWantsPhotosAndBluetooth() throws {
        let project = try app(.mac)
        let info = try plist(in: String(contentsOf: project.dir.appendingPathComponent("build.sh"), encoding: .utf8))
        for key in Self.refusedWithout {
            XCTAssertEqual((info[key] as? String)?.hasPrefix("Ann's Album "), true, key)
        }
    }

    func testTheMacHalfOfAnAppForBothSaysSoToo() throws {
        let project = try app(.universal)
        let info = try plist(in: String(contentsOf: project.dir.appendingPathComponent(".lamp/device/Info-macOS.plist"), encoding: .utf8))
        for key in Self.refusedWithout {
            XCTAssertEqual((info[key] as? String)?.hasPrefix("Ann's Album "), true, key)
        }
    }
}
