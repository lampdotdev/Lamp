import XCTest
@testable import Lamp

/// A screen's Android app built to an APK with Lamp's own Gradle, as Lamp builds it: the page's voice (`LampPageVoice`,
/// recording with the voice-recognition source, a TV remote's microphone included) is Kotlin in a Swift string beside
/// the activity that attaches it, so nothing else would notice it doesn't compile. Skipped on a Mac without Lamp's
/// Android tools.
final class ScreenAndroidVoiceBuildTests: XCTestCase {
    @MainActor
    func testAScreensAndroidAppListensAndBuilds() async throws {
        let environment = AndroidTools.environment
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: environment["LAMP_GRADLE"] ?? "")
                          && FileManager.default.fileExists(atPath: environment["ANDROID_HOME"] ?? "/none"), "Lamp's Android tools aren't on this Mac")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("screen-android-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("Board")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Web"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let screen = LampProject(id: "board.screen", name: "Board", exe: "Board", dir: dir, platform: .screen)
        try "<script src=\"lamp.js\"></script>".write(to: dir.appendingPathComponent("Web/index.html"), atomically: true, encoding: .utf8)

        try GameAndroid.write(for: screen)
        let main = dir.appendingPathComponent(GameAndroid.folder + "/app/src/main")
        let manifest = try String(contentsOf: main.appendingPathComponent("AndroidManifest.xml"), encoding: .utf8)
        XCTAssertTrue(manifest.contains("android.permission.RECORD_AUDIO"))
        XCTAssertFalse(GameAndroid.manifest.contains("RECORD_AUDIO"), "a game doesn't ask for the microphone")
        let kotlin = main.appendingPathComponent("kotlin/" + Template.androidPackage(for: screen).replacingOccurrences(of: ".", with: "/"))
        let activity = try String(contentsOf: kotlin.appendingPathComponent("MainActivity.kt"), encoding: .utf8)
        for needed in ["LampPageVoice.attach", "LampPageVoice.permissionResult", "LampPageVoice.cancel"] { XCTAssertTrue(activity.contains(needed), needed) }
        let gateway = try String(contentsOf: kotlin.appendingPathComponent("LampPageGateway.kt"), encoding: .utf8)
        XCTAssertTrue(gateway.contains("AudioSource.VOICE_RECOGNITION"))

        let script = "PLACE=android\n" + GameKit.stagePageSh + GameAndroid.buildSteps().replacingOccurrences(of: "{{SLUG}}", with: "board-screen")
        try script.write(to: dir.appendingPathComponent("build-android.sh"), atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["build-android.sh"]
        process.currentDirectoryURL = dir
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
            .merging(["ANDROID_USER_HOME": root.appendingPathComponent("android-user").path]) { $1 }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let said = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, said.split(separator: "\n").filter { $0.hasPrefix("e:") }.joined(separator: "\n") + "\n" + said.suffix(3000))
        XCTAssertTrue(FileManager.default.fileExists(atPath: GameAndroid.apk(screen).path))
    }
}
