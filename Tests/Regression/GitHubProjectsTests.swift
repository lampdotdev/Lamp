import XCTest
@testable import Lamp

/// `github_project` (`Store.githubProject`), as every engine calls it: a fetch that credits nothing, a snapshot named by
/// owner, name and commit, the credit and every license and notice file written by Lamp, the project the wish is made
/// from told apart from what it uses, and the wish checked as a Lamp repository would hold it. The license texts in
/// Tests/Fixtures/licenses are the projects' own files, fetched from GitHub on 2026-10-28 (WebGL-Fluid-Simulation at
/// a2d2929, d3-celestial at 7e720a3, git at 8d1b215). GitHub itself is stood in for by a local repository with a real
/// commit, so the tests run offline.
@MainActor
final class GitHubProjectsTests: XCTestCase {
    private var roots: [URL] = []
    private let licenses = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/licenses")

    override func tearDown() {
        GitHubProjects.fetcher = GitHubProjects.fetchAnyway
        GitHubProjects.openImport = nil
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

    func testEachLicenseAndNoticeIsKeptAsItsOwnFile() throws {
        let tree = try newRoot().appendingPathComponent("tree")
        let wish = try newRoot()
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        try text("webgl-fluid-simulation-LICENSE").write(to: tree.appendingPathComponent("LICENSE-MIT"), atomically: true, encoding: .utf8)
        try text("d3-celestial-LICENSE").write(to: tree.appendingPathComponent("LICENSE-BSD"), atomically: true, encoding: .utf8)
        try "Includes work by others.\n".write(to: tree.appendingPathComponent("NOTICE"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: tree.appendingPathComponent("COPYING"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))

        let kept = try RepoLicenses.keep(from: tree, place: "Licenses/someone-pair", in: wish)
        XCTAssertEqual(kept.license, "LicenseRef-someone-pair", "two licenses may be a choice or both: the texts are the terms")
        XCTAssertEqual(kept.licenseFile, "Licenses/someone-pair/LICENSE-BSD")
        XCTAssertEqual(kept.notices, ["Licenses/someone-pair/LICENSE-MIT", "Licenses/someone-pair/NOTICE"])
        let names = try FileManager.default.contentsOfDirectory(atPath: wish.appendingPathComponent("Licenses/someone-pair").path).sorted()
        XCTAssertEqual(names, ["LICENSE-BSD", "LICENSE-MIT", "NOTICE"], "a link brings nothing in")
    }

    // MARK: The tool

    func testFetchingCreditsNothingAndNamesOwnerNameAndCommit() async throws {
        let (store, wish) = try makeWish()
        GitHubProjects.fetcher = fake(["LICENSE": text("webgl-fluid-simulation-LICENSE"), "index.html": "<canvas></canvas>\n"])
        let answer = try await call(store, ["action": "fetch", "url": "https://github.com/PavelDoGreat/WebGL-Fluid-Simulation"], on: wish)
        let handle = try XCTUnwrap(answer.split(separator: "\n").first { $0.hasPrefix("Handle: ") }).dropFirst(8)
        let commit = String(handle.split(separator: "@")[1])
        XCTAssertEqual(commit.count, 40)
        XCTAssertTrue(FileManager.default.fileExists(atPath: wish.dir.appendingPathComponent(".lamp/reference/PavelDoGreat/WebGL-Fluid-Simulation@\(commit)/index.html").path))
        XCTAssertTrue(answer.contains("Terms: LICENSE (MIT)"), answer)
        XCTAssertNil(Credits.read(wish.dir.appendingPathComponent(Credits.file)), "a fetch to read it credits nothing")

        // Another owner's project of the same name is another snapshot, never this one.
        GitHubProjects.fetcher = fake(["README.md": "A fork.\n"])
        let fork = try await call(store, ["action": "fetch", "url": "https://github.com/someone/WebGL-Fluid-Simulation"], on: wish)
        XCTAssertTrue(fork.contains("Handle: someone/WebGL-Fluid-Simulation@"), fork)
        XCTAssertTrue(FileManager.default.fileExists(atPath: wish.dir.appendingPathComponent(".lamp/reference/PavelDoGreat/WebGL-Fluid-Simulation@\(commit)/index.html").path))
        let wrongOwner = try await call(store, ["action": "build_from", "handle": "someone/WebGL-Fluid-Simulation@\(commit)"], on: wish, failing: true)
        XCTAssertTrue(wrongOwner.contains("isn't fetched in this wish"), wrongOwner)
    }

    func testBuildFromCreditsThatSnapshotWithEveryTermsFileAndFollowsTheAdaptedProject() async throws {
        let (store, wish) = try makeWish()
        // A library credited first, as an agent may bring one in before the project it adapts.
        GitHubProjects.fetcher = fake(["LICENSE": text("d3-celestial-LICENSE"), "lib.js": "// lib\n"])
        let library = try handle(try await call(store, ["action": "fetch", "url": "https://github.com/ofrohn/d3-celestial"], on: wish))
        _ = try await call(store, ["action": "build_from", "handle": library, "adapted": false], on: wish)

        GitHubProjects.fetcher = fake(["LICENSE": text("webgl-fluid-simulation-LICENSE"), "NOTICE": "Fonts by others.\n", "script.js": "// fluid\n"])
        let project = try handle(try await call(store, ["action": "fetch", "url": "https://github.com/PavelDoGreat/WebGL-Fluid-Simulation"], on: wish))
        let answer = try await call(store, ["action": "build_from", "handle": project], on: wish)
        XCTAssertTrue(answer.contains("as the project this wish is made from"), answer)

        let credits = try XCTUnwrap(Credits.read(wish.dir.appendingPathComponent(Credits.file)))
        let source = try XCTUnwrap(credits.upstream.first { $0.name == "WebGL-Fluid-Simulation" })
        XCTAssertEqual(source.url, "https://github.com/PavelDoGreat/WebGL-Fluid-Simulation")
        XCTAssertEqual(source.author, "PavelDoGreat")
        XCTAssertEqual(source.commit, String(project.split(separator: "@")[1]))
        XCTAssertEqual(source.license, "MIT")
        XCTAssertEqual(source.licenseFile, "Licenses/PavelDoGreat-WebGL-Fluid-Simulation/LICENSE")
        XCTAssertEqual(source.noticeFiles, ["Licenses/PavelDoGreat-WebGL-Fluid-Simulation/NOTICE"])
        XCTAssertEqual(source.adapted, true)
        XCTAssertNotNil(Credits.read(wish.dir.appendingPathComponent(Credits.arrivedPath)), "Lamp's own record has it too")
        XCTAssertEqual(credits.upstream.first?.name, "d3-celestial", "listed first, but a library")

        // The updates follow the project it's made from, not the library listed before it.
        guard case .adapted(let followed)? = AppUpdates.route(of: try XCTUnwrap(store.projects.first { $0.id == wish.id })) else {
            return XCTFail("no update route")
        }
        XCTAssertEqual(followed.url, "https://github.com/PavelDoGreat/WebGL-Fluid-Simulation")
        XCTAssertEqual(credits.basedOn, "Based on WebGL-Fluid-Simulation by PavelDoGreat")

        // A wish is made from one project.
        GitHubProjects.fetcher = fake(["README.md": "Other.\n"])
        let other = try handle(try await call(store, ["action": "fetch", "url": "https://github.com/remvze/moodist"], on: wish))
        let refused = try await call(store, ["action": "build_from", "handle": other], on: wish, failing: true)
        XCTAssertTrue(refused.contains("already made from WebGL-Fluid-Simulation"), refused)
    }

    func testEveryLicenseAndNoticeFileGoesWithTheSharedFileAndComesBack() async throws {
        let (store, wish) = try makeApp()
        GitHubProjects.fetcher = fake(["LICENSE": text("webgl-fluid-simulation-LICENSE"), "NOTICE": "Fonts by others.\n"])
        let project = try handle(try await call(store, ["action": "fetch", "url": "https://github.com/PavelDoGreat/WebGL-Fluid-Simulation"], on: wish))
        _ = try await call(store, ["action": "build_from", "handle": project], on: wish)

        let file = try Sharing.export(wish)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let package = try Sharing.open(file)
        defer { try? FileManager.default.removeItem(at: package.folder) }
        XCTAssertEqual(package.licences.map(\.lastPathComponent).sorted(), ["LICENSE", "NOTICE"])
        let source = try XCTUnwrap(package.credits?.upstream.first)
        XCTAssertEqual(source.noticeFiles, ["Licenses/PavelDoGreat-WebGL-Fluid-Simulation/NOTICE"])
        XCTAssertEqual(source.adapted, true)
    }

    func testCheckMakesTheWishAsALampRepositoryAndOpensItAgain() async throws {
        let (store, wish) = try makeApp()
        GitHubProjects.fetcher = fake(["LICENSE": text("webgl-fluid-simulation-LICENSE"), "NOTICE": "Fonts by others.\n"])
        let project = try handle(try await call(store, ["action": "fetch", "url": "https://github.com/PavelDoGreat/WebGL-Fluid-Simulation"], on: wish))
        _ = try await call(store, ["action": "build_from", "handle": project], on: wish)

        let answer = try await call(store, ["action": "check"], on: wish)
        XCTAssertTrue(answer.contains("\"format\""), answer)
        XCTAssertTrue(answer.contains("Updates follow https://github.com/PavelDoGreat/WebGL-Fluid-Simulation"), answer)
        XCTAssertTrue(answer.contains("Every license and notice file is there"), answer)
        let kept = wish.dir.appendingPathComponent(".lamp/repository")
        for path in ["lamp-app.json", Credits.file, "Licenses/PavelDoGreat-WebGL-Fluid-Simulation/LICENSE",
                     "Licenses/PavelDoGreat-WebGL-Fluid-Simulation/NOTICE", "Package.swift", "build.sh"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: kept.appendingPathComponent(path).path), path)
        }
        XCTAssertNil(GitHubRepo.kept(for: wish), "nothing was put on GitHub")
    }

