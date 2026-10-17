import XCTest
@testable import Lamp

/// What Xcode puts into the app for the person's phone: only the app's own files. Xcode copies whatever a link
/// leads to, and on the phone the app can send what it carries anywhere, so a link in the app's folder (or the
/// folder itself swapped for one) must never bring in another file from the Mac.
final class PhoneBuildLinksTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    /// An app under the home folder, as a real one is, and a private folder beside it the agent can't read.
    private func project() throws -> (LampProject, URL) {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-phone-links-test-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("Apps/coinflip")
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        try "import SwiftUI".write(to: dir.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        try "heads".write(to: dir.appendingPathComponent("Assets/coin.txt"), atomically: true, encoding: .utf8)
        let mine = root.appendingPathComponent("Private")
        try fm.createDirectory(at: mine.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        try fm.createDirectory(at: mine.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "secret".write(to: mine.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try "secret".write(to: mine.appendingPathComponent("Assets/secret.txt"), atomically: true, encoding: .utf8)
        return (LampProject(id: "coinflip", name: "Coin Flip", exe: "CoinFlip", dir: dir), root)
    }

    /// Everything Xcode would copy from the folders the phone project names, links followed as Xcode follows them.
    private func carried(from source: URL) -> String {
        let fm = FileManager.default
        var text = ""
        for name in ["Assets", "Sources"] {
            let folder = source.appendingPathComponent(name).resolvingSymlinksInPath()
            for case let file as URL in fm.enumerator(at: folder, includingPropertiesForKeys: nil, options: []) ?? FileManager.DirectoryEnumerator() {
                text += (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            }
        }
        return text
    }

    private func stage(_ project: LampProject, _ root: URL) async throws -> URL {
        try await Devices.stage(project, team: "ABCDE12345", in: root.appendingPathComponent("Phone Builds/coinflip"))
    }

    func testAnOrdinaryAppIsCopiedWhole() async throws {
        let (project, root) = try project()
        let source = try await stage(project, root)
        XCTAssertTrue(carried(from: source).contains("heads"))
        // The project reads the copy, not the app's folder.
        let xcode = try String(contentsOf: source.deletingLastPathComponent().appendingPathComponent("CoinFlip.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertTrue(xcode.contains("path = \"\(source.standardizedFileURL.path)/Assets\""), xcode)
        XCTAssertFalse(xcode.contains(project.dir.path + "/"))
    }

    func testAssetsLinkedElsewhereAreRefused() async throws {
        let (project, root) = try project()
        let assets = project.dir.appendingPathComponent("Assets")
        try FileManager.default.removeItem(at: assets)
        try FileManager.default.createSymbolicLink(at: assets, withDestinationURL: root.appendingPathComponent("Private/Assets"))
        let source = try? await stage(project, root)
        XCTAssertNil(source)
        if let source { XCTAssertFalse(carried(from: source).contains("secret")) }
    }

    func testAFileLinkedElsewhereIsRefused() async throws {
        let (project, root) = try project()
        try FileManager.default.createSymbolicLink(at: project.dir.appendingPathComponent("Assets/photo.txt"),
                                                   withDestinationURL: root.appendingPathComponent("Private/secret.txt"))
        let source = try? await stage(project, root)
        XCTAssertNil(source)
        if let source { XCTAssertFalse(carried(from: source).contains("secret")) }
    }

    func testTheAppsFolderSwappedForALinkGivesNothingElse() async throws {
        let (project, root) = try project()
        try FileManager.default.removeItem(at: project.dir)
        try FileManager.default.createSymbolicLink(at: project.dir, withDestinationURL: root.appendingPathComponent("Private"))
        let source = try? await stage(project, root)
        XCTAssertNil(source)
        if let source { XCTAssertFalse(carried(from: source).contains("secret")) }
    }
}
