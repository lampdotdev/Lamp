import XCTest
@testable import Lamp

/// `lampify` (`Store.lampify`), as every engine calls it: a commit pinned once and never moved on by itself, Lamp's own
/// untouched copy at that commit, the credit and every license and notice file written by Lamp, the project the wish is
/// made from told apart from what it uses, and the shape of a Lamp app checked as sharing and the importer see it, with
/// what's missing said rather than thrown. The license texts in Tests/Fixtures/licenses are the projects' own files,
/// fetched from GitHub on 2026-10-28 (WebGL-Fluid-Simulation at a2d2929, d3-celestial at 7e720a3, git at 8d1b215).
/// GitHub itself is stood in for by a local repository whose commit depends only on what it holds, so the same files
/// give the same commit, and the tests run offline.
@MainActor
final class GitHubProjectsTests: XCTestCase {
    private var roots: [URL] = []
    private let licenses = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/licenses")
    private let fluid = "https://github.com/PavelDoGreat/WebGL-Fluid-Simulation"

    override func tearDown() {
        GitHubProjects.fetcher = GitHubProjects.fetchAnyway
        unsetenv("GIT_CONFIG_GLOBAL")
        for root in roots { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: Licenses

    func testTheLicensesLampCanTell() throws {
        XCTAssertEqual(RepoLicenses.id(of: text("webgl-fluid-simulation-LICENSE")), "MIT")
        XCTAssertEqual(RepoLicenses.id(of: text("d3-celestial-LICENSE")), "BSD-3-Clause")
        // GPL's text doesn't say "only" or "or later": Lamp leaves the id to the project.
        XCTAssertNil(RepoLicenses.id(of: text("git-COPYING")))
        XCTAssertNil(RepoLicenses.id(of: "All rights reserved."))
    }

    func testLicensesAndNoticesAnywhereInTheProjectAreKeptAsTheyCame() throws {
        let tree = try newRoot().appendingPathComponent("tree")
        let wish = try newRoot()
        try write([
            "LICENSE": text("webgl-fluid-simulation-LICENSE"),
            "NOTICE": "Includes work by others.\n",
            "vendor/howler/LICENSE.md": text("d3-celestial-LICENSE"),
            "node_modules/left-pad/LICENSE": "A tool's, not shipped.\n",
        ], in: tree)
        try FileManager.default.createSymbolicLink(at: tree.appendingPathComponent("COPYING"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))

        let kept = try RepoLicenses.keep(from: tree, place: "Licenses/someone-game", in: wish)
        XCTAssertEqual(kept.license, "MIT", "the project's own license is the one at its top")
        XCTAssertEqual(kept.licenseFile, "Licenses/someone-game/LICENSE")
        XCTAssertEqual(kept.notices, ["Licenses/someone-game/NOTICE", "Licenses/someone-game/vendor/howler/LICENSE.md"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: wish.appendingPathComponent("Licenses/someone-game/vendor/howler/LICENSE.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: wish.appendingPathComponent("Licenses/someone-game/COPYING").path), "a link brings nothing in")
        XCTAssertFalse(FileManager.default.fileExists(atPath: wish.appendingPathComponent("Licenses/someone-game/node_modules").path))

        // Two licenses at its top may be a choice or both: the texts are the terms.
        try text("d3-celestial-LICENSE").write(to: tree.appendingPathComponent("LICENSE-BSD"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try RepoLicenses.keep(from: tree, place: "Licenses/someone-game", in: wish).license, "LicenseRef-someone-game")
    }

    // MARK: The pinned commit

    func testTheFirstCallPinsTheCommitCreditsItAndSaysTheStructureIsMissing() async throws {
        let (store, wish) = try makeWish()
        GitHubProjects.fetcher = fake(["LICENSE": text("webgl-fluid-simulation-LICENSE"), "index.html": "<canvas></canvas>\n"])
        let answer = try await call(store, ["url": fluid], on: wish)
        let source = try XCTUnwrap(Credits.read(wish.dir.appendingPathComponent(Credits.file))?.upstream.first)
        let commit = try XCTUnwrap(source.commit)
        XCTAssertEqual(commit.count, 40)
        XCTAssertEqual(source.url, fluid)
        XCTAssertEqual(source.author, "PavelDoGreat")
        XCTAssertEqual(source.license, "MIT")
        XCTAssertEqual(source.licenseFile, "Licenses/PavelDoGreat-WebGL-Fluid-Simulation/LICENSE")
        XCTAssertEqual(source.adapted, true)
        XCTAssertNotNil(Credits.read(wish.dir.appendingPathComponent(Credits.arrivedPath)), "Lamp's own record has it too")
        XCTAssertTrue(FileManager.default.fileExists(atPath: wish.dir.appendingPathComponent(".lamp/lampify/PavelDoGreat/WebGL-Fluid-Simulation@\(commit)/index.html").path))
        XCTAssertTrue(answer.contains("Lamp pinned that commit"), answer)
        XCTAssertTrue(answer.contains("Still missing:\n- Its structure: give the wish its app with make_app_for"), answer)
    }

    func testALaterCallNeverMovesOnByItself() async throws {
        let (store, wish) = try makeWish()
        let files = ["LICENSE": text("webgl-fluid-simulation-LICENSE"), "index.html": "<canvas></canvas>\n"]
        GitHubProjects.fetcher = fake(files)
        _ = try await call(store, ["url": fluid], on: wish)
        let pinned = try XCTUnwrap(Credits.read(wish.dir.appendingPathComponent(Credits.file))?.upstream.first?.commit)

        // The project moved on upstream: a call with no commit stays where the wish was made from, without fetching.
        var asked: [String?] = []
        let moved = fake(["LICENSE": text("webgl-fluid-simulation-LICENSE"), "index.html": "<canvas id=new></canvas>\n"])
        GitHubProjects.fetcher = { source, folder in asked.append(source.ref); return try await moved(source, folder) }
        _ = try await call(store, ["url": fluid], on: wish)
        XCTAssertEqual(Credits.read(wish.dir.appendingPathComponent(Credits.file))?.upstream.first?.commit, pinned)
        XCTAssertTrue(asked.isEmpty, "Lamp's copy at the pinned commit is used as it is")

        // Another commit is an update's to bring in, not lampify's.
        let refused = try await call(store, ["url": fluid, "commit": String(repeating: "a", count: 40)], on: wish, failing: true)
        XCTAssertTrue(refused.contains("made from PavelDoGreat/WebGL-Fluid-Simulation at \(pinned)"), refused)

        // Its copy gone, the pinned commit itself is fetched again: never the branch.
        try FileManager.default.removeItem(at: wish.dir.appendingPathComponent(".lamp/lampify"))
        GitHubProjects.fetcher = { source, folder in asked.append(source.ref); return try await self.fake(files)(source, folder) }
        _ = try await call(store, ["url": fluid, "commit": pinned], on: wish)
        XCTAssertEqual(asked, [pinned])
    }

    func testTheCommitGivenIsTheOneReadAndCredited() async throws {
        let files = ["LICENSE": text("webgl-fluid-simulation-LICENSE"), "script.js": "// fluid\n"]
        let (scratch, scratchWish) = try makeWish()
        GitHubProjects.fetcher = fake(files)
        _ = try await call(scratch, ["url": fluid], on: scratchWish)
        let commit = try XCTUnwrap(Credits.read(scratchWish.dir.appendingPathComponent(Credits.file))?.upstream.first?.commit)

        let (store, wish) = try makeWish()
        var asked: [String?] = []
        GitHubProjects.fetcher = { source, folder in asked.append(source.ref); return try await self.fake(files)(source, folder) }
        let answer = try await call(store, ["url": fluid, "commit": commit], on: wish)
        XCTAssertEqual(asked, [commit], "Lamp fetches the commit the agent's clone is at")
        XCTAssertFalse(answer.contains("Lamp pinned that commit"))
        XCTAssertEqual(Credits.read(wish.dir.appendingPathComponent(Credits.file))?.upstream.first?.commit, commit)

        // A commit GitHub doesn't give for that repository is never credited.
        let (other, otherWish) = try makeWish()
        let wrong = try await call(other, ["url": fluid, "commit": String(repeating: "b", count: 40)], on: otherWish, failing: true)
        XCTAssertTrue(wrong.contains("GitHub gave"), wrong)
        XCTAssertNil(Credits.read(otherWish.dir.appendingPathComponent(Credits.file)))
    }

    // MARK: Credits and updates

    func testUpdatesFollowTheAdaptedProjectAndAWishIsMadeFromOne() async throws {
        let (store, wish) = try makeWish()
        // A library lampified first, as an agent may bring one in before the project it adapts.
        GitHubProjects.fetcher = fake(["LICENSE": text("d3-celestial-LICENSE"), "lib.js": "// lib\n"])
        _ = try await call(store, ["url": "https://github.com/ofrohn/d3-celestial", "adapted": false], on: wish)
        GitHubProjects.fetcher = fake(["LICENSE": text("webgl-fluid-simulation-LICENSE"), "NOTICE": "Fonts by others.\n"])
        _ = try await call(store, ["url": fluid], on: wish)

        let credits = try XCTUnwrap(Credits.read(wish.dir.appendingPathComponent(Credits.file)))
        XCTAssertEqual(credits.upstream.first?.name, "d3-celestial", "listed first, but a library")
        XCTAssertNil(credits.upstream.first?.adapted)
        guard case .adapted(let followed)? = AppUpdates.route(of: try XCTUnwrap(store.projects.first { $0.id == wish.id })) else {
            return XCTFail("no update route")
        }
        XCTAssertEqual(followed.url, fluid)
        XCTAssertEqual(credits.basedOn, "Based on WebGL-Fluid-Simulation by PavelDoGreat")
        XCTAssertEqual(credits.upstream.last?.noticeFiles, ["Licenses/PavelDoGreat-WebGL-Fluid-Simulation/NOTICE"])

        GitHubProjects.fetcher = fake(["README.md": "Other.\n"])
        let refused = try await call(store, ["url": "https://github.com/remvze/moodist"], on: wish, failing: true)
        XCTAssertTrue(refused.contains("already made from WebGL-Fluid-Simulation"), refused)
    }

    func testEveryLicenseAndNoticeFileGoesWithTheSharedFileAndComesBack() async throws {
        let (store, wish) = try makeApp()
        GitHubProjects.fetcher = fake(["LICENSE": text("webgl-fluid-simulation-LICENSE"), "NOTICE": "Fonts by others.\n",
                                       "lib/howler/LICENSE.md": text("d3-celestial-LICENSE")])
        _ = try await call(store, ["url": fluid], on: wish)

        let file = try Sharing.export(wish)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let package = try Sharing.open(file)
        defer { try? FileManager.default.removeItem(at: package.folder) }
        XCTAssertEqual(package.licences.map { Sharing.relativePath(of: $0, in: package.folder) }.sorted(), [
            "Licenses/PavelDoGreat-WebGL-Fluid-Simulation/LICENSE", "Licenses/PavelDoGreat-WebGL-Fluid-Simulation/NOTICE",
            "Licenses/PavelDoGreat-WebGL-Fluid-Simulation/lib/howler/LICENSE.md",
        ])
        XCTAssertEqual(package.credits?.upstream.first?.adapted, true)
    }

    // MARK: The shape

    func testTheShapeIsCheckedAsSharingAndTheImporterSeeItUntilNothingIsMissing() async throws {
        let (store, wish) = try makeApp()
        GitHubProjects.fetcher = fake(["LICENSE": text("webgl-fluid-simulation-LICENSE"), "NOTICE": "Fonts by others.\n"])
        let first = try await call(store, ["url": fluid], on: wish)
        XCTAssertTrue(first.contains("\"format\""), first)
        XCTAssertTrue(first.contains("Updates follow \(fluid)"), first)
        XCTAssertTrue(first.contains("- Its line: one plain sentence saying what it is, in about.json."), first)
        XCTAssertTrue(first.contains("- APP.md saying what it is and that it's based on WebGL-Fluid-Simulation by PavelDoGreat."), first)

        try #"{"description": "A living fluid artwork."}"#.write(to: wish.dir.appendingPathComponent(AppDescription.file), atomically: true, encoding: .utf8)
        try "# Fluid\n\nBased on WebGL-Fluid-Simulation by PavelDoGreat (MIT).\n".write(to: wish.dir.appendingPathComponent("APP.md"), atomically: true, encoding: .utf8)
        let commit = try XCTUnwrap(Credits.read(wish.dir.appendingPathComponent(Credits.file))?.upstream.first?.commit)
        let done = try await call(store, ["url": fluid, "commit": commit], on: wish)
        XCTAssertTrue(done.contains("Nothing missing"), done)
        XCTAssertTrue(done.contains("\"description\" : \"A living fluid artwork.\""), done)
        let kept = wish.dir.appendingPathComponent(".lamp/repository")
        for path in ["lamp-app.json", Credits.file, "Licenses/PavelDoGreat-WebGL-Fluid-Simulation/LICENSE",
                     "Licenses/PavelDoGreat-WebGL-Fluid-Simulation/NOTICE", "Package.swift", "build.sh", "README.md"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: kept.appendingPathComponent(path).path), path)
        }
        XCTAssertNil(GitHubRepo.kept(for: wish), "nothing was put on GitHub")
    }

    func testWhatSharingRefusesIsSaidAsMissingNotThrown() async throws {
        let (store, wish) = try makeApp()
        GitHubProjects.fetcher = fake(["index.html": "<canvas></canvas>\n"])
        let answer = try await call(store, ["url": "https://github.com/someone/unlicensed-game"], on: wish)
        XCTAssertTrue(answer.contains("It came with no license of its own"), answer)
        XCTAssertTrue(answer.contains("can't be shared. It uses unlicensed-game"), answer)
    }

    func testALampWishOnGitHubIsSentToOpenFromGitHub() async throws {
        let (store, wish) = try makeWish()
        GitHubProjects.fetcher = fake(["lamp-app.json": "{\"name\": \"Hot Shelf\", \"format\": 1}\n", "Sources/App.swift": "// app\n"])
        let refused = try await call(store, ["url": "https://github.com/someone/hot-shelf"], on: wish, failing: true)
        XCTAssertTrue(refused.contains("File → Open from GitHub…"), refused)
        XCTAssertNil(Credits.read(wish.dir.appendingPathComponent(Credits.file)))
    }

    /// A wish given its app with make_app_for keeps it in a folder of its own, its about.json there: the manifest and the
    /// README of a Lampified repository carry that app's line.
    func testTheRepositoryIsDescribedByTheAppInItsFolder() async throws {
        let (store, draft) = try makeWish()
        let body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": "make_app_for", "arguments": ["kind": "app", "made": "native", "devices": ["mac"]]]])
        _ = await store.mcp(body, for: draft, fileTools: false)
        let wish = try XCTUnwrap(store.projects.first { $0.id == draft.id })
        let app = try XCTUnwrap(store.parts(of: wish).first)
        XCTAssertNotEqual(app.dir, wish.dir, "the app is in a folder of its own")
        XCTAssertNil(AppDescription.description(of: wish))
        try #"{"description": "The classic 2048 sliding-tile puzzle."}"#.write(to: app.dir.appendingPathComponent(AppDescription.file), atomically: true, encoding: .utf8)

        XCTAssertEqual(Sharing.description(of: wish), "The classic 2048 sliding-tile puzzle.")
        let staged = try GitHubRepo.stage(wish, repo: nil, link: nil)
        defer { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: staged.folder.appendingPathComponent("lamp-app.json"))) as? [String: Any])
        XCTAssertEqual(manifest["description"] as? String, "The classic 2048 sliding-tile puzzle.")
        XCTAssertTrue(try String(contentsOf: staged.folder.appendingPathComponent("README.md"), encoding: .utf8).contains("The classic 2048 sliding-tile puzzle."))
    }

    func testARequestNamingAProjectIsPointedAtTheSkillWhateverItAsks() {
        for request in ["make this into a game https://github.com/gabrielecirulli/2048",
                        "explain this repo https://github.com/ofrohn/d3-celestial",
                        "<https://github.com/remvze/moodist>"] {
            let note = GitHubProjects.note(for: request)
            XCTAssertTrue(note.contains("github-projects skill") && note.contains("git clone") && note.contains("`lampify`"), request)
        }
        XCTAssertEqual(GitHubProjects.note(for: "make me a 2048 game"), "")
        XCTAssertEqual(GitHubProjects.note(for: "see github.com for ideas"), "")
    }

    // MARK: Helpers

    private func call(_ store: Store, _ arguments: [String: Any], on wish: LampProject, failing: Bool = false) async throws -> String {
        let (status, answer) = await store.lampify(arguments, for: wish)
        if failing {
            XCTAssertNotEqual(status, 200)
            return answer["error"] as? String ?? ""
        }
        XCTAssertEqual(status, 200, answer["error"] as? String ?? "")
        return answer["text"] as? String ?? ""
    }

    /// A fetch that makes the repository GitHub would give: one commit, its remote the project's address, its author and
    /// time fixed so the same files always make the same commit. Asked for a commit, it gives whatever its files make.
    private func fake(_ files: [String: String]) -> GitHubProjects.Fetch {
        { source, folder in
            let tree = folder.appendingPathComponent(source.name)
            try self.write(files, in: tree)
            let fixed = ["GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com", "GIT_AUTHOR_DATE": "2026-10-28T12:00:00Z",
                         "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com", "GIT_COMMITTER_DATE": "2026-10-28T12:00:00Z"]
            for arguments in [["init", "-q"], ["remote", "add", "origin", source.url + ".git"], ["add", "-A"], ["commit", "-q", "-m", "Project"]] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = arguments
                process.currentDirectoryURL = tree
                process.environment = ProcessInfo.processInfo.environment.merging(fixed) { $1 }
                process.standardOutput = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw GitHubProjects.Failure(message: "git \(arguments[0]) failed") }
            }
            return tree
        }
    }

