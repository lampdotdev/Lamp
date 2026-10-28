import CryptoKit
import Foundation
import LampSidebarKit

/// Lamp's starters as repositories on GitHub (`Starters.account`, one each): each starter made into a wish the way the
/// desk makes one and laid out as Put on GitHub lays a wish out (`GitHubRepo.stage`: the shared file's contents with
/// its checks, Lamp's own files so `./build.sh` builds it, a README, an MIT license), so it opens with File → Open from
/// GitHub…, and a copy on someone's desk takes the latest of it (Update from GitHub…) and sends changes back to it
/// (Send Changes Back…). `scripts/publish-starters.sh` runs this, puts each tree up and writes the address and commit
/// into the starter's starter.md, which every copy made from then on carries on its chain (`Starters.copy`).
///
/// The tree is the same every time for the same starter, so a starter that didn't change makes no new commit: its
/// identity is derived from the starter (never a random one), its export time is fixed, and the shared file isn't in
/// it (a zip differs every time it's made; the tree is what Lamp opens). Its README leads with the starter: its icon
/// and preview (in `.github/`, out of the code's way), what it is, the changes its chat offers, and for a game, the
/// page it plays on: the game staged as Publish stages one (`page`), which the script puts on the repository's
/// `gh-pages` branch for GitHub Pages.
enum StarterRepos {
    static let commandLineFlag = "--stage-starter-repos"

