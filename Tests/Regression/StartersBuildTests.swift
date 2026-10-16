import XCTest
@testable import Lamp

/// Each wish Lamp comes with, set up as the first launch sets it up (`Store.installStarters`) and built with the
/// build.sh Lamp writes for it, widget and all. Minutes of compiling, so only when asked:
/// `LAMP_BUILD_STARTERS=1 swift test --filter StartersBuildTests` (or `=today` for one). With
/// `LAMP_STARTERS_OUT=<folder>` the apps are kept there, to open and try.
final class StartersBuildTests: XCTestCase {
    func testEveryStarterBuilds() throws {
        guard let only = ProcessInfo.processInfo.environment["LAMP_BUILD_STARTERS"] else {
            throw XCTSkip("Set LAMP_BUILD_STARTERS=1 to build every starter.")
        }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let kept = ProcessInfo.processInfo.environment["LAMP_STARTERS_OUT"].map { URL(fileURLWithPath: $0) }
        let root = kept ?? FileManager.default.temporaryDirectory.appendingPathComponent("lamp-starters-\(UUID().uuidString)")
        defer { if kept == nil { try? FileManager.default.removeItem(at: root) } }
        let folders = try FileManager.default.contentsOfDirectory(at: repo.appendingPathComponent("Resources/Starters"),
                                                                   includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath && (only == "1" || $0.lastPathComponent == only) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(folders.isEmpty)
        for folder in folders {
            let text = try String(contentsOf: folder.appendingPathComponent("starter.md"), encoding: .utf8)
            let starter = try XCTUnwrap(Starters.parse(text, folder: folder))
            let project = try Template.draft(name: starter.name, in: root)
            try Template.fill(project)
            try Starters.copy(starter, into: project)
            try Template.writeOwnedFiles(for: project)
            XCTAssertTrue(Starters.isStarter(project))
            let (status, output) = try run(Shell.compatibleSDK + "./build.sh", in: project.dir)
            XCTAssertEqual(status, 0, "\(starter.name) didn't build:\n\(output.suffix(3000))")
            XCTAssertTrue(FileManager.default.fileExists(atPath: project.builtURL.path), starter.name)
            if Template.hasWidget(project) {
                let widget = project.builtURL.appendingPathComponent("Contents/PlugIns/\(project.exe)Widget.appex")
                XCTAssertTrue(FileManager.default.fileExists(atPath: widget.path), "\(starter.name)'s widget")
            }
        }
    }

    private func run(_ command: String, in directory: URL) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
