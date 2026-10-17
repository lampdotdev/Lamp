import XCTest
@testable import Lamp

/// Lamp writes an app's build.sh just before it runs it, but in the app's folder, which the agent's commands
/// write: one left running in the background can put its own build.sh there in between. Whatever runs then must
/// run as the agent's commands do, confined to the app, never as Lamp.
@MainActor
final class BuildInTheSandboxTests: XCTestCase {
    private var root: URL?
    private var racer: Process?

    override func tearDown() async throws {
        racer?.terminate()
        racer?.waitUntilExit()
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    /// A build.sh swapped in while Lamp builds runs, and reaches nothing outside the app: not a file beside the
    /// app's folder, and not Lamp's own folder.
    func testABuildScriptSwappedInRunsOnlyInsideTheApp() async throws {
        let fm = FileManager.default
        // Under the home folder, like a real app, so the home-folder rule is what's tested.
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-build-sandbox-test-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("Apps/swapped")
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        let project = LampProject(id: "swapped", name: "Swapped", exe: "Swapped", dir: dir)
        try Template.writeOwnedFiles(for: project)
        let escaped = root.appendingPathComponent("escaped.txt")
        let lamps = Sandbox.folder.appendingPathComponent("build-test-\(UUID().uuidString).txt")
        try fm.createDirectory(at: Sandbox.folder, withIntermediateDirectories: true)
        try "a key".write(to: lamps, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: lamps) }

        // The agent's background command: puts its own build.sh in place, over and over.
        let payload = """
            #!/bin/zsh
            cd "$(dirname "$0")"
            echo ran >> ran.txt
            echo out > \(Sandbox.quoted(escaped.path)) 2>/dev/null
            cat \(Sandbox.quoted(lamps.path)) >> read.txt 2>/dev/null
            exit 0

            """
        try payload.write(to: dir.appendingPathComponent(".payload"), atomically: true, encoding: .utf8)
        let racer = Process()
        racer.executableURL = URL(fileURLWithPath: "/bin/zsh")
        racer.arguments = ["-c", "while true; do cp .payload .next && chmod +x .next && mv -f .next build.sh; done"]
        racer.currentDirectoryURL = dir
        try racer.run()
        self.racer = racer

        for _ in 0..<10 {
            try Template.writeOwnedFiles(for: project)
            var output: [String] = []
            _ = await Store.runBuild("./build.sh", for: project, env: [:]) { output.append($0) }
        }
        racer.terminate()
        racer.waitUntilExit()

        let ran = (try? String(contentsOf: dir.appendingPathComponent("ran.txt"), encoding: .utf8)) ?? ""
        XCTAssertFalse(ran.isEmpty, "the swapped-in build.sh never ran, so nothing was tested")
        XCTAssertFalse(fm.fileExists(atPath: escaped.path), "a swapped-in build.sh wrote outside the app")
        let read = (try? String(contentsOf: dir.appendingPathComponent("read.txt"), encoding: .utf8)) ?? ""
        XCTAssertFalse(read.contains("a key"), "a swapped-in build.sh read Lamp's own folder")
    }
}
