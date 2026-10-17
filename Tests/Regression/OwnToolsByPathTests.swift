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

    /// The developer tools in /usr/bin (`git`, `xcrun`, `xcodebuild`…) are wrappers that look the real program up
    /// in a cache in the user's temporary folder, which the agent's commands may write. Lamp's look at the person's
    /// git settings runs git as Lamp, outside the sandbox, so it must run the real git and never what that cache
    /// names. The wrappers are pointed at a cache of the test's own (`xcrun_db`), so the Mac's own is never touched,
    /// and it names a fake git that notes whether it ran confined, then runs the real one.
    func testLampsOwnGitIsNeverFoundThroughTheToolCache() async throws {
        let fm = FileManager.default
        // The app first: making it runs git as the test, not as Lamp.
        let escape = HistoryEscapeTests()
        defer { escape.tearDown() }
        let app = try escape.app()
        let cache = URL(fileURLWithPath: "/tmp/lamp-xc-\(UUID().uuidString.prefix(6))")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: cache) }
        let db = cache.appendingPathComponent("db")
        let previous = ProcessInfo.processInfo.environment["xcrun_db"]
        setenv("xcrun_db", db.path, 1)
        defer { if let previous { setenv("xcrun_db", previous, 1) } else { unsetenv("xcrun_db") } }

        // The cache as the wrappers write it, then with the real git's path swapped for a fake one of the same length.
        let real = Subprocess.runBlocking("/usr/bin/xcrun", ["--find", "git"], mergeErrors: false).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(Subprocess.runBlocking("/usr/bin/git", ["--version"]).ok)
        let filler = real.count - cache.path.count - 1
        guard !real.isEmpty, filler > 0, var table = fm.contents(atPath: db.path) else { throw XCTSkip("No developer tools cache here") }
        let fake = cache.appendingPathComponent(String(repeating: "g", count: filler))
        let log = cache.appendingPathComponent("ran.txt")
        try """
            #!/bin/sh
            if ls "$HOME" >/dev/null 2>&1; then where=unconfined; else where=confined; fi
            echo "$where $*" >> \(Sandbox.quoted(log.path))
            exec \(Sandbox.quoted(real)) "$@"

            """.write(to: fake, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let found = try XCTUnwrap(table.lastRange(of: Data(real.utf8)))
        table.replaceSubrange(found, with: Data(fake.path.utf8))
        try table.write(to: db)

        // The poisoned cache really is what the wrapper follows, or this test would prove nothing.
        _ = Subprocess.runBlocking("/usr/bin/git", ["--version"])
        XCTAssertTrue(((try? String(contentsOf: log, encoding: .utf8)) ?? "").contains("unconfined --version"))
        try fm.removeItem(at: log)

        // A look for unsaved work reads the person's git settings first (each test has a settings file of its own,
        // so it's read again), then runs git in the app's sandbox.
        _ = await Versions.hasUnsavedChanges(app.project)
        let ran = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        XCTAssertFalse(ran.contains("unconfined"), "Lamp ran, as itself, the git the cache named:\n" + ran)
    }
}
