import XCTest
@testable import Lamp

/// The Xcode Lamp takes without being asked is one whose tools it then runs as itself, so it must be in
/// /Applications, which the agent's commands can't write. A link there to an Xcode somewhere else (one a command
/// could have made, in a folder it can write) doesn't count. Here a made-up Applications folder stands in.
final class XcodeFoundByItselfTests: XCTestCase {
    private var root: URL!
    private var applications: URL!
    private let commandLineTools = "/Library/Developer/CommandLineTools"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-xcode-found-\(UUID().uuidString)")
        applications = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    /// A bundle that `PhoneTools.isXcode` takes for Xcode: Apple's id and an xcodebuild that can be run.
    private func makeXcode(at app: URL) throws {
        let bin = app.appendingPathComponent("Contents/Developer/usr/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let info: NSDictionary = ["CFBundleIdentifier": "com.apple.dt.Xcode"]
        info.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
        let xcodebuild = bin.appendingPathComponent("xcodebuild")
        try "#!/bin/sh\nexit 0\n".write(to: xcodebuild, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: xcodebuild.path)
    }

    private func found(selected: String? = nil, env: [String: String] = [:], ready: Bool = true) -> String? {
        PhoneTools.installedXcode(env: env, selected: { selected ?? self.commandLineTools },
                                  applications: applications.path, isReady: { _ in ready })
    }

    func testAnXcodeInApplicationsIsTakenWhenTheCommandLineToolsAreSelected() throws {
        try makeXcode(at: applications.appendingPathComponent("Xcode.app"))
        let resolved = realpath(applications.path, nil)!
        defer { free(resolved) }
        let real = String(cString: resolved)
        XCTAssertEqual(found(), real + "/Xcode.app/Contents/Developer")
    }

    func testALinkToAnXcodeElsewhereIsNotTaken() throws {
        let elsewhere = root.appendingPathComponent("Writable/Xcode.app")
        try makeXcode(at: elsewhere)
        try FileManager.default.createSymbolicLink(at: applications.appendingPathComponent("Xcode.app"), withDestinationURL: elsewhere)
        XCTAssertNil(found())
    }

    func testAnXcodeWhoseToolsLeadOutOfItIsNotTaken() throws {
        // Its developer folder a link to one elsewhere.
        let outside = root.appendingPathComponent("Writable/Other.app")
        try makeXcode(at: outside)
        let first = applications.appendingPathComponent("Xcode.app")
        try FileManager.default.createDirectory(at: first.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: outside.appendingPathComponent("Contents/Info.plist"), to: first.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.createSymbolicLink(at: first.appendingPathComponent("Contents/Developer"),
                                                   withDestinationURL: outside.appendingPathComponent("Contents/Developer"))
        XCTAssertNil(found())
        // Its xcodebuild a link to a program elsewhere.
        try FileManager.default.removeItem(at: first)
        try makeXcode(at: first)
        let xcodebuild = first.appendingPathComponent("Contents/Developer/usr/bin/xcodebuild")
        try FileManager.default.removeItem(at: xcodebuild)
        try FileManager.default.createSymbolicLink(at: xcodebuild,
                                                   withDestinationURL: outside.appendingPathComponent("Contents/Developer/usr/bin/xcodebuild"))
        var asked: [String] = []
        XCTAssertNil(PhoneTools.installedXcode(env: [:], selected: { self.commandLineTools }, applications: applications.path,
                                               isReady: { asked.append($0); return true }))
        XCTAssertEqual(asked, [], "nothing outside the bundle may be run to check it")
    }

    func testNothingIsTakenWhenTheMacOrLampAlreadyNamesOne() throws {
        let xcode = applications.appendingPathComponent("Xcode.app")
        try makeXcode(at: xcode)
        XCTAssertNil(found(selected: xcode.appendingPathComponent("Contents/Developer").path))
        XCTAssertNil(found(env: ["DEVELOPER_DIR": "/somewhere/Xcode.app"]))
        // And none that isn't ready to build: its agreements not yet accepted.
        XCTAssertNil(found(ready: false))
    }
}
