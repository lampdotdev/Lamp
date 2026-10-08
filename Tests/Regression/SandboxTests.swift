import XCTest
@testable import Lamp

/// The sandbox the agent's shell commands run in: the app's folder open, the rest of the home folder and
/// Lamp's own folders closed, enforced by macOS rather than read off the command.
final class SandboxTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    /// Under the home folder, like a real app, so the home-folder rule is what's tested.
    private func project() throws -> (LampProject, URL) {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-sandbox-test-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("Apps/coinflip")
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "inside".write(to: dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        try "secret".write(to: root.appendingPathComponent("outside.txt"), atomically: true, encoding: .utf8)
        return (LampProject(id: "coinflip", name: "Coin Flip", exe: "CoinFlip", dir: dir), root)
    }

    private func run(_ command: String, in project: LampProject) throws -> (status: Int32, output: String) {
        let wrapped = try XCTUnwrap(Sandbox.wrap(command, for: project))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", wrapped]
        process.currentDirectoryURL = project.dir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testTheAppIsOpenAndTheRestIsClosed() throws {
        let (project, root) = try project()
        let inside = try run("cat Sources/App.swift && echo more >> Sources/App.swift && cat Sources/App.swift | wc -l", in: project)
        XCTAssertEqual(inside.status, 0, inside.output)
        XCTAssertTrue(inside.output.contains("inside"))
        let up = try run("cd Sources; cd ..; ls Sources", in: project)
        XCTAssertEqual(up.status, 0, up.output)   // a step up that stays inside the app is fine
        let outside = try run("cat \(Sandbox.quoted(root.appendingPathComponent("outside.txt").path))", in: project)
        XCTAssertNotEqual(outside.status, 0)
        XCTAssertTrue(outside.output.contains("not permitted"), outside.output)
        let home = try run("ls ~ | head -1", in: project)
        XCTAssertTrue(home.output.contains("not permitted"), home.output)
        let quoted = try run("echo 'it'\"'\"'s quoted > fine'", in: project)
        XCTAssertEqual(quoted.output.trimmingCharacters(in: .whitespacesAndNewlines), "it's quoted > fine")
    }

    /// SwiftPM's own sandbox can't start inside Lamp's: Lamp's `swift` turns it off for builds, and only there.
    func testSwiftBuildsInsideTheSandbox() throws {
        let (project, _) = try project()
        let which = try run("command -v swift", in: project)
        XCTAssertEqual(which.output.trimmingCharacters(in: .whitespacesAndNewlines), Sandbox.bin.appendingPathComponent("swift").path)
        let login = try run("/bin/zsh -lc 'command -v swift'", in: project)
        XCTAssertEqual(login.output.trimmingCharacters(in: .whitespacesAndNewlines), Sandbox.bin.appendingPathComponent("swift").path, login.output)
        let version = try run("swift --version 2>&1 | head -1", in: project)
        XCTAssertTrue(version.output.contains("Swift"), version.output)
        try """
        // swift-tools-version:5.9
        import PackageDescription
        let package = Package(name: "Probe", targets: [.executableTarget(name: "Probe", path: "Sources")])
        """.write(to: project.dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "print(\"built\")".write(to: project.dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        let build = try run("swift build 2>&1 | tail -1", in: project)
        XCTAssertTrue(build.output.contains("Build complete") || build.output.contains("Compiling"), build.output)
    }
}
