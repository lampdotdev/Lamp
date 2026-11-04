import XCTest
@testable import Lamp

/// Someone's shared copy fetched for the agent (`shared_copy`): every form a Lamp link is pasted in names the copy, and
/// what's laid out for the agent is only what the shared file's checks let through, in a folder its file tools and its
/// commands may read and never change, and no other wish's.
final class SharedCopiesTests: XCTestCase {
    func testEveryFormOfALinkNamesTheCopy() {
        let site = URL(string: "http://localhost:4321/api/wishes")!
        for link in ["https://lamp.dev/w/abcd2345XY", "https://lamp.dev/w/abcd2345XY-falling-blocks", "lamp.dev/w/abcd2345XY-falling-blocks",
                     "www.lamp.dev/w/abcd2345XY", "lamp://wish?shared=abcd2345XY", "lamp-nightly://wish?shared=abcd2345XY",
                     "lamp-dev://wish?shared=abcd2345XY&text=Snow", "lamp-dev-tide://wish?shared=abcd2345XY",
                     "http://localhost:4321/w/abcd2345XY-tally"] {
            XCTAssertEqual(Following.copy(fromLink: link, scheme: "lamp", site: site), .lamp("abcd2345XY"), link)
        }
        // A link in a sentence comes with what the sentence puts around it.
        XCTAssertEqual(SharedCopies.place(from: "(https://lamp.dev/w/abcd2345XY-tally)."), .lamp("abcd2345XY"))
        for bad in ["https://lamp.dev/w/abcd2345XYZ", "https://example.com/w/abcd2345XY", "http://lamp.dev/w/abcd2345XY",
                    "slamp://wish?shared=abcd2345XY", "lamp-dev-a/b://wish?shared=abcd2345XY", "http://localhost:9999/w/abcd2345XY"] {
            XCTAssertNil(Following.copy(fromLink: bad, scheme: "lamp", site: site).flatMap(\.link), bad)
        }
        // Installed Lamp knows no dev server's links.
        XCTAssertNil(Following.copy(fromLink: "http://localhost:4321/w/abcd2345XY", scheme: "lamp"))
    }

    func testOnlyCheckedFilesAreLaidOutForReadingOnly() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("shared-copies-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: scratch) }
        let saved = SharedCopies.root
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        SharedCopies.root = URL(fileURLWithPath: Privacy.resolved(scratch.path, in: scratch)).appendingPathComponent("copies")
        defer { SharedCopies.root = saved }

        // Their file, unpacked: its code and an asset, and besides them what no check lists (a script, a link out).
        let theirs = scratch.appendingPathComponent("theirs")
        try fm.createDirectory(at: theirs.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try fm.createDirectory(at: theirs.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        try "struct Water {}".write(to: theirs.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        try "wave".write(to: theirs.appendingPathComponent("Assets/wave.txt"), atomically: true, encoding: .utf8)
        try "#!/bin/sh\necho hi".write(to: theirs.appendingPathComponent("run.sh"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: theirs.appendingPathComponent("Assets/home.txt"), withDestinationURL: fm.homeDirectoryForCurrentUser)
        try #"{"format": 2, "name": "Tide", "exportedAt": "2026-01-01T00:00:00Z"}"#
            .write(to: theirs.appendingPathComponent("lamp-app.json"), atomically: true, encoding: .utf8)
        let package = try Sharing.open(unpacked: theirs)

        let mine = LampProject(id: "pond", name: "Pond", exe: "Pond", dir: scratch.appendingPathComponent("Pond"))
        let other = LampProject(id: "lake", name: "Lake", exe: "Lake", dir: scratch.appendingPathComponent("Lake"))
        let laid = try SharedCopies.lay(package, id: "abcd2345XY", for: mine)
        let listed = (fm.enumerator(atPath: laid.folder.path)?.allObjects as? [String] ?? []).filter { !$0.hasSuffix("Sources") && $0 != "Assets" }.sorted()
        XCTAssertEqual(listed, ["Assets/wave.txt", "Sources/App.swift"])

        let file = laid.folder.appendingPathComponent("Sources/App.swift").path
        XCTAssertEqual(Privacy.verdict(tool: "read", path: file, project: mine), .allow)
        for tool in ["write", "edit"] {
            XCTAssertEqual(Privacy.verdict(tool: tool, path: file, project: mine), .deny(SharedCopies.readOnly), tool)
        }
        guard case .deny = Privacy.verdict(tool: "read", path: file, project: other) else { return XCTFail("another wish read the copy") }
        // A command under Lamp's sandbox, and Codex's, reads there and writes nothing.
        XCTAssertTrue(Sandbox.profile(for: mine).contains("(deny file-write* (subpath \"\(SharedCopies.root.path)\"))"))
        XCTAssertTrue(Sandbox.codexPermissions(for: mine).contains("\(Agent.tomlString(SharedCopies.root.path))=\"read\""))
    }
}
