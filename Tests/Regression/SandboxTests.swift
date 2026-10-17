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
        // Nor a program in Lamp's phone builds, where Xcode leaves what it makes from the app.
        let builds = Devices.buildsFolder.appendingPathComponent("sandbox-exec-test-\(UUID().uuidString)")
        try fm.createDirectory(at: builds, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: builds)
            if (try? fm.contentsOfDirectory(atPath: Devices.buildsFolder.path))?.isEmpty == true { try? fm.removeItem(at: Devices.buildsFolder) }
        }
        let built = builds.appendingPathComponent("hello")
        try fm.copyItem(at: program, to: built)
        let fromBuilds = try run(Sandbox.quoted(built.path), in: project)
        XCTAssertNotEqual(fromBuilds.status, 0, fromBuilds.output)
        XCTAssertTrue(fromBuilds.output.contains("not permitted"), fromBuilds.output)
        // An ordinary program still starts.
        let plain = try run("/bin/echo fine", in: project)
        XCTAssertEqual(plain.output.trimmingCharacters(in: .whitespacesAndNewlines), "fine")
    }
    /// A command can swap the app's folder for a link to another folder: it may unlink and create at the
    /// folder's own path. Every later command, and Lamp's own checks and writes for the agent, must still
    /// open only the folder where the app really lives, never wherever that link leads (here the folder
    /// holding the app, standing in for Lamp's own).
    @MainActor func testTheAppsFolderSwappedForALinkOpensNothingElse() throws {
        let (project, root) = try project()
        let dir = Sandbox.quoted(project.dir.path)
        let swap = try run("cd / && rm -r \(dir) && ln -s \(Sandbox.quoted(root.path)) \(dir)", in: project)
        XCTAssertEqual(swap.status, 0, swap.output)
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: project.dir.path))

        let through = try run("cd / && cat \(dir)/outside.txt; echo planted > \(dir)/planted", in: project)
        XCTAssertFalse(through.output.contains("secret"), through.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("planted").path))

        XCTAssertNotEqual(Privacy.verdict(tool: "read", path: "outside.txt", project: project), .allow)
        XCTAssertNotEqual(Privacy.verdict(tool: "write", path: "planted", project: project), .allow)
        XCTAssertNotEqual(Store.deleteFile("outside.txt", in: project).0, 200)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("outside.txt").path))
        XCTAssertNil(Previews.destination(for: "shot.jpg", under: ".lamp/runtime/previews", in: project))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".lamp").path))
    }

    /// Homebrew's folders are on the path of what Lamp runs as itself, so a command must not be able to put a
    /// program there. Tried only where this user can't write anyway, so nothing lands there even without the
    /// rule: macOS checks the sandbox first ("Operation not permitted") and ownership after ("Permission denied").
    func testHomebrewFoldersAreClosedForWriting() throws {
        let (project, _) = try project()
        let fm = FileManager.default
        let folders = ["/opt/homebrew/bin", "/opt/homebrew", "/usr/local/bin", "/usr/local"].filter { folder in
            var isFolder: ObjCBool = false
            return fm.fileExists(atPath: folder, isDirectory: &isFolder) && isFolder.boolValue && !fm.isWritableFile(atPath: folder)
        }
        guard !folders.isEmpty else { throw XCTSkip("No Homebrew folder here that this user can't already write to") }
        for folder in folders {
            let planted = "\(folder)/codesign-\(UUID().uuidString)"
            let write = try run("printf fake > \(Sandbox.quoted(planted))", in: project)
            XCTAssertNotEqual(write.status, 0, write.output)
            XCTAssertTrue(write.output.contains("Operation not permitted"), "\(folder): \(write.output)")
            XCTAssertFalse(fm.fileExists(atPath: planted))
            // Reading what's there stays open.
            let read = try run("ls \(Sandbox.quoted(folder)) > /dev/null", in: project)
            XCTAssertEqual(read.status, 0, read.output)
        }
    }

    /// An Xcode the person dragged to /Applications is theirs to write, and Lamp runs its xcodebuild, simctl and
    /// devicectl as itself (`DeveloperTools.path`), so a command must not be able to change them. Here a pretend
    /// Xcode the user owns, given as Lamp's developer folder, stands in for it, and /Applications is tried where
    /// this user can't write anyway (Utilities), so nothing lands there even without the rule: macOS checks the
    /// sandbox first ("Operation not permitted") and ownership after ("Permission denied").
    func testApplicationsAndTheDeveloperFolderAreClosedForWriting() throws {
        let (project, _) = try project()
        let fm = FileManager.default
        let xcode = URL(fileURLWithPath: "/tmp/lamp-sandbox-test-\(UUID().uuidString)/Xcode.app")
        let tools = xcode.appendingPathComponent("Contents/Developer/usr/bin")
        try fm.createDirectory(at: tools, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: xcode.deletingLastPathComponent()) }
        let xcodebuild = tools.appendingPathComponent("xcodebuild")
        try "#!/bin/sh\necho real\n".write(to: xcodebuild, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: xcodebuild.path)
        let before = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
        setenv("DEVELOPER_DIR", xcode.appendingPathComponent("Contents/Developer").path, 1)
        defer { if let before { setenv("DEVELOPER_DIR", before, 1) } else { unsetenv("DEVELOPER_DIR") } }

        let swap = try run("printf '#!/bin/sh\\necho planted\\n' > \(Sandbox.quoted(xcodebuild.path))", in: project)
        XCTAssertTrue(swap.output.contains("Operation not permitted"), swap.output)
        XCTAssertEqual(try String(contentsOf: xcodebuild, encoding: .utf8), "#!/bin/sh\necho real\n")
        let beside = try run("mkdir \(Sandbox.quoted(xcode.appendingPathComponent("Contents/Planted").path))", in: project)
        XCTAssertTrue(beside.output.contains("Operation not permitted"), beside.output)
        // Running it, as a build does, stays open.
        let ran = try run(Sandbox.quoted(xcodebuild.path), in: project)
        XCTAssertEqual(ran.output.trimmingCharacters(in: .whitespacesAndNewlines), "real", ran.output)
        // The rest of the temporary folder, and the app's own, stay writable.
        let tmp = try run("echo ok > \(Sandbox.quoted(xcode.deletingLastPathComponent().appendingPathComponent("beside").path)) && echo ok > Sources/More.swift", in: project)
        XCTAssertEqual(tmp.status, 0, tmp.output)

        // Utilities is the system's, on every Mac. Not an app, nor a folder security software guards: those
        // answer "not permitted" on their own, with or without the rule.
        guard let folder = ["/Applications", "/Applications/Utilities"].first(where: { !fm.isWritableFile(atPath: $0) }) else {
            throw XCTSkip("Nothing in /Applications that this user can't already write to")
        }
        let planted = "\(folder)/lamp-\(UUID().uuidString)"
        let write = try run("mkdir \(Sandbox.quoted(planted))", in: project)
        XCTAssertTrue(write.output.contains("Operation not permitted"), "\(folder): \(write.output)")
        XCTAssertFalse(fm.fileExists(atPath: planted))
    }
}
