import XCTest
import AppKit
@testable import Lamp

/// A wish's credit travels with it and is only ever added to: a shared file carries what the wish arrived with even after
/// its own file lost it, the copy another Mac makes keeps it, and each share adds the wish shared to the chain.
final class CreditsTests: XCTestCase {
    private var folders: [URL] = []
    override func setUp() { expectNoSharingFoldersLeft() }
    override func tearDown() { folders.forEach { try? FileManager.default.removeItem(at: $0) } }

    private func app(_ id: String) throws -> LampProject {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-credits-\(UUID().uuidString)")
        folders.append(root)
        let project = LampProject(id: id, name: id.capitalized, exe: id.capitalized, dir: root.appendingPathComponent(id))
        try fm.createDirectory(at: project.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try fm.createDirectory(at: project.dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try Data("import SwiftUI\n".utf8).write(to: project.dir.appendingPathComponent("Sources/App.swift"))
        try Template.saveMeta(project)
        return project
    }

    func testCreditSurvivesAStrippedFileAndTheSharedFileRoundTrip() throws {
        let city = Credits.Source(name: "Slop New York", author: "Mr.doob", url: "https://github.com/mrdoob/slop-newyork",
                                  commit: "199f010cf9b35eb58ec934d95eba1ab977c880c1", license: "MIT")
        let sender = try app("city")
        try Credits.arrive(Credits(upstream: [city], remixOf: [Credits.Remix(name: "New York", starter: "newyork")]), in: sender)
        // The file rewritten with the city cut down to its name and a new source, as an agent might: the city is still
        // credited in full.
        try Data(#"{"upstream": [{"name": "Slop New York"}, {"name": "Snow", "license": "CC0-1.0", "url": "javascript:alert(1)"}, {"author": "no name"}]}"#.utf8)
            .write(to: sender.dir.appendingPathComponent(Credits.file))
        XCTAssertEqual(Credits.load(sender).upstream.map(\.name), ["Slop New York", "Snow"])
        XCTAssertEqual(Credits.load(sender).upstream.first, city)
        XCTAssertNil(Credits.load(sender).upstream[1].url, "only https addresses are kept")

        let package = try opened(try exported(sender))
        let receiver = try app("copy")
        try Sharing.install(package, into: receiver)
        let arrived = Credits.load(receiver)
        XCTAssertEqual(arrived.upstream.first, city)
        XCTAssertEqual(arrived.basedOn, "Based on Slop New York by Mr.doob")
        XCTAssertEqual(arrived.remixOf.map(\.name), ["New York", "City"])
        XCTAssertEqual(arrived.remixOf.last?.wish, Sharing.identity(of: sender, create: false))

        // The copy's file emptied: it still shares its whole credit, with itself added once however often it's shared.
        try Data("{}".utf8).write(to: receiver.dir.appendingPathComponent(Credits.file))
        let again = try opened(try exported(receiver))
        _ = try opened(try exported(receiver))
        XCTAssertEqual(again.credits?.upstream.map(\.name), ["Slop New York", "Snow"])
        XCTAssertEqual(again.credits?.remixOf.map(\.name), ["New York", "City", "Copy"])
    }

    /// Work with no licence, a missing licence file or a key in the code keeps a wish from being shared; a share-alike
    /// licence doesn't, and is named.
    func testWhatKeepsAWishFromBeingShared() throws {
        let saved = Sharing.knownSecrets
        defer { Sharing.knownSecrets = saved }
        Sharing.knownSecrets = { _ in ["sk-or-v1-made-up-key-for-the-test-0123456789"] }
        let project = try app("remix")
        func share() -> String? {
            do { _ = try exported(project); return nil } catch { return (error as? LocalizedError)?.recoverySuggestion ?? "\(error)" }
        }
        XCTAssertNil(share())

        try Credits.arrive(Credits(upstream: [Credits.Source(name: "Found Code", author: "Someone")]), in: project)
        XCTAssertEqual(share(), "It uses Found Code by Someone, which came with no licence. It can still be used on this Mac.")

        try Credits.arrive(Credits(upstream: [Credits.Source(name: "Engine", license: "GPL-3.0-or-later", licenseFile: "LICENSE-engine")]), in: project)
        XCTAssertNotNil(share(), "its licence file is missing")
        try Data("GPL".utf8).write(to: project.dir.appendingPathComponent("LICENSE-engine"))
        XCTAssertNil(share())
        XCTAssertEqual(ShareCheck.notes(for: Credits.load(project)).count, 1)
        // The licence goes with the file, so the copy can be shared on.
        let copy = try app("copy")
        try Sharing.install(try opened(try exported(project)), into: copy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.dir.appendingPathComponent("LICENSE-engine").path))

        try Data("let key = \"sk-or-v1-made-up-key-for-the-test-0123456789\"\n".utf8).write(to: project.dir.appendingPathComponent("Sources/Key.swift"))
        XCTAssertEqual(share()?.hasPrefix("It's in Sources/Key.swift"), true)

        XCTAssertEqual(ShareCheck.licence("MIT OR GPL-2.0"), .open)
        XCTAssertEqual(ShareCheck.licence("MIT AND GPL-2.0"), .shareAlike)
        XCTAssertEqual(ShareCheck.licence("GPL-3.0-only AND (MIT OR Apache-2.0)"), .shareAlike)
        XCTAssertEqual(ShareCheck.licence("(MIT OR GPL-2.0) AND Apache-2.0 WITH LLVM-exception"), .open)
        XCTAssertEqual(ShareCheck.licence("LicenseRef-NYC-Open-Data"), .ownTerms)
        XCTAssertEqual(ShareCheck.licence(nil), .none)
    }

    func testPicturesMadeWithAIAreMarked() throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        XCTAssertFalse(AIMark.isMarked(png))
        XCTAssertTrue(AIMark.isMarked(AIMark.marked(png)))
    }
}
