import XCTest
@testable import Lamp

/// A game's Android app of a wish of several, built to an APK with Lamp's own Gradle as Lamp builds it: Lamp's Kotlin
/// building blocks with `LampWish`, the bridge that answers the page's `Lamp.wish` with it, and what they need in the
/// build are strings to Swift, so nothing else would notice they don't compile together. A game on its own carries none
/// of it. Skipped on a Mac without Lamp's Android tools.
final class WishGameAndroidBuildTests: XCTestCase {
    @MainActor
    func testAGamesAndroidAppOfAWishBuilds() async throws {
        let environment = AndroidTools.environment
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: environment["LAMP_GRADLE"] ?? "")
                          && FileManager.default.fileExists(atPath: environment["ANDROID_HOME"] ?? "/none"), "Lamp's Android tools aren't on this Mac")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wish-game-android-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("Game")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Web"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let game = LampProject(id: "scoreboard.game", name: "Scoreboard", exe: "Scoreboard", dir: dir, platform: .game, partOf: "scoreboard")
        // The same game's folder, as an app on its own: the same package, as a game's never changes.
        let alone = LampProject(id: "scoreboard.game", name: "Scoreboard", exe: "Scoreboard", dir: dir, platform: .game)
        try "<script src=\"lamp.js\"></script>".write(to: dir.appendingPathComponent("Web/index.html"), atomically: true, encoding: .utf8)

        // On its own first: nothing of the wish, then all of it once the game is one of several, then none again.
        try GameAndroid.write(for: alone)
        let kotlin = dir.appendingPathComponent(GameAndroid.folder + "/app/src/main/kotlin/" + Template.androidPackage(for: alone).replacingOccurrences(of: ".", with: "/"))
        XCTAssertFalse(try String(contentsOf: kotlin.appendingPathComponent("MainActivity.kt"), encoding: .utf8).contains("LampPageWish"))
        try GameAndroid.write(for: game)
        let wishKotlin = dir.appendingPathComponent(GameAndroid.folder + "/app/src/main/kotlin/" + Template.androidPackage(for: game).replacingOccurrences(of: ".", with: "/"))
        XCTAssertTrue(try String(contentsOf: wishKotlin.appendingPathComponent(Template.androidSupportFile), encoding: .utf8).contains("object LampWish"))
        XCTAssertTrue(try String(contentsOf: wishKotlin.appendingPathComponent("MainActivity.kt"), encoding: .utf8).contains("LampPageWish.attach"))
        let gradle = try String(contentsOf: dir.appendingPathComponent(GameAndroid.folder + "/app/build.gradle.kts"), encoding: .utf8)
        for needed in ["compose.compiler", "compose = true", "libs.androidx.webkit", "libs.kotlinx.serialization.json"] { XCTAssertTrue(gradle.contains(needed), needed) }

        let script = "PLACE=android\n" + GameAndroid.buildSteps().replacingOccurrences(of: "{{SLUG}}", with: "scoreboard-game")
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: GameAndroid.apk(game).path))
        if let keep = ProcessInfo.processInfo.environment["LAMP_KEEP_GAME_APK"] {
            try? FileManager.default.copyItem(at: GameAndroid.apk(game), to: URL(fileURLWithPath: keep))
        }

        try GameAndroid.write(for: alone)
        XCTAssertFalse(FileManager.default.fileExists(atPath: wishKotlin.appendingPathComponent(Template.androidSupportFile).path), "a game on its own again carries none of it")
    }
}
