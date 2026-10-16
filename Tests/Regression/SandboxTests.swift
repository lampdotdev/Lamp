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

    /// The apps Lamp installs can't be started by a command: exec maps the binary without the read the
    /// profile closes, so the profile refuses it by name. A command could otherwise run another app with a
    /// library of its own inside (DYLD_INSERT_LIBRARIES) and read that app's secrets out of Lamp through it.
    func testInstalledAppsCantBeStarted() throws {
        let (project, _) = try project()
        let fm = FileManager.default
        // A pretend installed app, cleaned up after: the rule names the apps folder, so the program must be there.
        let place = Edition.appsFolder.appendingPathComponent("sandbox-exec-test-\(UUID().uuidString)")
        try fm.createDirectory(at: place, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: place) }
        let program = place.appendingPathComponent("hello")
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        compile.arguments = ["xcrun", "clang", "-x", "c", "-", "-o", program.path]
        let stdin = Pipe()
        compile.standardInput = stdin
        try compile.run()
        stdin.fileHandleForWriting.write(Data("int main(void) { return 0; }".utf8))
        stdin.fileHandleForWriting.closeFile()
        compile.waitUntilExit()
        XCTAssertEqual(compile.terminationStatus, 0)

        let started = try run(Sandbox.quoted(program.path), in: project)
        XCTAssertNotEqual(started.status, 0, started.output)
        XCTAssertTrue(started.output.contains("not permitted"), started.output)
        let injected = try run("DYLD_INSERT_LIBRARIES=/tmp/nothing.dylib \(Sandbox.quoted(program.path))", in: project)
        XCTAssertTrue(injected.output.contains("not permitted"), injected.output)
        // An ordinary program still starts.
        let plain = try run("/bin/echo fine", in: project)
        XCTAssertEqual(plain.output.trimmingCharacters(in: .whitespacesAndNewlines), "fine")
    }

    /// Nor the copies Lamp opens to run an app's checks: they're signed as their app, so a command that could put
    /// a program there and start it would run as that app, with its permissions and sign-ins.
    func testCheckCopiesCantBeTouched() throws {
        let (project, _) = try project()
        let fm = FileManager.default
        let existed = fm.fileExists(atPath: Checks.folder.path)
        let place = Checks.folder.appendingPathComponent("sandbox-test-\(UUID().uuidString)")
        try fm.createDirectory(at: place, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: existed ? place : Checks.folder) }
        let program = place.appendingPathComponent("hello")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: program)

        let started = try run(Sandbox.quoted(program.path), in: project)
        XCTAssertNotEqual(started.status, 0, started.output)
        XCTAssertTrue(started.output.contains("not permitted"), started.output)
        let written = try run("echo x > \(Sandbox.quoted(place.appendingPathComponent("planted").path))", in: project)
        XCTAssertNotEqual(written.status, 0, written.output)
        XCTAssertFalse(fm.fileExists(atPath: place.appendingPathComponent("planted").path))
    }
}
