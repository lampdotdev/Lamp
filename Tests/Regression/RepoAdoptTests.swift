import XCTest
@testable import Lamp

/// A project on GitHub named in a wish typed on the desk (`Store.adopt`): Lamp fetches it and writes its credit, the
/// commit fetched and its license files into the wish before the request goes, so the app's updates have where they
/// came from. The wishes below are ones typed into Lamp's desk as written. The license texts in Tests/Fixtures/licenses
/// are the projects' own files, fetched from GitHub on 2026-10-28 (WebGL-Fluid-Simulation at a2d2929, d3-celestial at
/// 7e720a3, git at 8d1b215).
@MainActor
final class RepoAdoptTests: XCTestCase {
    private var roots: [URL] = []
    private let licenses = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/licenses")

    override func tearDown() {
        unsetenv("GIT_CONFIG_GLOBAL")
        for root in roots { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: What a wish names

    func testTheWishesAsTypedNameTheirProjectAndAskForAnApp() throws {
        let fluid = try XCTUnwrap(RepoImport.mention(in: "https://github.com/PavelDoGreat/WebGL-Fluid-Simulation make this a full-screen living artwork for my Mac, without the analytics and promo stuff"))
        XCTAssertEqual(fluid.source, RepoImport.Source(owner: "PavelDoGreat", name: "WebGL-Fluid-Simulation"))
        XCTAssertEqual(fluid.ask, "make this a full-screen living artwork for my Mac, without the analytics and promo stuff")
        XCTAssertTrue(fluid.asksForApp)

        let moodist = try XCTUnwrap(RepoImport.mention(in: "https://github.com/remvze/moodist turn this into my personal ambient-sound room, and tell me which of its sounds I can keep given their licenses"))
        XCTAssertEqual(moodist.source.url, "https://github.com/remvze/moodist")
        XCTAssertTrue(moodist.asksForApp)

        let sky = try XCTUnwrap(RepoImport.mention(in: "https://github.com/ofrohn/d3-celestial make this show tonight's sky above my home"))
        XCTAssertEqual(sky.ask, "make this show tonight's sky above my home")
        XCTAssertTrue(sky.asksForApp)
    }

    func testAnAddressAloneAsksForAnApp() throws {
        let bare = try XCTUnwrap(RepoImport.mention(in: "  github.com/ofrohn/d3-celestial  "))
        XCTAssertEqual(bare.ask, "")
        XCTAssertTrue(bare.asksForApp)
        let quoted = try XCTUnwrap(RepoImport.mention(in: "<https://github.com/ofrohn/d3-celestial>: make it a sky map"))
        XCTAssertEqual(quoted.ask, "make it a sky map")
    }

    func testAQuestionAboutAProjectIsNotARequestForAnApp() throws {
        let question = try XCTUnwrap(RepoImport.mention(in: "explain this repo https://github.com/ofrohn/d3-celestial"))
        XCTAssertEqual(question.ask, "explain this repo")
        XCTAssertFalse(question.asksForApp)
        XCTAssertFalse(try XCTUnwrap(RepoImport.mention(in: "what does https://github.com/remvze/moodist do?")).asksForApp)
    }

    func testABranchOrTagIsKept() throws {
        let tagged = try XCTUnwrap(RepoImport.mention(in: "https://github.com/ofrohn/d3-celestial/tree/v0.7.35 make a sky map"))
        XCTAssertEqual(tagged.source.ref, "v0.7.35")
    }

    func testAFileTwoProjectsOrNoProjectGoAsWritten() {
        XCTAssertNil(RepoImport.mention(in: "https://github.com/ofrohn/d3-celestial/blob/master/celestial.js what does this do"))
        XCTAssertNil(RepoImport.mention(in: "https://github.com/remvze/moodist/issues/12 fix this"))
        XCTAssertNil(RepoImport.mention(in: "mix https://github.com/remvze/moodist with https://github.com/ofrohn/d3-celestial"))
        XCTAssertNil(RepoImport.mention(in: "a sky map of tonight"))
        XCTAssertNotNil(RepoImport.mention(in: "https://github.com/ofrohn/d3-celestial, like github.com/ofrohn/d3-celestial"))
    }

    // MARK: License files

    func testTheLicensesLampCanTell() throws {
        XCTAssertEqual(RepoLicenses.id(of: try String(contentsOf: licenses.appendingPathComponent("webgl-fluid-simulation-LICENSE"), encoding: .utf8)), "MIT")
        XCTAssertEqual(RepoLicenses.id(of: try String(contentsOf: licenses.appendingPathComponent("d3-celestial-LICENSE"), encoding: .utf8)), "BSD-3-Clause")
        // GPL's text doesn't say "only" or "or later": Lamp leaves the id to the project.
        XCTAssertNil(RepoLicenses.id(of: try String(contentsOf: licenses.appendingPathComponent("git-COPYING"), encoding: .utf8)))
        XCTAssertNil(RepoLicenses.id(of: "All rights reserved."))
    }

    func testEachLicenseAndNoticeIsKeptAsItsOwnFile() throws {
        let tree = try newRoot().appendingPathComponent("tree")
        let wish = try newRoot().appendingPathComponent("wish")
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wish, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: licenses.appendingPathComponent("webgl-fluid-simulation-LICENSE"), to: tree.appendingPathComponent("LICENSE-MIT"))
        try FileManager.default.copyItem(at: licenses.appendingPathComponent("d3-celestial-LICENSE"), to: tree.appendingPathComponent("LICENSE-BSD"))
        try "Includes work by others.\n".write(to: tree.appendingPathComponent("NOTICE"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: tree.appendingPathComponent("COPYING"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))

        let kept = try RepoLicenses.keep(from: tree, name: "pair", in: wish)
        XCTAssertNil(kept.license, "two licenses may be a choice or both: only the project says")
        XCTAssertEqual(kept.licenseFile, "Licenses/pair/LICENSE-BSD")
        let names = try FileManager.default.contentsOfDirectory(atPath: wish.appendingPathComponent("Licenses/pair").path).sorted()
        XCTAssertEqual(names, ["LICENSE-BSD", "LICENSE-MIT", "NOTICE"], "a link brings nothing in")
    }

    // MARK: The wish

    func testTheCreditCommitAndLicenseAreInTheWishBeforeTheRequestGoes() async throws {
        let (store, wish) = try makeWish()
        let photo = try attachment()
        var sent: [String] = []
        store.sendDraft = { project in
            // What the agent will find when the request reaches it.
            XCTAssertNotNil(Credits.read(project.dir.appendingPathComponent(Credits.file)), "the credit is written before the request goes")
            sent.append(project.id)
        }
        var sha = ""
        store.fetchRepository = { source, folder, _ in
            let tree = try self.repository(source, in: folder, files: ["LICENSE": self.text("webgl-fluid-simulation-LICENSE"), "NOTICE": "Thanks.\n", "index.html": "<canvas></canvas>\n"])
            sha = try self.head(tree)
            return tree
        }
        let typed = "https://github.com/PavelDoGreat/WebGL-Fluid-Simulation make this a full-screen living artwork for my Mac"
        store.adopt(try XCTUnwrap(RepoImport.mention(in: typed)), draft: Store.Draft(text: typed, attachments: [photo]), in: wish)
        XCTAssertTrue(store.busy.contains(wish.id), "the chat's Stop shows while it's fetched")
        try await waitUntilFree(store, wish)

        XCTAssertEqual(sent, [wish.id])
        let credits = try XCTUnwrap(Credits.read(wish.dir.appendingPathComponent(Credits.file)))
        let source = try XCTUnwrap(credits.upstream.first)
        XCTAssertEqual(source.url, "https://github.com/PavelDoGreat/WebGL-Fluid-Simulation")
        XCTAssertEqual(source.author, "PavelDoGreat")
        XCTAssertEqual(source.commit, sha)
        XCTAssertEqual(source.license, "MIT")
        XCTAssertEqual(source.licenseFile, "Licenses/WebGL-Fluid-Simulation/LICENSE")
        XCTAssertTrue(FileManager.default.fileExists(atPath: wish.dir.appendingPathComponent("Licenses/WebGL-Fluid-Simulation/NOTICE").path))
        // Lamp's own record of what the wish arrived with, which the file can't take back.
        XCTAssertNotNil(Credits.read(wish.dir.appendingPathComponent(Credits.arrivedPath)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: wish.dir.appendingPathComponent(".lamp/reference/WebGL-Fluid-Simulation/index.html").path))

        let draft = store.draft(for: wish)
        XCTAssertEqual(draft.text, AppUpdates.adaptRequest(RepoImport.Source(owner: "PavelDoGreat", name: "WebGL-Fluid-Simulation"), commit: sha,
                                                           change: "make this a full-screen living artwork for my Mac",
                                                           reference: ".lamp/reference/WebGL-Fluid-Simulation"))
        XCTAssertTrue(draft.text.contains(sha))
        XCTAssertEqual(draft.attachments, [photo])

        // Its updates are looked for where it came from, from the commit it was made from.
        guard case .adapted(let followed)? = AppUpdates.route(of: wish) else { return XCTFail("no update route") }
        XCTAssertEqual(followed.url, "https://github.com/PavelDoGreat/WebGL-Fluid-Simulation")
        XCTAssertEqual(followed.commit, sha)
    }

    func testAFetchThatFailsKeepsTheWishAndOffersRetry() async throws {
        let (store, wish) = try makeWish()
        let photo = try attachment()
        var sent = 0
        store.sendDraft = { _ in sent += 1 }
        store.fetchRepository = { _, _, _ in throw Sharing.ImportError("Lamp couldn't get remvze/moodist from GitHub.", detail: "Check the address and that you're online.") }
        let typed = "https://github.com/remvze/moodist turn this into my ambient-sound room"
        store.adopt(try XCTUnwrap(RepoImport.mention(in: typed)), draft: Store.Draft(text: typed, attachments: [photo]), in: wish)
        try await waitUntilFree(store, wish)

        XCTAssertEqual(sent, 0, "nothing goes without the commit it's made from")
        XCTAssertEqual(store.draft(for: wish).text, typed)
        XCTAssertEqual(store.draft(for: wish).attachments, [photo])
        let line = try XCTUnwrap(store.logs[wish.id]?.last)
        XCTAssertEqual(line.kind, .error)
        XCTAssertEqual(line.retryFetch, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: wish.dir.appendingPathComponent(Credits.file).path))

        // Retry fetches what's in the box again.
        store.fetchRepository = { source, folder, _ in try self.repository(source, in: folder, files: ["README.md": "Sounds.\n"]) }
        store.retryFetch(wish)
        try await waitUntilFree(store, wish)
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(store.draft(for: wish).attachments, [photo])
        XCTAssertTrue(store.draft(for: wish).text.hasPrefix("Make https://github.com/remvze/moodist into an app, from its commit "))
        let source = try XCTUnwrap(Credits.read(wish.dir.appendingPathComponent(Credits.file))?.upstream.first)
        XCTAssertNil(source.license, "no license file, no license")
        XCTAssertNil(source.licenseFile)
    }

    func testStopEndsGitAndNothingIsSent() async throws {
        let (store, wish) = try makeWish()
        var sent = 0
        store.sendDraft = { _ in sent += 1 }
        var git: Process?
        store.fetchRepository = { source, folder, started in
            // A fetch that would take half a minute, as a big project's does.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["30"]
            try process.run()
            git = process
            started(process)
            while process.isRunning { try await Task.sleep(for: .milliseconds(50)) }
            return try self.repository(source, in: folder, files: ["README.md": "Late.\n"])
        }
        let typed = "https://github.com/ofrohn/d3-celestial make this show tonight's sky above my home"
        store.adopt(try XCTUnwrap(RepoImport.mention(in: typed)), draft: Store.Draft(text: typed), in: wish)
        try await waitFor { git != nil }
        store.stop(wish)
        try await waitUntilFree(store, wish)

        XCTAssertEqual(git?.isRunning, false)
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(store.draft(for: wish).text, typed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: wish.dir.appendingPathComponent(Credits.file).path))
        XCTAssertEqual(store.logs[wish.id]?.last?.text, "Stopped. Your wish is back in the box.")
    }

