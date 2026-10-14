import XCTest
import AppKit
@testable import Lamp

/// A shared file says which app it is, so a Mac that already has the app can update it rather than make a
/// second copy; and updating replaces the app's code and files while leaving what Lamp keeps for it.
final class SharingUpdateTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func project(_ id: String = "tally", code: String = "let version = 1") throws -> LampProject {
        let fm = FileManager.default
        let root = self.root ?? fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-update-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent(id)
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try code.write(to: dir.appendingPathComponent("Sources/ContentView.swift"), atomically: true, encoding: .utf8)
        return LampProject(id: id, name: "Tally", exe: "Tally", dir: dir)
    }

    /// A file from a Lamp that didn't write an identity, or one with something else in its place, still opens.
    func testFilesWithoutAnIdentityStillOpen() throws {
        let project = try project()
        for app in ["", ",\"app\":\"../../somewhere\""] {
            let stage = try XCTUnwrap(root).appendingPathComponent("stage-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: project.dir, to: stage)
            try FileManager.default.removeItem(at: stage.appendingPathComponent(".lamp"))
            try "{\"format\":2,\"name\":\"Tally\",\"exportedAt\":\"2026-10-01T00:00:00Z\"\(app)}"
                .write(to: stage.appendingPathComponent("lamp-app.json"), atomically: true, encoding: .utf8)
            let file = try XCTUnwrap(root).appendingPathComponent("\(UUID().uuidString).lampapp")
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            zip.arguments = ["-c", "-k", "--norsrc", stage.path, file.path]
            try zip.run()
            zip.waitUntilExit()
            let package = try Sharing.open(file)
            XCTAssertEqual(package.name, "Tally")
            XCTAssertNil(package.identity)
            XCTAssertEqual(package.sources.count, 1)
        }
    }

    func testUpdatingReplacesCodeAndFilesAndKeepsTheRest() throws {
        let fm = FileManager.default
        let sender = try project("sender", code: "let version = 2")
        try fm.createDirectory(at: sender.dir.appendingPathComponent(Sharing.Assets.folder), withIntermediateDirectories: true)
        try Data([2]).write(to: sender.dir.appendingPathComponent("\(Sharing.Assets.folder)/new.png"))
        let package = try Sharing.open(try Sharing.export(sender))

        let mine = try project("mine")
        try "mine".write(to: mine.dir.appendingPathComponent("Sources/Mine.swift"), atomically: true, encoding: .utf8)
        try "lamp's".write(to: mine.dir.appendingPathComponent("Sources/LampSupport.swift"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: mine.dir.appendingPathComponent(Sharing.Assets.folder), withIntermediateDirectories: true)
        try Data([1]).write(to: mine.dir.appendingPathComponent("\(Sharing.Assets.folder)/old.png"))
        try "[]".write(to: mine.dir.appendingPathComponent(".lamp/chat.json"), atomically: true, encoding: .utf8)

        try Sharing.install(package, into: mine, replacing: true)

        func text(_ path: String) -> String? { try? String(contentsOf: mine.dir.appendingPathComponent(path), encoding: .utf8) }
        XCTAssertEqual(text("Sources/ContentView.swift"), "let version = 2")
        XCTAssertNil(text("Sources/Mine.swift"))
        XCTAssertEqual(text("Sources/LampSupport.swift"), "lamp's")
        XCTAssertEqual(text(".lamp/chat.json"), "[]")
        XCTAssertTrue(fm.fileExists(atPath: mine.dir.appendingPathComponent("\(Sharing.Assets.folder)/new.png").path))
        XCTAssertFalse(fm.fileExists(atPath: mine.dir.appendingPathComponent("\(Sharing.Assets.folder)/old.png").path))
    }
}
