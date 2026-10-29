import AppKit
import Foundation
import LampFileLook
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
    /// Nil from a Lamp before the choice was kept, read as no license. `commit` is the one the last Put on GitHub
    /// pushed, which a later share names on the chain (`Sharing.export`); nil from a Lamp before it was kept.
    /// `isPublic` is what GitHub said after the last push, and `version` the wish's own version that push carried: a
    /// remix starts from the repository only while both hold (`remixOrigin`). Nil from a Lamp before they were kept.
    struct Repo: Codable, Equatable {
        var repo: String   // "owner/name"
        var url: String
        var license: Bool? = nil
        var commit: String? = nil
        var isPublic: Bool? = nil
        var version: String? = nil
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
        /// The wish's own version this is of, kept with the repository once it's up (`Repo.version`).
        var version: String? = nil
        /// Where the README's Open in Lamp goes, in a public repository (`remixLink`): what the card names as its remix
        /// link, in place of the Share Link a private one's README uses.
        var remix: String? = nil
    }

    /// Stages the repository for `repo`, its README's remix link going to `link` (the wish's Share Link, which works
    /// for someone without Lamp) when there is one: refused, with why, when the wish can't leave this Mac.
    /// Without a repository it's staged as it would be for one not yet made (a check of what it would hold,
    /// `GitHubProjects.check`): the chain ends with the wish as its shared file does, and the README names no address.
    /// `isPublic` is whether anyone will be able to read the repository: its README then offers it by a link of Lamp's
    /// site (`Showcase.remix`), which Lamp fetches without a sign-in.
    static func stage(_ project: LampProject, repo: String?, link: URL?, isPublic: Bool = true) throws -> Staged {
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
        let shared = try Sharing.export(project, repository: repo.map(url), commit: kept(for: project).flatMap { $0.repo == repo ? $0.commit : nil })
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
        // The icon the shared file carries, as it's drawn: never a picture of the app running, which could show the
        // person's data.
        let icon = fm.fileExists(atPath: tree.appendingPathComponent(LampFile.iconEntry).path) ? LampFile.iconEntry : nil
        // The ideas its chat offers beside it on a Mac without Lamp (`RemixSuggestions`), each a remix of its own.
        let ideas = (RemixSuggestions.load(project) ?? []).map(\.text)
        var showcase = Showcase(icon: icon, ideas: ideas)
        if isPublic, repo != nil { try writeButtons(in: tree); showcase.remix = true }
        try Data(readme(for: project, credits: credits, open: open, build: build, repo: repo, showcase: showcase).utf8)
            .write(to: tree.appendingPathComponent("README.md"))

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
        return Staged(folder: tree, files: all.filter { !$0.hasDirectoryPath }.count, bytes: bytes, credits: chain, open: open,
                      version: version, remix: showcase.remix ? repo.map { remixLink($0) } : nil)
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

    /// What a README shows of the wish before anything about Lamp: pictures and ideas, by their paths in the
    /// repository. A person's own wish shows its icon only: a picture of it running could show their data. A starter
    /// shows its preview (example content only), what to try with it, and where to play it when it's a game.
    struct Showcase {
        var icon: String? = nil
        var preview: String? = nil
        /// Where it plays in a browser, for a game whose page is up.
        var play: String? = nil
        /// What to ask for first, and the line that offers them ("Make Hours fit your work").
        var ideas: [String] = []
        var ideasTitle: String? = nil
        /// The repository carries an MIT license.
        var license = false
        /// Anyone can read the repository, so the README offers it by a link of Lamp's site, which opens Lamp on a fresh
        /// copy (`RemixLink.site`), with the button `writeButtons` drew; each idea is such a link with its request. A private one is opened from its file instead, since Lamp fetches a repository without a sign-in.
        var remix = false
    }

    /// The README's buttons, in the repository's pictures (`Starters.picturesFolder`): Open in Lamp, and for a game
    /// with a page, Play in your browser before it, since someone who hasn't tried a thing wants to try it first.
    static let openButton = ".github/open-in-lamp.svg"
    static let playButton = ".github/play-in-browser.svg"

    /// The buttons drawn as lamp.dev's are, words alone: Open in Lamp in the paper's color on ink, Play in your browser
    /// in ink on the stripes' yellow. Each is edged so it holds on GitHub's dark theme as on its light one.
    static let openWidth = 164, playWidth = 220

    static func writeButtons(in tree: URL) throws {
        func button(_ words: String, width: Int, fill: String, ink: String, edge: String) -> String {
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="48" viewBox="0 0 \(width) 48" role="img" aria-label="\(words)">\
            <rect x="1" y="1" width="\(width - 2)" height="46" rx="6" fill="\(fill)" stroke="\(edge)" stroke-width="2"/>\
            <text x="\(width / 2)" y="30.5" text-anchor="middle" fill="\(ink)" \
            font-family="-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif" font-size="18" font-weight="800">\(words)</text></svg>

            """
        }
        let buttons = [(openButton, button("Open in Lamp", width: openWidth, fill: "#1b1a17", ink: "#f2ecda", edge: "#f2ecda")),
                       (playButton, button("Play in your browser", width: playWidth, fill: "#f6b81c", ink: "#1b1a17", edge: "#1b1a17"))]
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
            if let play = showcase.play { links.append("<a href=\"\(play)\"><b>Play it in your browser</b></a>") }
            links.append("<a href=\"#remix-it-with-lamp\">Remix it with Lamp</a>")
        }
        if build.alone { links.append("<a href=\"#build-it-yourself\">Build it yourself</a>") }
        // Trying it comes first, as buttons where the eye lands under the name: a game's page to play, then Lamp, which
        // opens a copy of it to use and to change.
        if let remix {
            var buttons: [String] = []
            if let play = showcase.play {
                buttons.append("<a href=\"\(Publish.escaped(play))\"><img src=\"\(playButton)\" width=\"\(playWidth)\" height=\"48\" alt=\"Play in your browser\"></a>")
            }
            buttons.append("<a href=\"\(Publish.escaped(remixLink(remix)))\"><img src=\"\(openButton)\" width=\"\(openWidth)\" height=\"48\" alt=\"Open in Lamp\"></a>")
            text += "<p align=\"center\">" + buttons.joined(separator: "&nbsp;&nbsp;") + "</p>\n\n"
        }
        if !links.isEmpty { text += "<p align=\"center\">" + links.joined(separator: " · ") + "</p>\n\n" }
        if let preview = showcase.preview { text += "<p align=\"center\"><img src=\"\(preview)\" width=\"720\" alt=\"\(name)\"></p>\n\n" }
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
                text += "[Make your own](\(link.absoluteString)) from this wish, with Lamp or by getting Lamp from that page. "
            }
            if let file = open.file {
                text += (open.link == nil ? "Download" : "Or download") + " [\(file)](\(file)) and open it with Lamp (double-click it, or File → Import Shared Wish…): "
                    + "you get this exact wish, yours to change, with the credits below kept. The code here is what that file holds."
            } else if let repo {
                text += (open.link == nil ? "In" : "Or, in") + " Lamp, choose File → Open from GitHub… and paste `\(url(repo))`: "
                    + "you get this exact wish, yours to change, with the credits below kept."
            }
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
        if showcase.license { text += "## License\n\nMIT. See [LICENSE](LICENSE).\n" }
        return text
    }

    /// An idea as a link's words: Markdown's own characters escaped, so a bracket can't end the link.
    static func markdownText(_ text: String) -> String {
        String(text.flatMap { "\\`*_[]<>#|".contains($0) ? ["\\", $0] : [$0] })
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
    /// there; `step` hears what it's doing. `changed` is false when the repository already had the wish as it is. The
    /// record returned names the commit up there now.
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
                                                 "--description", Sharing.description(of: project) ?? "\(project.name), made with Lamp"],
                                            timeout: 60)
            guard made.ok else { throw Failure(message: "GitHub didn't make \(repo): \(made.output.trimmed.suffix(200))") }
            // Kept as soon as it's made, so a try that fails after this goes on with the same repository rather than
            // leaving this one behind and making another.
            keep(Repo(repo: repo, url: url, license: license, commit: kept(for: project)?.commit), for: project)
        }
        let git = git
        let identity = identity(login: login)
        let signedIn = signedIn(gh: gh)
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
            // and the file is zipped afresh each time. The manifest's other fields matter (which device an app opens on),
            // so it's compared with only its time left out; the archive follows the manifest.
            // The chain names the commit up there (`Sharing.export`), which each push moves on: the credits compare
            // without it, so real credit changes count and the bookkeeping doesn't.
            if await Subprocess.run(git, ["diff", "--cached", "--quiet", "--", ".", ":(exclude)lamp-app.json", ":(exclude)*.lampapp", ":(exclude)\(Credits.file)"], cwd: clone, timeout: 60).ok {
                let before = await Subprocess.run(git, ["show", "HEAD:lamp-app.json"], cwd: clone, mergeErrors: false, timeout: 30)
                let credits = await Subprocess.run(git, ["show", "HEAD:\(Credits.file)"], cwd: clone, mergeErrors: false, timeout: 30)
                if before.ok, let after = try? Data(contentsOf: clone.appendingPathComponent("lamp-app.json")),
                   manifestsMatch(Data(before.output.utf8), after),
                   creditsMatch(credits.ok ? Data(credits.output.utf8) : nil, try? Data(contentsOf: clone.appendingPathComponent(Credits.file))) {
                    return (Repo(repo: repo, url: url, license: license, commit: await head(git, in: clone),
                                 isPublic: await isPublic(repo, gh: gh), version: staged.version), false)
                }
            }
            let committed = await Subprocess.run(git, identity + ["commit", "-q", "-m", "Update \(project.name) from Lamp"], cwd: clone, timeout: 120)
            guard committed.ok else { throw Failure(message: "Couldn't prepare the repository: \(committed.output.trimmed.suffix(200))") }
            work = clone
        }
        step("Uploading…")
        let pushed = await Subprocess.run(git, signedIn + ["push", "-q", remote, "HEAD:main"], cwd: work, timeout: 600)
        guard pushed.ok else { throw Failure(message: "GitHub didn't take it: \(pushed.output.trimmed.suffix(200))") }
        return (Repo(repo: repo, url: url, license: license, commit: await head(git, in: work),
                     isPublic: await isPublic(repo, gh: gh), version: staged.version), true)
    }

    /// The git that talks to GitHub for the person, with their own settings: Homebrew's when they have it, else Apple's.
    static var git: String {
        FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/git") ? "/opt/homebrew/bin/git" : "/usr/bin/git"
    }

    /// The commits are the person's, under their GitHub name.
    static func identity(login: String) -> [String] {
        ["-c", "user.name=\(login)", "-c", "user.email=\(login)@users.noreply.github.com"]
    }

    /// Signed in through gh, for these commands alone: nothing is kept in a git configuration.
    static func signedIn(gh: String) -> [String] {
        ["-c", "credential.helper=", "-c", "credential.helper=!\(gh) auth git-credential"]
    }

    /// The commit a work folder is at, as the credits take one.
    /// A public repository with no website of its own gets the remix link as one, which GitHub shows beside its
    /// description. One the person set is never changed.
    static func offerRemixAsWebsite(_ repo: String, gh: String) async {
        let now = await Subprocess.run(gh, ["repo", "view", repo, "--json", "homepageUrl", "--jq", ".homepageUrl"], mergeErrors: false, timeout: 30)
        guard now.ok, now.output.trimmed.isEmpty else { return }
        _ = await Subprocess.run(gh, ["repo", "edit", repo, "--homepage", remixLink(repo, from: "github")], timeout: 30)
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
            let isPublic: Bool
            // The README offers a remix by link only where anyone can read it: as GitHub says for one that's up, as
            // chosen for a new one (choosing again stages it again, `setPrivate`).
            if let known = GitHubRepo.kept(for: project)?.repo {
                repo = known
                isPublic = await GitHubRepo.isPublic(known, gh: gh) ?? false
            } else {
                repo = await Publish.freeName(for: project, login: login, gh: gh)
                isPublic = !(cards[project.id]?.isPrivate ?? false)
            }
            do {
                let staged = try await Task.detached(priority: .userInitiated) {
                    try GitHubRepo.stage(project, repo: repo, link: WishLink.kept(for: project)?.url, isPublic: isPublic)
                }.value
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

    func setPrivate(_ project: LampProject, _ isPrivate: Bool) {
        guard cards[project.id]?.isPrivate != isPrivate else { return }
        cards[project.id]?.isPrivate = isPrivate
        // A new repository's README offers a remix by link only if it's public: staged again for the choice.
        if cards[project.id]?.kept == nil { prepare(project) }
    }
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
                let before = GitHubRepo.kept(for: project)
                GitHubRepo.keep(kept, for: project)
                // The chat beside the installed app names the repository and commit for a remix (`Sidebar.install`).
                if kept.isPublic == true { await GitHubRepo.offerRemixAsWebsite(kept.repo, gh: gh) }
                if before?.repo != kept.repo || before?.commit != kept.commit || before?.isPublic != kept.isPublic || before?.version != kept.version {
                    for app in Store.shared.apps(of: project) { Store.shared.refreshInstalled(app) }
                }
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
        // What the README offers: in a public repository the repository itself on lamp.dev, so no Share Link is asked
        // for; in a private one the Share Link, when there is one.
        let link = card.staged?.open.link ?? WishLink.kept(for: project)?.url
        let remix = card.staged?.remix.flatMap(URL.init(string:)).flatMap { url in
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "repo" }?.value
                .map { "lamp.dev, from " + $0.replacingOccurrences(of: "https://", with: "") }
        }
        return SidebarRepo(name: project.name, icon: card.icon, stage: card.stage, repo: card.repo, url: card.kept?.url,
                           credit: credits.basedOn, openInLamp: remix ?? link.map { url in url.host.map { $0 + url.path } ?? url.absoluteString },
                           notes: notes, size: size, copied: card.copied,
                           update: card.kept != nil, canPut: card.canPut, isPrivate: card.isPrivate, license: card.license,
                           canChooseLicense: card.staged.map { GitHubRepo.canOfferLicense($0.credits) } ?? true)
    }
}