    func testALampWishOnGitHubGoesToTheReviewWithTheRequest() async throws {
        let (store, wish) = try makeWish()
        var opened: URL?
        GitHubProjects.openImport = { opened = $0 }
        GitHubProjects.fetcher = fake(["lamp-app.json": "{\"name\": \"Hot Shelf\", \"format\": 1}\n", "Sources/App.swift": "// app\n"])
        let answer = try await call(store, ["action": "fetch", "url": "https://github.com/someone/hot-shelf"], on: wish)
        XCTAssertTrue(answer.contains("It's a Lamp wish"), answer)
        let refused = try await call(store, ["action": "build_from", "handle": try handle(answer)], on: wish, failing: true)
        XCTAssertTrue(refused.contains("open_wish"), refused)

        _ = try await call(store, ["action": "open_wish", "handle": try handle(answer), "request": "add a 10+ filter"], on: wish)
        let tree = try XCTUnwrap(opened)
        defer { try? FileManager.default.removeItem(at: tree.deletingLastPathComponent()) }
        XCTAssertEqual(Store.fetchedRequest(beside: tree), "add a 10+ filter", "the request waits for the new wish's box")
        XCTAssertTrue(RepoImport.holdsWish(tree))
        XCTAssertNil(Credits.read(wish.dir.appendingPathComponent(Credits.file)))
    }

