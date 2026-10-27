import AppKit
import Foundation
import LampSidebarKit

/// Putting a wish on GitHub: its code as a repository on the person's own account, made with GitHub's command-line tool
/// (`gh`) and their sign-in there, as Publish puts a game's page up. Nothing goes through Lamp's servers.
///
/// What goes up is what a shared file carries (`Sharing.export`: the code, APP.md, the icon, the app's own files,
/// credits.json and the licenses it names; never the chat, the app's data or a key), unpacked so the code reads on
/// GitHub, with Lamp's own files beside it (build.sh, Package.swift, LampSupport.swift and the rest, so `./build.sh`
/// makes the app on any Mac with Apple's tools and no Lamp), the shared file itself (what Lamp opens today), a README
/// that says what it is, how to remix it with Lamp and what it's based on, and an MIT license when the person wants one.
/// The wish's own git history stays on the Mac: it holds every version and the chat's attachments, so each Put on
/// GitHub is one commit of the wish as it is now, on top of the last.
enum GitHubRepo {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// A repository that's up, and whether it carries the MIT license the person chose: an update keeps to that choice.
    /// Nil from a Lamp before the choice was kept, read as no license.
    struct Repo: Codable, Equatable {
        var repo: String   // "owner/name"
        var url: String
        var license: Bool? = nil
    }

    static func url(_ repo: String) -> String { "https://github.com/\(repo)" }

    // MARK: Where it went

    private static var keptURL: URL { Edition.supportFolder.appendingPathComponent("GitHub Repositories.json") }
    private static func key(_ project: LampProject) -> String { project.instance.isEmpty ? project.id : project.instance }

    static func kept(for project: LampProject) -> Repo? { readKept()[key(project)] }

