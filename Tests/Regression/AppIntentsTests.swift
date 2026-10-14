import XCTest
@testable import Lamp

/// App Intents in a package build: build.sh asks the compiler for its record of the code's constant values
/// and runs Xcode's tools on it for the app and its widget, before each is signed; the list of protocols they
/// read is written by the script. A live build, with Xcode, when LAMP_LIVE_INTENTS is set.
@MainActor
final class AppIntentsTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDown() {
        for root in roots { try? FileManager.default.removeItem(at: root) }
    }

    private func app(_ platform: Platform, widget: Bool = false) throws -> LampProject {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-intents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        let project = try Template.draft(name: "Groceries", platform: platform, in: root)
        try Template.fill(project)
        try """
        import AppIntents

        struct AddItemIntent: AppIntent {
            static let title: LocalizedStringResource = "Add Item"
            @Parameter(title: "Item") var item: String
            func perform() async throws -> some IntentResult & ProvidesDialog {
                .result(dialog: "Added \\(item)")
            }
        }

        struct GroceryShortcuts: AppShortcutsProvider {
            static var appShortcuts: [AppShortcut] {
                AppShortcut(intent: AddItemIntent(), phrases: ["Add an item to \\(.applicationName)"],
                            shortTitle: "Add Item", systemImageName: "cart")
            }
        }

        """.write(to: project.dir.appendingPathComponent("Sources/Intents.swift"), atomically: true, encoding: .utf8)
        if widget {
            let folder = project.dir.appendingPathComponent("Widget")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "import WidgetKit\n".write(to: folder.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
        }
        try Template.writeOwnedFiles(for: project)
        return project
    }

    private func script(_ project: LampProject) throws -> String {
        try String(contentsOf: project.dir.appendingPathComponent("build.sh"), encoding: .utf8)
    }

    func testEveryBuildScriptReadsIntentsBeforeSigning() throws {
        for (platform, widget) in [(Platform.mac, false), (.mac, true), (.iphone, false), (.iphone, true), (.universal, false), (.universal, true)] {
            let project = try app(platform, widget: widget)
            let text = try script(project)
            let parse = Process()
            parse.executableURL = URL(fileURLWithPath: "/bin/zsh")
            parse.arguments = ["-n", project.dir.appendingPathComponent("build.sh").path]
            try parse.run()
            parse.waitUntilExit()
            XCTAssertEqual(parse.terminationStatus, 0, "\(platform) widget: \(widget)")

            XCTAssertTrue(text.contains("-emit-const-values"), "\(platform)")
            let app = try XCTUnwrap(text.range(of: "intents \(project.exe) \"$APP\""), "\(platform)")
            let signApp = try XCTUnwrap(text.range(of: "codesign --force -s - \"$APP\""), "\(platform)")
            XCTAssertLessThan(app.lowerBound, signApp.lowerBound)
            if widget {
                let read = try XCTUnwrap(text.range(of: "intents \(project.exe)Widget \"$WIDGET\""), "\(platform)")
                let sign = try XCTUnwrap(text.range(of: "\"$WIDGET\"\n", range: read.upperBound..<text.endIndex), "\(platform)")
                XCTAssertTrue(text[read.upperBound..<sign.upperBound].contains("codesign"))
            }
        }
    }

    func testTheSetupIsTheSameForAMacAndAPhoneButWhereItWrites() throws {
        let list = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Template.appIntentsProtocols.utf8)) as? [String])
        XCTAssertTrue(list.contains("AppIntent") && list.contains("AppShortcutsProvider"))
        let mac = Template.appIntentsSetup(ios: false), phone = Template.appIntentsSetup(ios: true)
        XCTAssertTrue(mac.contains("--platform-family macOS") && mac.contains("$bundle/Contents/Resources"))
        XCTAssertTrue(phone.contains("--platform-family iOS") && phone.contains("arm64-apple-ios17.0-simulator"))
        XCTAssertFalse(phone.contains("Contents/"))
    }

    /// The widget compiles Widget/Shared/ with LAMP_WIDGET, in the package and in Xcode's project, so an
    /// intent there can leave its work to the app, where iOS performs it.
    func testTheWidgetKnowsItIsTheWidget() throws {
        let package = Template.iPhonePackageSwift(widget: true)
        XCTAssertTrue(package.contains(".define(\"LAMP_WIDGET\")"))
        XCTAssertEqual(package.components(separatedBy: "LAMP_WIDGET").count, 2, "only the widget's target")
        XCTAssertTrue(Template.universalPackageSwift(widget: true).contains(".define(\"LAMP_WIDGET\")"))
        let project = try app(.iphone, widget: true)
        try Template.writeDeviceProject(for: project, team: "ABCDE12345")
        let pbxproj = try String(contentsOf: project.dir.appendingPathComponent(".lamp/device/\(project.exe).xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertEqual(pbxproj.components(separatedBy: "SWIFT_ACTIVE_COMPILATION_CONDITIONS = LAMP_WIDGET;").count, 2)
    }

    func testEveryKindOfAppIsTold() {
        for prompt in [Agent.systemPrompt, Agent.iPhonePrompt(for: .iphone), Agent.universalPrompt(for: .iphone)] {
            XCTAssertTrue(prompt.contains("AppShortcutsProvider"))
        }
        XCTAssertTrue(Agent.iPhonePrompt(for: .iphone).contains("#if !LAMP_WIDGET"))
        XCTAssertFalse(Agent.systemPrompt.contains("LiveActivityIntent"), "a Mac widget's buttons run in the widget")
        XCTAssertTrue(Agent.universalPrompt(for: .iphone).contains("`LiveActivityIntent` there goes under `#if os(iOS)`"))
    }

    /// Builds the app with build.sh and looks for the intent in what Xcode's tools wrote.
    func testALiveBuildCarriesTheIntent() throws {
        guard ProcessInfo.processInfo.environment["LAMP_LIVE_INTENTS"] != nil else { throw XCTSkip("set LAMP_LIVE_INTENTS to build") }
        for platform in [Platform.mac, .iphone] {
            let project = try app(platform)
            let build = Process()
            build.executableURL = project.dir.appendingPathComponent("build.sh")
            let out = Pipe()
            build.standardOutput = out
            build.standardError = out
            try build.run()
            let log = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            build.waitUntilExit()
            XCTAssertEqual(build.terminationStatus, 0, String(log.suffix(3000)))
            let bundle = project.dir.appendingPathComponent("build/\(project.exe).app")
            let metadata = bundle.appendingPathComponent(platform == .mac ? "Contents/Resources/Metadata.appintents" : "Metadata.appintents")
            let actions = try String(decoding: Data(contentsOf: metadata.appendingPathComponent("extract.actionsdata")), as: UTF8.self)
            XCTAssertTrue(actions.contains("AddItemIntent"), "\(platform)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: metadata.appendingPathComponent("nlu").path), "\(platform): \(log.suffix(3000))")
        }
    }
}
