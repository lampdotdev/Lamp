import XCTest
@testable import Lamp

/// lamp's command line (cli/) gives an app the files Lamp's app writes into it, which are made by Lamp's own code. The
/// list of controllers is one, and a game's runtime can't load without it, so the command line keeps a copy
/// (cli/lamps/lamp-controllers.js) that must be the list as Lamp writes it. A new Mac app's starting files are another,
/// made on demand. Run with LAMP_WRITE_CLI_FILES=1 (scripts/cli-files.sh) to write both again.
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
    /// that page is given it, Lamp's building blocks for a page, which the command line gives a game's page too.
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