    static func keep(_ repo: Repo, for project: LampProject) {
        var all = readKept()
        all[key(project)] = repo
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: keptURL, options: .atomic) }
    }

    private static func readKept() -> [String: Repo] {
        (try? Data(contentsOf: keptURL)).flatMap { try? JSONDecoder().decode([String: Repo].self, from: $0) } ?? [:]
    }

    // MARK: What goes up

    /// What will go up, staged in a folder of its own, checked.
    struct Staged {
        let folder: URL          // its parent is removed with it
        let files: Int
        let bytes: Int
        let credits: Credits
        /// Where the README's Remix it with Lamp goes.
        let open: Publish.OpenInLamp
    }

    /// Stages the repository for `repo`, its README's remix link going to `link` (the wish's Share Link, which works
    /// for someone without Lamp) when there is one: refused, with why, when the wish can't leave this Mac.
    static func stage(_ project: LampProject, repo: String, link: URL?) throws -> Staged {
        let fm = FileManager.default
        let credits = Credits.load(project)
        if let refusal = ShareCheck.refusal(of: project, credits: credits) { throw refusal }
        let work = Sharing.workFolder.appendingPathComponent("lamp-github-\(UUID().uuidString)")
        let tree = work.appendingPathComponent("repo")
        var done = false
        defer { if !done { try? fm.removeItem(at: work) } }
        try fm.createDirectory(at: tree, withIntermediateDirectories: true)

        // The wish as a shared file, held to the same checks and carrying the credits with this wish at the end of the
        // chain, and its contents unpacked beside it: the code as people read it on GitHub.
        let fileName = Publish.slug(project.name) + ".lampapp"
        let shared = try Sharing.export(project)
        defer { try? fm.removeItem(at: shared.deletingLastPathComponent()) }
        guard Subprocess.runBlocking("/usr/bin/ditto", ["-x", "-k", shared.path, tree.path], timeout: 120).ok else {
            throw Failure(message: "Couldn't unpack \(project.name)'s files.")
        }
        try fm.copyItem(at: shared, to: tree.appendingPathComponent(fileName))
        // Lamp's own files for each of the wish's apps, where the shared file put that app (`Sharing.layout`: one at the
        // root, the others in their folders), so the code builds as it is: the shared file leaves them out because
        // the Lamp that opens it writes its own.
        let (root, parts) = Sharing.layout(of: project)
        for (app, folder) in [(root, "")] + parts.map { ($0, $0.dir.lastPathComponent + "/") } {
            for path in ownedPaths(in: app) {
                let to = tree.appendingPathComponent(folder + path)
                guard !fm.fileExists(atPath: to.path) else { continue }
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: app.dir.appendingPathComponent(path), to: to)
            }
        }
        try Data(".build/\nbuild/\n.lamp/\n".utf8).write(to: tree.appendingPathComponent(".gitignore"))
        // The file's credits.json ends the chain with this wish, for whoever opens it; the README is this wish's own, so it
        // names what the wish was remixed from, not itself.
        let chain = Credits.read(tree.appendingPathComponent(Credits.file)) ?? credits
        let open = Publish.OpenInLamp(link: link, file: fileName)
        let build = Build(alone: root.platform.target.recipe.buildsAlone, app: root.platform.target.identity.name, others: !parts.isEmpty)
        try Data(readme(for: project, credits: credits, open: open, build: build).utf8).write(to: tree.appendingPathComponent("README.md"))

        let leaks = ShareCheck.secrets(in: tree, known: Sharing.knownSecrets(project))
        if let first = leaks.first {
            throw Sharing.ImportError("\(project.name) can't go on GitHub: it holds a key or a password.",
                                      detail: "It's in \(first). Ask Lamp to take it out and keep it out of the code.")
        }
        let all = fm.enumerator(at: tree, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { $0 as? URL } ?? []
        let bytes = all.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        // GitHub refuses a file over 100 MB and a repository is meant to stay well under 1 GB.
        guard bytes < 900_000_000 else { throw Failure(message: "\(project.name) is too big to put on GitHub.") }
        done = true
        return Staged(folder: tree, files: all.filter { !$0.hasDirectoryPath }.count, bytes: bytes, credits: chain, open: open)
    }

    /// The files in the wish's folder that are Lamp's (the ones the builder can't delete, `Store`'s list), by their
    /// paths in the wish: regular files only, never a link.
    static func ownedPaths(in project: LampProject) -> [String] {
        let fm = FileManager.default
        let skipped: Set<String> = [".lamp", ".git", ".build", "build", Attachments.folder]
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let items = fm.enumerator(at: project.dir, includingPropertiesForKeys: keys) else { return [] }
        var paths: [String] = []
        for case let file as URL in items {
            let relative = Sharing.relativePath(of: file, in: project.dir)
            if skipped.contains(file.lastPathComponent), file.deletingLastPathComponent().standardizedFileURL == project.dir.standardizedFileURL {
                items.skipDescendants()
                continue
            }
            let values = try? file.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true, values?.isSymbolicLink != true, isOwned(relative, in: project) else { continue }
            paths.append(relative)
        }
        return paths.sorted()
    }

    /// Whether a file at `relative` is one Lamp writes into every app of its kind.
    static func isOwned(_ relative: String, in project: LampProject) -> Bool {
        let owned = ["Package.swift", "build.sh", "Sources/LampSupport.swift", Template.sceneSupportPath,
                     Template.widgetFolder + "/" + Template.widgetSupportFile, Template.shareFolder + "/" + Template.shareSupportFile] + Template.watchSupportPaths
        let lowered = relative.lowercased()
        if owned.contains(where: { lowered == $0.lowercased() }) { return true }
        if project.platform.target.recipe.language == .kotlin, Template.isAndroidSupport(relative) { return true }
        return DeviceSupport.isSupport(relative, in: project)
    }

    /// What the README can say about building the repository: whether the app at its root builds with its own script
    /// and Apple's tools alone (`Recipe.buildsAlone`), what that app is, and whether the wish has other apps, which Lamp builds.
    struct Build {
        var alone: Bool
        var app: String
        var others: Bool
    }

    /// The repository's README: what the wish is, how to remix it with Lamp, how to build it, and what it's based on.
    static func readme(for project: LampProject, credits: Credits, open: Publish.OpenInLamp, build: Build) -> String {
        var text = "# \(project.name)\n\n"
        if let line = AppDescription.description(of: project) { text += line + "\n\n" }
        text += "Made with [Lamp](https://lamp.dev), a Mac app that builds apps from a description and changes them as you ask.\n\n"
        text += "## Remix it with Lamp\n\n"
        if let link = open.link {
            text += "[Make your own](\(link.absoluteString)) from this wish: with Lamp, or by getting Lamp from that page. "
        }
        if let file = open.file {
            text += (open.link == nil ? "Download" : "Or download") + " [\(file)](\(file)) and open it with Lamp (double-click it, or File → Import Shared Wish…): "
                + "you get this exact wish, yours to change by asking, with the credits below kept. The code here is what that file holds."
            if open.link == nil { text += " Don't have Lamp? [Get it](https://lamp.dev)." }
        }
        if build.alone {
            text += "\n\n## Build it yourself\n\n"
            text += "With Apple's Command Line Tools installed (`xcode-select --install`):\n\n```bash\n./build.sh\n```\n\n"
            if build.others { text += "That builds \(build.app); the wish's other apps, in their folders, are built by Lamp.\n\n" }
            text += "The AI inside the app, and anything it does with other apps or devices, goes through Lamp, so those need Lamp open on the same Mac.\n\n"
        } else {
            text += "\n\n## Building it\n\nLamp builds this kind of app: it needs Xcode and signing on your Mac, which Lamp sets up. Open it in Lamp, above.\n\n"
        }
        text += Publish.creditsSection(credits)
        return text
    }

    /// The MIT license, in the person's name.
    static func mitLicense(holder: String) -> String {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        return """
        MIT License

        Copyright (c) \(year) \(holder)

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.

        """
    }

    /// An MIT license can be offered: nothing the wish is based on asks that a remix stay under its own license.
    static func canOfferLicense(_ credits: Credits) -> Bool {
        !credits.upstream.contains { ShareCheck.licence($0.license) == .shareAlike && !ShareCheck.isDataLicence($0.license) }
    }

    // MARK: Putting it up

    /// Puts the staged tree in `repo` (made, if it's new, public or private as asked) as one commit on top of what's
    /// there; `step` hears what it's doing. `changed` is false when the repository already had the wish as it is.
    static func upload(_ staged: Staged, of project: LampProject, to repo: String, gh: String, login: String, isNew: Bool,
                       isPrivate: Bool, license: Bool, step: @escaping @Sendable (String) -> Void) async throws -> (repo: Repo, changed: Bool) {
        let fm = FileManager.default
        let url = url(repo)
        let tree = staged.folder
        let licenseFile = tree.appendingPathComponent("LICENSE")
        if license, !fm.fileExists(atPath: licenseFile.path) {
            try Data(mitLicense(holder: login).utf8).write(to: licenseFile)
        }
        if isNew {
            step("Making \(repo)…")
            let made = await Subprocess.run(gh, ["repo", "create", repo, isPrivate ? "--private" : "--public",
                                                 "--description", AppDescription.description(of: project) ?? "\(project.name), made with Lamp"],
                                            timeout: 60)
            guard made.ok else { throw Failure(message: "GitHub didn't make \(repo): \(made.output.trimmed.suffix(200))") }
            // Kept as soon as it's made, so a try that fails after this goes on with the same repository rather than
            // leaving this one behind and making another.
            keep(Repo(repo: repo, url: url, license: license), for: project)
        }
        let git = fm.isExecutableFile(atPath: "/opt/homebrew/bin/git") ? "/opt/homebrew/bin/git" : "/usr/bin/git"
        let identity = ["-c", "user.name=\(login)", "-c", "user.email=\(login)@users.noreply.github.com"]
        // Signed in through gh, for these commands alone: nothing is kept in a git configuration.
        let signedIn = ["-c", "credential.helper=", "-c", "credential.helper=!\(gh) auth git-credential"]
        let remote = "https://github.com/\(repo).git"

        let work: URL
        if isNew {
            step("Preparing…")
            // A try after a failed one finds the tree committed already, and pushes that commit again.
            var committed = false
            if fm.fileExists(atPath: tree.appendingPathComponent(".git").path) {
                committed = await Subprocess.run(git, ["rev-parse", "--verify", "-q", "HEAD"], cwd: tree, timeout: 10).ok
            }
            for arguments in committed ? [] : [["init", "-q", "-b", "main"], ["add", "-A"], identity + ["commit", "-q", "-m", "\(project.name), from Lamp"]] {
                let ran = await Subprocess.run(git, arguments, cwd: tree, timeout: 120)
                guard ran.ok else { throw Failure(message: "Couldn't prepare the repository: \(ran.output.trimmed.suffix(200))") }
            }
            work = tree
        } else {
            // What's up already, with the wish as it is now in its place: one commit of the difference.
            step("Reading what's on GitHub…")
            let clone = tree.deletingLastPathComponent().appendingPathComponent("clone")
            try? fm.removeItem(at: clone)
            let cloned = await Subprocess.run(git, signedIn + ["clone", "-q", "--depth", "1", remote, clone.path], timeout: 600)
            guard cloned.ok else { throw Failure(message: "GitHub didn't give back \(repo): \(cloned.output.trimmed.suffix(200))") }
            for item in try fm.contentsOfDirectory(at: clone, includingPropertiesForKeys: nil) where item.lastPathComponent != ".git" {
                try fm.removeItem(at: item)
            }
            for item in try fm.contentsOfDirectory(at: tree, includingPropertiesForKeys: nil) where item.lastPathComponent != ".git" {
                try fm.copyItem(at: item, to: clone.appendingPathComponent(item.lastPathComponent))
            }
            let added = await Subprocess.run(git, ["add", "-A"], cwd: clone, timeout: 120)
            guard added.ok else { throw Failure(message: "Couldn't prepare the repository: \(added.output.trimmed.suffix(200))") }
            // Unchanged when nothing but the export's own marks differ: the shared file's manifest says when it was made,
            // and the file is zipped afresh each time. Those go up only with a real change.
            if await Subprocess.run(git, ["diff", "--cached", "--quiet", "--", ".", ":(exclude)lamp-app.json", ":(exclude)*.lampapp"], cwd: clone, timeout: 60).ok {
                return (Repo(repo: repo, url: url, license: license), false)
            }
            let committed = await Subprocess.run(git, identity + ["commit", "-q", "-m", "Update \(project.name) from Lamp"], cwd: clone, timeout: 120)
            guard committed.ok else { throw Failure(message: "Couldn't prepare the repository: \(committed.output.trimmed.suffix(200))") }
            work = clone
        }
        step("Uploading…")
        let pushed = await Subprocess.run(git, signedIn + ["push", "-q", remote, "HEAD:main"], cwd: work, timeout: 600)
        guard pushed.ok else { throw Failure(message: "GitHub didn't take it: \(pushed.output.trimmed.suffix(200))") }
        return (Repo(repo: repo, url: url, license: license), true)
    }
}

