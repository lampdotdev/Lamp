import AppKit
import Foundation
import LampFileLook
import LampSidebarKit

/// Putting a wish on GitHub: its code as a repository on the person's own account, made with GitHub's command-line tool
/// (`gh`) and their sign-in there. Nothing goes through Lamp's servers.
///
/// What goes up is what a shared file carries (`Sharing.export`: the code, APP.md, the icon, the app's own files,
/// credits.json and the licenses it names; never the chat, the app's data or a key), unpacked so the code reads on
/// GitHub, with Lamp's own files beside it (build.sh, Package.swift, LampSupport.swift and the rest, so `zsh build.sh`
/// makes the app on any Mac with Apple's tools and no Lamp), the shared file itself (what Lamp opens today), a README
/// that says what it is, how to remix it with Lamp and what it's based on, an MIT license when the person wants one, and
/// the wish's picture when they include it, which shows whatever is in the app at the time.
/// A web game or a web app in a public repository also gets its page, to play or use in any browser, on the repository's
/// `gh-pages` branch, served by GitHub Pages (`Publish`), which the README's Play (or Open) in your browser links.
/// The wish's own git history stays on the Mac: it holds every version and the chat's attachments, so each push is
/// one commit of the wish as it is now, on top of the last. Release Update is the one way it goes there (`GitHubRelease`).
enum GitHubRepo {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// A repository that's up, and whether it carries the MIT license the person chose: an update keeps to that choice.
    /// Nil from a Lamp before the choice was kept, read as no license. `commit` is the one Lamp last
    /// pushed, which a later share names on the chain (`Sharing.export`); nil from a Lamp before it was kept.
    /// `isPublic` is what GitHub said after the last push, and `version` the wish's own version that push carried: a
    /// remix starts from the repository only while both hold (`remixOrigin`). Nil from a Lamp before they were kept.
    /// `page` is the page's address (a web game's or a web app's), once GitHub has put it up. `picture` is whether the person had the README
    /// show the wish's picture, which an update keeps to.
    /// `taken` is a commit of the repository's that came after `commit` (someone's pull request merged on GitHub, an
    /// edit made there) whose changes the wish has brought in since (`BringIn`), so the next release goes on top of it;
    /// a push of Lamp's records a new `commit` without it.
    struct Repo: Codable, Equatable {
        var repo: String   // "owner/name"
        var url: String
        var license: Bool? = nil
        var commit: String? = nil
        var isPublic: Bool? = nil
        var version: String? = nil
        var page: String? = nil
        var picture: Bool? = nil
        var taken: String? = nil
        /// The wish's own version `taken` was saved in, which its history must still have (`BringIn.holds`).
        var takenIn: String? = nil
        /// Files the repository keeps as GitHub has them (`keptFromGitHub`): each push keeps them so, not only the first
        /// after they changed there.
        var ownFiles: [String]? = nil

        /// The commit the repository must be at for the wish to go over it: the last one whose changes the wish has.
        var expected: String? { taken ?? commit }
    }

    /// The repository has commits the wish hasn't brought in (`BringIn`), so putting the wish there would undo them:
    /// said apart from a failure that trying again can fix.
    struct Moved: LocalizedError {
        let repo: String
        let name: String
        var errorDescription: String? { "\(repo) has changes on GitHub that \(name) doesn't have yet." }
    }

    static func url(_ repo: String) -> String { "https://github.com/\(repo)" }

    /// The repository a remix of this wish starts from (`RemixLink.Origin`): only one anyone can read, since Lamp fetches
    /// it without a sign-in, and only while it holds the wish as it is now, so a remix never starts from an older version
    /// than the page or app it was asked from. Nil otherwise, and the remix goes by the Share Link or the request.
    /// An app in a folder of its wish's (`Mac/`, `Game/`) goes by its wish, which is what was put on GitHub.
    static func remixOrigin(for app: LampProject) -> RemixLink.Origin? {
        let project = app.partOf == nil ? app : Store.readWish(at: app.dir.deletingLastPathComponent()) ?? app
        guard let kept = kept(for: project), kept.isPublic == true, let version = kept.version, let commit = kept.commit,
              Versions.savedVersion(of: project.dir) == version else { return nil }
        return .repository(url: url(kept.repo), commit: commit)
    }

    // MARK: Where it went

    /// A test points this at a folder of its own, so it never writes over the person's own record.
    nonisolated(unsafe) static var keptURL = Edition.supportFolder.appendingPathComponent("GitHub Repositories.json")
    private static func key(_ project: LampProject) -> String { project.instance.isEmpty ? project.id : project.instance }

    static func kept(for project: LampProject) -> Repo? { readKept()[key(project)] }

    /// The wish is on GitHub: a repository Lamp made and pushed it to. One made by a first push that failed before
    /// anything went up has no commit yet, and the next release with Also put on GitHub finishes it
    /// (`GitHubRelease.FirstPush`); a record from a Lamp before
    /// commits were kept had no license kept either, and is up.
    static func isUp(_ project: LampProject) -> Bool {
        guard let kept = kept(for: project) else { return false }
        return kept.commit != nil || kept.license == nil
    }

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
        /// The wish's own version this is of, kept with the repository once it's up (`Repo.version`).
        var version: String? = nil
        /// Where the README's Open in Lamp goes, in a public repository (`remixLink`): what the card names as its remix
        /// link, in place of the Share Link a private one's README uses.
        var remix: String? = nil
        /// A web game's or a web app's page, for the page branch, in a public repository.
        var page: Page? = nil
        /// A plain site's address (`StaticSite`), in a public repository: its page is the tree's root, served by GitHub
        /// Pages from the main branch as it is, with no page branch and nothing of Lamp's over it.
        var site: String? = nil