    /// `Lamp --stage-starter-repos <folder> [<pages>]`, with `STAGE_STARTERS=1`: each starter's tree into
    /// `<folder>/<starter>`, and a game's page into `<pages>/<starter>`, then quits.
    static func stageFromCommandLine() -> Never {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: commandLineFlag), index + 1 < arguments.count else {
            FileHandle.standardError.write(Data("Usage: Lamp \(commandLineFlag) <folder> [<pages>]\n".utf8))
            exit(2)
        }
        let out = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        let pages = index + 2 < arguments.count && !arguments[index + 2].hasPrefix("-") ? URL(fileURLWithPath: arguments[index + 2], isDirectory: true) : nil
        // The starters hold none of the person's keys, and reading them would ask the keychain from a command line.
        Sharing.knownSecrets = { _ in [] }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-starter-repos-\(UUID().uuidString)")
        var failed = false
        for starter in Starters.bundled {
            // A kind Lamp can't share yet (a screen) can't be opened from a repository either: it has none until it can.
            if let refusal = starter.kind.target.recipe.shareRefusal {
                print("Skipped \(starter.name): \(refusal)")
                continue
            }
            do {
                try fm.createDirectory(at: root, withIntermediateDirectories: true)
                let (tree, page) = try stage(starter, in: root)
                let to = out.appendingPathComponent(starter.folder.lastPathComponent)
                try? fm.removeItem(at: to)
                try fm.createDirectory(at: out, withIntermediateDirectories: true)
                try fm.copyItem(at: tree, to: to)
                if let page, let pages {
                    let pageTo = pages.appendingPathComponent(starter.folder.lastPathComponent)
                    try? fm.removeItem(at: pageTo)
                    try fm.createDirectory(at: pages, withIntermediateDirectories: true)
                    try fm.copyItem(at: page, to: pageTo)
                }
                print("Staged \(starter.name)" + (page == nil ? "" : ", with its page"))
            } catch {
                FileHandle.standardError.write(Data("Couldn't stage \(starter.name): \(error.localizedDescription) \((error as? LocalizedError)?.recoverySuggestion ?? "")\n".utf8))
                failed = true
            }
            try? fm.removeItem(at: root)
        }
        exit(failed ? 1 : 0)
    }

    /// The repository a starter goes in: "<account>/newyork".
    static func repo(of starter: Starters.Starter) -> String {
        Starters.account + "/" + Starters.repositoryName(of: starter.folder.lastPathComponent)
    }

    /// One starter's tree, and a game's page, in work folders under `root`.
    static func stage(_ starter: Starters.Starter, in root: URL) throws -> (tree: URL, page: URL?) {
        let fm = FileManager.default
        let project = try Template.draft(name: starter.name, platform: starter.kind, in: root)
        try Template.fill(project)
        try Starters.copy(starter, into: project)
        try Template.writeOwnedFiles(for: project)
        Sharing.setIdentity(identity(of: starter), of: project)
        let repo = repo(of: starter)
        let staged = try GitHubRepo.stage(project, repo: repo, link: nil)
        let tree = staged.folder
        // The tree alone, not the shared file beside it.
        for file in try fm.contentsOfDirectory(at: tree, includingPropertiesForKeys: nil) where file.pathExtension == "lampapp" {
            try fm.removeItem(at: file)
        }
        // The chain: what the starter is based on, and the starter itself, named where it lives. The commit is the
        // one this tree becomes, which whoever opens it gets from the repository (`RepoImport.naming`).
        let based = Credits.read(starter.folder.appendingPathComponent(Credits.file)) ?? Credits()
        let chain = based.remixed(from: Credits.Remix(name: starter.name, starter: starter.folder.lastPathComponent, url: GitHubRepo.url(repo)))
        try chain.encoded().write(to: tree.appendingPathComponent(Credits.file), options: .atomic)
        // Made at no particular time, so an unchanged starter is an unchanged tree.
        let manifestURL = tree.appendingPathComponent("lamp-app.json")
        if var manifest = try? JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any] {
            manifest["exportedAt"] = "2026-01-01T00:00:00Z"
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: manifestURL)
        }
        let license = GitHubRepo.canOfferLicense(chain)
        if license {
            try Data(GitHubRepo.mitLicense(holder: "Roo Code, Inc.").utf8).write(to: tree.appendingPathComponent("LICENSE"))
        }
        // The README's pictures: the starter's icon as it ships, and its preview, which shows only example content.
        var showcase = GitHubRepo.Showcase(ideas: starter.tweaks.map(\.title), ideasTitle: starter.offer.isEmpty ? nil : starter.offer, license: license)
        let pictures = tree.appendingPathComponent(".github")
        for (from, name) in [(starter.folder.appendingPathComponent(Starters.iconFolder).appendingPathComponent("icon.png"), "icon.png"),
                             (starter.folder.appendingPathComponent("preview.png"), "preview.png")] where fm.fileExists(atPath: from.path) {
            try fm.createDirectory(at: pictures, withIntermediateDirectories: true)
            try fm.copyItem(at: from, to: pictures.appendingPathComponent(name))
            if name == "icon.png" { showcase.icon = ".github/icon.png" } else { showcase.preview = ".github/preview.png" }
        }
        let page = try stagePage(project, starter: starter, repo: repo, in: root)
        if page != nil { showcase.play = Publish.pageURL(repo) }
        let (app, parts) = Sharing.layout(of: project)
        let build = GitHubRepo.Build(alone: app.platform.target.recipe.buildsAlone, app: app.platform.target.identity.name, others: !parts.isEmpty)
        // Its credits are what it's based on; the chain would name only the starter itself, which is this page.
        try Data(GitHubRepo.readme(for: project, credits: Credits(upstream: based.upstream, generated: based.generated),
                                   open: Publish.OpenInLamp(link: nil, file: nil), build: build, repo: repo, showcase: showcase).utf8)
            .write(to: tree.appendingPathComponent("README.md"))
        return (tree, page)
    }

    /// A game's page as Publish stages one to play in any browser (`Publish.stage`), with the credit bar, the starter's
    /// changes in its Remix panel and Lamp's site for the rest: nothing else (no shared file, which differs every time
    /// it's made). Nil for a starter that isn't a game with a page.
    static func stagePage(_ project: LampProject, starter: Starters.Starter, repo: String, in root: URL) throws -> URL? {
        guard project.holdsApp, GameKit.isGame(project), GameKit.engine(project) == .web else { return nil }
        let fm = FileManager.default
        let site = root.appendingPathComponent("page-\(starter.folder.lastPathComponent)")
        try? fm.removeItem(at: site)
        try fm.createDirectory(at: site, withIntermediateDirectories: true)
        let web = project.dir.appendingPathComponent(GameKit.webFolder)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let items = fm.enumerator(at: web, includingPropertiesForKeys: keys) else { return nil }
        for case let file as URL in items {
            if file.lastPathComponent.hasPrefix(".") { items.skipDescendants(); continue }
            let values = try? file.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
            let target = site.appendingPathComponent(Sharing.relativePath(of: file, in: web))
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: file, to: target)
        }
        let anyBrowser = GamePage.anyBrowser
        try GamePage.stage(site, in: site) { try GamePage.descriptor(id: anyBrowser.id, name: anyBrowser.name, input: anyBrowser.input) }
        let index = site.appendingPathComponent("index.html")
        guard let html = try? String(contentsOf: index, encoding: .utf8) else { return nil }
        let credits = Credits.load(project)
        let ideas = starter.tweaks.map { RemixIdea(text: $0.title, symbol: $0.symbol ?? "sparkles") }
        try Data(Publish.withCreditBar(html, credits: credits, open: Publish.OpenInLamp(link: nil, file: nil),
                                       suggestions: ideas.isEmpty ? RemixOffer.fallback : ideas, name: project.name,
                                       about: AppDescription.description(of: project)).utf8).write(to: index)
        try Data().write(to: site.appendingPathComponent(".nojekyll"))
        try Data("# \(project.name), to play\n\nThe page at \(Publish.pageURL(repo)). The wish itself, to open in Lamp and change, is on the [main branch](\(GitHubRepo.url(repo))).\n".utf8)
            .write(to: site.appendingPathComponent("README.md"))
        let leaks = ShareCheck.secrets(in: site, known: [])
        if let first = leaks.first { throw Sharing.ImportError("\(project.name)'s page holds something shaped like a key.", detail: "It's in \(first).") }
        return site
    }

    /// The identity the starter's repository gives the wish: the same for every staging of the same starter, and no
    /// copy's own (copies keep the identity they were made with).
    static func identity(of starter: Starters.Starter) -> String {
        var bytes = Array(SHA256.hash(data: Data(("lamp-starter:" + starter.folder.lastPathComponent).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])).uuidString
    }
}