/// The Put on GitHub card of each wish while it's open, in the chat's place. Preparing it finds `gh` and the person's
/// sign-in and stages the repository with its checks, so the card shows exactly what will go up before the person
/// confirms.
@MainActor final class GitHubRepoCards: ObservableObject {
    static let shared = GitHubRepoCards()

    struct Card {
        var stage: RepoCard.Stage = .preparing
        var repo: String?
        var login: String?
        var gh: String?
        var staged: GitHubRepo.Staged?
        var kept: GitHubRepo.Repo?
        var copied = false
        var icon: Data?
        /// The choices made before it goes up the first time. Once it's up, `license` is the repository's (`Repo.license`):
        /// an update never adds a license the person left out, nor takes away one they chose.
        var isPrivate = false
        var license = true

        /// Ready, or failed with the tree still staged, so Put on GitHub tries again.
        var canPut: Bool {
            switch stage {
            case .ready: true
            case .failed: staged != nil
            default: false
            }
        }
    }

    @Published private(set) var cards: [String: Card] = [:]

    func card(for project: LampProject) -> Card? { cards[project.id] }

    func open(_ project: LampProject) {
        guard cards[project.id] == nil else { return }
        let kept = GitHubRepo.kept(for: project)
        cards[project.id] = Card(kept: kept, license: kept.map { $0.license ?? false } ?? true)
        Task { cards[project.id]?.icon = await Sharing.sharedIcon(of: project) }
        prepare(project)
    }

