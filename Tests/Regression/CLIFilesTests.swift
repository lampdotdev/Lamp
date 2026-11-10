import XCTest
@testable import Lamp

/// lamp's command line (cli/) gives an app the files Lamp's app writes into it, which are made by Lamp's own code. The
/// list of controllers is one, and a game's runtime can't load without it, so the command line keeps a copy
/// (cli/lamps/lamp-controllers.js) that must be the list as Lamp writes it. A new Mac app's starting files are another,
/// made on demand. Run with LAMP_WRITE_CLI_FILES=1 (scripts/cli-files.sh) to write them again.
final class CLIFilesTests: XCTestCase {
    private static let cli = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("cli/lamps")

    /// A new Mac app's folder as Lamp makes one (`Template.scaffold`), under a name the command line puts the app's own
    /// in the place of (`lamp new --mac`): Lamp's own files and the card the app shows until it's written. Made only
    /// when asked (LAMP_WRITE_CLI_FILES=1, which scripts/cli-files.sh sets) and never committed: the building blocks
    /// change often, and a copy kept in the repository would be one more thing to keep in step with them.
    func testWritesAMacAppsStartingFiles() throws {
        guard ProcessInfo.processInfo.environment["LAMP_WRITE_CLI_FILES"] == "1" else { throw XCTSkip("Only when asked: scripts/cli-files.sh") }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-cli-starter-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let project = try Template.scaffold(name: "Zqx App Name", platform: .mac, in: root)
        let starter = Self.cli.appendingPathComponent("mac-starter")
        try? fm.removeItem(at: starter)
        try fm.createDirectory(at: Self.cli, withIntermediateDirectories: true)
        try fm.copyItem(at: project.dir, to: starter)
        // What the command line needs to know of it: the names it stands in for.
        let names = ["name": project.name, "exe": project.exe, "slug": project.id, "bundle": Edition.appBundlePrefix + project.id]
        try JSONSerialization.data(withJSONObject: names, options: [.sortedKeys, .prettyPrinted]).write(to: starter.appendingPathComponent("lamp-starter.json"))
        XCTAssertTrue(fm.fileExists(atPath: starter.appendingPathComponent("Sources/LampSupport.swift").path))
        XCTAssertTrue(fm.fileExists(atPath: starter.appendingPathComponent("build.sh").path))
    }

    /// A new web app's page as Lamp makes one (`Template.scaffold` for `Platform.webApp`), for `lamp new --web`: what's in
    /// its Web/ folder and its notes, without the app around the page, which is Lamp's app's to build. And lamp.js as
    /// that page is given it, Lamp's building blocks for a page, and as a game's page is given it.
    /// Made only when asked, and never committed, as a Mac app's starting files are.
    func testWritesAWebAppsStartingFiles() throws {
        guard ProcessInfo.processInfo.environment["LAMP_WRITE_CLI_FILES"] == "1" else { throw XCTSkip("Only when asked: scripts/cli-files.sh") }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-cli-web-starter-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let project = try Template.draft(name: "Zqx App Name", platform: .webApp, in: root)
        // The page's own files are written first, then the app around the page, whose kit a test run doesn't have (it's
        // in Lamp's bundle): that failure is the end of what's wanted here.
        _ = try? ScreenKit.fill(project)
        let web = project.dir.appendingPathComponent(TVTemplate.webFolder)
        // lamp.js as Lamp writes it for the page, with the QR encoder it carries read from the repository, where a
        // test run finds it (Lamp reads it from its bundle).
        let qr = Self.cli.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/WebLibraries/qrcode")
        let encoder = try String(contentsOf: qr.appendingPathComponent("qrcode.js"), encoding: .utf8)
        let license = try? String(contentsOf: qr.appendingPathComponent("LICENSE"), encoding: .utf8)
        let lampJSText = TVTemplate.lampJS(for: project)
            .replacingOccurrences(of: DeviceSupport.qrJS(encoder: nil, license: nil), with: DeviceSupport.qrJS(encoder: encoder, license: license))
        try lampJSText.write(to: web.appendingPathComponent(TVTemplate.supportFile.components(separatedBy: "/").last ?? "lamp.js"), atomically: true, encoding: .utf8)
        let starter = Self.cli.appendingPathComponent("web-starter")
        try? fm.removeItem(at: starter)
        try fm.createDirectory(at: Self.cli, withIntermediateDirectories: true)
        try fm.copyItem(at: web, to: starter)
        let notes = project.dir.appendingPathComponent("APP.md")
        if fm.fileExists(atPath: notes.path) { try fm.copyItem(at: notes, to: starter.appendingPathComponent("APP.md")) }
        let names = ["name": project.name, "exe": project.exe, "slug": project.id]
        try JSONSerialization.data(withJSONObject: names, options: [.sortedKeys, .prettyPrinted]).write(to: starter.appendingPathComponent("lamp-starter.json"))
        XCTAssertTrue(fm.fileExists(atPath: starter.appendingPathComponent("index.html").path))
        let lampJS = starter.appendingPathComponent("lamp.js")
        XCTAssertTrue(fm.fileExists(atPath: lampJS.path))
        try? fm.removeItem(at: Self.cli.appendingPathComponent("lamp.js"))
        try fm.copyItem(at: lampJS, to: Self.cli.appendingPathComponent("lamp.js"))
        // And lamp.js as a game is given it (`GameKit.lampJS`), which leaves out a TV's remote: a game reads its own
        // controller, and the remote's code would take the keys the Xbox's controller sends.
        let gameJS = GameKit.lampJS(for: project)
            .replacingOccurrences(of: DeviceSupport.qrJS(encoder: nil, license: nil), with: DeviceSupport.qrJS(encoder: encoder, license: license))
        try gameJS.write(to: Self.cli.appendingPathComponent("lamp-for-games.js"), atomically: true, encoding: .utf8)
    }

