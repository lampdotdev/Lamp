import XCTest
@testable import Lamp

/// An app for both the Mac and the iPhone: one code, built for where Try On points, with the Mac build
/// Xcode's and signed for the person's team.
@MainActor
final class UniversalAppTests: XCTestCase {
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

    private func draft() throws -> LampProject {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-universal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        return try Template.draft(name: "Both Ways", platform: .universal, in: root)
    }

    func testTheKindAndWhereItOpensRoundTripThroughMeta() throws {
        var project = try draft()
        XCTAssertEqual(AppKind(project), .universal)
        XCTAssertEqual(AppKind.universal.platform, .universal)
        // Three kinds to choose from, named as the intro's sentence says them; iPhone and iPad are one.
        XCTAssertEqual(AppKind.allCases.map(\.rawValue), ["Mac", "iPhone & iPad", "Mac, iPhone & iPad"])
        var ipad = project; ipad.platform = .iphone; ipad.family = .ipad
        XCTAssertEqual(AppKind(ipad), .phone)
        XCTAssertEqual(AppKind.phone.platform, .iphone)
        XCTAssertEqual(project.destination, .mac)
        XCTAssertFalse(project.onIOS)
        project.chosen = .ios
        try Template.saveMeta(project)
        let meta = try JSONDecoder().decode(ProjectMeta.self, from: Data(contentsOf: project.dir.appendingPathComponent(".lamp/meta.json")))
        XCTAssertEqual(meta.platform, .universal)
        XCTAssertEqual(meta.target, .ios)
        XCTAssertEqual(meta.family, .iphone)
        // A Mac app and an iPhone app have one place each, whatever was chosen.
        var mac = project; mac.platform = .mac
        var phone = project; phone.platform = .iphone; phone.chosen = .mac
        XCTAssertEqual(mac.destination, .mac)
        XCTAssertEqual(phone.destination, .ios)
        XCTAssertTrue(Platform.universal.hasMac && Platform.universal.hasIOS)
        XCTAssertFalse(Platform.mac.hasIOS || Platform.iphone.hasMac)
    }

