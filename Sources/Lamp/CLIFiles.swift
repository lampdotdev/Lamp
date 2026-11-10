import Foundation

/// The files lamp's command line (cli/) takes from Lamp's own code, which only Lamp's Swift makes: a new Mac app's
/// starting files, a new web app's, lamp.js as a page and as a game are given it, and Lamp's Android app around a page,
/// each under a stand-in name the command line puts the app's own in the place of. Written into the repository's
/// cli/lamps by scripts/cli-files.sh (CLIFilesTests), never committed, and into the copy of lamp Lamp's app carries by
/// build.sh (`flag`), so the lamp a person's agent runs from Lamp's app has them too.
enum CLIFiles {
    static let flag = "--cli-files"

    /// Writes them all into `folder` (cli/lamps). `qrcode` is the folder of the QR encoder lamp.js carries
    /// (Resources/WebLibraries/qrcode), read from wherever the caller has it.
    static func write(into folder: URL, qrcode: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try writeMacStarter(into: folder)
        try writeWebStarter(into: folder, qrcode: qrcode)
        try writeAndroidHost(into: folder)
    }

    /// A new Mac app's folder as Lamp makes one (`Template.scaffold`), for `lamp new --mac`: Lamp's own files and the
    /// card the app shows until it's written, with the names it stands in for.
    static func writeMacStarter(into folder: URL) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-cli-starter-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let project = try Template.scaffold(name: "Zqx App Name", platform: .mac, in: root)
        let starter = folder.appendingPathComponent("mac-starter")
        try? fm.removeItem(at: starter)
        try fm.copyItem(at: project.dir, to: starter)
        let names = ["name": project.name, "exe": project.exe, "slug": project.id, "bundle": Edition.appBundlePrefix + project.id]
        try JSONSerialization.data(withJSONObject: names, options: [.sortedKeys, .prettyPrinted]).write(to: starter.appendingPathComponent("lamp-starter.json"))
    }

    /// A new web app's page as Lamp makes one (`Template.scaffold` for `Platform.webApp`), for `lamp new --web`: what's in
    /// its Web/ folder and its notes, without the app around the page. And lamp.js as that page is given it, Lamp's
    /// building blocks for a page, and as a game's page is given it (`GameKit.lampJS`, without a TV's remote: a game
    /// reads its own controller, and the remote's code would take the keys the Xbox's controller sends).
    static func writeWebStarter(into folder: URL, qrcode: URL) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-cli-web-starter-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let project = try Template.draft(name: "Zqx App Name", platform: .webApp, in: root)
        // The page's own files are written first, then the app around the page, whose kit may not be at hand (a test run
        // has none): that failure is the end of what's wanted here.
        _ = try? ScreenKit.fill(project)
        let web = project.dir.appendingPathComponent(TVTemplate.webFolder)
        let encoder = try String(contentsOf: qrcode.appendingPathComponent("qrcode.js"), encoding: .utf8)
        let license = try? String(contentsOf: qrcode.appendingPathComponent("LICENSE"), encoding: .utf8)
        func withQR(_ text: String) -> String {
            text.replacingOccurrences(of: DeviceSupport.qrJS(encoder: nil, license: nil), with: DeviceSupport.qrJS(encoder: encoder, license: license))
        }
        try withQR(TVTemplate.lampJS(for: project)).write(to: web.appendingPathComponent("lamp.js"), atomically: true, encoding: .utf8)
        let starter = folder.appendingPathComponent("web-starter")
        try? fm.removeItem(at: starter)
        try fm.copyItem(at: web, to: starter)
        let notes = project.dir.appendingPathComponent("APP.md")
        if fm.fileExists(atPath: notes.path) { try fm.copyItem(at: notes, to: starter.appendingPathComponent("APP.md")) }
        let names = ["name": project.name, "exe": project.exe, "slug": project.id]
        try JSONSerialization.data(withJSONObject: names, options: [.sortedKeys, .prettyPrinted]).write(to: starter.appendingPathComponent("lamp-starter.json"))
        try? fm.removeItem(at: folder.appendingPathComponent("lamp.js"))
        try fm.copyItem(at: starter.appendingPathComponent("lamp.js"), to: folder.appendingPathComponent("lamp.js"))
        try withQR(GameKit.lampJS(for: project)).write(to: folder.appendingPathComponent("lamp-for-games.js"), atomically: true, encoding: .utf8)
    }

    /// Lamp's Android app around a page (`GameAndroid`), for `lamp open --on android`: its Gradle files, its manifest
    /// and activity for a game and for any other page, and what answers the page's building blocks, each with the
    /// app's own names still to be put in, and the tools Lamp builds it with, as Lamp downloads them on this kind of Mac.
    static func writeAndroidHost(into folder: URL) throws {
        let fm = FileManager.default
        let host = folder.appendingPathComponent("android-host")
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
        try JSONSerialization.data(withJSONObject: AndroidTools.spec, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
            .write(to: host.appendingPathComponent("tools.json"))
    }

    /// `Lamp --cli-files <folder>`, from build.sh: the files written into the copy of lamp in Lamp's bundle, with the QR
    /// encoder read from the bundle. Ends the process.
    static func writeFromCommandLine() -> Never {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count,
              let qrcode = Bundle.main.resourceURL?.appendingPathComponent("WebLibraries/qrcode") else {
            FileHandle.standardError.write(Data("No folder was given for lamp's files.\n".utf8))
            exit(1)
        }
        do {
            try write(into: URL(fileURLWithPath: arguments[index + 1]), qrcode: qrcode)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Lamp couldn't write lamp's files: \(error)\n".utf8))
            exit(1)
        }
    }
}
