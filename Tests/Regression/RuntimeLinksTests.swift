import XCTest
import AppKit
@testable import Lamp

/// What Lamp reads from an app's runtime folder and hands the agent (what it printed, its pictures) is read by Lamp
/// itself, outside the sandbox. The agent can put a link there, so a link must never bring the agent a file its own
/// commands can't read.
final class RuntimeLinksTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    /// An app under the home folder, as a real one is, and a private folder beside it the agent can't read.
    private func project() throws -> (LampProject, URL, URL) {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-runtime-links-test-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("Apps/coinflip")
        let runtime = dir.appendingPathComponent(".lamp/runtime")
        try fm.createDirectory(at: runtime, withIntermediateDirectories: true)
        let mine = root.appendingPathComponent("Private")
        try fm.createDirectory(at: mine, withIntermediateDirectories: true)
        try "secret line".write(to: mine.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        try png(of: .red).write(to: mine.appendingPathComponent("photo.png"))
        return (LampProject(id: "coinflip", name: "Coin Flip", exe: "CoinFlip", dir: dir), runtime, mine)
    }

    private func png(of colour: NSColor) throws -> Data {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in colour.setFill(); rect.fill(); return true }
        let rep = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    func testThePrintedLinesAreTheAppsOwn() throws {
        let (project, runtime, _) = try project()
        try "hello from the app".write(to: runtime.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Runtime.logTail(project), "hello from the app")
        XCTAssertEqual(Runtime.log(of: project, from: 6), "from the app")
    }

    func testALogLinkedElsewhereIsNotRead() throws {
        let (project, runtime, mine) = try project()
        try FileManager.default.createSymbolicLink(at: runtime.appendingPathComponent("log.txt"), withDestinationURL: mine.appendingPathComponent("log.txt"))
        XCTAssertFalse(Runtime.logTail(project)?.contains("secret") ?? false)
        XCTAssertFalse(Runtime.log(of: project, from: 0)?.contains("secret") ?? false)
        XCTAssertEqual(Runtime.logSize(project), 0)
    }

    func testTheRuntimeFolderLinkedElsewhereIsNotRead() throws {
        let (project, runtime, mine) = try project()
        try FileManager.default.removeItem(at: runtime)
        try FileManager.default.createSymbolicLink(at: runtime, withDestinationURL: mine)
        XCTAssertFalse(Runtime.logTail(project)?.contains("secret") ?? false)
    }

    @MainActor func testAPictureLinkedElsewhereIsNotHandedOver() throws {
        let (project, runtime, mine) = try project()
        let shot = runtime.appendingPathComponent("screenshot.png")
        try FileManager.default.createSymbolicLink(at: shot, withDestinationURL: mine.appendingPathComponent("photo.png"))
        XCTAssertEqual(Store.agentPictures([shot], in: project), [])
    }

    @MainActor func testTheAppsOwnPictureIsHandedOver() throws {
        let (project, runtime, _) = try project()
        let shot = runtime.appendingPathComponent("screenshot.png")
        try png(of: .blue).write(to: shot)
        XCTAssertEqual(Store.agentPictures([shot], in: project).count, 1)
    }

    /// The engine is given the picture's bytes, read when they're sent: a copy swapped for a link after Lamp made it
    /// brings nothing.
    @MainActor func testACopySwappedForALinkSendsNothing() throws {
        let (project, runtime, mine) = try project()
        let shot = runtime.appendingPathComponent("screenshot.png")
        try png(of: .blue).write(to: shot)
        let paths = Store.agentPictures([shot], in: project)
        XCTAssertEqual(Store.pictureData(paths, in: project).count, 1)
        let copy = URL(fileURLWithPath: try XCTUnwrap(paths.first))
        try FileManager.default.removeItem(at: copy)
        try FileManager.default.createSymbolicLink(at: copy, withDestinationURL: mine.appendingPathComponent("photo.png"))
        XCTAssertEqual(Store.pictureData(paths, in: project).count, 0)
    }
}
