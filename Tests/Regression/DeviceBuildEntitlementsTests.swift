import XCTest
@testable import Lamp

/// The phone's build is signed with the entitlements Lamp wrote, whatever the agent's commands do while it runs.
/// Xcode builds the app's project in the app's folder, in its sandbox and with signing off; Lamp signs a copy in its
/// own folder with entitlements from its own project. A command left running in the background can rewrite every
/// entitlements file in the app's folder while that happens, and none of it is what the app is signed with.
///
/// The build is Lamp's own (`Template.writeDeviceProject`, `Devices.build`) for the simulator, which needs no team,
/// and the copy is signed ad hoc (`TeamSigning.sign`) with what Lamp's own project names; the command is run in
/// Lamp's sandbox (`Sandbox.wrap`), as the agent's are.
@MainActor
final class DeviceBuildEntitlementsTests: XCTestCase {
    private var root: URL?
    private var project: LampProject?

    override func tearDown() {
        let fm = FileManager.default
        if let root { try? fm.removeItem(at: root) }
        if let project {
            try? fm.removeItem(at: Devices.buildFolder(for: project))
            try? fm.removeItem(at: Devices.signingFolder(for: project))
            // The command's sandbox profile, which Lamp would otherwise clear only after an hour.
            for file in (try? fm.contentsOfDirectory(atPath: Sandbox.folder.path)) ?? [] where file.hasPrefix(project.id + "-") {
                try? fm.removeItem(at: Sandbox.folder.appendingPathComponent(file))
            }
        }
        for folder in [Devices.buildsFolder.appendingPathComponent(".signing"), Devices.buildsFolder]
        where (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty == true { try? fm.removeItem(at: folder) }
    }

    func testAPhoneBuildIsSignedWithLampsEntitlementsWhileACommandRewritesThem() async throws {
        let sdk = await Subprocess.run("/usr/bin/xcrun", ["--sdk", "iphonesimulator", "--show-sdk-path"], timeout: 30)
        try XCTSkipUnless(sdk.ok, "needs Xcode with the iOS simulator")
        let fm = FileManager.default
        // Under the home folder, like a real app, so the sandbox's home-folder rule is what's tested.
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-device-build-test-\(UUID().uuidString)")
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let letters = UUID().uuidString.filter(\.isLetter).prefix(6)
        let project = try Template.scaffold(name: "Probe \(letters)", platform: .iphone, in: root)
        let team = "ABCDE12345"
        self.project = project

        // What the agent would leave behind: entitlements of its own, and a command that writes them over every
        // entitlements file it can reach as soon as it appears, the app's folder and Lamp's build folder alike.
        // Once each: Xcode stops a build whose entitlements file keeps changing.
        try """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
            <key>com.apple.security.application-groups</key><array><string>group.injected.other-app</string></array>
            <key>keychain-access-groups</key><array><string>\(team).injected.other-app</string></array>
            </dict></plist>
            """.write(to: project.dir.appendingPathComponent("injected.plist"), atomically: true, encoding: .utf8)
        let loop = """
            B=\(Sandbox.quoted(Devices.buildFolder(for: project).path))
            touch "$B/written-by-the-agent" 2>/dev/null && echo yes > reached-lamps-folder
            while [ ! -e stop ]; do
              find . "$B" \\( -name '*.entitlements' -o -name '*.xcent' \\) -exec sh -c 'cmp -s injected.plist "$1" || cp injected.plist "$1"' _ {} \\; 2>/dev/null
              sleep 0.02
            done
            """
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/bin/bash")
        command.arguments = ["-c", try XCTUnwrap(Sandbox.wrap(loop, for: project))]
        command.currentDirectoryURL = project.dir
        command.standardOutput = FileHandle.nullDevice
        command.standardError = FileHandle.nullDevice
        try command.run()
        defer {
            fm.createFile(atPath: project.dir.appendingPathComponent("stop").path, contents: nil)
            command.waitUntilExit()
        }

        // What Lamp does when the person tries the app on their phone (`Store.installOnDevice`), with an ad hoc
        // signature where the team's certificate would be, and Lamp's own entitlements where Xcode's would be.
        try await Devices.stage(project, team: team)
        var output: [String] = []
        let built: URL
        do {
            built = try await Devices.build(project, team: team, destination: "generic/platform=iOS Simulator") { output.append($0) }
        } catch {
            return XCTFail("\(error.localizedDescription)\n" + output.filter { $0.contains("error") }.suffix(10).joined(separator: "\n"))
        }
        let planDir = TeamSigning.folder(for: project, place: .iphone).appendingPathComponent("Plan")
        try fm.createDirectory(at: planDir, withIntermediateDirectories: true)
        let lampsEntitlements = Template.Capabilities.load(project).entitlementsPlist(for: project, platform: .ios, appGroup: nil)
        try lampsEntitlements.write(to: planDir.appendingPathComponent("0.entitlements"), atomically: true, encoding: .utf8)
        let plan = TeamSigning.Plan(stamp: "", expires: .distantFuture,
                                    pieces: [.init(path: "", id: project.deviceBundleID(team: team), entitlements: "0.entitlements", profile: nil)])
        let install = Devices.signingFolder(for: project).appendingPathComponent("Install")
        try fm.createDirectory(at: install, withIntermediateDirectories: true)
        let app = install.appendingPathComponent("\(project.exe).app")
        try AppFolder.copy(built, in: Devices.buildFolder(for: project), to: app, in: install)
        try await TeamSigning.sign(app, with: plan, in: planDir, identity: "-")

        fm.createFile(atPath: project.dir.appendingPathComponent("stop").path, contents: nil)
        command.waitUntilExit()
        XCTAssertFalse(fm.fileExists(atPath: project.dir.appendingPathComponent("reached-lamps-folder").path),
                       "the agent's command could write Lamp's build folder")

        let read = await Subprocess.run("/usr/bin/codesign", ["-d", "--entitlements", "-", "--xml", app.path], mergeErrors: false, timeout: 60)
        let signed = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(read.output.utf8), format: nil) as? [String: Any],
                                   read.output + output.suffix(20).joined(separator: "\n"))
        let lamps = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(lampsEntitlements.utf8), format: nil) as? [String: Any])
        XCTAssertEqual(NSDictionary(dictionary: signed), NSDictionary(dictionary: lamps), "signed with \(signed)")
        XCTAssertNil(signed["com.apple.security.application-groups"])
        XCTAssertNil(signed["keychain-access-groups"])
    }
}
