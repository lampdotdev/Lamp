import XCTest
@testable import Lamp

/// Send Changes Back sends only what the remix changed, on top of where the repository is now: measured from what the
/// remix last took in, never from the commit its credits name, with Lamp's own files, the manifest's marks and the
/// shared file left as the repository has them but for the change.
final class ContributeTests: XCTestCase {
    private let escape = HistoryEscapeTests()
    private var folders: [URL] = []
    private let source = RepoImport.Source(owner: "maker", name: "drive")
    override func setUp() { expectNoSharingFoldersLeft() }
    override func tearDown() {
        escape.tearDown()
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
    }

    // MARK: A repository put up by Lamp, and a remix of it

    /// What Put on GitHub puts beside the code and leaves out of the shared file.
    private static let notShared: Set<String> = ["README.md", "Package.swift", "build.sh", "Sources/LampSupport.swift", ".gitignore"]

    private func write(_ files: [String: String?], in folder: URL) throws {
        for (path, text) in files {
            let url = folder.appendingPathComponent(path)
            guard let text else { try? FileManager.default.removeItem(at: url); continue }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func git(_ command: String, in folder: URL) throws -> String {
        let ran = try escape.loose(command, in: folder)
        XCTAssertEqual(ran.status, 0, "\(command): \(ran.output)")
        return ran.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The repository with a first commit of `files`, laid out as Put on GitHub lays one out.
    private func repository(_ files: [String: String]) throws -> URL {
        let repo = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-contribute-upstream-\(UUID().uuidString)")
        folders.append(repo)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = try git("git init -q -b main", in: repo)
        let base: [String: String] = [
            "lamp-app.json": #"{"app":"6F1C1E44-0000-4000-8000-000000000001","exportedAt":"2026-01-01T00:00:00Z","format":2,"name":"Drive","description":"A drive"}"#,
            Credits.file: #"{"remixOf":[{"name":"Drive","url":"https://github.com/maker/drive"}],"upstream":[]}"#,
            "README.md": "# Drive\n", "Package.swift": "// Drive\n", "build.sh": "# Drive\n", "Sources/LampSupport.swift": "// runtime 2\n",
            "icon.json": "{\"symbol\": \"car\"}\n",
        ]
        _ = try commit(repo, base.merging(files) { $1 }, "First")
        return repo
    }

    /// Changes the repository and commits it with its shared file made again from what it shares, as a push from Lamp
    /// does. The new commit.
    @discardableResult
    private func commit(_ repo: URL, _ files: [String: String?], _ message: String) throws -> String {
        try write(files, in: repo)
        let stage = repo.deletingLastPathComponent().appendingPathComponent("stage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stage) }
        for path in Contribute.regularFiles(in: repo) where !path.hasPrefix(".git/") && !path.hasSuffix(".lampapp") && !Self.notShared.contains(path) {
            try write([path: try String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8)], in: stage)
        }
        let file = repo.appendingPathComponent("drive.lampapp")
        try? FileManager.default.removeItem(at: file)
        try Sharing.zip(stage, to: file)
        return try git("git add -A && git -c user.name=Maker -c user.email=maker@example.com commit -qm \(Sandbox.quoted(message)) && git rev-parse HEAD", in: repo)
    }

    /// A remix of the repository as it was at `files`: the shared file's code with this Lamp's own files beside it, and
    /// credits naming the repository at `commit`, saved as the version it arrived as.
    private func remix(of files: [String: String], commit: String) async throws -> (project: LampProject, arrival: String) {
        let app = try escape.app()
        let project = app.project
        try FileManager.default.removeItem(at: project.dir.appendingPathComponent("Sources/App.swift"))
        try write(files.filter { !Self.notShared.contains($0.key) && $0.key != "lamp-app.json" && $0.key != Credits.file }, in: project.dir)
        try write([".gitignore": ".lamp/\n", "Package.swift": "// CoinFlip\n", "build.sh": "# CoinFlip\n", "Sources/LampSupport.swift": "// runtime 1\n",
                   Credits.file: #"{"remixOf":[{"name":"Drive","url":"https://github.com/maker/drive","commit":"\#(commit)"}],"upstream":[]}"#,
                   AppDescription.file: #"{"description":"A drive"}"#],
                  in: project.dir)
        let saved = await Versions.save(project, message: "Imported from a shared file")
        XCTAssertTrue(saved)
        let head = await Versions.head(project)
        return (project, try XCTUnwrap(head))
    }

    private func change(_ project: LampProject, _ files: [String: String?], _ message: String) async throws {
        try write(files, in: project.dir)
        let saved = await Versions.save(project, message: message)
        XCTAssertTrue(saved)
    }

    private func prepare(_ project: LampProject, from repo: URL) async throws -> Contribute.Prepared {
        let prepared = try await Contribute.prepare(project, remote: "file://" + repo.path, baseBranch: "main", source: source,
                                                    git: "/usr/bin/git", access: [], login: "remixer")
        // Before the check that the temporary folder is left empty, which was set up first.
        addTeardownBlock { try? FileManager.default.removeItem(at: prepared.folder) }
        return prepared
    }

    private func file(_ path: String, at commit: String, in clone: URL) -> String? {
        let shown = try? escape.loose("git show \(commit):\(Sandbox.quoted(path))", in: clone)
        return shown?.status == 0 ? shown?.output : nil
    }

    /// The shared file in the prepared commit, unpacked.
    private func sharedFile(of prepared: Contribute.Prepared) throws -> URL {
        let out = prepared.folder.appendingPathComponent("check-\(UUID().uuidString)")
        _ = try git("mkdir -p \(Sandbox.quoted(out.path)) && git show \(prepared.commit):drive.lampapp > \(Sandbox.quoted(out.path))/drive.zip "
                    + "&& /usr/bin/ditto -x -k \(Sandbox.quoted(out.path))/drive.zip \(Sandbox.quoted(out.path))/files", in: prepared.clone)
        return out.appendingPathComponent("files")
    }

    // MARK: The cases

    /// A remix opened from a shared file that names the commit before the one it went up in, changed here, while the
    /// repository moved on: only the remix's files go, on the latest commit, and the repository's later work, Lamp's
    /// newer files, its manifest and its credits stay as they are. Its shared file is made again with the change in it.
    func testOnlyTheRemixsOwnChangesGoOnTheLatest() async throws {
        let first = ["Sources/App.swift": "speed\nradio\ngears\n", "Sources/Radio.swift": "fm\n"]
        let repo = try repository(first)
        let stale = try git("git rev-parse HEAD", in: repo)
        let shared = first.merging(["Sources/Radio.swift": "fm\nam\n", "icon.json": "{\"symbol\": \"car\"}\n"]) { $1 }
        try commit(repo, ["Sources/Radio.swift": "fm\nam\n"], "Radio")
        let (project, _) = try await remix(of: shared, commit: stale)
        try await change(project, ["Sources/App.swift": "dial\nradio\ngears\n", "Sources/Gearbox.swift": "six speeds\n",
                                   "icon.json": "{\"symbol\": \"car\"}"], "Dial")
        let tip = try commit(repo, ["Sources/App.swift": "speed\nradio\ngears and splash\n", "Sources/Radio.swift": "fm\nam\nearbuds\n",
                                    "Sources/LampSupport.swift": "// runtime 3\n", "README.md": "# Drive, now\n"], "Later")

        let prepared = try await prepare(project, from: repo)
        XCTAssertEqual(prepared.tip, tip)
        XCTAssertEqual(try git("git rev-parse \(prepared.commit)^", in: prepared.clone), tip, "on the repository's latest")
        XCTAssertEqual(prepared.changed, ["Sources/App.swift", "Sources/Gearbox.swift", "drive.lampapp"])
        XCTAssertEqual(file("Sources/App.swift", at: prepared.commit, in: prepared.clone), "dial\nradio\ngears and splash\n", "both sides' changes")
        for path in ["Sources/Radio.swift", "Sources/LampSupport.swift", "Package.swift", "build.sh", "README.md", "lamp-app.json", Credits.file, "icon.json"] {
            XCTAssertEqual(file(path, at: prepared.commit, in: prepared.clone), file(path, at: tip, in: prepared.clone), path)
        }
        let unpacked = try sharedFile(of: prepared)
        for path in ["Sources/App.swift", "Sources/Gearbox.swift", "Sources/Radio.swift", "lamp-app.json", Credits.file] {
            XCTAssertEqual(try? String(contentsOf: unpacked.appendingPathComponent(path), encoding: .utf8),
                           file(path, at: prepared.commit, in: prepared.clone), "the shared file has \(path) as the code does")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: unpacked.appendingPathComponent("Sources/LampSupport.swift").path))
    }

    /// Changed here, then updated from the repository, which later took that update's change back: the remix is measured
    /// from what the update brought, so what the repository took back isn't sent again as the remix's.
    func testAnUpdateTakenInIsNotSentBack() async throws {
        let repo = try repository(["Sources/App.swift": "a\nb\nc\n"])
        let (project, arrival) = try await remix(of: ["Sources/App.swift": "a\nb\nc\n", "icon.json": "{\"symbol\": \"car\"}\n"],
                                                 commit: try git("git rev-parse HEAD", in: repo))
        try await change(project, ["Sources/Mine.swift": "mine\n"], "Mine")
        let brought = try commit(repo, ["Sources/App.swift": "a\nb\nC\n"], "Capital")

        let update = Sharing.workFolder.appendingPathComponent("update-\(UUID().uuidString)")
        try write(["Sources/App.swift": "a\nb\nC\n", "icon.json": "{\"symbol\": \"car\"}\n",
                   "lamp-app.json": #"{"format": 2, "name": "Drive", "exportedAt": "2026-01-01T00:00:00Z"}"#,
                   Credits.file: #"{"remixOf":[{"name":"Drive","url":"https://github.com/maker/drive","commit":"\#(brought)"}]}"#], in: update)
        let package = try Sharing.open(unpacked: update)
        defer { try? FileManager.default.removeItem(at: package.folder) }
        let merged = try await Upstream.merge(package, into: project, from: nil, commit: nil, arrival: arrival)
        XCTAssertEqual(merged.conflicts, [])
        try Credits.add(try XCTUnwrap(package.credits), to: project)
        let saved = await Versions.save(project, message: "Merged the latest from GitHub")
        XCTAssertTrue(saved)
        try commit(repo, ["Sources/App.swift": "a\nb\nc\n"], "Take it back")

        let prepared = try await prepare(project, from: repo)
        XCTAssertEqual(prepared.changed, ["Sources/Mine.swift", "drive.lampapp"])
        XCTAssertEqual(file("Sources/App.swift", at: prepared.commit, in: prepared.clone), "a\nb\nc\n")
    }

    /// A change the repository already has leaves nothing to send.
    func testAChangeTheRepositoryHasIsNothingToSend() async throws {
        let repo = try repository(["Sources/App.swift": "a\nb\nc\n"])
        let (project, _) = try await remix(of: ["Sources/App.swift": "a\nb\nc\n"], commit: try git("git rev-parse HEAD", in: repo))
        try await change(project, ["Sources/App.swift": "a\nb\nC\n"], "Capital")
        try commit(repo, ["Sources/App.swift": "a\nb\nC\n"], "Capital too")
        do {
            _ = try await prepare(project, from: repo)
            XCTFail("nothing should be prepared")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("already has everything"), error.localizedDescription)
        }
    }

    /// Both changed the same line: nothing goes, and the person is told to bring the repository's changes in first.
    func testTheSameLineChangedOnBothSidesStops() async throws {
        let repo = try repository(["Sources/App.swift": "a\nb\nc\n"])
        let (project, _) = try await remix(of: ["Sources/App.swift": "a\nb\nc\n"], commit: try git("git rev-parse HEAD", in: repo))
        try await change(project, ["Sources/App.swift": "A\nb\nc\n"], "Mine")
        try commit(repo, ["Sources/App.swift": "X\nb\nc\n"], "Theirs")
        do {
            _ = try await prepare(project, from: repo)
            XCTFail("nothing should be prepared")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Sources/App.swift") && error.localizedDescription.contains("Check for Updates"),
                          error.localizedDescription)
        }
    }

    /// A file taken out and one renamed go as that, in the code and in the shared file.
    func testDeletedAndRenamedFiles() async throws {
        let files = ["Sources/App.swift": "app\n", "Sources/Radio.swift": "fm\n", "Sources/Old.swift": "old\n"]
        let repo = try repository(files)
        let (project, _) = try await remix(of: files, commit: try git("git rev-parse HEAD", in: repo))
        try await change(project, ["Sources/Radio.swift": nil, "Sources/Old.swift": nil, "Sources/New.swift": "old\n"], "Tidy")
        try commit(repo, ["README.md": "# Drive, now\n"], "Readme")

        let prepared = try await prepare(project, from: repo)
        XCTAssertEqual(prepared.changed, ["Sources/New.swift", "Sources/Old.swift", "Sources/Radio.swift", "drive.lampapp"])
        XCTAssertNil(file("Sources/Radio.swift", at: prepared.commit, in: prepared.clone))
        XCTAssertNil(file("Sources/Old.swift", at: prepared.commit, in: prepared.clone))
        XCTAssertEqual(file("README.md", at: prepared.commit, in: prepared.clone), "# Drive, now\n")
        let unpacked = try sharedFile(of: prepared)
        XCTAssertEqual(Contribute.regularFiles(in: unpacked), ["Sources/App.swift", "Sources/New.swift", Credits.file, "icon.json", "lamp-app.json"].sorted())
    }
}
