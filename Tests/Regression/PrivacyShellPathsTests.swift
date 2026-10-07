import XCTest
@testable import Lamp

/// The shell check reads relative paths from where the command is: after `cd Sources`, `../icon.json` is
/// the app's own, not a step out of its folder.
final class PrivacyShellPathsTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    /// Under the home folder, not the temporary one: paths in temporary folders are open to the agent anyway.
    private func project() throws -> (LampProject, URL) {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-privacy-test-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("tipcalculator")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "{}".write(to: dir.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
        try "".write(to: dir.appendingPathComponent("Sources/ContentView.swift"), atomically: true, encoding: .utf8)
        return (LampProject(id: "tipcalculator", name: "Tip Calculator", exe: "TipCalculator", dir: dir), dir)
    }

    func testStepUpAfterCdIntoSubfolderStaysInside() throws {
        let (project, dir) = try project()
        try XCTSkipUnless(Privacy.asksOutsideFolder, "the outside-folder rule is off in Settings")
        let command = "cd \"\(dir.path)/Sources\" && python3 - <<'EOF'\np='ContentView.swift'\nEOF\ncat > ../icon.json <<'EOF'\n{}\nEOF"
        XCTAssertFalse(Privacy.reachesOutside(command, project: project))
    }

    func testStepUpFromTheAppFolderReachesOutside() throws {
        let (project, dir) = try project()
        XCTAssertTrue(Privacy.reachesOutside("cd \"\(dir.path)\" && cat ../other/secret.txt", project: project))
    }

    func testCdOutOfTheFolderReachesOutside() throws {
        let (project, dir) = try project()
        XCTAssertTrue(Privacy.reachesOutside("cd \"\(dir.path)/..\" && ls", project: project))
    }
}
