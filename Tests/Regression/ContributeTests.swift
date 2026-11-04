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
            "lamp-app.json": #"{"app":"6F1C1E44-0000-4000-8000-000000000001","exportedAt":"2026-01-01T00:00:00Z","format":2,"name":"Drive","description":"A drive","platform":"mac"}"#,
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
            let to = stage.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: repo.appendingPathComponent(path), to: to)
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
                   "lamp-app.json": #"{"format": 2, "name": "Drive", "exportedAt": "2026-01-01T00:00:00Z", "description": "A drive", "platform": "mac"}"#,
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

    /// A change the repository already has leaves nothing to send, even where its shared file was zipped as Lamp zipped
    /// one before (with ditto), which remaking it would change.
    func testAChangeTheRepositoryHasIsNothingToSend() async throws {
        let repo = try repository(["Sources/App.swift": "a\nb\nc\n"])
        let (project, _) = try await remix(of: ["Sources/App.swift": "a\nb\nc\n"], commit: try git("git rev-parse HEAD", in: repo))
        try await change(project, ["Sources/App.swift": "a\nb\nC\n"], "Capital")
        try commit(repo, ["Sources/App.swift": "a\nb\nC\n"], "Capital too")
        _ = try git("mkdir ../ditto-$$ && /usr/bin/ditto -x -k drive.lampapp ../ditto-$$ && rm drive.lampapp && /usr/bin/ditto -c -k --norsrc ../ditto-$$ drive.lampapp "
                    + "&& rm -rf ../ditto-$$ && git add -A && git -c user.name=Maker -c user.email=maker@example.com commit -qm Zipped", in: repo)
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

    /// A new line for the app, written after an update was taken in, goes in the manifest; the repository's identity,
    /// name and date stay.
    func testTheLineChangedAfterAnUpdateGoes() async throws {
        let repo = try repository(["Sources/App.swift": "a\nb\nc\n"])
        let (project, arrival) = try await remix(of: ["Sources/App.swift": "a\nb\nc\n"], commit: try git("git rev-parse HEAD", in: repo))
        let brought = try commit(repo, ["Sources/App.swift": "a\nb\nC\n"], "Capital")
        let update = Sharing.workFolder.appendingPathComponent("update-\(UUID().uuidString)")
        try write(["Sources/App.swift": "a\nb\nC\n",
                   "lamp-app.json": #"{"format": 2, "name": "Drive", "exportedAt": "2026-01-01T00:00:00Z", "description": "A drive", "platform": "mac"}"#,
                   Credits.file: #"{"remixOf":[{"name":"Drive","url":"https://github.com/maker/drive","commit":"\#(brought)"}]}"#], in: update)
        let package = try Sharing.open(unpacked: update)
        defer { try? FileManager.default.removeItem(at: package.folder) }
        _ = try await Upstream.merge(package, into: project, from: nil, commit: nil, arrival: arrival)
        try Credits.add(try XCTUnwrap(package.credits), to: project)
        let saved = await Versions.save(project, message: "Merged the latest from GitHub")
        XCTAssertTrue(saved)
        try await change(project, [AppDescription.file: #"{"description":"A faster drive"}"#], "Faster")

        let prepared = try await prepare(project, from: repo)
        XCTAssertEqual(prepared.changed, ["drive.lampapp", "lamp-app.json"])
        let manifest = try XCTUnwrap(file("lamp-app.json", at: prepared.commit, in: prepared.clone).flatMap {
            try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        })
        XCTAssertEqual(manifest["description"] as? String, "A faster drive")
        XCTAssertEqual(manifest["app"] as? String, "6F1C1E44-0000-4000-8000-000000000001")
        XCTAssertEqual(manifest["exportedAt"] as? String, "2026-01-01T00:00:00Z")
        XCTAssertEqual(manifest["platform"] as? String, "mac")
    }

    /// An Android remix's code is in this Mac's package for it: what it changed goes back in the repository's package,
    /// at the repository's paths, and the id Lamp set for this Mac stays out of the build file.
    func testAnAndroidRemixGoesBackInTheRepositorysPackage() async throws {
        let app = try escape.app()
        let sender = try Template.scaffold(name: "Tally", platform: .android, in: app.root.appendingPathComponent("Sender"))
        let theirs = Template.androidPackage(for: sender)
        let exported = try Sharing.export(sender)
        defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }
        let repo = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-contribute-upstream-\(UUID().uuidString)")
        folders.append(repo)
        _ = try git("mkdir -p \(Sandbox.quoted(repo.path)) && /usr/bin/ditto -x -k \(Sandbox.quoted(exported.path)) \(Sandbox.quoted(repo.path)) && git -C \(Sandbox.quoted(repo.path)) init -q -b main",
                    in: app.root)
        try write([Credits.file: #"{"remixOf":[{"name":"Tally","url":"https://github.com/maker/drive"}],"upstream":[]}"#], in: repo)
        let first = try commit(repo, [:], "First")

        var receiver = try Template.scaffold(name: "Counter", platform: .android, in: app.root.appendingPathComponent("Receiver"))
        receiver.platform = .android
        _ = try git("git init -q -b main && printf '.lamp/\\nbuild/\\n.gradle/\\n' > .gitignore", in: receiver.dir)
        let package = try Sharing.open(unpacked: { () throws -> URL in
            let folder = Sharing.workFolder.appendingPathComponent("arriving-\(UUID().uuidString)")
            _ = try git("mkdir -p \(Sandbox.quoted(folder.path)) && git archive HEAD | tar -x -C \(Sandbox.quoted(folder.path))", in: repo)
            return folder
        }())
        defer { try? FileManager.default.removeItem(at: package.folder) }
        _ = try Sharing.install(package, into: receiver)
        try write([Credits.file: #"{"remixOf":[{"name":"Tally","url":"https://github.com/maker/drive","commit":"\#(first)"}],"upstream":[]}"#], in: receiver.dir)
        let arrived = await Versions.save(receiver, message: "Imported from a shared file")
        XCTAssertTrue(arrived)

        let ours = Template.androidPackage(for: receiver)
        XCTAssertNotEqual(ours, theirs)
        func folder(_ package: String) -> String { "app/src/main/kotlin/" + package.replacingOccurrences(of: ".", with: "/") }
        let activity = receiver.dir.appendingPathComponent(folder(ours) + "/MainActivity.kt")
        let text = try String(contentsOf: activity, encoding: .utf8)
        try await change(receiver, [folder(ours) + "/MainActivity.kt": text + "\n// Counts by twos\n",
                                    folder(ours) + "/Twos.kt": "package \(ours)\n\nval step = 2\n"], "Twos")

        let prepared = try await prepare(receiver, from: repo)
        XCTAssertEqual(prepared.changed, [folder(theirs) + "/MainActivity.kt", folder(theirs) + "/Twos.kt", "drive.lampapp"].sorted())
        let sent = try XCTUnwrap(file(folder(theirs) + "/MainActivity.kt", at: prepared.commit, in: prepared.clone))
        XCTAssertEqual(sent, (file(folder(theirs) + "/MainActivity.kt", at: first, in: prepared.clone) ?? "") + "\n// Counts by twos\n")
        XCTAssertEqual(file(folder(theirs) + "/Twos.kt", at: prepared.commit, in: prepared.clone), "package \(theirs)\n\nval step = 2\n")
        XCTAssertFalse(try git("git ls-tree -r --name-only \(prepared.commit)", in: prepared.clone).contains(ours.replacingOccurrences(of: ".", with: "/")))
    }

    /// What goes is the export's, which passed its checks for keys: a key in the version's capabilities.json, which the
    /// export writes again from only what it declares, never goes.
    func testAKeyTheExportLeavesOutNeverGoes() async throws {
        let key = "sk-or-v1-made-up-key-for-the-test-0123456789abcdef"
        let saved = Sharing.knownSecrets
        defer { Sharing.knownSecrets = saved }
        Sharing.knownSecrets = { _ in [key] }
        let repo = try repository(["Sources/App.swift": "a\n"])
        let (project, _) = try await remix(of: ["Sources/App.swift": "a\n"], commit: try git("git rev-parse HEAD", in: repo))
        try await change(project, [Template.Capabilities.file: #"{"background": true, "apiKey": "\#(key)"}"#, "Sources/App.swift": "A\n"], "Background")

        let prepared = try await prepare(project, from: repo)
        XCTAssertTrue(prepared.changed.contains(Template.Capabilities.file))
        let sent = try git("git grep -l \(Sandbox.quoted(key)) \(prepared.commit) || true", in: prepared.clone)
        XCTAssertEqual(sent, "", "the key is in what would be pushed")
        let capabilities = try XCTUnwrap(file(Template.Capabilities.file, at: prepared.commit, in: prepared.clone))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(capabilities.utf8)) as? NSDictionary, ["background": true])
        let unpacked = try sharedFile(of: prepared)
        XCTAssertFalse(try String(contentsOf: unpacked.appendingPathComponent(Template.Capabilities.file), encoding: .utf8).contains(key))
    }

    /// Work credited here after the remix arrived keeps its credit, though Lamp's running record of credits has it too.
    func testWorkCreditedHereKeepsItsCredit() async throws {
        let repo = try repository(["Sources/App.swift": "a\n"])
        let (project, _) = try await remix(of: ["Sources/App.swift": "a\n"], commit: try git("git rev-parse HEAD", in: repo))
        try write(["Sources/Tiny.swift": "// tiny\n"], in: project.dir)
        try Credits.add(Credits(upstream: [Credits.Source(name: "Tiny", author: "Someone", url: "https://github.com/someone/tiny", license: "MIT")]), to: project)
        let saved = await Versions.save(project, message: "Tiny")
        XCTAssertTrue(saved)

        let prepared = try await prepare(project, from: repo)
        XCTAssertEqual(prepared.changed, ["Sources/Tiny.swift", Credits.file, "drive.lampapp"])
        let credits = try XCTUnwrap(file(Credits.file, at: prepared.commit, in: prepared.clone).flatMap { Credits.decoded(Data($0.utf8)) })
        XCTAssertEqual(credits.upstream.map(\.name), ["Tiny"])
        XCTAssertEqual(credits.remixOf.map(\.name), ["Drive"], "the repository's chain stays its own")
    }

    /// A plain site's repository has its page at the root and Lamp's files in its folder: a change to the page goes
    /// there, not into a Web/ folder the repository doesn't have.
    func testAPlainSitesPageGoesToTheRepositorysRoot() async throws {
        let app = try escape.app()
        var project = app.project
        project.platform = .webApp
        try FileManager.default.removeItem(at: project.dir.appendingPathComponent("Sources/App.swift"))
        try ScreenKit.markSite(project)
        try write(["Web/index.html": "<html>hello</html>\n", "Web/style.css": "body {}\n", "APP.md": "# Drive\n", ".gitignore": ".lamp/\n",
                   AppDescription.file: #"{"description":"A drive"}"#], in: project.dir)
        let exported = try Sharing.export(project)
        defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }
        let repo = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-contribute-upstream-\(UUID().uuidString)")
        folders.append(repo)
        _ = try git("mkdir -p \(Sandbox.quoted(repo.path))/.lamp-wish && cd \(Sandbox.quoted(repo.path)) && git init -q -b main "
                    + "&& /usr/bin/unzip -q -p \(Sandbox.quoted(exported.path)) lamp-app.json > .lamp-wish/lamp-app.json", in: app.root)
        try write(["index.html": "<html>hello</html>\n", "style.css": "body {}\n", ".lamp-wish/APP.md": "# Drive\n",
                   ".lamp-wish/\(Credits.file)": #"{"remixOf":[{"name":"Drive","url":"https://github.com/maker/drive"}],"upstream":[]}"#], in: repo)
        let first = try git("git add -A && git -c user.name=Maker -c user.email=maker@example.com commit -qm First && git rev-parse HEAD", in: repo)
        try write([Credits.file: #"{"remixOf":[{"name":"Drive","url":"https://github.com/maker/drive","commit":"\#(first)"}],"upstream":[]}"#], in: project.dir)
        let arrived = await Versions.save(project, message: "Imported from a shared file")
        XCTAssertTrue(arrived)
        try await change(project, ["Web/index.html": "<html>hello, again</html>\n", "Web/about.html": "<html>about</html>\n"], "About")

        let prepared = try await prepare(project, from: repo)
        XCTAssertEqual(prepared.changed, ["about.html", "index.html"])
        XCTAssertEqual(file("index.html", at: prepared.commit, in: prepared.clone), "<html>hello, again</html>\n")
        XCTAssertFalse(try git("git ls-tree -r --name-only \(prepared.commit)", in: prepared.clone).contains("Web/"))
    }

    /// A plain site opened as it is has no folder of Lamp's in its repository: credit for work the remix adds still
    /// goes, in a folder made for it.
    func testCreditForAPlainSiteWithNoFolderOfLampsGoes() async throws {
        let app = try escape.app()
        var project = app.project
        project.platform = .webApp
        try FileManager.default.removeItem(at: project.dir.appendingPathComponent("Sources/App.swift"))
        try ScreenKit.markSite(project)
        try write(["Web/index.html": "<html>hello</html>\n", "APP.md": "# Site\n", ".gitignore": ".lamp/\n"], in: project.dir)
        let repo = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-contribute-upstream-\(UUID().uuidString)")
        folders.append(repo)
        try write(["index.html": "<html>hello</html>\n"], in: repo)
        let first = try git("git init -q -b main && git add -A && git -c user.name=Maker -c user.email=maker@example.com commit -qm First && git rev-parse HEAD", in: repo)
        try write([Credits.file: #"{"remixOf":[{"name":"Site","url":"https://github.com/maker/drive","commit":"\#(first)"}],"upstream":[]}"#], in: project.dir)
        let arrived = await Versions.save(project, message: "Imported from a shared file")
        XCTAssertTrue(arrived)
        try write(["Web/tiny.js": "// tiny\n"], in: project.dir)
        try Credits.add(Credits(upstream: [Credits.Source(name: "Tiny", author: "Someone", url: "https://github.com/someone/tiny", license: "MIT")]), to: project)
        let saved = await Versions.save(project, message: "Tiny")
        XCTAssertTrue(saved)

        let prepared = try await prepare(project, from: repo)
        XCTAssertEqual(prepared.changed, [StaticSite.folder + "/" + Credits.file, "tiny.js"])
        let credits = try XCTUnwrap(file(StaticSite.folder + "/" + Credits.file, at: prepared.commit, in: prepared.clone).flatMap { Credits.decoded(Data($0.utf8)) })
        XCTAssertEqual(credits.upstream.map(\.name), ["Tiny"])
    }
}
