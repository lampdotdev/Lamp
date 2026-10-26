import XCTest
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
                                  commit: "199f010cf9b35eb58ec934d95eba1ab977c880c1", license: "MIT", licenseFile: "Web/LICENSE-slop-newyork")
        let sender = try app("city")
        try Credits.arrive(Credits(upstream: [city], remixOf: [Credits.Remix(name: "New York", starter: "newyork")]), in: sender)
        // The file rewritten with only a new source, as an agent might: the city is still credited.
        try Data(#"{"upstream": [{"name": "Snow", "license": "CC0-1.0", "url": "javascript:alert(1)"}, {"author": "no name"}]}"#.utf8)
            .write(to: sender.dir.appendingPathComponent(Credits.file))
        XCTAssertEqual(Credits.load(sender).upstream.map(\.name), ["Slop New York", "Snow"])
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
}
