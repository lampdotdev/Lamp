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
    func testARemovedXcodeNeedsReinstalling() {
        let developer = root.appendingPathComponent("Xcode.app/Contents/Developer").path
        XCTAssertEqual(SetupCheck.macSDKRepair(env: ["DEVELOPER_DIR": developer, "SDKROOT": ""]), .reinstallXcode)
    }

    /// The look is the build's own: an SDK the build is told to use (`SDKROOT`) that isn't there fails it too. What puts it
    /// right depends on the tools this Mac builds with, Xcode's or the Command Line Tools.
    func testAnSDKTheBuildIsToldToUseMustBeThere() throws {
        try XCTSkipUnless(SetupCheck.buildToolsInstalled(), "This Mac has no Apple tools to look at.")
        XCTAssertNotNil(SetupCheck.macSDKRepair(env: ["SDKROOT": root.appendingPathComponent("MacOSX.sdk").path]))
    }
}