    // MARK: Helpers

    private func call(_ store: Store, _ arguments: [String: Any], on wish: LampProject, failing: Bool = false) async throws -> String {
        let (status, answer) = await store.githubProject(arguments, for: wish)
        if failing {
            XCTAssertNotEqual(status, 200)
            return answer["error"] as? String ?? ""
        }
        XCTAssertEqual(status, 200, answer["error"] as? String ?? "")
        return answer["text"] as? String ?? ""
    }

    private func handle(_ answer: String) throws -> String {
        String(try XCTUnwrap(answer.split(separator: "\n").first { $0.hasPrefix("Handle: ") }).dropFirst(8))
    }

    /// A fetch that makes the repository GitHub would give: one commit, its remote the project's address.
    private func fake(_ files: [String: String]) -> GitHubProjects.Fetch {
        { source, folder in
            let tree = folder.appendingPathComponent(source.name)
            for (path, contents) in files {
                let file = tree.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try contents.write(to: file, atomically: true, encoding: .utf8)
            }
            for arguments in [["init", "-q"], ["remote", "add", "origin", source.url + ".git"], ["add", "-A"],
                              ["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-q", "-m", "Project \(UUID().uuidString)"]] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = arguments
                process.currentDirectoryURL = tree
                process.standardOutput = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw GitHubProjects.Failure(message: "git \(arguments[0]) failed") }
            }
            return tree
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

    /// A Mac app with its scaffold, saved as a version, as a wish is once make_app_for has given it its structure.
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
