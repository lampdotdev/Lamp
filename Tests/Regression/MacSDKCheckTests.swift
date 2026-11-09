import XCTest
@testable import Lamp

/// Setup looks at the macOS SDK the way an app's build finds it (`Shell.compatibleSDK`, then xcrun, in the build's
/// environment), so tools that have a compiler but nothing to build a Mac app against are said before any build, with
/// what puts them right, rather than every build failing for it. These run Apple's real xcrun on this Mac.
final class MacSDKCheckTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-sdk-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    /// The tools this Mac builds with find an SDK: nothing to repair, so setup is unchanged where they work.
    func testTheToolsThisMacBuildsWithNeedNoRepair() throws {
        try XCTSkipUnless(SetupCheck.buildToolsInstalled(), "This Mac has no Apple tools to look at.")
        XCTAssertNil(SetupCheck.macSDKRepair())
    }

    /// Command Line Tools whose folder has no SDK, as an update that stopped halfway leaves them.
    /// (`SDKROOT` is emptied here and below: the tests are run with one, which the look would take.)
    func testCommandLineToolsWithNoSDKNeedReinstalling() throws {
        let developer = root.appendingPathComponent("CommandLineTools")
        try FileManager.default.createDirectory(at: developer.appendingPathComponent("usr/bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: developer.appendingPathComponent("SDKs"), withIntermediateDirectories: true)
        XCTAssertEqual(SetupCheck.macSDKRepair(env: ["DEVELOPER_DIR": developer.path, "SDKROOT": ""]), .reinstallTools)
    }

    /// An Xcode that builds were set to use and that has since been removed: installed again, it's back where it was.
    /// An SDK Lamp was given that's still there doesn't hide it: the build's compiler is found through the folder.
    func testARemovedXcodeNeedsReinstalling() throws {
        let developer = root.appendingPathComponent("Xcode.app/Contents/Developer").path
        XCTAssertEqual(SetupCheck.macSDKRepair(env: ["DEVELOPER_DIR": developer, "SDKROOT": ""]), .reinstallXcode)
        let sdk = try XCTUnwrap(realSDK(), "This Mac has no macOS SDK to name.")
        XCTAssertEqual(SetupCheck.macSDKRepair(env: ["DEVELOPER_DIR": developer, "SDKROOT": sdk]), .reinstallXcode)
    }

    /// An SDK the build is told to use (`SDKROOT`) that isn't there fails the build too, but the tools are fine: it's
    /// said as Lamp's setting, never as tools to reinstall, which would remove a working folder.
    func testAMissingSDKSettingIsNotTakenForBrokenTools() throws {
        try XCTSkipUnless(SetupCheck.buildToolsInstalled(), "This Mac has no Apple tools to look at.")
        XCTAssertEqual(SetupCheck.macSDKRepair(env: ["SDKROOT": root.appendingPathComponent("MacOSX.sdk").path]), .sdkSetting)
    }

    /// Lamp opened from a shell that set `SDKROOT` to the Command Line Tools' newest SDK (Apple's /usr/bin/python3
    /// does): an app's build still takes an SDK whose `@State` needs no plugin those tools lack, and compiles.
    func testAnInheritedSDKThatNeedsTheMissingPluginIsNotBuiltAgainst() throws {
        let tools = SetupCheck.commandLineTools
        let fm = FileManager.default
        try XCTSkipUnless(fm.fileExists(atPath: tools + "/usr/bin/swiftc")
                          && !fm.fileExists(atPath: tools + "/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib"),
                          "These Command Line Tools have the plugin, or aren't here.")
        let needsPlugin = TestShell.run("/usr/bin/grep -qs StateMacro /dev/null \(tools)/SDKs/MacOSX.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/*-macos.swiftinterface(N)")
        try XCTSkipUnless(needsPlugin.status == 0, "The tools' newest SDK doesn't make @State a macro.")
        try "import SwiftUI\nstruct Counter: View { @State var count = 0; var body: some View { Text(\"\\(count)\") } }\n"
            .write(to: root.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let built = TestShell.run(Shell.compatibleSDK + "/usr/bin/xcrun swiftc -typecheck main.swift 2>&1", in: root,
                                  env: ["DEVELOPER_DIR": tools, "SDKROOT": tools + "/SDKs/MacOSX.sdk"])
        XCTAssertEqual(built.status, 0, built.output)
    }

    /// The SDK this Mac's tools find by themselves.
    private func realSDK() -> String? {
        let found = Subprocess.runBlocking("/usr/bin/env", ["-u", "SDKROOT", "/usr/bin/xcrun", "--no-cache", "--sdk", "macosx", "--show-sdk-path"],
                                           mergeErrors: false, timeout: 30)
        return found.ok ? found.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }
}
