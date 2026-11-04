import XCTest
@testable import Lamp

/// Who the commits Lamp puts on GitHub are made as: someone whose git signs gets commits signed by their key under their
/// own address, which GitHub can verify (a signed commit under the GitHub private address it can't: "bad_email");
/// everyone else gets the private address, unsigned. A signature that fails stops the commit rather than dropping it.
final class CommitAuthorTests: XCTestCase {
    private var root: URL!
    private let git = "/usr/bin/git"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-author-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// A repository with one staged file and its own settings, which win over the Mac's.
    private func repository(_ settings: [(String, String)]) throws -> URL {
        let folder = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertTrue(Subprocess.runBlocking(git, ["init", "-q", "-b", "main"], cwd: folder, timeout: 30).ok)
        for (key, value) in settings {
            XCTAssertTrue(Subprocess.runBlocking(git, ["config", key, value], cwd: folder, timeout: 30).ok)
        }
        try Data("hello\n".utf8).write(to: folder.appendingPathComponent("a.txt"))
        XCTAssertTrue(Subprocess.runBlocking(git, ["add", "-A"], cwd: folder, timeout: 30).ok)
        return folder
    }

    /// Signing as someone does with an SSH key of their own.
    private func signing(program: String? = nil) throws -> [(String, String)] {
        let key = root.appendingPathComponent("key")
        XCTAssertTrue(Subprocess.runBlocking("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-f", key.path], timeout: 30).ok)
        return [("commit.gpgSign", "true"), ("gpg.format", "ssh"), ("user.signingKey", key.path + ".pub"),
                ("user.name", "Signer"), ("user.email", "signer@example.com")] + (program.map { [("gpg.ssh.program", $0)] } ?? [])
    }

    private func show(_ format: String, _ commit: String, in folder: URL) -> String {
        Subprocess.runBlocking(git, ["show", "-s", "--format=" + format, commit], cwd: folder, mergeErrors: false, timeout: 30).output.trimmed
    }

    private func signed(_ commit: String, in folder: URL) -> Bool {
        Subprocess.runBlocking(git, ["cat-file", "commit", commit], cwd: folder, mergeErrors: false, timeout: 30).output.contains("\ngpgsig")
    }

    func testSomeoneWhoSignsCommitsAsThemselvesWithTheirKey() async throws {
        let folder = try repository(try signing())
        let author = try await GitHubRepo.author(login: "someone", git: git, in: folder)
        XCTAssertTrue(author.signs)
        XCTAssertEqual(author.email, "signer@example.com")
        XCTAssertEqual(author.note, "Your git signs your commits, so they go as you sign them, showing signer@example.com on GitHub.")
        let commit = try await GitHubRepo.commit(["commit", "-q", "-m", "Up"], as: author, shown: author, git: git, in: folder)
        XCTAssertEqual(show("%ae %ce", commit, in: folder), "signer@example.com signer@example.com")
        XCTAssertTrue(signed(commit, in: folder))
    }

    /// commit-tree, what a page goes up with, signs only when asked.
    func testAPageCommitIsSignedToo() async throws {
        let folder = try repository(try signing())
        let tree = Subprocess.runBlocking(git, ["write-tree"], cwd: folder, mergeErrors: false, timeout: 30).output.trimmed
        let author = try await GitHubRepo.author(login: "someone", git: git, in: folder)
        let commit = try await GitHubRepo.commit(["commit-tree", tree, "-m", "Page"], as: author, shown: nil, git: git, in: folder)
        XCTAssertTrue(signed(commit, in: folder))
        XCTAssertEqual(show("%ae", commit, in: folder), "signer@example.com")
    }

    func testSomeoneWhoDoesntSignCommitsUnderTheirPrivateAddress() async throws {
        let folder = try repository([("commit.gpgSign", "false"), ("user.email", "personal@example.com")])
        let author = try await GitHubRepo.author(login: "someone", git: git, in: folder)
        XCTAssertFalse(author.signs)
        XCTAssertNil(author.note)
        let commit = try await GitHubRepo.commit(["commit", "-q", "-m", "Up"], as: author, shown: author, git: git, in: folder)
        XCTAssertEqual(show("%an %ae", commit, in: folder), "someone someone@users.noreply.github.com")
        XCTAssertFalse(signed(commit, in: folder))
    }

    func testASignatureThatFailsStopsTheCommit() async throws {
        let folder = try repository(try signing(program: "/usr/bin/false"))
        let author = try await GitHubRepo.author(login: "someone", git: git, in: folder)
        do {
            _ = try await GitHubRepo.commit(["commit", "-q", "-m", "Up"], as: author, shown: author, git: git, in: folder)
            XCTFail("An unsigned commit was made")
        } catch {
            XCTAssertTrue(error.localizedDescription.hasPrefix("Your git signs your commits and couldn't sign this one"), error.localizedDescription)
        }
        XCTAssertFalse(Subprocess.runBlocking(git, ["rev-parse", "--verify", "-q", "HEAD"], cwd: folder, timeout: 30).ok)
    }

    /// An address the card didn't show never goes out: the card said the private one, and git now says another.
    func testAnAddressTheCardDidntShowStopsTheCommit() async throws {
        let folder = try repository(try signing())
        let author = try await GitHubRepo.author(login: "someone", git: git, in: folder)
        let shown = GitHubRepo.Author(signs: false, email: "someone@users.noreply.github.com", options: [])
        do {
            _ = try await GitHubRepo.commit(["commit", "-q", "-m", "Up"], as: author, shown: shown, git: git, in: folder)
            XCTFail("A commit under an address the card didn't show was made")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("signer@example.com"), error.localizedDescription)
        }
        XCTAssertFalse(Subprocess.runBlocking(git, ["rev-parse", "--verify", "-q", "HEAD"], cwd: folder, timeout: 30).ok)
    }
}
