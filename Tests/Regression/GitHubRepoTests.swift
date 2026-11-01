import XCTest
@testable import Lamp

/// What goes on GitHub: the shared wish unpacked, with what builds it, the shared file, a README and never Lamp's
/// own records or a key. And what comes back: the tree opens in Lamp as the file does, its credits naming the repository.
final class GitHubRepoTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-github-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// A web game's page plays in any browser: the page as the app plays it, with what lamp-game.js needs beside it and
    /// Lamp's license, linked from the README by Play in your browser.
    func testAWebGamesPageHasWhatItNeedsToPlay() throws {
        let dir = root.appendingPathComponent("Hopper")
        let web = dir.appendingPathComponent(GameKit.webFolder)
        try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
        try "A game made with Lamp.\nengine: web\n".write(to: dir.appendingPathComponent(GameKit.marker), atomically: true, encoding: .utf8)
        try "<html><body><script type=module src=game.js></script></body></html>".write(to: web.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "import device from './lamp-device.js';".write(to: web.appendingPathComponent(GamePage.runtimeFile), atomically: true, encoding: .utf8)
        let game = LampProject(id: "hopper", name: "Hopper", exe: "Hopper", dir: dir, platform: .game)
        XCTAssertTrue(Publish.hasPage(game))
        let site = root.appendingPathComponent("page")
        let html = try Publish.copyPage(of: game, into: site)
        XCTAssertTrue(html.contains("game.js"))
        for path in [GamePage.deviceFile, GamePage.buildFile, Publish.runtimeLicense, ".nojekyll"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: site.appendingPathComponent(path).path), path)
        }
        let readme = GitHubRepo.readme(for: game, credits: Credits(), open: Publish.OpenInLamp(), build: GitHubRepo.Build(alone: false, app: "Game", others: false),
                                       repo: "someone/hopper", showcase: GitHubRepo.Showcase(play: Publish.pageURL("someone/hopper"), remix: true))
        XCTAssertTrue(readme.contains("<a href=\"https://someone.github.io/hopper/\"><img src=\"\(GitHubRepo.playButton)\""), readme)
    }

    func testTheStagedRepositoryBuildsOnItsOwnAndOpensInLamp() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        try Template.writeOwnedFiles(for: wish)
        let staged = try GitHubRepo.stage(wish, repo: "someone/tally", link: URL(string: "https://lamp.dev/w/AyTkit4xCc"))
        defer { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        let fm = FileManager.default
        func has(_ path: String) -> Bool { fm.fileExists(atPath: staged.folder.appendingPathComponent(path).path) }

        // The code and what builds it, so `zsh build.sh` works with no Lamp.
        for path in ["Sources/App.swift", "Sources/LampSupport.swift", "Package.swift", "build.sh", "APP.md", "lamp-app.json", Credits.file, ".gitignore"] {
            XCTAssertTrue(has(path), path)
        }
        // The shared file beside it. A public repository's README offers it on Lamp's site, by its Open in Lamp button, and
        // a private one's (which Lamp can't fetch without a sign-in) by the Share Link and the file.
        XCTAssertTrue(has("tally.lampapp"))
        XCTAssertTrue(has(GitHubRepo.openButton))
        let readme = try String(contentsOf: staged.folder.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(readme.contains("<a href=\"https://lamp.dev/?repo=https://github.com/someone/tally&amp;from=readme\"><img src=\"\(GitHubRepo.openButton)\""), readme)
        XCTAssertFalse(readme.contains("https://lamp.dev/w/AyTkit4xCc"))
        XCTAssertEqual(staged.remix, "https://lamp.dev/?repo=https://github.com/someone/tally&from=readme", "the card names what the README offers")
        XCTAssertTrue(readme.contains("zsh build.sh"))
        let closed = try GitHubRepo.stage(wish, repo: "someone/tally", link: URL(string: "https://lamp.dev/w/AyTkit4xCc"), isPublic: false)
        defer { try? FileManager.default.removeItem(at: closed.folder.deletingLastPathComponent()) }
        let closedReadme = try String(contentsOf: closed.folder.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(closedReadme.contains("https://lamp.dev/w/AyTkit4xCc"))
        XCTAssertTrue(closedReadme.contains("[tally.lampapp](tally.lampapp)"))
        XCTAssertFalse(closedReadme.contains("lamp.dev/?repo="))
        XCTAssertNil(closed.remix)
        XCTAssertFalse(fm.fileExists(atPath: closed.folder.appendingPathComponent(GitHubRepo.openButton).path))
        // Each idea is a remix with its request, its words kept from ending the link.
        let ideas = GitHubRepo.readme(for: wish, credits: Credits(), open: Publish.OpenInLamp(), build: GitHubRepo.Build(alone: true, app: "Mac", others: false),
                                      repo: "someone/tally", showcase: GitHubRepo.Showcase(ideas: ["Count [by] twos (fast)"], remix: true))
        XCTAssertTrue(ideas.contains("- [Count \\[by\\] twos (fast)](https://lamp.dev/?repo=https://github.com/someone/tally&from=readme&ask=Count%20%5Bby%5D%20twos%20%28fast%29)"), ideas)
        // A reel takes the preview's place: its silent loop, linked to the video with sound.
        let reel = GitHubRepo.readme(for: wish, credits: Credits(), open: Publish.OpenInLamp(), build: GitHubRepo.Build(alone: true, app: "Mac", others: false),
                                     repo: "someone/tally", showcase: GitHubRepo.Showcase(preview: ".github/preview.png", reel: ".github/showcase", remix: true))
        XCTAssertTrue(reel.contains("<a href=\".github/showcase/reel.mp4\"><img src=\".github/showcase/loop.webp\""), reel)
        XCTAssertFalse(reel.contains("preview.png"), reel)
        // Nothing of Lamp's records.
        XCTAssertFalse(has(".lamp"))
        XCTAssertFalse(has(".git"))
        XCTAssertEqual(staged.open.link?.absoluteString, "https://lamp.dev/w/AyTkit4xCc")
        XCTAssertTrue(readme.contains("https://github.com/someone/tally"))

        // The tree opens as the shared file does: only the sender's code is read (Lamp's own file beside it isn't), and
        // the chain ends with this wish, named where it lives and at the commit the tree is at, which an update is
        // merged from.
        let made = TestShell.run("git init -q && git remote add origin https://github.com/someone/tally.git && git add -A "
                                 + "&& git -c user.name=t -c user.email=t@localhost commit -qm one && git rev-parse HEAD", in: staged.folder)
        XCTAssertEqual(made.status, 0, made.output)
        let package = try Sharing.open(staged.folder)
        defer { try? fm.removeItem(at: package.folder) }
        XCTAssertEqual(package.name, "Tally")
        XCTAssertTrue(package.sources.contains { $0.lastPathComponent == "App.swift" })
        XCTAssertFalse(package.sources.contains { $0.lastPathComponent == "LampSupport.swift" })
        XCTAssertEqual(package.credits?.remixOf.last?.url, "https://github.com/someone/tally")
        XCTAssertEqual(package.credits?.remixOf.last?.commit, made.output.trimmed)
        XCTAssertFalse(fm.fileExists(atPath: package.folder.appendingPathComponent("tally.lampapp").path))
        // The file inside says the same.
        let file = try Sharing.open(staged.folder.appendingPathComponent("tally.lampapp"))
        defer { try? fm.removeItem(at: file.folder) }
        XCTAssertEqual(file.credits?.remixOf.last?.url, "https://github.com/someone/tally")
        // Opened here as the same wish and shared on as a file, it still says where it lives; put on another repository,
        // it gets a link for that place after the one it came from, which stays the origin an update is merged from
        // and a change goes back to.
        let link = Credits.Remix(name: "Tally", wish: file.credits?.remixOf.last?.wish)
        XCTAssertEqual(file.credits?.remixed(from: link).remixOf.last?.url, "https://github.com/someone/tally")
        var moved = link
        moved.url = "https://github.com/else/tally"
        let chain = try XCTUnwrap(file.credits?.remixed(from: moved))
        XCTAssertEqual(chain.remixOf.map(\.url), ["https://github.com/someone/tally", "https://github.com/else/tally"])
        XCTAssertEqual(chain.origin(own: "https://github.com/else/tally")?.url, "https://github.com/someone/tally")
        XCTAssertEqual(chain.remixed(from: moved).remixOf.count, 2, "put there again, it stays one link")
        // The origin's commit moves on with what's merged in, and the file's older word doesn't take it back.
        var fetched = chain
        fetched.remixOf[0].commit = "199f010cf9b35eb58ec934d95eba1ab977c880c1"
        XCTAssertEqual(chain.merged(with: fetched).remixOf.first?.commit, "199f010cf9b35eb58ec934d95eba1ab977c880c1")
        XCTAssertEqual(chain.merged(with: fetched).remixOf.count, 2)
    }

    func testARepositoryAddressIsReadAsGitTakesIt() {
        XCTAssertEqual(RepoImport.source(from: "https://github.com/someone/tally"), RepoImport.Source(owner: "someone", name: "tally"))
        XCTAssertEqual(RepoImport.source(from: " github.com/someone/tally.git/ "), RepoImport.Source(owner: "someone", name: "tally"))
        XCTAssertEqual(RepoImport.source(from: "git@github.com:someone/tally.git"), RepoImport.Source(owner: "someone", name: "tally"))
        XCTAssertEqual(RepoImport.source(from: "ssh://git@github.com/someone/tally.git"), RepoImport.Source(owner: "someone", name: "tally"))
        XCTAssertEqual(RepoImport.source(from: "https://github.com/someone/tally/tree/feature/x")?.ref, "feature/x")
        XCTAssertEqual(RepoImport.source(from: "https://github.com/someone/tally/commit/199f010cf9b35eb58ec934d95eba1ab977c880c1")?.ref,
                       "199f010cf9b35eb58ec934d95eba1ab977c880c1")
        for bad in ["https://example.com/someone/tally", "https://github.com/someone", "https://github.com/someone/tally/tree/--upload-pack=x",
                    "https://github.com/someone/tally/tree/../x", "https://github.com/someone/tally/blob/main/README.md", "not an address"] {
            XCTAssertNil(RepoImport.source(from: bad), bad)
        }
    }

    func testAShareAlikeUpstreamLeavesNoLicenseToChoose() {
        var credits = Credits()
        XCTAssertTrue(GitHubRepo.canOfferLicense(credits))
        credits.upstream = [Credits.Source(name: "Engine", license: "GPL-3.0-or-later")]
        XCTAssertFalse(GitHubRepo.canOfferLicense(credits))
        credits.upstream = [Credits.Source(name: "Map", license: "ODbL-1.0")]
        XCTAssertTrue(GitHubRepo.canOfferLicense(credits), "data under its own share-alike licence stays credited, the code can still be MIT")
        XCTAssertTrue(GitHubRepo.mitLicense(holder: "someone").contains("Copyright (c)"))
    }

    /// Unticking the license after GitHub refused to make the repository: the retry leaves it out.
    func testAnUntickedLicenseStaysOutWhenARefusedRepositoryIsTriedAgain() async throws {
        let pushed = try await retryAfterARefusal(firstLicense: true, retryLicense: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pushed.appendingPathComponent("LICENSE").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pushed.appendingPathComponent("README.md").path), "the wish did go up")
    }

    func testALicenseLeftTickedGoesUpWhenARefusedRepositoryIsTriedAgain() async throws {
        let pushed = try await retryAfterARefusal(firstLicense: true, retryLicense: true)
        let license = try String(contentsOf: pushed.appendingPathComponent("LICENSE"), encoding: .utf8)
        XCTAssertTrue(license.hasPrefix("MIT License"), license)
    }

    /// The wish's own license is the person's, whichever way the box goes.
    func testTheWishsOwnLicenseStaysWhenARefusedRepositoryIsTriedAgain() async throws {
        for retryLicense in [false, true] {
            let pushed = try await retryAfterARefusal(firstLicense: true, retryLicense: retryLicense, own: "Apache License\n")
            XCTAssertEqual(try String(contentsOf: pushed.appendingPathComponent("LICENSE"), encoding: .utf8), "Apache License\n")
        }
    }

    /// Puts a wish on GitHub through a stand-in `gh` that refuses to make the repository the first time, then again with
    /// the choice made on the card, and returns a checkout of what reached the repository (a bare one here, by git's
    /// own address rewriting). The second try is the card's: a new repository, since nothing was made or kept.
    private func retryAfterARefusal(firstLicense: Bool, retryLicense: Bool, own: String? = nil) async throws -> URL {
        let fm = FileManager.default
        let place = root.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: place, withIntermediateDirectories: true)
        let bare = place.appendingPathComponent("tally.git")
        XCTAssertEqual(TestShell.run("git init -q --bare -b main \(Sandbox.quoted(bare.path))").status, 0)
        let gh = place.appendingPathComponent("gh")
        try """
        #!/bin/zsh
        if [[ "$1 $2" == "repo create" ]]; then
          [[ -e "$0.refused" ]] && exit 0
          touch "$0.refused"
          echo "HTTP 422: refused" >&2
          exit 1
        fi
        [[ "$1 $2" == "repo view" ]] && echo PRIVATE
        exit 0
        """.write(to: gh, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gh.path)

        // Git reads this process's surroundings: the push lands in the bare repository, with none of this Mac's settings.
        let surroundings = ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_COUNT": "1",
                            "GIT_CONFIG_KEY_0": "url.\(bare.absoluteString).insteadOf",
                            "GIT_CONFIG_VALUE_0": "https://github.com/someone/tally.git"]
        for (name, value) in surroundings { setenv(name, value, 1) }
        let keptURL = GitHubRepo.keptURL
        GitHubRepo.keptURL = place.appendingPathComponent("kept.json")
        defer {
            for name in surroundings.keys { unsetenv(name) }
            GitHubRepo.keptURL = keptURL
        }

        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: place)
        try Template.writeOwnedFiles(for: wish)
        let staged = try GitHubRepo.stage(wish, repo: "someone/tally", link: nil, isPublic: false)
        defer { try? fm.removeItem(at: staged.folder.deletingLastPathComponent()) }
        if let own { try own.write(to: staged.folder.appendingPathComponent("LICENSE"), atomically: true, encoding: .utf8) }
        func put(license: Bool) async throws {
            _ = try await GitHubRepo.upload(staged, of: wish, to: "someone/tally", gh: gh.path, login: "someone", isNew: true,
                                            isPrivate: true, license: license) { _ in }
        }
        do {
            try await put(license: firstLicense)
            XCTFail("the first try was to be refused")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("refused"), error.localizedDescription)
        }
        try await put(license: retryLicense)

        let pushed = place.appendingPathComponent("pushed")
        let cloned = TestShell.run("git clone -q \(Sandbox.quoted(bare.path)) \(Sandbox.quoted(pushed.path))")
        XCTAssertEqual(cloned.status, 0, cloned.output)
        return pushed
    }
}
