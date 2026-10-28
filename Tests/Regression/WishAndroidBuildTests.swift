import XCTest
@testable import Lamp

/// LampSupport.kt as an Android app of a wish of several is given it, `LampWish` and its channel included, built to an
/// APK with Lamp's own Gradle, as Lamp builds the app: the Kotlin block is a string to Swift, so nothing else would
/// notice it doesn't compile. Skipped on a Mac without Lamp's Android tools.
final class WishAndroidBuildTests: XCTestCase {
    func testAnAndroidAppOfAWishBuilds() async throws {
        let environment = AndroidTools.environment
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: environment["LAMP_GRADLE"] ?? "")
                          && FileManager.default.fileExists(atPath: environment["ANDROID_HOME"] ?? "/none"), "Lamp's Android tools aren't on this Mac")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wish-android-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let made = try Template.scaffold(name: "Scoreboard", platform: .android, in: root)
        let part = LampProject(id: "scoreboard.android", name: made.name, exe: made.exe, dir: made.dir, platform: .android, partOf: "scoreboard")
        try Template.writeOwnedFiles(for: part)
        let support = try String(contentsOf: try XCTUnwrap(FileManager.default.enumerator(at: made.dir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.first { $0.lastPathComponent == "LampSupport.kt" }), encoding: .utf8)
        XCTAssertTrue(support.contains("object LampWish"), "the app of a wish carries the block")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [made.dir.appendingPathComponent("build.sh").path]
        // Android's own settings for the build kept in the test's folder, not any Lamp's.
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
            .merging(["ANDROID_USER_HOME": root.appendingPathComponent("android-user").path]) { $1 }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let said = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, said.split(separator: "\n").filter { $0.hasPrefix("e:") }.joined(separator: "\n") + "\n" + said.suffix(2000))
    }
}
