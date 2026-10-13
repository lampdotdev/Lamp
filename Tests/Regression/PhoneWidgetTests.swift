import XCTest
@testable import Lamp

/// Home screen widgets and Live Activities for iPhone apps and the iPhone half of an app for both: the
/// generated Package.swift and build.sh, the extension's Info.plist and entitlements, the Xcode project's
/// extension target, the code both sides share, and what the agent is told.
@MainActor
final class PhoneWidgetTests: XCTestCase {
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

    private func app(_ platform: Platform, widget: Bool = true, shared: Bool = false) throws -> LampProject {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-phone-widget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        let project = try Template.draft(name: "Tea Timer", platform: platform, in: root)
        try Template.fill(project)
        if widget {
            let folder = project.dir.appendingPathComponent("Widget")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "import WidgetKit\n".write(to: folder.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
            if shared {
                try FileManager.default.createDirectory(at: folder.appendingPathComponent("Shared"), withIntermediateDirectories: true)
                try "struct Shared {}\n".write(to: folder.appendingPathComponent("Shared/Attributes.swift"), atomically: true, encoding: .utf8)
            }
        }
        try Template.writeOwnedFiles(for: project)
        return project
    }

    private func text(_ path: String, in project: LampProject) throws -> String {
        try String(contentsOf: project.dir.appendingPathComponent(path), encoding: .utf8)
    }

    func testAnIPhoneAppWithAWidgetBuildsItsExtension() throws {
        let project = try app(.iphone)
        XCTAssertTrue(Template.hasWidget(project))
        XCTAssertFalse(Template.isWidgetOnly(project), "only a Mac app can be just its widget")
        let package = try text("Package.swift", in: project)
        XCTAssertTrue(package.contains(".executableTarget(name: \"TeaTimer\", path: \"Sources\")"))
        XCTAssertTrue(package.contains(".executableTarget(name: \"TeaTimerWidget\", path: \"Widget\""))
        XCTAssertTrue(package.contains("_NSExtensionMain"))
        let build = try text("build.sh", in: project)
        XCTAssertTrue(build.contains("swift build \"${FLAGS[@]}\" --product TeaTimer 2>&1"))
        XCTAssertTrue(build.contains("swift build \"${WFLAGS[@]}\" --product TeaTimerWidget 2>&1"))
        XCTAssertTrue(build.contains("WIDGET=\"$APP/PlugIns/TeaTimerWidget.appex\""))
        XCTAssertTrue(build.contains("<key>CFBundlePackageType</key><string>XPC!</string>"))
        XCTAssertTrue(build.contains("<key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>"))
        XCTAssertTrue(build.contains("<key>CFBundleIdentifier</key><string>\(project.bundleID).widget</string>"))
        XCTAssertTrue(build.contains("<key>MinimumOSVersion</key><string>17.0</string>"))
        XCTAssertTrue(build.contains("<key>NSSupportsLiveActivities</key><true/>"))
        XCTAssertTrue(build.contains("<key>LampAppGroup</key><string>group.\(project.bundleID)</string>"))
        // The extension is signed before the app around it.
        let widgetSign = try XCTUnwrap(build.range(of: "codesign --force -s - \"$WIDGET\""))
        let appSign = try XCTUnwrap(build.range(of: "codesign --force -s - \"$APP\""))
        XCTAssertLessThan(widgetSign.lowerBound, appSign.lowerBound)
        // The shell takes the whole script.
        let parse = Process()
        parse.executableURL = URL(fileURLWithPath: "/bin/zsh")
        parse.arguments = ["-n", project.dir.appendingPathComponent("build.sh").path]
        try parse.run()
        parse.waitUntilExit()
        XCTAssertEqual(parse.terminationStatus, 0)
        // Both binaries carry the app group, each with its own identity.
        let app = try text(".lamp/entitlements.plist", in: project)
        let widget = try text(".lamp/widget-entitlements.plist", in: project)
        XCTAssertTrue(app.contains("<string>group.\(project.bundleID)</string>"))
        XCTAssertTrue(widget.contains("<string>group.\(project.bundleID)</string>"))
        XCTAssertTrue(widget.contains("<key>application-identifier</key><string>ABCDE12345.\(project.bundleID).widget</string>"))
        // Lamp's own file in the widget is the iPhone's, reading the shared folder.
        let support = try text("Widget/LampWidgetSupport.swift", in: project)
        XCTAssertTrue(support.contains("forSecurityApplicationGroupIdentifier"))
        XCTAssertFalse(support.contains("NWConnection"))
    }

    func testWithoutAWidgetNothingChanges() throws {
        let project = try app(.iphone, widget: false)
        XCTAssertEqual(try text("Package.swift", in: project).replacingOccurrences(of: "TeaTimer", with: "{{EXE}}"), Template.iPhonePackageSwift)
        XCTAssertFalse(try text("build.sh", in: project).contains("Widget"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.dir.appendingPathComponent(".lamp/widget-entitlements.plist").path))
    }

    func testSharedCodeIsLinkedIntoSourcesAndTakenAwayWithIt() throws {
        let project = try app(.iphone, shared: true)
        let link = project.dir.appendingPathComponent("Sources/WidgetShared")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), "../Widget/Shared")
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.appendingPathComponent("Attributes.swift").path))
        try FileManager.default.removeItem(at: project.dir.appendingPathComponent("Widget/Shared"))
        try Template.writeOwnedFiles(for: project)
        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path))
    }

    func testTheXcodeProjectHasTheExtensionTarget() throws {
        let both = try app(.universal)
        let device = both.dir.appendingPathComponent(".lamp/device")
        let pbxproj = try String(contentsOf: device.appendingPathComponent("TeaTimer.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertTrue(pbxproj.contains("productType = \"com.apple.product-type.app-extension\""))
        XCTAssertTrue(pbxproj.contains("PRODUCT_BUNDLE_IDENTIFIER = \"\(both.bundleID).widget\""))
        XCTAssertTrue(pbxproj.contains("dstSubfolderSpec = 13"))
        XCTAssertTrue(pbxproj.contains("targets = (A0000000000000000000000B /* TeaTimer */, B00000000000000000000005 /* TeaTimerWidget */);"))
        // The Mac half builds without it.
        XCTAssertEqual(pbxproj.components(separatedBy: "platformFilter = ios;").count - 1, 2)
        // The app target compiles Widget/Shared/ too, as a group of its own: Xcode doesn't follow the link.
        XCTAssertTrue(pbxproj.contains("fileSystemSynchronizedGroups = (A00000000000000000000007 /* Sources */, B0000000000000000000000C /* Shared */);"))
        let widgetPlist = try String(contentsOf: device.appendingPathComponent("Widget-Info.plist"), encoding: .utf8)
        XCTAssertTrue(widgetPlist.contains("com.apple.widgetkit-extension"))
        let group = Template.appGroup(for: both, onDevice: true)
        XCTAssertTrue(widgetPlist.contains("<key>LampAppGroup</key><string>\(group)</string>"))
        XCTAssertTrue(try String(contentsOf: device.appendingPathComponent("Info.plist"), encoding: .utf8).contains("<key>NSSupportsLiveActivities</key><true/>"))
        XCTAssertTrue(try String(contentsOf: device.appendingPathComponent("Widget.entitlements"), encoding: .utf8).contains(group))
        XCTAssertTrue(try String(contentsOf: device.appendingPathComponent("App.entitlements"), encoding: .utf8).contains(group))
        XCTAssertFalse(try String(contentsOf: device.appendingPathComponent("App-macOS.entitlements"), encoding: .utf8).contains("application-groups"))
        // The simulator half's script builds the extension too, into the iOS folder.
        let build = try text("build.sh", in: both)
        XCTAssertTrue(build.contains("--product TeaTimerWidget"))
        XCTAssertTrue(build.contains("APP=\"build/iOS/TeaTimer.app\""))
        // A phone's own project, with the team in the ids.
        var phone = both; phone.platform = .iphone
        try Template.saveMeta(phone)
        try Template.writeDeviceProject(for: phone, team: "ABCDE12345")
        let phoneProject = try String(contentsOf: device.appendingPathComponent("TeaTimer.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertTrue(phoneProject.contains("PRODUCT_BUNDLE_IDENTIFIER = \"\(phone.deviceBundleID(team: "ABCDE12345")).widget\""))
        XCTAssertEqual(Template.appGroup(for: phone, onDevice: true), "group." + phone.deviceBundleID(team: "ABCDE12345"))
    }

    func testTheAgentIsToldOnlyWhereThereIsAPhone() throws {
        let both = try app(.universal)
        var phone = both; phone.platform = .iphone
        var mac = both; mac.platform = .mac
        XCTAssertTrue(Agent.systemPrompt(for: phone).contains(Agent.Rules.iPhoneWidget))
        XCTAssertTrue(Agent.systemPrompt(for: both).contains("home screen widgets and Live Activities"))
        XCTAssertFalse(Agent.systemPrompt(for: mac).contains("home screen widgets"))
    }
}
