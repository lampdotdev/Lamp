import XCTest
@testable import Lamp

/// A device of the person's (a phone, or a TV on the Wi‑Fi) needs only what a build and adb need from Google: the
/// emulator, its system image and the emulator Lamp makes are for the emulator alone. Checked against a folder of
/// stand-ins made here, never the real tools.
final class AndroidDeviceReadinessTests: XCTestCase {
    private var root: URL!
    private var savedFolder: URL!
    private var savedAVDHome: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("android-readiness-\(UUID().uuidString)")
        savedFolder = AndroidTools.folder
        savedAVDHome = AndroidTools.avdHome
        AndroidTools.folder = root.appendingPathComponent("Android")
        AndroidTools.avdHome = root.appendingPathComponent("avd")
        // What a build and adb need, and nothing of the emulator's.
        try executable(AndroidTools.java)
        try executable(AndroidTools.sdkmanager)
        try executable(AndroidTools.gradle)
        try file(AndroidTools.sdkFolder.appendingPathComponent("build-tools/\(AndroidTools.buildTools)/aapt2").path)
        try file(AndroidTools.sdkFolder.appendingPathComponent("platforms/android-\(AndroidTools.platformLevel)/android.jar").path)
        // An adb that lists one TV, ready, and answers nothing else.
        try executable(AndroidTools.adb, """
            #!/bin/sh
            case "$1" in devices) printf 'List of devices attached\\n192.168.1.30:5555 device product:tv model:TV\\n' ;; esac
            """)
    }

    override func tearDownWithError() throws {
        AndroidTools.folder = savedFolder
        AndroidTools.avdHome = savedAVDHome
        try? FileManager.default.removeItem(at: root)
    }

    /// Checked as Try On checks a device being chosen: choosing it confirms the address it's at (`Store.setAndroidDevice`),
    /// since this one says nothing of itself that would tell another device at that address from it.
    func testADeviceIsReadyWithoutTheEmulator() async {
        let report = await AndroidTools.check(device: "192.168.1.30:5555", confirmed: ["192.168.1.30:5555"])
        XCTAssertEqual(report.passed, [.tools, .device], "issue: \(String(describing: report.issue?.title))")
        XCTAssertNil(report.issue)
    }

    func testADeviceNotAnsweringIsAskedForAfterTheTools() async {
        let report = await AndroidTools.check(device: "192.168.1.31:5555")
        XCTAssertEqual(report.passed, [.tools])
        XCTAssertEqual(report.issue?.step, .device)
    }

    func testTheEmulatorStillNeedsItsOwnDownload() async {
        let report = await AndroidTools.check()
        XCTAssertEqual(report.issue?.step, .tools)
    }

    private func file(_ path: String, _ contents: String = "") throws {
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func executable(_ path: String, _ contents: String = "#!/bin/sh\n") throws {
        try file(path, contents)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }
}
