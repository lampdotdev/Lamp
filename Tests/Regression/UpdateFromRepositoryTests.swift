import XCTest
@testable import Lamp

/// A repository opened twice with Keep Both leaves two wishes: the first takes the repository's identity, the second
/// gets none of its own. Update from GitHub… in the second one's info panel must offer to update that wish, never the
/// first, which is the one the fetched repository's identity names.
final class UpdateFromRepositoryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-repo-update-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func wish(_ id: String, identity: String?) throws -> LampProject {
        let dir = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try "// swift-tools-version:5.9".write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let project = LampProject(id: id, name: "Tally", exe: "Tally", dir: dir)
        if let identity { Sharing.setIdentity(identity, of: project) }
        return project
    }

    private func fetched(identity: String?) -> Sharing.Package {
        Sharing.Package(name: "Tally", identity: identity, folder: root.appendingPathComponent("fetched"),
                        sources: [], attachments: [], fileCount: 0)
    }

    func testUpdatingTheSecondCopyLeavesTheFirstAlone() throws {
        let identity = UUID().uuidString
        let first = try wish("tally", identity: identity), second = try wish("tally-2", identity: nil)
        let projects = [first, second]

        XCTAssertEqual(Store.copy(of: fetched(identity: identity), among: projects, updating: second.id)?.id, second.id)
        XCTAssertEqual(Store.copy(of: fetched(identity: identity), among: projects, updating: first.id)?.id, first.id)
        // A repository opened by hand still finds the wish it's a version of.
        XCTAssertEqual(Store.copy(of: fetched(identity: identity), among: projects)?.id, first.id)
    }
}
