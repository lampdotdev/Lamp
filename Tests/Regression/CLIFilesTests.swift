import XCTest
@testable import Lamp

/// lamp's command line (cli/) gives an app the files Lamp's app writes into it, which are made by Lamp's own code. The
/// list of controllers is one, and a game's runtime can't load without it, so the command line keeps a copy
/// (cli/lamps/lamp-controllers.js) that must be the list as Lamp writes it. A new Mac app's starting files are another,
/// made on demand. Run with LAMP_WRITE_CLI_FILES=1 (scripts/cli-files.sh) to write them again.
final class CLIFilesTests: XCTestCase {
    private static let cli = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("cli/lamps")

    /// A new Mac app's and web app's starting files, lamp.js for a page and a game, and Lamp's Android app around a page,
    /// as Lamp's own code makes them (`CLIFiles`), under names the command line puts the app's own in the place of. Made
    /// only when asked (LAMP_WRITE_CLI_FILES=1, which scripts/cli-files.sh sets) and never committed: the building blocks
    /// change often, and a copy kept in the repository would be one more thing to keep in step with them.
    func testWritesTheCommandLinesFiles() throws {
        guard ProcessInfo.processInfo.environment["LAMP_WRITE_CLI_FILES"] == "1" else { throw XCTSkip("Only when asked: scripts/cli-files.sh") }
        let qrcode = Self.cli.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/WebLibraries/qrcode")
        try CLIFiles.write(into: Self.cli, qrcode: qrcode)
        let fm = FileManager.default
        for path in ["mac-starter/Sources/LampSupport.swift", "mac-starter/build.sh", "mac-starter/lamp-starter.json", "web-starter/index.html",
                     "web-starter/lamp.js", "lamp.js", "lamp-for-games.js", "android-host/tools.json"] {
            XCTAssertTrue(fm.fileExists(atPath: Self.cli.appendingPathComponent(path).path), path)
        }
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