    /// Finds gh and the sign-in, and stages what will go up.
    func prepare(_ project: LampProject) {
        guard cards[project.id] != nil else { return }
        cards[project.id]?.stage = .preparing
        if let old = cards[project.id]?.staged { try? FileManager.default.removeItem(at: old.folder.deletingLastPathComponent()) }
        cards[project.id]?.staged = nil
        Task {
            guard let gh = await Publish.gh() else { return set(project, .needsGitHub(.install)) }
            guard let login = await Publish.login(gh: gh) else { return set(project, .needsGitHub(.signIn)) }
            let repo: String
            if let known = GitHubRepo.kept(for: project)?.repo { repo = known } else { repo = await Publish.freeName(for: project, login: login, gh: gh) }
            do {
                let staged = try await Task.detached(priority: .userInitiated) { try GitHubRepo.stage(project, repo: repo, link: WishLink.kept(for: project)?.url) }.value
                guard cards[project.id] != nil else {
                    try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent())
                    return
                }
                cards[project.id]?.gh = gh
                cards[project.id]?.login = login
                cards[project.id]?.repo = repo
                cards[project.id]?.staged = staged
                if cards[project.id]?.kept == nil, !GitHubRepo.canOfferLicense(staged.credits) { cards[project.id]?.license = false }
                cards[project.id]?.stage = .ready
            } catch {
                set(project, .refused(((error as? LocalizedError)?.recoverySuggestion).map { "\(error.localizedDescription) \($0)" } ?? error.localizedDescription))
            }
        }
    }

    private func set(_ project: LampProject, _ stage: RepoCard.Stage) { cards[project.id]?.stage = stage }

    func setPrivate(_ project: LampProject, _ isPrivate: Bool) { cards[project.id]?.isPrivate = isPrivate }
    func setLicense(_ project: LampProject, _ license: Bool) { cards[project.id]?.license = license }

    func put(_ project: LampProject) {
        guard let card = cards[project.id], card.canPut, let staged = card.staged, let repo = card.repo,
              let gh = card.gh, let login = card.login else { return }
        // A first try that made the repository before failing kept it (`upload`): this goes on with it.
        let isNew = (card.kept ?? GitHubRepo.kept(for: project))?.repo != repo
        set(project, .working("Starting…"))
        Task {
            do {
                let id = project.id
                let (kept, changed) = try await GitHubRepo.upload(staged, of: project, to: repo, gh: gh, login: login, isNew: isNew,
                                                                  isPrivate: card.isPrivate, license: card.license) { step in
                    Task { @MainActor in GitHubRepoCards.shared.cards[id]?.stage = .working(step) }
                }
                GitHubRepo.keep(kept, for: project)
                try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent())
                cards[project.id]?.staged = nil
                cards[project.id]?.kept = kept
                set(project, .done(unchanged: !changed))
            } catch {
                // The tree stays staged, so Put on GitHub can try again; a repository made on the way is kept (`upload`).
                cards[project.id]?.kept = GitHubRepo.kept(for: project) ?? cards[project.id]?.kept
                set(project, .failed(error.localizedDescription))
            }
        }
    }

    func fix(_ project: LampProject) {
        guard case .needsGitHub(let need) = cards[project.id]?.stage else { return }
        Publish.obtain(need, stillNeeded: { [weak self] in
            if case .needsGitHub = self?.cards[project.id]?.stage { return true } else { return false }
        }, signedIn: { [weak self] in self?.prepare(project) })
    }

    /// Share Link's card in this card's place, for the person to see and change what the link shows before it's made:
    /// Put on GitHub never sends the wish's words or picture itself. This card is opened again once the link is out.
    func makeLink(_ project: LampProject) {
        close(project)
        WishLinkCards.shared.open(project, inSidebar: true)
    }

    func openRepo(_ project: LampProject) {
        if let url = cards[project.id]?.kept?.url ?? GitHubRepo.kept(for: project)?.url, let page = URL(string: url) { NSWorkspace.shared.open(page) }
    }

    func copy(_ project: LampProject) {
        guard let url = cards[project.id]?.kept?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        cards[project.id]?.copied = true
    }

    func close(_ project: LampProject) {
        if let staged = cards[project.id]?.staged { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        cards[project.id] = nil
    }

    /// The card as the chat draws it.
    func wire(_ card: Card, of project: LampProject) -> SidebarRepo {
        let credits = card.staged?.credits ?? Credits.load(project)
        var notes = ShareCheck.notes(for: credits)
        if !credits.generated.isEmpty { notes.append(Credits.generatedLine(credits.generated.count) + ", marked as such.") }
        let size = card.staged.map { "\($0.files) files · " + ByteCountFormatter.string(fromByteCount: Int64($0.bytes), countStyle: .file) }
        let link = card.staged?.open.link ?? WishLink.kept(for: project)?.url
        return SidebarRepo(name: project.name, icon: card.icon, stage: card.stage, repo: card.repo, url: card.kept?.url,
                           credit: credits.basedOn, openInLamp: link.map { url in url.host.map { $0 + url.path } ?? url.absoluteString }, notes: notes, size: size, copied: card.copied,
                           update: card.kept != nil, canPut: card.canPut, isPrivate: card.isPrivate, license: card.license,
                           canChooseLicense: card.staged.map { GitHubRepo.canOfferLicense($0.credits) } ?? true)
    }
}
