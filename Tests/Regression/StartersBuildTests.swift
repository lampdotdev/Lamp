import XCTest
@testable import Lamp

/// Each wish Lamp comes with, set up as the first launch sets it up (`Store.installStarters`) and built with the
/// build.sh Lamp writes for it, widget and all, the way Lamp runs it (`Store.runBuild`, in the app's sandbox). Minutes of compiling, so only when asked:
/// `LAMP_BUILD_STARTERS=1 swift test --filter StartersBuildTests` (or `=today` for one). With
/// `LAMP_STARTERS_OUT=<folder>` the apps are kept there, to open and try.
@MainActor
final class StartersBuildTests: XCTestCase {
    func testEveryStarterBuilds() async throws {
        guard let only = ProcessInfo.processInfo.environment["LAMP_BUILD_STARTERS"] else {
            throw XCTSkip("Set LAMP_BUILD_STARTERS=1 to build every starter.")
        }
        let kept = ProcessInfo.processInfo.environment["LAMP_STARTERS_OUT"].map { URL(fileURLWithPath: $0) }
        let root = kept ?? FileManager.default.temporaryDirectory.appendingPathComponent("lamp-starters-\(UUID().uuidString)")
        defer { if kept == nil { try? FileManager.default.removeItem(at: root) } }
        let folders = try StarterTrees.folders().filter { only == "1" || $0.lastPathComponent == only }
        XCTAssertFalse(folders.isEmpty)
        for folder in folders {
            let starter = try XCTUnwrap(Starters.read(folder))
            let project = try Template.draft(name: starter.name, platform: starter.kind, in: root)
            try Template.fill(project)
            try Starters.copy(starter, into: project)
            try Template.writeOwnedFiles(for: project)
            XCTAssertTrue(Starters.isStarter(project))
            var output: [String] = []
            let status = await Store.runBuild("./build.sh", for: project, env: [:]) { output.append($0) }
            XCTAssertEqual(status, 0, "\(starter.name) didn't build:\n\(output.joined(separator: "\n").suffix(3000))")
            XCTAssertTrue(FileManager.default.fileExists(atPath: project.builtURL.path), starter.name)
            if Template.hasWidget(project) {
                let widget = project.builtURL.appendingPathComponent("Contents/PlugIns/\(project.exe)Widget.appex")
                XCTAssertTrue(FileManager.default.fileExists(atPath: widget.path), "\(starter.name)'s widget")
            }
        }
    }
}