    /// Lamp's Android app around a page (`GameAndroid`), for `lamp open --on android`: its Gradle files, its manifest
    /// and activity for a game and for any other page, and what answers the page's building blocks, each with the
    /// app's own names still to be put in ({{PACKAGE}}, {{NAME}} and the rest, which the command line fills as
    /// `Template.write` does). And the tools Lamp builds it with, as Lamp downloads them on this kind of Mac.
    /// Made only when asked, and never committed, as a Mac app's starting files are.
    func testWritesThePageHostForAndroid() throws {
        guard ProcessInfo.processInfo.environment["LAMP_WRITE_CLI_FILES"] == "1" else { throw XCTSkip("Only when asked: scripts/cli-files.sh") }
        let fm = FileManager.default
        let host = Self.cli.appendingPathComponent("android-host")
        try? fm.removeItem(at: host)
        let files: [(String, String)] = [
            ("settings.gradle.kts", Template.androidSettingsGradle),
            ("build.gradle.kts", GameAndroid.rootBuildGradle),
            ("gradle.properties", Template.androidGradleProperties),
            ("gradle/libs.versions.toml", Template.androidVersionsCatalogue),
            ("app/build.gradle.kts", GameAndroid.aloneBuildGradle),
            ("game/AndroidManifest.xml", GameAndroid.manifest),
            ("game/MainActivity.kt", GameAndroid.withoutWish(activity: GameAndroid.gameActivity)),
            ("page/AndroidManifest.xml", GameAndroid.screenManifest),
            ("page/MainActivity.kt", GameAndroid.withoutWish(activity: GameAndroid.screenActivity)),
            ("LampPageGateway.kt", GameAndroid.pageGateway),
        ]
        for (path, text) in files {
            let url = host.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let tools = AndroidTools.spec
        try JSONSerialization.data(withJSONObject: tools, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]).write(to: host.appendingPathComponent("tools.json"))
        XCTAssertTrue(GameAndroid.gameActivity.contains("{{PACKAGE}}"))
    }

    /// An Xbox's package is the command line's alone to make (cli/msix.mjs, which Lamp's app has make it: `LampCLI`).
    /// What Lamp's app still works out itself is what Windows calls a package, which the bridge launches and removes it
    /// by: held to the example the command line's own test is held to (cli/tests/fixtures/msix, a package as Lamp's
    /// Swift code made it before the command line took that over).
    func testWindowsNamesAPackageAsTheCommandLineDoes() throws {
        let file = Self.cli.deletingLastPathComponent().appendingPathComponent("tests/fixtures/msix/names.json")
        let names = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String])
        let identity = MSIX.Identity(name: "Lamp.harbor-racer-1a2b3c4d", publisher: "CN=Lamp", version: "1.7.4660.2", architecture: "x64")
        XCTAssertEqual(identity.fullName, names["fullName"])
        XCTAssertEqual(identity.appUserModelID, names["appUserModelID"])
    }

    /// The command line refuses a folder in a newer format than it reads, and makes files in it: the same number as Lamp's.
    func testTheCommandLineReadsLampsFormat() throws {
        let state = try String(contentsOf: Self.cli.deletingLastPathComponent().appendingPathComponent("state.mjs"), encoding: .utf8)
        let format = state.range(of: #"export const FORMAT = (\d+);"#, options: .regularExpression).map { state[$0].filter(\.isNumber) }
        XCTAssertEqual(format, String(Sharing.formatVersion), "cli/state.mjs's FORMAT isn't Sharing.formatVersion: change it, and what lamp reads and makes, with it")
    }

    func testTheCommandLinesControllersAreLamps() throws {
        let copy = Self.cli.appendingPathComponent("lamp-controllers.js")
        if ProcessInfo.processInfo.environment["LAMP_WRITE_CLI_FILES"] == "1" {
            try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Controllers.pageJS.write(to: copy, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), Controllers.pageJS,
                       "cli/lamps/lamp-controllers.js isn't the controllers as Lamp writes them: run this test with LAMP_WRITE_CLI_FILES=1")
    }
}