        /// The page as staged beside the tree: its folder, its index.html before the credit bar (which goes over it as
        /// it's pushed, naming the commit pushed with it, `upload`), what the bar says, and where it plays.
        struct Page {
            let folder: URL
            let html: String
            let credits: Credits
            /// credits.json's chain, whose last link names the commit pushed with the page, written then.
            let chain: Credits
            let link: URL?
            let suggestions: [RemixIdea]
            let about: String?
            let url: String
        }
    }

    /// Stages the repository for `repo`, its README's remix link going to `link` (the wish's Share Link, which works
    /// for someone without Lamp) when there is one: refused, with why, when the wish can't leave this Mac.
    /// Without a repository it's staged as it would be for one not yet made (a check of what it would hold,
    /// `GitHubProjects.check`): the chain ends with the wish as its shared file does, and the README names no address.
    /// `isPublic` is whether anyone will be able to read the repository: its README then offers it by a link of Lamp's
    /// site (`Showcase.remix`), which Lamp fetches without a sign-in, and a web game gets its page (`withPage`; a starter's
    /// repository stages its own, `StarterRepos.stagePage`). `picture` is the wish's picture for the README to show, when
    /// the person chose to show it (`GitHubRelease.FirstPush`).
    static func stage(_ project: LampProject, repo: String?, link: URL?, isPublic: Bool = true, withPage: Bool = true,
                      picture: Data? = nil) throws -> Staged {
        let fm = FileManager.default
        let credits = Credits.load(project)
        if let refusal = ShareCheck.refusal(of: project, credits: credits) { throw refusal }
        // Read before the export, so a change landing meanwhile is never taken for what went up; none while anything is
        // unsaved, since what goes up is then no version of the wish.
        let version = Versions.savedVersion(of: project.dir)
        let work = Sharing.workFolder.appendingPathComponent("lamp-github-\(UUID().uuidString)")
        let tree = work.appendingPathComponent("repo")
        var done = false
        defer { if !done { try? fm.removeItem(at: work) } }
        try fm.createDirectory(at: tree, withIntermediateDirectories: true)

        // The wish as a shared file, held to the same checks and carrying the credits with this wish at the end of the
        // chain, and its contents unpacked beside it: the code as people read it on GitHub.
        let fileName = Publish.slug(project.name) + ".lampapp"
        // The file's credits end the chain with this wish, named where it's going: the repository's address, which a
        // remix opened from there carries on, and the commit up there now, which the next one is on top of.
        let shared = try Sharing.export(project, repository: repo.map(url), commit: kept(for: project).flatMap { $0.repo == repo ? $0.expected : nil })
        defer { try? fm.removeItem(at: shared.deletingLastPathComponent()) }
        guard Subprocess.runBlocking("/usr/bin/ditto", ["-x", "-k", shared.path, tree.path], timeout: 120).ok else {
            throw Failure(message: "Couldn't unpack \(project.name)'s files.")
        }
        try fm.copyItem(at: shared, to: tree.appendingPathComponent(fileName))
        // Lamp's own files for each of the wish's apps, where the shared file put that app (`Sharing.layout`: one at the
        // root, the others in their folders), so the code builds as it is: the shared file leaves them out because
        // the Lamp that opens it writes its own.
        let (root, parts) = Sharing.layout(of: project)
        // A plain site keeps its repository's layout (`StaticSite`): none of Lamp's own files go up, which the Lamp
        // that opens it writes afresh, but lamp.js when the page loads it, with its license.
        let site = parts.isEmpty && ScreenKit.isSite(root)
        let runtime = site && StaticSite.loadsRuntime(root.dir.appendingPathComponent(TVTemplate.webFolder))
        for (app, folder) in [(root, "")] + parts.map { ($0, $0.dir.lastPathComponent + "/") } {
            for path in ownedPaths(in: app) where !site || (runtime && path == TVTemplate.supportFile) {
                let to = tree.appendingPathComponent(folder + path)
                guard !fm.fileExists(atPath: to.path) else { continue }
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: app.dir.appendingPathComponent(path), to: to)
            }
        }
        if runtime {
            try Data(mitLicense(holder: "Roo Code, Inc.", year: 2026).utf8)
                .write(to: tree.appendingPathComponent("\(TVTemplate.webFolder)/\(Publish.runtimeLicense)"))
            // Served as it is, so it keeps its saves apart from the account's other pages as a published page does.
            if let repo { try Publish.scope(tree.appendingPathComponent(TVTemplate.supportFile), to: String(repo.split(separator: "/").last ?? "")) }
        }
        try Data(".build/\nbuild/\n.lamp/\n".utf8).write(to: tree.appendingPathComponent(".gitignore"))
        // The file's credits.json ends the chain with this wish, for whoever opens it; the README is this wish's own, so it
        // names what the wish was remixed from, not itself.
        let chain = Credits.read(tree.appendingPathComponent(Credits.file)) ?? credits
        let open = Publish.OpenInLamp(link: link, file: fileName)
        let build = Build(alone: root.platform.target.recipe.buildsAlone, app: root.platform.target.identity.name, others: !parts.isEmpty,
                          // Web/ even for a wish whose one app is in a part: the export puts that app at the root (`Sharing.layout`).
                          page: Publish.hasPage(project) ? (site ? "" : TVTemplate.webFolder + "/") : nil)
        // The icon the shared file carries, as it's drawn: never a picture of the app running, which could show the
        // person's data.
        let icon = fm.fileExists(atPath: tree.appendingPathComponent(LampFile.iconEntry).path) ? LampFile.iconEntry : nil
        // The ideas its chat offers beside it on a Mac without Lamp (`RemixSuggestions`), each a remix of its own.
        let ideas = (RemixSuggestions.load(project) ?? []).map(\.text)
        var showcase = Showcase(icon: icon, ideas: ideas)
        if let picture {
            let file = tree.appendingPathComponent(previewPicture)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try picture.write(to: file)
            showcase.preview = previewPicture
        }
        if isPublic, repo != nil { try writeButtons(in: tree, page: Publish.pageUse(project)); showcase.remix = true }
        // A web game or a web app is a page too, staged here so it's checked and shown before anything goes up: only in a public
        // repository, since GitHub serves a private one's page only on a paid plan.
        var page: Staged.Page?
        let sitePage = site && isPublic ? repo.map(Publish.pageURL) : nil
        if let sitePage {
            showcase.play = sitePage
            showcase.plays = false
        } else if withPage, isPublic, let repo, Publish.hasPage(project) {
            let site = work.appendingPathComponent("page")
            let html = try Publish.copyPage(of: project, into: site, scope: String(repo.split(separator: "/").last ?? ""))
            try Data(Publish.pageReadme(for: project, credits: credits, repo: repo, site: site).utf8)
                .write(to: site.appendingPathComponent("README.md"))
            let leaks = ShareCheck.secrets(in: site, known: Sharing.knownSecrets(project))
            if let first = leaks.first {
                throw Sharing.ImportError("\(project.name)'s page can't go on GitHub: it holds a key or a password.",
                                          detail: "It's in \(first). Ask Lamp to take it out and keep it out of the code.")
            }
            page = Staged.Page(folder: site, html: html, credits: credits, chain: chain, link: link,
                               suggestions: RemixSuggestions.load(project) ?? RemixOffer.fallback,
                               about: AppDescription.description(of: project), url: Publish.pageURL(repo))
            showcase.play = page?.url
            showcase.plays = Publish.pageUse(project) != .use
        }
        // Never "Remixed from" itself: a wish put back where it came from.
        var told = credits
        if let repo { told.remixOf.removeAll { $0.url.map { Credits.Source.plain($0) == Credits.Source.plain(url(repo)) } ?? false } }
        try Data(readme(for: project, credits: told, open: open, build: build, repo: repo, showcase: showcase).utf8)
            .write(to: tree.appendingPathComponent("README.md"))
        // A site's page at the root, as its repository has it, and Lamp's README with the rest in Lamp's folder.
        if site { try StaticSite.layOut(tree) }

        let leaks = ShareCheck.secrets(in: tree, known: Sharing.knownSecrets(project))
        if let first = leaks.first {
            throw Sharing.ImportError("\(project.name) can't go on GitHub: it holds a key or a password.",
                                      detail: "It's in \(first). Ask Lamp to take it out and keep it out of the code.")
        }
        // Everything that goes up: the tree, and the page beside it.
        let all = ([tree] + (page.map { [$0.folder] } ?? [])).flatMap { folder in
            fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { $0 as? URL } ?? []
        }
        let bytes = all.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        // GitHub refuses a file over 100 MB and a repository (and a Pages site) is meant to stay well under 1 GB.
        guard bytes < 900_000_000 else { throw Failure(message: "\(project.name) is too big to put on GitHub.") }
        done = true
        return Staged(folder: tree, files: all.filter { !$0.hasDirectoryPath }.count, bytes: bytes, credits: chain, open: open,
                      version: version, remix: showcase.remix ? repo.map { remixLink($0) } : nil, page: page, site: sitePage)
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
        /// Where a page that runs as it is (`Target.publishedPage`) is in the repository: "Web/", or "" for a site at its root.
        var page: String? = nil
    }

    /// What a README shows of the wish before anything about Lamp: pictures and ideas, by their paths in the
    /// repository. A person's own wish shows its picture only when they chose to, on the card that shows it, since a
    /// picture of it running could show their data (`previewPicture`). A starter shows its preview (example content
    /// only), what to try with it, and where to play it when it's a game.
    struct Showcase {
        var icon: String? = nil
        var preview: String? = nil
        /// The folder of its reel (loop.webp, reel.mp4): GitHub plays no video a README holds, so the README shows the
        /// silent loop and links the video, which GitHub plays with its sound.
        var reel: String? = nil
        /// Where it plays in a browser, for a game whose page is up, or where it's used, for an app's (`plays` false).
        var play: String? = nil
        var plays = true
        /// What to ask for first, and the line that offers them ("Make Hours fit your work").
        var ideas: [String] = []
        var ideasTitle: String? = nil
        /// The repository carries an MIT license.
        var license = false
        /// Anyone can read the repository, so the README offers it by a link of Lamp's site, which opens Lamp on a fresh
        /// copy (`RemixLink.site`), with the button `writeButtons` drew; each idea is such a link with its request. A private one is opened from its file instead, since Lamp fetches a repository without a sign-in.
        var remix = false
    }

    /// The README's buttons, in the repository's pictures (`Starters.picturesFolder`): Open in Lamp, and for a wish with
    /// a page, Play (a game) or Open (an app) in your browser before it, since someone who hasn't tried a thing wants to
    /// try it first.
    static let openButton = ".github/open-in-lamp.svg"
    /// The wish's picture, as the desk shows it, when the person chose to show it.
    static let previewPicture = ".github/preview.png"
    static let playButton = ".github/play-in-browser.svg"
    static let useButton = ".github/open-in-browser.svg"

    /// The buttons drawn as lamp.dev's are, words alone: Open in Lamp in the paper's color on ink, Play in your browser
    /// in ink on the stripes' yellow. Each is edged so it holds on GitHub's dark theme as on its light one.
    static let openWidth = 164, playWidth = 220, useWidth = 224

    static func writeButtons(in tree: URL, page: Publish.PageUse?) throws {
        func button(_ words: String, width: Int, fill: String, ink: String, edge: String) -> String {
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="48" viewBox="0 0 \(width) 48" role="img" aria-label="\(words)">\
            <rect x="1" y="1" width="\(width - 2)" height="46" rx="6" fill="\(fill)" stroke="\(edge)" stroke-width="2"/>\
            <text x="\(width / 2)" y="30.5" text-anchor="middle" fill="\(ink)" \
            font-family="-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif" font-size="18" font-weight="800">\(words)</text></svg>

            """
        }
        var buttons = [(openButton, button("Open in Lamp", width: openWidth, fill: "#1b1a17", ink: "#f2ecda", edge: "#f2ecda"))]
        switch page {
        case .play: buttons.append((playButton, button("Play in your browser", width: playWidth, fill: "#f6b81c", ink: "#1b1a17", edge: "#1b1a17")))
        case .use: buttons.append((useButton, button("Open in your browser", width: useWidth, fill: "#f6b81c", ink: "#1b1a17", edge: "#1b1a17")))
        case nil: break
        }
        for (path, svg) in buttons {
            let file = tree.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(svg.utf8).write(to: file)
        }
    }

    /// The repository remixed on Lamp's site, with a request when given.
    /// Parentheses are encoded too, so the link ends where Markdown's does.
    static func remixLink(_ repo: String, ask: String? = nil, from: String = "readme") -> String {
        RemixLink.site(for: .repository(url: url(repo), commit: nil), ask: ask, from: from).absoluteString
            .replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
    }

    /// The repository's README: the wish first (its icon, what it is, a picture of it, where to play it, ideas to try),
    /// then how to remix it with Lamp, how to build it, and what it's based on.
    static func readme(for project: LampProject, credits: Credits, open: Publish.OpenInLamp, build: Build, repo: String? = nil,
                       showcase: Showcase = Showcase()) -> String {
        let name = Publish.escaped(project.name)
        var text = ""
        if let icon = showcase.icon { text += "<p align=\"center\"><img src=\"\(icon)\" width=\"128\" height=\"128\" alt=\"\"></p>\n\n" }
        text += "<h1 align=\"center\">\(name)</h1>\n\n"
        if let line = Sharing.description(of: project) { text += "<p align=\"center\">\(Publish.escaped(line))</p>\n\n" }
        let remix = showcase.remix ? repo : nil
        var links: [String] = []
        if remix == nil {
            if let play = showcase.play { links.append("<a href=\"\(play)\"><b>\(showcase.plays ? "Play" : "Open") it in your browser</b></a>") }
            links.append("<a href=\"#remix-it-with-lamp\">Remix it with Lamp</a>")
        }
        if build.alone { links.append("<a href=\"#build-it-yourself\">Build it yourself</a>") }
        // Trying it comes first, as buttons where the eye lands under the name: a game's page to play, then Lamp, which
        // opens a copy of it to use and to change.
        if let remix {
            var buttons: [String] = []
            if let play = showcase.play {
                let (button, width, words) = showcase.plays ? (playButton, playWidth, "Play in your browser") : (useButton, useWidth, "Open in your browser")
                buttons.append("<a href=\"\(Publish.escaped(play))\"><img src=\"\(button)\" width=\"\(width)\" height=\"48\" alt=\"\(words)\"></a>")
            }
            buttons.append("<a href=\"\(Publish.escaped(remixLink(remix)))\"><img src=\"\(openButton)\" width=\"\(openWidth)\" height=\"48\" alt=\"Open in Lamp\"></a>")
            text += "<p align=\"center\">" + buttons.joined(separator: "&nbsp;&nbsp;") + "</p>\n\n"
        }
        if !links.isEmpty { text += "<p align=\"center\">" + links.joined(separator: " · ") + "</p>\n\n" }
        if let reel = showcase.reel {
            text += "<p align=\"center\"><a href=\"\(reel)/reel.mp4\"><img src=\"\(reel)/loop.webp\" width=\"720\" alt=\"\(name)\"></a></p>\n\n"
            text += "<p align=\"center\"><a href=\"\(reel)/reel.mp4\">Watch it with sound</a></p>\n\n"
        } else if let preview = showcase.preview {
            text += "<p align=\"center\"><img src=\"\(preview)\" width=\"720\" alt=\"\(name)\"></p>\n\n"
        }
        if !showcase.ideas.isEmpty {
            text += "## \(showcase.ideasTitle ?? "Ideas to try")\n\n"
            if let remix {
                text += "Each opens Lamp with a copy of \(name) and that change, ready to send:\n\n"
                text += showcase.ideas.map { "- [\(markdownText($0))](\(remixLink(remix, ask: $0)))" }.joined(separator: "\n") + "\n\n"
            } else {
                text += "It's yours to change by asking Lamp. A few places to start:\n\n"
                text += showcase.ideas.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
            }
        }
        text += remix == nil ? "## Remix it with Lamp\n\n" : "## Open it in Lamp\n\n"
        text += "[Lamp](https://lamp.dev) is a Mac app that builds apps from a description and changes them as you ask. "
        if let remix {
            text += "[Open \(name) in Lamp](\(remixLink(remix))) for a copy of your own, to use and to change as you like, with the credits below kept. "
                + "Or, in Lamp, choose File → Open from GitHub… and paste `\(url(remix))`."
        } else {
            if let link = open.link {
                text += "[Make your own](\(link.absoluteString)) from this app, with Lamp or by getting Lamp from that page. "
            }
            if let file = open.file {
                text += (open.link == nil ? "Download" : "Or download") + " [\(file)](\(file)) and open it with Lamp (double-click it, or File → Import Shared App…): "
                    + "you get this exact app, yours to change, with the credits below kept. The code here is what that file holds."
            } else if let repo {
                text += (open.link == nil ? "In" : "Or, in") + " Lamp, choose File → Open from GitHub… and paste `\(url(repo))`: "
                    + "you get this exact app, yours to change, with the credits below kept."
            }
        }
        if build.alone {
            text += "\n\n## Build it yourself\n\n"
            text += "With Apple's Command Line Tools installed (`xcode-select --install`):\n\n```sh\nzsh build.sh\n```\n\n"
            if build.others { text += "That builds \(build.app); the apps that go with it, in their folders, are built by Lamp.\n\n" }
            text += "The AI inside the app, and anything it does with other apps or devices, goes through Lamp, so those need Lamp open on the same Mac.\n\n"
        } else if let page = build.page {
            text += "\n\n## Running it\n\nIt's a web page with no build step: serve " + (page.isEmpty ? "the repository's top folder" : "`\(page)`")
                + " with any static web server and open it in a browser. The AI inside it, and anything it does with other apps or your Mac, goes through Lamp, so a browser shows it without them.\n\n"
        } else {
            text += "\n\n## Building it\n\nLamp builds this kind of app: it needs Xcode and signing on your Mac, which Lamp sets up. Open it in Lamp, above.\n\n"
        }
        text += Publish.creditsSection(credits)
        if showcase.license { text += "## License\n\nMIT. See [LICENSE](LICENSE).\n" }
        return text
    }

    /// An idea as a link's words: Markdown's own characters escaped, so a bracket can't end the link.
    static func markdownText(_ text: String) -> String {
        String(text.flatMap { "\\`*_[]<>#|".contains($0) ? ["\\", $0] : [$0] })
    }

    /// The MIT license, in the person's name.
    static func mitLicense(holder: String, year: Int = Calendar(identifier: .gregorian).component(.year, from: Date())) -> String {
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

    /// Whether two shared-file manifests say the same, apart from when each was made (`exportedAt`).
    static func manifestsMatch(_ a: Data, _ b: Data) -> Bool {
        func fields(_ data: Data) -> NSDictionary? {
            guard var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            json.removeValue(forKey: "exportedAt")
            return json as NSDictionary
        }
        guard let first = fields(a), let second = fields(b) else { return false }
        return first == second
    }

    /// Whether two credits files say the same, apart from the commits on the chain.
    static func creditsMatch(_ a: Data?, _ b: Data?) -> Bool {
        func plain(_ data: Data?) -> Credits? {
            guard var credits = data.flatMap(Credits.decoded) else { return data == nil ? Credits() : nil }
            for index in credits.remixOf.indices { credits.remixOf[index].commit = nil }
            return credits
        }
        guard let first = plain(a), let second = plain(b) else { return false }
        return first == second
    }

    // MARK: Putting it up

    /// Puts the staged tree in `repo` (made, if it's new, public or private as asked) as one commit on top of what's
    /// there, then a web game's page on the page branch, with Pages turned on for it; `step` hears what it's doing.
    /// `changed` is false when the repository already had the wish (and its page) as it is. The record returned names
    /// the commit up there now. Once the code is up it's kept, so a page that fails to go up is tried again on top of it.
    /// `expected` is the commit the repository must be at for the wish to go over it: the one Lamp last pushed, or for
    /// the person's own repository the wish was opened from, the one it was opened at. A repository that has moved on
    /// since is refused rather than overwritten (a push of a commit on top of its tip would quietly undo what's there).
    /// `release` is a release of the wish's (Release Update, `GitHubRelease`): its lines are the commit's message, and once
    /// the code is up it's made a release of the repository's too, tagged with its version, before the page goes up.
    /// `pushed` hears when everything is up and only GitHub's building of the page is left to wait for.
    /// `lastPushed` is the commit Lamp last pushed, when the wish has brought in commits made on GitHub after it
    /// (`expected` then names the latest of them): what changed there since is weighed file by file (`keptFromGitHub`),
    /// so nothing of it is lost. `broughtIn` lists the files of the app as the wish brought them in (`BringIn.paths`).
    /// `keeping` are the files earlier pushes kept as GitHub has them (`Repo.ownFiles`), which this one keeps too.
    static func upload(_ staged: Staged, of project: LampProject, to repo: String, gh: String, login: String, isNew: Bool, expected: String? = nil,
                       lastPushed: String? = nil, broughtIn: Set<String> = [], keeping: [String] = [],
                       isPrivate: Bool, license: Bool, picture: Bool? = nil, authors shown: [Author]? = nil,
                       release: GitHubRelease.Version? = nil, pushed: @escaping @Sendable () -> Void = {},
                       step: @escaping @Sendable (String) -> Void) async throws -> (repo: Repo, changed: Bool) {
        let fm = FileManager.default
        let url = url(repo)
        let tree = staged.folder
        if isNew {
            step("Making \(repo)…")
            let made = await Subprocess.run(gh, ["repo", "create", repo, isPrivate ? "--private" : "--public",
                                                 "--description", Sharing.description(of: project) ?? "\(project.name), made with Lamp"],
                                            timeout: 60)
            guard made.ok else { throw Failure(message: "GitHub didn't make \(repo): \(made.output.trimmed.suffix(200))") }
            // Kept as soon as it's made, so a try that fails after this goes on with the same repository rather than
            // leaving this one behind and making another.
            keep(Repo(repo: repo, url: url, license: license, commit: kept(for: project)?.commit, picture: picture), for: project)
        }
        // Written only now the repository exists and the choice is settled: a refused repository leaves the box on the
        // card to untick, and the tree it stays staged in holds no license the retry would carry up.
        let licenseFile = tree.appendingPathComponent("LICENSE")
        if license, !fm.fileExists(atPath: licenseFile.path) {
            try Data(mitLicense(holder: login).utf8).write(to: licenseFile)
        }
        let git = git
        let signedIn = signedIn(gh: gh)
        let remote = "https://github.com/\(repo).git"

        let work: URL
        var changed = true
        var theirs: [String] = []
        // The repository's own branch, what its clone checked out; a new one's is main.
        var branch = "main"
        if isNew {
            step("Preparing…")
            // A try after a failed one finds the tree committed already, and pushes that commit again.
            var committed = false
            if fm.fileExists(atPath: tree.appendingPathComponent(".git").path) {
                committed = await Subprocess.run(git, ["rev-parse", "--verify", "-q", "HEAD"], cwd: tree, timeout: 10).ok
            }
            for arguments in committed ? [] : [["init", "-q", "-b", "main"], ["add", "-A"]] {
                let ran = await Subprocess.run(git, arguments, cwd: tree, timeout: 120)
                guard ran.ok else { throw Failure(message: "Couldn't prepare the repository: \(ran.output.trimmed.suffix(200))") }
            }
            if !committed {
                let author = try await author(login: login, git: git, in: tree)
                // The release's what's new is the first commit's message too, when it says any.
                _ = try await commit(["commit", "-q", "-m", release?.message ?? "\(project.name), from Lamp"], as: author, shown: shown, git: git, in: tree)
            }
            work = tree
        } else {
            // What's up already, with the wish as it is now in its place: one commit of the difference.
            step("Reading what's on GitHub…")
            let clone = tree.deletingLastPathComponent().appendingPathComponent("clone")
            try? fm.removeItem(at: clone)
            let cloned = await Subprocess.run(git, signedIn + ["clone", "-q", "--depth", "1", remote, clone.path], timeout: 600)
            guard cloned.ok else { throw Failure(message: "GitHub didn't give back \(repo): \(cloned.output.trimmed.suffix(200))") }
            let checkedOut = await Subprocess.run(git, ["symbolic-ref", "--short", "HEAD"], cwd: clone, mergeErrors: false, timeout: 10)
            guard checkedOut.ok, !checkedOut.output.trimmed.isEmpty else { throw Failure(message: "Lamp couldn't tell which branch \(repo) keeps its code on.") }
            branch = checkedOut.output.trimmed
            let there = await head(git, in: clone)
            if let expected, there != expected { throw Moved(repo: repo, name: project.name) }
            // What changed on GitHub since Lamp's last push, which the wish brought in: each file stays as GitHub has
            // it unless it's the app's (`keptFromGitHub`).
            // Those an earlier push kept stay kept, but for a file the app has come to have since.
            theirs = keeping.filter { ["README.md", "LICENSE"].contains($0) || !fm.fileExists(atPath: tree.appendingPathComponent($0).path) }
            if let lastPushed, let there, lastPushed != there {
                for path in try await keptFromGitHub(in: clone, since: lastPushed, tree: tree, broughtIn: broughtIn, project: project, gh: gh)
                where !theirs.contains(path) { theirs.append(path) }
            }
            // The wish takes the place of what's there, but for what a wish never carries: a hidden file or folder at the
            // top (the person's .github/workflows, .gitignore, an editor's settings) stays as it is, with the tree's own
            // over it file by file. Lamp's folder in a site's repository is Lamp's, and goes whole.
            // A site's hidden files that travel with its page (`ScreenFiles.servedHidden`) are the wish's too: replaced, or
            // taken away when the wish has none.
            let site = fm.fileExists(atPath: tree.appendingPathComponent("\(StaticSite.folder)/lamp-app.json").path)
            let wishes = Set([StaticSite.folder]).union(site ? ScreenFiles.servedHidden : [])
            for item in try fm.contentsOfDirectory(at: clone, includingPropertiesForKeys: nil)
            where item.lastPathComponent != ".git" && (!item.lastPathComponent.hasPrefix(".") || wishes.contains(item.lastPathComponent)) {
                try fm.removeItem(at: item)
            }
            for item in try fm.contentsOfDirectory(at: tree, includingPropertiesForKeys: nil) where item.lastPathComponent != ".git" {
                try merge(item, into: clone.appendingPathComponent(item.lastPathComponent))
            }
            for path in theirs {
                let restored = await Subprocess.run(git, ["checkout", "-q", "HEAD", "--", path], cwd: clone, timeout: 30)
                // Taken away on GitHub: it stays away.
                if !restored.ok { try? fm.removeItem(at: clone.appendingPathComponent(path)) }
            }
            let added = await Subprocess.run(git, ["add", "-A"], cwd: clone, timeout: 120)
            guard added.ok else { throw Failure(message: "Couldn't prepare the repository: \(added.output.trimmed.suffix(200))") }
            // Unchanged when nothing but the export's own marks differ: the shared file's manifest says when it was made,
            // and the file is zipped afresh each time. The manifest's other fields matter (which device an app opens on),
            // so it's compared with only its time left out; the archive follows the manifest.
            // The chain names the commit up there (`Sharing.export`), which each push moves on: the credits compare
            // without it, so real credit changes count and the bookkeeping doesn't.
            // A site's are in Lamp's folder (`StaticSite.layOut`).
            let at = fm.fileExists(atPath: tree.appendingPathComponent("\(StaticSite.folder)/lamp-app.json").path) ? StaticSite.folder + "/" : ""
            if await Subprocess.run(git, ["diff", "--cached", "--quiet", "--", ".", ":(exclude)\(at)lamp-app.json", ":(exclude)\(at)*.lampapp", ":(exclude)\(at)\(Credits.file)"], cwd: clone, timeout: 60).ok {
                let before = await Subprocess.run(git, ["show", "HEAD:\(at)lamp-app.json"], cwd: clone, mergeErrors: false, timeout: 30)
                let credits = await Subprocess.run(git, ["show", "HEAD:\(at)\(Credits.file)"], cwd: clone, mergeErrors: false, timeout: 30)
                if before.ok, let after = try? Data(contentsOf: clone.appendingPathComponent("\(at)lamp-app.json")),
                   manifestsMatch(Data(before.output.utf8), after),
                   creditsMatch(credits.ok ? Data(credits.output.utf8) : nil, try? Data(contentsOf: clone.appendingPathComponent(at + Credits.file))) {
                    changed = false
                }
            }
            if changed {
                let author = try await author(login: login, git: git, in: clone)
                let message = release?.message ?? "Update \(project.name) from Lamp"
                _ = try await commit(["commit", "-q", "-m", message], as: author, shown: shown, git: git, in: clone)
            }
            work = clone
        }
        if changed {
            step("Uploading to GitHub…")
            let pushed = await Subprocess.run(git, signedIn + ["push", "-q", remote, "HEAD:\(branch)"], cwd: work, timeout: 600)
            guard pushed.ok else { throw Failure(message: "GitHub didn't take it: \(pushed.output.trimmed.suffix(200))") }
        }
        var record = Repo(repo: repo, url: url, license: license, commit: await head(git, in: work),
                          isPublic: await isPublic(repo, gh: gh), version: staged.version, page: kept(for: project)?.page, picture: picture,
                          ownFiles: theirs.isEmpty ? nil : theirs)
        if let release, let commit = record.commit {
            // Kept first: the code is up whatever happens to the release.
            keep(record, for: project)
            step("Making release \(release.tag) on GitHub…")
            try await GitHubRelease.tag(release, of: repo, at: commit, gh: gh)
        }
        // A site is served from the main branch as it is: Pages turned on for it, and waited for.
        if let site = staged.site, record.isPublic == true, let commit = record.commit {
            keep(record, for: project)
            pushed()
            try await Publish.servePage(repo, commit: commit, changed: changed, gh: gh, branch: branch, step: step)
            record.page = site
            return (record, changed || kept(for: project)?.page != site)
        }
        guard let page = staged.page, record.isPublic == true, let commit = record.commit else { pushed(); return (record, changed) }
        keep(record, for: project)
        // The page's Open in Lamp and Remix… start from the code just pushed with it, which is the game it plays.
        step("Putting up its page on GitHub…")
        let open = Publish.OpenInLamp(link: page.link, file: nil, origin: .repository(url: url, commit: commit))
        try Data(Publish.withCreditBar(page.html, credits: page.credits, open: open, suggestions: page.suggestions,
                                       name: project.name, about: page.about).utf8)
            .write(to: page.folder.appendingPathComponent("index.html"))
        // The chain names the code it was put up with, as the commit up there now, so an unchanged wish is an unchanged page.
        var chain = page.chain
        if let last = chain.remixOf.indices.last, chain.remixOf[last].url == url { chain.remixOf[last].commit = commit }
        try chain.encoded().write(to: page.folder.appendingPathComponent(Credits.file))
        let pagePushed = try await Publish.pushPage(page.folder, to: repo, gh: gh, login: login, authors: shown, message: "\(project.name)'s page, from Lamp")
        pushed()
        try await Publish.servePage(repo, commit: pagePushed.commit, changed: pagePushed.changed, gh: gh, step: step)
        record.page = page.url
        return (record, changed || pagePushed.changed || kept(for: project)?.page != page.url)
    }

    /// The files changed on GitHub since Lamp's last push (`lastPushed`) that stay as GitHub has them when the wish goes
    /// over the clone: the repository's own (a README or license edited there, a file added there that the app never had),
    /// never the app's. The app's files are what the wish has (`tree`), with what it brought in from GitHub in them
    /// (`broughtIn`, so a file it took away again stays away); what Lamp makes from the app (its manifest, the shared
    /// file, its credits) follows the app. A file Lamp writes itself to build the app (build.sh, Package.swift), edited on
    /// GitHub, can't be both: it's refused, saying which, rather than undone.
    /// When Lamp can't get its last push from GitHub any more (a force push), every file GitHub has that the app doesn't
    /// is the repository's own, and its README and license stay as GitHub has them.
    static func keptFromGitHub(in clone: URL, since lastPushed: String, tree: URL, broughtIn: Set<String>, project: LampProject, gh: String) async throws -> [String] {
        let git = git
        let fetched = await Subprocess.run(git, signedIn(gh: gh) + ["fetch", "-q", "--depth", "1", "origin", lastPushed], cwd: clone, timeout: 300)
        let listed = fetched.ok
            ? await Subprocess.run(git, ["diff", "--name-only", "--no-renames", "-z", lastPushed, "HEAD"], cwd: clone, mergeErrors: false, timeout: 60)
            : await Subprocess.run(git, ["ls-tree", "-r", "--name-only", "-z", "HEAD"], cwd: clone, mergeErrors: false, timeout: 60)
        guard listed.ok else { throw Failure(message: "Lamp couldn't tell what changed on GitHub: \(listed.output.trimmed.suffix(200))") }
        let site = FileManager.default.fileExists(atPath: tree.appendingPathComponent("\(StaticSite.folder)/lamp-app.json").path)
        var kept: [String] = []
        for path in listed.output.split(separator: "\0").map(String.init) where !path.isEmpty {
            let inLamps = site && path.hasPrefix(StaticSite.folder + "/")
            let relative = inLamps ? String(path.dropFirst(StaticSite.folder.count + 1)) : path
            let top = relative.split(separator: "/").first.map(String.init) ?? relative
            // A hidden file at the top is left as it is already (`upload`), or is the app's (a site's served ones).
            if path.hasPrefix(".") { continue }
            if ["lamp-app.json", Credits.file].contains(relative) || (top == relative && relative.hasSuffix(".lampapp")) { continue }
            // Lamp's own files for the app the path is in: a part's in its folder (`Sharing.layout`), the root's at the top.
            let (root, parts) = Sharing.layout(of: project)
            let part = parts.first { relative.hasPrefix($0.dir.lastPathComponent + "/") }
            if part.map({ isOwned(String(relative.dropFirst($0.dir.lastPathComponent.count + 1)), in: $0) }) ?? isOwned(relative, in: root) {
                throw Failure(message: "\(path) was changed on GitHub, and Lamp writes it itself, so putting \(project.name) there would undo that. Change it back on GitHub, or ask for the change in the app.")
            }
            if !["README.md", "LICENSE"].contains(path) {
                if FileManager.default.fileExists(atPath: tree.appendingPathComponent(path).path) { continue }
                if broughtIn.contains(path) || broughtIn.contains(relative) { continue }
            }
            kept.append(path)
        }
        return kept
    }

    /// Copies `item` to `to`, a folder into what's there already, file by file.
    private static func merge(_ item: URL, into to: URL) throws {
        let fm = FileManager.default
        var isFolder: ObjCBool = false
        if fm.fileExists(atPath: item.path, isDirectory: &isFolder), isFolder.boolValue,
           fm.fileExists(atPath: to.path, isDirectory: &isFolder), isFolder.boolValue {
            for child in try fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
                try merge(child, into: to.appendingPathComponent(child.lastPathComponent))
            }
            return
        }
        try? fm.removeItem(at: to)
        try fm.copyItem(at: item, to: to)
    }

    /// The git that talks to GitHub for the person, with their own settings: Homebrew's when they have it, else Apple's.
    static var git: String {
        FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/git") ? "/opt/homebrew/bin/git" : "/usr/bin/git"
    }

    /// Who the commits Lamp puts on GitHub are made as. Someone whose git signs their commits gets them as their git
    /// makes them, name, address and key alike: GitHub verifies a signature only under an address its key names, so
    /// the GitHub name and private address Lamp gives everyone else would show their signed commits as Unverified.
    struct Author: Equatable, Sendable {
        let signs: Bool
        /// The addresses the commits show on GitHub: the author's and the committer's, which git can set apart.
        let emails: [String]
        /// What git is run with to commit as them.
        let options: [String]

        /// The addresses that aren't the one GitHub keeps for an account that hides its own.
        var publicEmails: [String] { emails.filter { !$0.lowercased().hasSuffix("@users.noreply.github.com") } }
    }

    /// The card's words for the addresses that go out with the commits, said before anything does.
    static func note(for authors: [Author]) -> String? {
        var shown: [String] = []
        for email in authors.flatMap(\.publicEmails) where !shown.contains(email) { shown.append(email) }
        guard !shown.isEmpty else { return nil }
        return "Your git signs your commits, so they go as you sign them, showing \(shown.joined(separator: " and ")) on GitHub."
    }

    /// The person's author for commits made in `folder`, as their git says there: conditional settings follow the
    /// folder, its branch and its remote, so it's asked where the commit is made, or somewhere set up the same way.
    static func author(login: String, git: String, in folder: URL) async throws -> Author {
        let signs = await Subprocess.run(git, ["config", "--type=bool", "--get", "commit.gpgSign"], cwd: folder, mergeErrors: false, timeout: 10)
        guard signs.ok, signs.output.trimmed == "true" else {
            return Author(signs: false, emails: ["\(login)@users.noreply.github.com"],
                          options: ["-c", "user.name=\(login)", "-c", "user.email=\(login)@users.noreply.github.com"])
        }
        var emails: [String] = []
        for role in ["GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"] {
            let ident = await Subprocess.run(git, ["var", role], cwd: folder, mergeErrors: false, timeout: 10)
            guard ident.ok, let open = ident.output.firstIndex(of: "<"), let close = ident.output[open...].firstIndex(of: ">"),
                  case let email = String(ident.output[ident.output.index(after: open)..<close]), email.contains("@") else {
                throw Failure(message: "Your git signs your commits but has no email address set for them. Set one, then try again.")
            }
            if !emails.contains(email) { emails.append(email) }
        }
        return Author(signs: true, emails: emails, options: [])
    }

    /// Where a first push's commits will be made, set up as they will be, and who they're made as there: the code's in
    /// `staged.folder` on main for a new repository or in a clone beside it on the repository's branch for one that's
    /// up, and a page's in its folder on the page branch. What the card shows, before anything goes.
    static func authors(for staged: Staged, repo: String, isNew: Bool, gh: String, login: String) async throws -> [Author] {
        try await authors(repo: repo, isNew: isNew, code: staged.folder, page: staged.page?.folder, gh: gh, login: login)
    }

    /// Who a release's commits to a repository that's up are made as (`GitHubRelease`), found in folders of their own
    /// set up as `upload`'s will be, so the release card says it before anything goes.
    static func authors(releasingTo repo: String, withPage: Bool, gh: String, login: String) async throws -> [Author] {
        let work = Sharing.workFolder.appendingPathComponent("lamp-github-authors-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let code = work.appendingPathComponent("repo"), page = work.appendingPathComponent("page")
        for folder in [code, page] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        return try await authors(repo: repo, isNew: false, code: code, page: withPage ? page : nil, gh: gh, login: login)
    }

    private static func authors(repo: String, isNew: Bool, code: URL, page: URL?, gh: String, login: String) async throws -> [Author] {
        let git = git
        func ready(_ folder: URL, branch: String, remote: String?) async throws -> URL {
            for arguments in [["init", "-q", "-b", branch]] + (remote.map { [["remote", "add", "origin", $0]] } ?? []) {
                let ran = await Subprocess.run(git, arguments, cwd: folder, mergeErrors: false, timeout: 30)
                guard ran.ok else { throw Failure(message: "Couldn't prepare the repository: \(ran.errors.trimmed.suffix(200))") }
            }
            return folder
        }
        var authors: [Author] = []
        if isNew {
            authors.append(try await author(login: login, git: git, in: try await ready(code, branch: "main", remote: nil)))
        } else {
            // `upload` clones it here, which replaces this.
            let clone = code.deletingLastPathComponent().appendingPathComponent("clone")
            try? FileManager.default.removeItem(at: clone)
            try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)
            let branch = await Subprocess.run(gh, ["repo", "view", repo, "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name"], mergeErrors: false, timeout: 30)
            let name = branch.ok && !branch.output.trimmed.isEmpty ? branch.output.trimmed : "main"
            authors.append(try await author(login: login, git: git, in: try await ready(clone, branch: name, remote: "https://github.com/\(repo).git")))
            try? FileManager.default.removeItem(at: clone)
        }
        if let page {
            // `pushPage` starts its own afresh here.
            authors.append(try await author(login: login, git: git, in: try await ready(page, branch: Publish.pageBranch, remote: nil)))
            try? FileManager.default.removeItem(at: page.appendingPathComponent(".git"))
        }
        return authors
    }

    /// Makes a commit as `author` (`git commit …` or `git commit-tree …` in `arguments`, run with `options` first) and
    /// returns it. A commit the person's git should have signed and didn't is an error, never sent unsigned in its place.
    /// `shown` is who the card showed: an address it didn't show never goes out, whether git names it beforehand or
    /// writes it in the commit.
    static func commit(_ arguments: [String], as author: Author, shown: [Author]?, git: String, options: [String] = [], in folder: URL) async throws -> String {
        let allowed = shown.map { Set($0.flatMap(\.emails)) }
        func unshown(_ emails: [String]) -> String? {
            guard let allowed else { return nil }
            return emails.first { !allowed.contains($0) && !$0.lowercased().hasSuffix("@users.noreply.github.com") }
        }
        if let email = unshown(author.emails) {
            throw Failure(message: "Your commits would now show \(email) on GitHub, which this didn't say. Close this and try again.")
        }
        // commit-tree signs only when asked.
        let made = author.signs && arguments.first == "commit-tree" ? ["commit-tree", "-S"] + arguments.dropFirst() : arguments
        let ran = await Subprocess.run(git, author.options + options + made, cwd: folder, mergeErrors: false, timeout: 120)
        guard ran.ok else {
            let why = (ran.errors + ran.output).trimmed.suffix(200)
            throw Failure(message: author.signs ? "Your git signs your commits and couldn't sign this one: \(why)" : "Couldn't make the commit: \(why)")
        }
        let commit = arguments.first == "commit-tree" ? ran.output.trimmed
            : (await Subprocess.run(git, ["rev-parse", "HEAD"], cwd: folder, mergeErrors: false, timeout: 10)).output.trimmed
        guard let commit = Credits.validCommit(commit) else { throw Failure(message: "Couldn't make the commit.") }
        // What the commit carries, as written, read from the object itself, which no display setting changes: nothing
        // is sent under an address that wasn't said, nor unsigned when it should be signed.
        let object = await Subprocess.run(git, ["cat-file", "commit", commit], cwd: folder, mergeErrors: false, timeout: 10)
        let header = object.output.components(separatedBy: "\n\n").first ?? ""
        let emails = header.split(separator: "\n").filter { $0.hasPrefix("author ") || $0.hasPrefix("committer ") }.compactMap { line -> String? in
            guard let open = line.firstIndex(of: "<"), let close = line[open...].firstIndex(of: ">") else { return nil }
            return String(line[line.index(after: open)..<close])
        }
        guard object.ok, emails.count == 2, emails.allSatisfy(author.emails.contains) else {
            throw Failure(message: "Git made the commit under \(emails.joined(separator: " and ")), which this didn't say, so it wasn't sent.")
        }
        if author.signs, !header.contains("\ngpgsig") {
            throw Failure(message: "Your git signs your commits, but this one came out unsigned, so it wasn't sent.")
        }
        return commit
    }

    /// Signed in through gh, for these commands alone: nothing is kept in a git configuration.
    static func signedIn(gh: String) -> [String] {
        ["-c", "credential.helper=", "-c", "credential.helper=!\(gh) auth git-credential"]
    }

    /// Keeps what went up, and passes it on: the repository's website, and the chat beside each installed app, which
    /// names the repository and commit for a remix (`Sidebar.install`).
    @MainActor static func settle(_ kept: Repo, before: Repo?, of project: LampProject, gh: String) async {
        keep(kept, for: project)
        if kept.isPublic == true { await offerWebsite(kept.repo, page: kept.page, gh: gh) }
        if before?.repo != kept.repo || before?.commit != kept.commit || before?.isPublic != kept.isPublic || before?.version != kept.version {
            for app in Store.shared.apps(of: project) { Store.shared.refreshInstalled(app) }
        }
    }

    /// A public repository with no website of its own gets one, which GitHub shows beside its description: a game's page
    /// once it's up (in place of the remix link Lamp set before it had one), else the remix link. One the person set is
    /// never changed.
    static func offerWebsite(_ repo: String, page: String?, gh: String) async {
        let now = await Subprocess.run(gh, ["repo", "view", repo, "--json", "homepageUrl", "--jq", ".homepageUrl"], mergeErrors: false, timeout: 30)
        let remix = remixLink(repo, from: "github")
        let current = now.output.trimmed
        guard now.ok, current.isEmpty || (page != nil && current == remix) else { return }
        let website = page ?? remix
        guard website != current else { return }
        _ = await Subprocess.run(gh, ["repo", "edit", repo, "--homepage", website], timeout: 30)
    }

    /// The person's own repository the wish was opened from (`AppUpdates.origin`: a wish or a plain site opened from
    /// GitHub, never a project the agent made a wish from), as GitHub has it now: a release puts the wish back there
    /// rather than beside it, so a site's Pages address goes on working. Nil for anyone else's, or one GitHub doesn't
    /// answer for.
    /// `behind` says why it can't go up yet: the repository has moved on from the commit the wish has.
    static func ownOrigin(of project: LampProject, login: String, gh: String) async -> (repo: String, isPublic: Bool, commit: String?, behind: String?)? {
        guard let origin = AppUpdates.origin(of: project), let url = origin.url, let source = RepoImport.source(from: url), source.ref == nil,
              source.owner.lowercased() == login.lowercased() else { return nil }
        let repo = "\(source.owner)/\(source.name)"
        guard let isPublic = await isPublic(repo, gh: gh) else { return nil }
        let head = await Subprocess.run(git, signedIn(gh: gh) + ["ls-remote", "https://github.com/\(repo).git", "HEAD"], mergeErrors: false, timeout: 60)
        let now = head.output.split(whereSeparator: \.isWhitespace).first.map(String.init)
        let behind = head.ok && now != nil && now != origin.commit
            ? "\(repo) has changes on GitHub that \(project.name) doesn't have yet. Check for Updates… first, then try again." : nil
        return (repo, isPublic, origin.commit, behind)
    }

    /// Whether anyone can read the repository, as GitHub says now; nil when it can't be asked.
    static func isPublic(_ repo: String, gh: String) async -> Bool? {
        let answer = await Subprocess.run(gh, ["repo", "view", repo, "--json", "visibility", "--jq", ".visibility"], mergeErrors: false, timeout: 30)
        guard answer.ok else { return nil }
        return answer.output.trimmed.uppercased() == "PUBLIC"
    }

    static func head(_ git: String, in folder: URL) async -> String? {
        let head = await Subprocess.run(git, ["rev-parse", "HEAD"], cwd: folder, mergeErrors: false, timeout: 10)
        return head.ok ? Credits.validCommit(head.output.trimmed) : nil
    }
}