    private func write(_ files: [String: String], in tree: URL) throws {
        for (path, contents) in files {
            let file = tree.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    /// Under the home folder, as Lamp's own git runs confined to it, with git's Mac-wide settings an empty file.
    private func newRoot() throws -> URL {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-github-projects-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        let settings = fm.temporaryDirectory.appendingPathComponent("lamp-test-git-settings-\(UUID().uuidString)")
        roots.append(settings)
        try "".write(to: settings, atomically: true, encoding: .utf8)
        setenv("GIT_CONFIG_GLOBAL", settings.path, 1)
        return root
    }

    private func makeWish() throws -> (Store, LampProject) {
        let root = try newRoot()
        let draft = try Template.draft(name: "Untitled \(UUID().uuidString.prefix(6))", untitled: true, in: root)
        let store = Store(testingAt: root)
        return (store, try XCTUnwrap(store.projects.first { $0.id == draft.id }))
    }

    /// A Mac app with its scaffold, as a wish is once make_app_for has given it its structure.
    private func makeApp() throws -> (Store, LampProject) {
        let root = try newRoot()
        let made = try Template.scaffold(name: "Fluid \(UUID().uuidString.prefix(6))", platform: .mac, in: root)
        let store = Store(testingAt: root)
        return (store, try XCTUnwrap(store.projects.first { $0.id == made.id }))
    }

    private func text(_ fixture: String) -> String {
        (try? String(contentsOf: licenses.appendingPathComponent(fixture), encoding: .utf8)) ?? ""
    }
}