    func testAWishFoundOnGitHubOpensWithTheAskAndFiles() async throws {
        let (store, wish) = try makeWish()
        let photo = try attachment()
        var sent = 0
        store.sendDraft = { _ in sent += 1 }
        var opened: URL?
        store.openFetchedWish = { opened = $0 }
        store.fetchRepository = { source, folder, _ in
            try self.repository(source, in: folder, files: ["lamp-app.json": "{\"name\": \"Hot Shelf\"}\n", "Sources/App.swift": "// app\n"])
        }
        let typed = "https://github.com/someone/hot-shelf add a 10+ filter"
        store.adopt(try XCTUnwrap(RepoImport.mention(in: typed)), draft: Store.Draft(text: typed, attachments: [photo]), in: wish)
        try await waitFor { opened != nil }

        let tree = try XCTUnwrap(opened)
        XCTAssertEqual(Store.fetchedRequest(beside: tree), "add a 10+ filter", "the ask waits for the wish's box, as a link's does")
        XCTAssertEqual(store.fetchedAttachments[tree.standardizedFileURL.path], [photo])
        XCTAssertEqual(sent, 0)
        XCTAssertFalse(store.projects.contains { $0.id == wish.id }, "the new wish, never sent to, leaves nothing behind")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tree.deletingLastPathComponent().appendingPathComponent(Credits.file).path))
        try? FileManager.default.removeItem(at: tree.deletingLastPathComponent())
    }

    func testAQuestionAboutAProjectCanGoAsWritten() async throws {
        let (store, wish) = try makeWish()
        var sent = 0
        store.sendDraft = { _ in sent += 1 }
        var asked: String?
        store.askToAdapt = { _, ask in asked = ask; return .asWritten }
        store.fetchRepository = { source, folder, _ in try self.repository(source, in: folder, files: ["README.md": "Stars.\n"]) }
        let typed = "explain this repo https://github.com/ofrohn/d3-celestial"
        store.adopt(try XCTUnwrap(RepoImport.mention(in: typed)), draft: Store.Draft(text: typed), in: wish)
        try await waitUntilFree(store, wish)

        XCTAssertEqual(asked, "explain this repo")
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(store.draft(for: wish).text, typed, "the person's own words, not a request for an app")
        XCTAssertFalse(FileManager.default.fileExists(atPath: wish.dir.appendingPathComponent(Credits.file).path))
    }

    func testTheFetchEndsInTheWishItWasStartedIn() async throws {
        let (store, wish) = try makeWish()
        let other = try Template.draft(name: "Other \(UUID().uuidString.prefix(6))", untitled: true, in: wish.dir.deletingLastPathComponent())
        store.reload()
        var sent: [String] = []
        store.sendDraft = { sent.append($0.id) }
        var release: CheckedContinuation<Void, Never>?
        store.fetchRepository = { source, folder, _ in
            await withCheckedContinuation { release = $0 }
            return try self.repository(source, in: folder, files: ["README.md": "Fluid.\n"])
        }
        let typed = "https://github.com/PavelDoGreat/WebGL-Fluid-Simulation make it a screen saver"
        store.adopt(try XCTUnwrap(RepoImport.mention(in: typed)), draft: Store.Draft(text: typed), in: wish)
        try await waitFor { release != nil }
        store.selection = other.id
        release?.resume()
        try await waitUntilFree(store, wish)

        XCTAssertEqual(sent, [wish.id])
        XCTAssertNotNil(Credits.read(wish.dir.appendingPathComponent(Credits.file)))
        XCTAssertNil(Credits.read(other.dir.appendingPathComponent(Credits.file)))
        XCTAssertTrue(store.draft(for: other).isEmpty)
    }

    // MARK: Helpers

    /// Under the home folder, as Lamp's own git runs confined to it, with git's Mac-wide settings an empty file.
    private func newRoot() throws -> URL {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-repo-adopt-test-\(UUID().uuidString)")
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

    private func attachment() throws -> URL {
        let file = try newRoot().appendingPathComponent("sketch.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)
        return file
    }

    private func text(_ fixture: String) -> String {
        (try? String(contentsOf: licenses.appendingPathComponent(fixture), encoding: .utf8)) ?? ""
    }

    /// A repository as a fetch leaves it: one commit, its remote the project's address on GitHub.
    private func repository(_ source: RepoImport.Source, in folder: URL, files: [String: String]) throws -> URL {
        let tree = folder.appendingPathComponent(source.name)
        for (path, contents) in files {
            let file = tree.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
        for arguments in [["init", "-q"], ["remote", "add", "origin", source.url + ".git"], ["add", "-A"],
                          ["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-q", "-m", "Project"]] {
            try git(arguments, in: tree)
        }
        return tree
    }

    private func head(_ tree: URL) throws -> String { try git(["rev-parse", "HEAD"], in: tree).trimmingCharacters(in: .whitespacesAndNewlines) }

    @discardableResult private func git(_ arguments: [String], in folder: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = folder
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, arguments.joined(separator: " "))
        return String(decoding: data, as: UTF8.self)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let until = Date().addingTimeInterval(20)
        while !condition(), Date() < until { try await Task.sleep(for: .milliseconds(20)) }
        guard condition() else {
            XCTFail("it never came")
            throw CancellationError()
        }
    }

    private func waitUntilFree(_ store: Store, _ wish: LampProject) async throws {
        let until = Date().addingTimeInterval(20)
        while store.busy.contains(wish.id), Date() < until { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(store.busy.contains(wish.id), "the fetch ended")
    }
}
