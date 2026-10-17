import XCTest
@testable import Lamp

/// What Lamp runs as itself, outside the agent's sandbox, is never found on the path: a folder earlier on it
/// (Homebrew's, put first by the person's own shell setup) could hold a look-alike, and Lamp would run it
/// unconfined. Here a made-up shell setup puts a folder holding a fake `codesign` first, the way a person's
/// does with Homebrew's.
final class OwnToolsByPathTests: XCTestCase {
    private var root: URL!
    private var previousZDOTDIR: String?

    override func setUpWithError() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("lamp-own-tools-\(UUID().uuidString)")
        let fake = root.appendingPathComponent("fake")
        let zdot = root.appendingPathComponent("zsh")
        try fm.createDirectory(at: fake, withIntermediateDirectories: true)
        try fm.createDirectory(at: zdot, withIntermediateDirectories: true)
        for tool in ["codesign"] {
            let file = fake.appendingPathComponent(tool)
            try "#!/bin/sh\necho \(tool) >> \(Sandbox.quoted(ran.path))\n".write(to: file, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        // Shell.run starts a login zsh, which reads its startup files from ZDOTDIR.
        try "path=(\(Sandbox.quoted(fake.path)) $path)\n".write(to: zdot.appendingPathComponent(".zprofile"), atomically: true, encoding: .utf8)
        previousZDOTDIR = ProcessInfo.processInfo.environment["ZDOTDIR"]
        setenv("ZDOTDIR", zdot.path, 1)
    }

    override func tearDown() {
        if let previousZDOTDIR { setenv("ZDOTDIR", previousZDOTDIR, 1) } else { unsetenv("ZDOTDIR") }
        try? FileManager.default.removeItem(at: root)
    }

    private var ran: URL { root.appendingPathComponent("ran.txt") }
    private var faked: String { (try? String(contentsOf: ran, encoding: .utf8)) ?? "" }

    /// A small app to sign: a copy of a system program in a bundle.
    private func app() throws -> URL {
        let fm = FileManager.default
        let app = root.appendingPathComponent("Probe.app")
        try fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try fm.copyItem(atPath: "/usr/bin/true", toPath: app.appendingPathComponent("Contents/MacOS/Probe").path)
        let plist: [String: Any] = ["CFBundleExecutable": "Probe", "CFBundleIdentifier": "dev.lamp.test.own-tools", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    @MainActor
    func testSigningNeverRunsACodesignFoundOnThePath() async throws {
        // The fake really is what a bare `codesign` finds in Lamp's shell, or this test would prove nothing.
        var found: [String] = []
        _ = await Shell.run("command -v codesign", cwd: root) { found.append($0) }
        XCTAssertEqual(found.first, root.appendingPathComponent("fake/codesign").path)

        let app = try app()
        let env = ["LAMP_APP": app.path, "LAMP_SIDEBAR": app.appendingPathComponent("Contents/PlugIns/none.appex").path]
        var output: [String] = []
        let status = await Shell.run(AppSigning.command(adHoc: true, widget: false), cwd: root, env: env) { output.append($0) }
        XCTAssertEqual(status, 0, output.joined(separator: "\n"))
        let requirement = await AppSigning.requirement(of: app)
        XCTAssertNotNil(requirement)
        XCTAssertEqual(faked, "", "Lamp ran a program found on the path instead of the system's")
        XCTAssertTrue(Subprocess.runBlocking("/usr/bin/codesign", ["--verify", app.path]).ok)
    }
}
