import XCTest
@testable import Lamp

/// A Mac app's desktop widget: Swift in the app's Widget folder becomes a second program in Lamp's build, put
/// into the app as a widget extension and signed by itself, sandboxed, inside the unsandboxed app.
final class WidgetBuildTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func app(_ name: String = "Tide Clock", platform: Platform = .mac) throws -> LampProject {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-widget-test-\(UUID().uuidString)")
        self.root = root
        return try Template.scaffold(name: name, platform: platform, in: root)
    }

    private func addWidget(to project: LampProject) throws {
        let folder = project.dir.appendingPathComponent("Widget")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.widgetSwift.write(to: folder.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
    }

    private func text(_ path: String, in project: LampProject) throws -> String {
        try String(contentsOf: project.dir.appendingPathComponent(path), encoding: .utf8)
    }

    @discardableResult
    private func run(_ command: String, in directory: URL, env: [String: String] = [:]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // MARK: - What Lamp writes

    func testAnAppWithoutAWidgetBuildsAsBefore() throws {
        let project = try app()
        XCTAssertFalse(Template.hasWidget(project))
        let package = try text("Package.swift", in: project)
        let build = try text("build.sh", in: project)
        XCTAssertFalse(package.contains("Widget"))
        XCTAssertFalse(package.contains("unsafeFlags"))
        XCTAssertFalse(build.contains("PlugIns"))
        XCTAssertFalse(build.contains("entitlements"))
    }

    func testSwiftInTheWidgetFolderAddsTheSecondProgram() throws {
        let project = try app()
        // An empty folder, or one with no Swift in it, is not a widget: SwiftPM refuses a target with no code.
        try FileManager.default.createDirectory(at: project.dir.appendingPathComponent("Widget"), withIntermediateDirectories: true)
        try "notes".write(to: project.dir.appendingPathComponent("Widget/README.md"), atomically: true, encoding: .utf8)
        XCTAssertFalse(Template.hasWidget(project))

        try addWidget(to: project)
        XCTAssertTrue(Template.hasWidget(project))
        try Template.writeOwnedFiles(for: project)
        let package = try text("Package.swift", in: project)
        XCTAssertTrue(package.contains(#".executableTarget(name: "TideClock", path: "Sources")"#))
        XCTAssertTrue(package.contains(#".executableTarget(name: "TideClockWidget", path: "Widget""#))
        XCTAssertTrue(package.contains("_NSExtensionMain"))
        let build = try text("build.sh", in: project)
        XCTAssertTrue(build.contains(#"WIDGET="$APP/Contents/PlugIns/TideClockWidget.appex""#))
        XCTAssertTrue(build.contains("<string>\(project.bundleID).widget</string>"))
        XCTAssertTrue(build.contains("com.apple.widgetkit-extension"))
        // The widget is signed before the app around it, or the app's signature wouldn't cover it.
        let widgetSigned = try XCTUnwrap(build.range(of: #"codesign --force -s - --entitlements "build/TideClockWidget.entitlements" "$WIDGET""#))
        let appSigned = try XCTUnwrap(build.range(of: #"codesign --force -s - "$APP""#))
        XCTAssertLessThan(widgetSigned.lowerBound, appSigned.lowerBound)

        // Deleting the widget's code takes the second program away again.
        try FileManager.default.removeItem(at: project.dir.appendingPathComponent("Widget/Widget.swift"))
        try Template.writeOwnedFiles(for: project)
        XCTAssertFalse(try text("Package.swift", in: project).contains("Widget"))
        XCTAssertFalse(try text("build.sh", in: project).contains("PlugIns"))
    }

    func testAnIPhoneAppGetsNoWidget() throws {
        let project = try app(platform: .iphone)
        try addWidget(to: project)
        XCTAssertFalse(Template.hasWidget(project))
        try Template.writeOwnedFiles(for: project)
        XCTAssertFalse(try text("Package.swift", in: project).contains("Widget"))
    }

    func testAChangeToTheWidgetNeedsABuild() throws {
        let project = try app()
        let before = Runtime.fingerprint(project)
        try addWidget(to: project)
        let added = Runtime.fingerprint(project)
        XCTAssertNotEqual(before, added)
        try (Self.widgetSwift + "\n// changed").write(to: project.dir.appendingPathComponent("Widget/Widget.swift"), atomically: true, encoding: .utf8)
        XCTAssertNotEqual(added, Runtime.fingerprint(project))
    }

    // MARK: - Signing

    func testTheWidgetIsSandboxedAndNothingOfTheAppsIsOpenedToIt() throws {
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(Template.widgetEntitlementsPlist.utf8), format: nil) as? [String: Any])
        XCTAssertEqual(plist["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(plist["com.apple.security.network.client"] as? Bool, true)
        // How a widget reads its app's data isn't decided (Template.WidgetSharing): until it is, the
        // signature carries no app group and no exception to the sandbox, and the agent is told there's no way.
        XCTAssertEqual(Set(plist.keys), ["com.apple.security.app-sandbox", "com.apple.security.network.client"])
        XCTAssertTrue(Template.WidgetSharing.entitlements.isEmpty)
        XCTAssertTrue(Agent.Rules.widget.contains(Template.WidgetSharing.rule))
    }

    func testTheWidgetIsSignedBeforeTheApp() {
        XCTAssertEqual(AppSigning.command(adHoc: true, widget: false), #"codesign --force -s - "$LAMP_APP" 2>&1"#)
        XCTAssertEqual(AppSigning.command(adHoc: false, widget: false),
                       #"codesign --force --keychain "$LAMP_KEYCHAIN" -s "$LAMP_IDENTITY" "$LAMP_APP" 2>&1"#)
        XCTAssertEqual(AppSigning.command(adHoc: false, widget: true),
                       #"codesign --force --keychain "$LAMP_KEYCHAIN" -s "$LAMP_IDENTITY" --entitlements "$LAMP_WIDGET_ENTITLEMENTS" "$LAMP_WIDGET" 2>&1 && "#
                       + #"codesign --force --keychain "$LAMP_KEYCHAIN" -s "$LAMP_IDENTITY" "$LAMP_APP" 2>&1"#)
    }

    // MARK: - What the agent is told

    func testOnlyAMacAppIsToldItCanHaveAWidget() {
        let mac = Agent.systemPrompt
        XCTAssertTrue(mac.contains("Widget/Widget.swift"))
        XCTAssertTrue(mac.contains("Edit Widgets"))
        XCTAssertTrue(mac.contains("containerBackground(for: .widget)"))
        XCTAssertTrue(mac.contains("(and a widget's code in Widget/)"))
        for family in [DeviceFamily.iphone, .ipad] {
            let phone = Agent.iPhonePrompt(for: family)
            XCTAssertFalse(phone.contains("Widget/"))
            XCTAssertFalse(phone.contains("Edit Widgets"))
            XCTAssertTrue(phone.contains("Not possible yet: widgets, Live Activities"))
        }
    }

    // MARK: - A real build

    /// The whole way through with the real tools: SwiftPM builds both programs, build.sh makes the bundle, and
    /// Lamp's signing command, here ad hoc as when there's no certificate, leaves a widget macOS would accept.
    func testAnAppWithAWidgetBuildsAndSigns() throws {
        let project = try app()
        try addWidget(to: project)
        try Template.writeOwnedFiles(for: project)
        let built = try run(Shell.compatibleSDK + "./build.sh", in: project.dir)
        XCTAssertEqual(built.status, 0, String(built.output.suffix(3000)))

        let widget = Template.widgetURL(in: project.builtURL, of: project)
        XCTAssertEqual(widget.path, project.builtURL.path + "/Contents/PlugIns/TideClockWidget.appex")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: widget.appendingPathComponent("Contents/MacOS/TideClockWidget").path))
        let info = try XCTUnwrap(NSDictionary(contentsOf: widget.appendingPathComponent("Contents/Info.plist")) as? [String: Any])
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, Template.widgetBundleID(for: project))
        XCTAssertEqual(info["CFBundlePackageType"] as? String, "XPC!")
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Tide Clock")
        XCTAssertEqual((info["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String, "com.apple.widgetkit-extension")
        XCTAssertNotNil(Int(info["CFBundleVersion"] as? String ?? ""))

        // Signed again the way an install does, with the entitlements Lamp writes itself.
        let entitlements = project.dir.appendingPathComponent(".lamp/widget-entitlements.plist")
        try Template.widgetEntitlementsPlist.write(to: entitlements, atomically: true, encoding: .utf8)
        let signed = try run(AppSigning.command(adHoc: true, widget: true), in: project.dir,
                             env: ["LAMP_APP": project.builtURL.path, "LAMP_WIDGET": widget.path, "LAMP_WIDGET_ENTITLEMENTS": entitlements.path])
        XCTAssertEqual(signed.status, 0, signed.output)
        let verified = try run("codesign --verify --deep --strict \"$APP\" 2>&1", in: project.dir, env: ["APP": project.builtURL.path])
        XCTAssertEqual(verified.status, 0, verified.output)
        let widgetHas = try run("codesign -d --entitlements - --xml \"$CODE\" 2>/dev/null", in: project.dir, env: ["CODE": widget.path]).output
        XCTAssertTrue(widgetHas.contains("com.apple.security.app-sandbox"), widgetHas)
        // The app itself stays unsandboxed: everything a Lamp app does (its files, Lamp's gateway) depends on it.
        let appHas = try run("codesign -d --entitlements - --xml \"$CODE\" 2>/dev/null", in: project.dir, env: ["CODE": project.builtURL.path]).output
        XCTAssertFalse(appHas.contains("app-sandbox"), appHas)
    }

    static let widgetSwift = """
    import WidgetKit
    import SwiftUI

    struct Entry: TimelineEntry { let date: Date }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: .now) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(date: .now)], policy: .after(.now.addingTimeInterval(900))))
        }
    }

    @main
    struct TideWidget: Widget {
        var body: some WidgetConfiguration {
            StaticConfiguration(kind: "tide", provider: Provider()) { entry in
                Text(entry.date, style: .time)
                    .containerBackground(for: .widget) { Color.teal }
            }
            .configurationDisplayName("Tide Clock")
            .description("The time.")
            .supportedFamilies([.systemSmall])
        }
    }

    """
}
