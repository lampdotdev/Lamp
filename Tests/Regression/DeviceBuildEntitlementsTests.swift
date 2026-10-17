import XCTest
@testable import Lamp

/// The phone's build is signed with the entitlements Lamp wrote, whatever the agent's commands do while it runs.
/// Xcode signs with the file its project names, after copying it into its build folder; both used to be in the
/// app's folder, where a command left running in the background could rewrite them before the signature.
///
/// The build is Lamp's own (`Template.writeDeviceProject`, `Devices.build`) for the simulator, which takes its
/// entitlements through the same steps as the phone's and needs no team; the command is run in Lamp's sandbox
/// (`Sandbox.wrap`), as the agent's are.
@MainActor
final class DeviceBuildEntitlementsTests: XCTestCase {
    private var root: URL?
    private var project: LampProject?

    override func tearDown() {
        let fm = FileManager.default
        if let root { try? fm.removeItem(at: root) }
        if let project {
            try? fm.removeItem(at: Devices.buildFolder(for: project))
            // The command's sandbox profile, which Lamp would otherwise clear only after an hour.
            for file in (try? fm.contentsOfDirectory(atPath: Sandbox.folder.path)) ?? [] where file.hasPrefix(project.id + "-") {
                try? fm.removeItem(at: Sandbox.folder.appendingPathComponent(file))
            }
        }
        if (try? fm.contentsOfDirectory(atPath: Devices.buildsFolder.path))?.isEmpty == true { try? fm.removeItem(at: Devices.buildsFolder) }
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

        // What Lamp does when the person tries the app on their phone (`Store.installOnDevice`).
        try Template.writeDeviceProject(for: project, team: team, in: Devices.buildFolder(for: project))
        var output: [String] = []
        let app: URL
        do {
            app = try await Devices.build(project, team: team, destination: "generic/platform=iOS Simulator") { output.append($0) }
        } catch {
            return XCTFail("\(error.localizedDescription)\n" + output.filter { $0.contains("error") }.suffix(10).joined(separator: "\n"))
        }

        fm.createFile(atPath: project.dir.appendingPathComponent("stop").path, contents: nil)
        command.waitUntilExit()
        XCTAssertFalse(fm.fileExists(atPath: project.dir.appendingPathComponent("reached-lamps-folder").path),
                       "the agent's command could write Lamp's build folder")

        // The simulator's entitlements are a section of the binary, put there from the file Xcode signed with.
        let section = await Subprocess.run("/usr/bin/xcrun", ["otool", "-arch", "arm64", "-s", "__TEXT", "__entitlements",
                                                              app.appendingPathComponent(project.exe).path], timeout: 60)
        // otool prints it in hex, each line an address, a tab and the bytes, which for arm64 come in 32-bit
        // little-endian words.
        let bytes = section.output.split(separator: "\n").filter { $0.contains("\t") }.flatMap { line in
            line.split(separator: "\t").dropFirst().joined(separator: " ").split(separator: " ").flatMap { word -> [UInt8] in
                stride(from: 0, to: word.count, by: 2).compactMap { offset in
                    UInt8(word.dropFirst(offset).prefix(2), radix: 16)
                }.reversed()
            }
        }
        let signed = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(bytes), format: nil) as? [String: Any],
                                   section.output + output.suffix(20).joined(separator: "\n"))
        let lamps = try XCTUnwrap(try PropertyListSerialization.propertyList(
            from: Data(Template.Capabilities.load(project).entitlementsPlist(for: project, platform: .ios, appGroup: nil).utf8),
            format: nil) as? [String: Any])
        // Xcode adds the app's identity; everything else is Lamp's.
        XCTAssertEqual(NSDictionary(dictionary: signed.filter { $0.key != "application-identifier" }), NSDictionary(dictionary: lamps),
                       "signed with \(signed)")
        XCTAssertNil(signed["com.apple.security.application-groups"])
        XCTAssertNil(signed["keychain-access-groups"])
    }
}
