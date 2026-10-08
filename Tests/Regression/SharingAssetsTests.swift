import XCTest
@testable import Lamp

/// What leaves the Mac with a shared app: its Assets/ folder, never the chat's attachments. An attachment
/// the code names is adopted into Assets/ first, so apps from before the folder existed share what they use.
final class SharingAssetsTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func project() throws -> LampProject {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-sharing-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("coinflip")
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent(Attachments.folder), withIntermediateDirectories: true)
        try "let coin = LampAssets.image(\"heads.png\")".write(to: dir.appendingPathComponent("Sources/ContentView.swift"), atomically: true, encoding: .utf8)
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent("\(Attachments.folder)/heads.png"))
        try Data([4, 5, 6]).write(to: dir.appendingPathComponent("\(Attachments.folder)/bug-screenshot.png"))
        return LampProject(id: "coinflip", name: "Coin Flip", exe: "CoinFlip", dir: dir)
    }

    /// The archive's own listing: what a recipient's Lamp would unpack.
    private func entries(of archive: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", archive.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    func testOnlyAssetsAreShared() throws {
        let project = try project()
        let entries = try entries(of: try Sharing.export(project))
        XCTAssertTrue(entries.contains { $0.hasSuffix("Sources/ContentView.swift") }, "\(entries)")
        XCTAssertTrue(entries.contains { $0.hasSuffix("\(Sharing.Assets.folder)/heads.png") }, "\(entries)")
        XCTAssertFalse(entries.contains { $0.contains("bug-screenshot") }, "\(entries)")
        XCTAssertFalse(entries.contains { $0.contains("\(Attachments.folder)/") }, "\(entries)")
    }

    func testNamedAttachmentIsAdoptedIntoAssets() throws {
        let project = try project()
        Sharing.Assets.adopt(in: project)
        let assets = project.dir.appendingPathComponent(Sharing.Assets.folder)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: assets.path).sorted(), ["heads.png"])
        // The chat keeps its copies.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: project.dir.appendingPathComponent(Attachments.folder).path).count, 2)
    }
}