    func testTheOwnedFilesBuildForBothAndTheProjectIsMultiplatform() throws {
        let project = try draft()
        try Template.fill(project)
        func text(_ path: String) throws -> String { try String(contentsOf: project.dir.appendingPathComponent(path), encoding: .utf8) }
        XCTAssertTrue(try text("Package.swift").contains(".macOS(.v14), .iOS(.v17)"))
        let build = try text("build.sh")
        XCTAssertTrue(build.hasPrefix("#!/bin/zsh\n"))
        XCTAssertTrue(build.contains("if [[ \"${1:-mac}\" == \"ios\" ]]; then"))
        XCTAssertTrue(build.contains("\nSDK=\"$(xcrun --sdk iphonesimulator --show-sdk-path)\"\n"), "the simulator build is the iPhone's")
        XCTAssertTrue(build.contains("\nPLIST\n"), "the heredoc that writes Info.plist ends at the start of a line")
        XCTAssertTrue(build.contains("APP=\"build/iOS/BothWays.app\""), "the iOS half has its own build folder")
        XCTAssertTrue(build.contains("APP=\"build/BothWays.app\""), "the Mac half keeps the usual one")
        XCTAssertTrue(build.contains("-destination \"platform=macOS\""))
        XCTAssertTrue(build.contains("LAMP_TEAM"))
        // The shell must take the whole script: the iOS branch's heredoc ends where the shell expects it to.
        let parse = Process()
        parse.executableURL = URL(fileURLWithPath: "/bin/zsh")
        parse.arguments = ["-n", project.dir.appendingPathComponent("build.sh").path]
        try parse.run()
        parse.waitUntilExit()
        XCTAssertEqual(parse.terminationStatus, 0, "build.sh doesn't parse")
        let app = try text("Sources/App.swift")
        XCTAssertTrue(app.contains("#if os(macOS)\n        .commands { LampCommands() }\n        #endif"))
        let pbxproj = try text(".lamp/device/BothWays.xcodeproj/project.pbxproj")
        XCTAssertTrue(pbxproj.contains("SUPPORTED_PLATFORMS = \"iphoneos iphonesimulator macosx\""))
        XCTAssertTrue(pbxproj.contains("SDKROOT = auto"))
        XCTAssertTrue(pbxproj.contains("MACOSX_DEPLOYMENT_TARGET = 14.0"))
        XCTAssertTrue(pbxproj.contains("\"INFOPLIST_FILE[sdk=macosx*]\" = \"Info-macOS.plist\""))
        XCTAssertTrue(pbxproj.contains("\"ASSETCATALOG_COMPILER_APPICON_NAME[sdk=iphone*]\" = AppIcon"))
        XCTAssertTrue(try text(".lamp/device/Info-macOS.plist").contains("NSPrincipalClass"))
        XCTAssertTrue(try text(".lamp/device/Info.plist").contains("LSRequiresIPhoneOS"))
        // No team yet: the id is the plain one, and a team gives it the suffix everywhere, phone included.
        XCTAssertTrue(pbxproj.contains("PRODUCT_BUNDLE_IDENTIFIER = \"\(Edition.appBundlePrefix)bothways\""))
        UserDefaults.standard.set("ABCDE12345", forKey: "appleTeam")
        XCTAssertEqual(project.bundleID, Edition.appBundlePrefix + "bothways.abcde12345")
        XCTAssertEqual(project.deviceBundleID(team: "ABCDE12345"), project.bundleID)
        var mac = project; mac.platform = .mac
        XCTAssertEqual(mac.bundleID, Edition.appBundlePrefix + "bothways")
        // One build per place, and the Mac's where every Mac app's is.
        XCTAssertEqual(project.builtURL.lastPathComponent, "BothWays.app")
        XCTAssertEqual(project.builtURL.deletingLastPathComponent().lastPathComponent, "build")
        var onPhone = project; onPhone.chosen = .ios
        XCTAssertEqual(onPhone.builtURL.deletingLastPathComponent().lastPathComponent, "iOS")
        XCTAssertEqual(Devices.validFingerprints(in: """
          1) B0F571D758FA881D2EA72E5CE0BDCDDDFF053E20 "Apple Development: Someone (ABCDE12345)"
          2) 7532baa19eda09cc45e82e804cc7a30f7ae5eb56 "Developer ID Application: Someone (ABCDE12345)"
             2 valid identities found
        """), ["B0F571D758FA881D2EA72E5CE0BDCDDDFF053E20", "7532BAA19EDA09CC45E82E804CC7A30F7AE5EB56"])
    }

    func testMovingTheAppUnderTryOnIsAChangeToBuild() throws {
        var project = try draft()
        try Template.fill(project)
        let onMac = Runtime.fingerprint(project)
        project.chosen = .ios
        XCTAssertNotEqual(Runtime.fingerprint(project), onMac)
        var mac = project; mac.platform = .mac
        var macAgain = mac; macAgain.chosen = .ios
        XCTAssertEqual(Runtime.fingerprint(mac), Runtime.fingerprint(macAgain))
    }

    func testThePromptGivesBothHalvesTheirRules() throws {
        let project = try draft()
        let prompt = Agent.systemPrompt(for: project)
        XCTAssertTrue(prompt.hasPrefix("You are Lamp's builder agent. The current directory is a standalone SwiftUI app for the Mac and for iPhone and"))
        XCTAssertTrue(prompt.contains("- One code for both."))
        XCTAssertTrue(prompt.contains("- On the Mac: LampSupport.swift has tested building blocks for common Mac jobs."))
        XCTAssertTrue(prompt.contains("- On iPhone and iPad: LampSupport.swift has tested building blocks"))
        XCTAssertTrue(prompt.contains("- On the Mac: Base design"))
        XCTAssertTrue(prompt.contains("- On iPhone and iPad: Base design"))
        XCTAssertFalse(prompt.contains("{{DEVICE}}"))
        XCTAssertTrue(prompt.contains("iPhone simulator"))
        var phone = project; phone.platform = .iphone
        XCTAssertEqual(Agent.systemPrompt(for: phone), Agent.iPhonePrompt(for: .iphone))
        var mac = project; mac.platform = .mac
        XCTAssertEqual(Agent.systemPrompt(for: mac), Agent.systemPrompt)
    }
}
