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
