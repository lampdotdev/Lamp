import XCTest
@testable import Lamp

/// lamp's command line (cli/) serves a game the files Lamp's app writes beside its page at every build. The list of
/// controllers is one of them, and the game runtime can't load without it, so the command line keeps a copy
/// (cli/lamps/lamp-controllers.js) that must be the list as Lamp writes it. Run with LAMP_WRITE_CLI_FILES=1 to write the
/// copy again after the list changes.
final class CLIFilesTests: XCTestCase {
    func testTheCommandLinesControllersAreLamps() throws {
        let copy = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("cli/lamps/lamp-controllers.js")
        if ProcessInfo.processInfo.environment["LAMP_WRITE_CLI_FILES"] == "1" {
            try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Controllers.pageJS.write(to: copy, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), Controllers.pageJS,
                       "cli/lamps/lamp-controllers.js isn't the controllers as Lamp writes them: run this test with LAMP_WRITE_CLI_FILES=1")
    }
}
