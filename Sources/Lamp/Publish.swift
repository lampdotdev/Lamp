import AppKit
import Foundation
import LampSidebarKit

/// Publishing a game drawn with three.js as a page anyone can play in a browser: a public repository on the person's own
/// GitHub account, served by GitHub Pages, made with GitHub's own command-line tool (`gh`) and their sign-in there.
/// Nothing goes through Lamp's servers: the person's account holds the page, under GitHub's terms, and Lamp pays nothing
/// for its plays.
///
/// What goes up is the game's page (Web/) as the app plays it, with a credit bar over it ("Based on Slop New York by
/// Mr.doob", and Open in Lamp, the wish's Share Link), the wish's credits.json, a README saying what
/// it is, what it's based on and under which licenses, and the shared file itself, made by `Sharing.export` and so held
/// to the same checks (`ShareCheck`). The page is searched for keys and secrets the same way before anything leaves.
/// The person sees all of it on the card (`PublishCard`) and confirms before anything goes up.
///
/// An experiment for now (Settings → Experimental, Lamp Dev only): the page carries Lamp's own runtime (lamp-game.js,
/// lamp.js), which needs a license that lets anyone pass it on before it can be published from every Lamp.
enum Publish {
    nonisolated static let switchKey = "experimentPublishPages"
    nonisolated static var enabled: Bool { Edition.isDev && UserDefaults.standard.bool(forKey: switchKey) }

    /// A wish whose one app is a game drawn with three.js: its page is the whole game.
    static func canPublish(_ project: LampProject) -> Bool {
        enabled && project.holdsApp && GameKit.isGame(project) && GameKit.engine(project) == .web
            && Parts.folders(in: project.dir).isEmpty
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Where it went

    /// A page that's up: the repository and its address.
    struct Page: Codable, Equatable {
        var repo: String   // "owner/name"
        var url: String
    }

    private static var keptURL: URL { Edition.supportFolder.appendingPathComponent("Published Pages.json") }
    private static func key(_ project: LampProject) -> String { project.instance.isEmpty ? project.id : project.instance }

    static func kept(for project: LampProject) -> Page? { readKept()[key(project)] }

    static func keep(_ page: Page, for project: LampProject) {
        var all = readKept()
        all[key(project)] = page
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: keptURL, options: .atomic) }
    }

    private static func readKept() -> [String: Page] {
        (try? Data(contentsOf: keptURL)).flatMap { try? JSONDecoder().decode([String: Page].self, from: $0) } ?? [:]
    }

    // MARK: GitHub

    /// Where `gh` is: Homebrew's, or wherever the person's shell finds it.
    static func gh() async -> String? {
        for path in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"] where FileManager.default.isExecutableFile(atPath: path) { return path }
        let found = await Subprocess.run("/bin/zsh", ["-lc", "command -v gh"], timeout: 10)
        let path = found.output.trimmed
        return found.ok && path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// The account `gh` is signed in to, or nil.
    static func login(gh: String) async -> String? {
        let answer = await Subprocess.run(gh, ["api", "user", "--jq", ".login"], mergeErrors: false, timeout: 30)
        let login = answer.output.trimmed
        return answer.ok && !login.isEmpty && login.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) ? login : nil
    }

    /// The repository's name for a wish: its name, lowercased, words joined with hyphens ("New York" → "new-york").
    static func slug(_ name: String) -> String {
        let words = name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        let slug = words.joined(separator: "-")
        return slug.isEmpty ? "lamp-wish" : String(slug.prefix(80))
    }

    // MARK: The page

    /// Where the page's Open in Lamp goes. Its Share Link first (`WishLink`), once the person has made one (the card offers
    /// to, through Share Link's own card, where they see and change what it shows): that page works for someone without
    /// Lamp (Download Lamp carries the wish into its welcome) and with it ("Open it with this wish"). With no link, the
    /// wish as a shared file, which goes beside the page either way, for the README's download: the exact game.
    struct OpenInLamp: Equatable {
        var link: URL?
        var file: String?
    }

    /// What will go up, staged in a folder of its own, checked.
    struct Staged {
        let folder: URL          // its parent is removed with it
        let files: Int
        let bytes: Int
        let credits: Credits
        let open: OpenInLamp
    }

    /// Stages the page for `repo` at `url`: refused, with why, when the wish can't leave this Mac.
    static func stage(_ project: LampProject, url: String, link: URL?) throws -> Staged {
        let fm = FileManager.default
        let credits = Credits.load(project)
        if let refusal = ShareCheck.refusal(of: project, credits: credits) { throw refusal }
        let work = Sharing.workFolder.appendingPathComponent("lamp-publish-\(UUID().uuidString)")
        let site = work.appendingPathComponent("site")
        var done = false
        defer { if !done { try? fm.removeItem(at: work) } }
        try fm.createDirectory(at: site, withIntermediateDirectories: true)

        // The page as the app plays it: Web/, its own files and Lamp's runtime beside them, never a hidden file or a link.
        let web = project.dir.appendingPathComponent(GameKit.webFolder)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let items = fm.enumerator(at: web, includingPropertiesForKeys: keys) else { throw Failure(message: "\(project.name) has no page to publish.") }
        for case let file as URL in items {
            if file.lastPathComponent.hasPrefix(".") { items.skipDescendants(); continue }
            let values = try? file.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
            let target = site.appendingPathComponent(Sharing.relativePath(of: file, in: web))
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: file, to: target)
        }
        // Played in whatever browser opens it, so it's told no one device's facts (`GamePage.anyBrowser`).
        let anyBrowser = GamePage.anyBrowser
        try GamePage.stage(site, in: site) { try GamePage.descriptor(id: anyBrowser.id, name: anyBrowser.name, input: anyBrowser.input) }
        let index = site.appendingPathComponent("index.html")
        guard let html = try? String(contentsOf: index, encoding: .utf8) else { throw Failure(message: "\(project.name) has no page to publish.") }

        // The wish itself, as a file Lamp opens, beside the page, made as any shared file is, so it's held to the same
        // checks and carries the credits with this wish at the end of the chain.
        let fileName = slug(project.name) + ".lampapp"
        let shared = try Sharing.export(project)
        defer { try? fm.removeItem(at: shared.deletingLastPathComponent()) }
        try fm.copyItem(at: shared, to: site.appendingPathComponent(fileName))
        let open = OpenInLamp(link: link, file: fileName)
        let chain = credits.remixed(from: Credits.Remix(name: project.name, wish: Sharing.identity(of: project)))
        try chain.encoded().write(to: site.appendingPathComponent(Credits.file))

        try Data(withCreditBar(html, credits: credits, open: open, suggestions: RemixSuggestions.load(project) ?? RemixOffer.fallback,
                               name: project.name, about: AppDescription.description(of: project)).utf8).write(to: index)
        try Data(readme(for: project, credits: chain, url: url, open: open).utf8).write(to: site.appendingPathComponent("README.md"))
        // Served as files are, with nothing taken out for Jekyll (folders that start with _ included).
        try Data().write(to: site.appendingPathComponent(".nojekyll"))

        let leaks = ShareCheck.secrets(in: site, known: Sharing.knownSecrets(project))
        if let first = leaks.first {
            throw Sharing.ImportError("\(project.name) can't be published: it holds a key or a password.",
                                      detail: "It's in \(first). Ask Lamp to take it out and keep it out of the code.")
        }
        let all = fm.enumerator(at: site, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { $0 as? URL } ?? []
        let bytes = all.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        // GitHub refuses a file over 100 MB, and a Pages site over 1 GB.
        guard bytes < 900_000_000 else { throw Failure(message: "\(project.name) is too big to publish as a page.") }
        done = true
        return Staged(folder: site, files: all.filter { !$0.hasDirectoryPath }.count, bytes: bytes, credits: chain, open: open)
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The page with Lamp's credit bar over it: what it's based on, linked, and Open in Lamp. It starts at the top in the
    /// middle, over the game's loading, and after a few seconds settles into a thin line on the bottom edge, where a
    /// game's own controls rarely are, so it never sits over a button the game draws.
    static func withCreditBar(_ html: String, credits: Credits, open: OpenInLamp, suggestions: [RemixIdea] = RemixOffer.fallback,
                              name: String = "", about: String? = nil) -> String {
        var parts: [String] = []
        if let source = credits.upstream.first {
            let name = source.url.map { "<a href=\"\(escaped($0))\" target=\"_blank\" rel=\"noopener\">\(escaped(source.name))</a>" } ?? escaped(source.name)
            parts.append("Based on \(name)" + (source.author.map { " by \(escaped($0))" } ?? ""))
        }
        if !credits.generated.isEmpty { parts.append(escaped(Credits.generatedLine(credits.generated.count))) }
        if let link = open.link {
            parts.append("<a href=\"\(escaped(link.absoluteString))\" target=\"_blank\" rel=\"noopener\">Open in Lamp</a>")
        } else if let file = open.file {
            // The file means nothing without Lamp, so Lamp's site is beside it.
            parts.append("<a href=\"\(escaped(file))\" download>Open in Lamp</a>")
            parts.append("<a href=\"https://lamp.dev\" target=\"_blank\" rel=\"noopener\">Get Lamp</a>")
        } else {
            parts.append("<a href=\"https://lamp.dev\" target=\"_blank\" rel=\"noopener\">Made with Lamp</a>")
        }
        // Remix…: a panel over the page with three things to change and a box for the player's own words. Continue with
        // Lamp opens the wish's Share Link page with the request (which gives this exact wish, with Lamp or by getting
        // it), or Lamp's site with a request that names the game. Nothing leaves the page until that press.
        parts.append("<a href=\"#\" id=\"lamp-remix-open\">Remix…</a>")
        let offer = RemixOffer(name: name, about: about, suggestions: suggestions, shareLink: open.link)
        let target: [String: Any] = ["link": open.link?.absoluteString as Any, "request": RemixLink.request(for: offer, ask: "{ask}")]
        let targetJSON = (try? JSONSerialization.data(withJSONObject: target)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let buttons = offer.suggestions.map { "<button type=\"button\" class=\"lamp-remix-pick\">\(escaped($0.text))</button>" }.joined()
        let panel = """
            <div id="lamp-remix" hidden>
              <div class="lamp-remix-head">Make \(escaped(name.isEmpty ? "it" : name)) yours<button type="button" id="lamp-remix-close" aria-label="Close">×</button></div>
              <p>Say what you'd change. Lamp makes the change and keeps your data.</p>
              \(buttons)
              <textarea id="lamp-remix-ask" rows="3" placeholder="Or say it your way"></textarea>
              <button type="button" id="lamp-remix-go" disabled>Continue with Lamp</button>
              <p class="lamp-remix-note">\(open.link == nil ? "Opens lamp.dev with your request. Lamp is a free Mac app; it makes its own version and changes it as you ask." : "Opens this wish's page with your request. Lamp is a free Mac app; it opens on this exact wish and changes it as you ask.")</p>
            </div>
            <script type="application/json" id="lamp-remix-target">\(targetJSON.replacingOccurrences(of: "<", with: "\\u003c"))</script>
            <script>
            (function(){var o=document.getElementById('lamp-remix-open'),p=document.getElementById('lamp-remix'),a=document.getElementById('lamp-remix-ask'),g=document.getElementById('lamp-remix-go');
            if(!o||!p||!a||!g)return;var t=JSON.parse(document.getElementById('lamp-remix-target').textContent||'{}');
            o.addEventListener('click',function(e){e.preventDefault();p.hidden=!p.hidden;if(!p.hidden)a.focus();});
            document.getElementById('lamp-remix-close').addEventListener('click',function(){p.hidden=true;});
            var picks=p.querySelectorAll('.lamp-remix-pick');for(var i=0;i<picks.length;i++)picks[i].addEventListener('click',function(e){a.value=e.currentTarget.textContent;g.disabled=false;a.focus();});
            a.addEventListener('input',function(){g.disabled=!a.value.trim();});
            g.addEventListener('click',function(){var ask=a.value.trim().slice(0,\(RemixLink.askLimit));if(!ask)return;
              var u=new URL(t.link||'https://lamp.dev/');u.searchParams.set('ask',t.link?ask:String(t.request||'{ask}').replace('{ask}',ask));window.open(u.href,'_blank','noopener');});})();
            </script>
            """
        let bar = """

            <div id="lamp-credit">\(parts.joined(separator: " · "))</div>
            \(panel)
            <style>
            #lamp-credit{position:fixed;top:10px;left:50%;transform:translateX(-50%);z-index:2147483647;width:max-content;
              max-width:calc(100vw - 24px);box-sizing:border-box;text-align:center;font:500 12px/1.4 -apple-system,system-ui,sans-serif;color:#fff;
              background:rgba(0,0,0,.6);padding:5px 14px;border-radius:999px;transition:all .8s;pointer-events:none}
            #lamp-credit a{color:#fff;text-decoration:underline;pointer-events:auto}
            #lamp-credit.settled{top:auto;bottom:0;font-size:10px;padding:1px 10px;border-radius:6px 6px 0 0;background:rgba(0,0,0,.45);opacity:.8}
            #lamp-remix{position:fixed;right:12px;bottom:28px;z-index:2147483647;width:min(320px,calc(100vw - 24px));box-sizing:border-box;padding:14px 16px;
              border-radius:14px;background:rgba(20,20,22,.94);color:#fff;font:13px/1.45 -apple-system,system-ui,sans-serif;box-shadow:0 12px 40px rgba(0,0,0,.4)}
            #lamp-remix[hidden]{display:none}
            #lamp-remix .lamp-remix-head{display:flex;justify-content:space-between;align-items:center;font-size:15px;font-weight:600;margin-bottom:4px}
            #lamp-remix .lamp-remix-head button{background:none;border:0;color:#fff;font-size:18px;cursor:pointer;opacity:.7}
            #lamp-remix p{margin:0 0 10px;opacity:.8}
            #lamp-remix .lamp-remix-note{margin:10px 0 0;font-size:11px;opacity:.6}
            #lamp-remix .lamp-remix-pick{display:block;width:100%;text-align:left;margin:0 0 6px;padding:7px 10px;border-radius:8px;border:1px solid rgba(255,255,255,.18);
              background:rgba(255,255,255,.08);color:#fff;font:inherit;cursor:pointer}
            #lamp-remix .lamp-remix-pick:hover{background:rgba(255,255,255,.16)}
            #lamp-remix textarea{display:block;width:100%;box-sizing:border-box;margin:6px 0 10px;padding:8px 10px;border-radius:8px;border:1px solid rgba(255,255,255,.18);
              background:rgba(255,255,255,.08);color:#fff;font:inherit;resize:vertical}
            #lamp-remix #lamp-remix-go{display:block;width:100%;padding:9px 12px;border-radius:8px;border:0;background:#f0a04b;color:#1a1a1a;font:600 13px/1 -apple-system,system-ui,sans-serif;cursor:pointer}
            #lamp-remix #lamp-remix-go[disabled]{opacity:.45;cursor:default}
            </style>
            <script>setTimeout(function(){var c=document.getElementById('lamp-credit');if(c)c.className='settled'},8000)</script>

            """
        if let end = html.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            return html.replacingCharacters(in: end.lowerBound..<end.lowerBound, with: bar)
        }
        return html + bar
    }

    /// The repository's README: what the page is, where to play it, what it's based on and under which licenses.
    static func readme(for project: LampProject, credits: Credits, url: String, open: OpenInLamp) -> String {
        var text = "# \(project.name)\n\n"
        if let line = AppDescription.description(of: project) { text += line + "\n\n" }
        text += "**Play it:** \(url)\n\n"
        text += creditsSection(credits)
        text += "## Open in Lamp\n\nMade with [Lamp](https://lamp.dev)."
        if let link = open.link { text += " [Make your own](\(link.absoluteString)) from the same wish, with Lamp or by downloading it." }
        if let file = open.file { text += " Or download [\(file)](\(file)) and open it with Lamp: it's this exact wish, yours to remix, with the credits above kept." }
        text += "\n\n"
        text += "`lamp-game.js`, `lamp-phaser.js`, `lamp-controllers.js`, `lamp-device.js`, `lamp.js`, `three/` and `phaser/` are the game's runtime, written by Lamp; three.js is MIT (`three/LICENSE`), and so is Phaser (`phaser/LICENSE.md`).\n"
        return text
    }

    /// What a README says of the wish's credits: what it's based on and under which licenses, what else it uses, the
    /// pictures made with AI and the wishes it was remixed from. Empty for a wish with none.
    static func creditsSection(_ credits: Credits) -> String {
        var text = ""
        if !credits.upstream.isEmpty {
            text += "## Credits\n\n"
            for (index, source) in credits.upstream.enumerated() {
                let name = source.url.map { "[\(source.name)](\($0))" } ?? source.name
                var line = (index == 0 ? "Based on " : "Uses ") + name + (source.author.map { " by \($0)" } ?? "")
                if let license = source.license { line += ", \(license)" }
                if let commit = source.commit { line += ", at commit `\(commit.prefix(12))`" }
                if let file = source.licenseFile { line += " (license: `\(file.hasPrefix("Web/") ? String(file.dropFirst(4)) : file)`)" }
                text += "- \(line)\n"
            }
            text += "\n"
            for note in ShareCheck.notes(for: credits) { text += note + "\n\n" }
        }
        if !credits.generated.isEmpty {
            text += "\(Credits.generatedLine(credits.generated.count)), each marked as such in the file itself: "
                + credits.generated.map { "`\($0.file)`" }.joined(separator: ", ") + ".\n\n"
        }
        if !credits.remixOf.isEmpty {
            text += "Remixed from " + credits.remixOf.map { $0.name + ($0.starter != nil ? " (a Lamp starter)" : "") }.joined(separator: ", then ") + ".\n\n"
        }
        return text
    }

    /// The wish's name as a repository the account doesn't have yet: "new-york", else "new-york-2" and on.
    static func freeName(for project: LampProject, login: String, gh: String) async -> String {
        let base = slug(project.name)
        for n in 1...20 {
            let name = "\(login)/\(n == 1 ? base : "\(base)-\(n)")"
            if !(await Subprocess.run(gh, ["repo", "view", name, "--json", "name"], timeout: 30)).ok { return name }
        }
        return "\(login)/\(base)-\(UUID().uuidString.prefix(6).lowercased())"
    }

    /// Gets what a card needs from GitHub: gh's site to install it from, or a sign-in. gh signs in on github.com in the
    /// browser, from a terminal it asks a question in, so Terminal comes to the front with it; once the sign-in is seen
    /// (checked every few seconds for up to five minutes, while `stillNeeded`), `signedIn` is called.
    @MainActor static func obtain(_ need: PublishCard.Need, stillNeeded: @escaping @MainActor () -> Bool, signedIn: @escaping @MainActor () -> Void) {
        switch need {
        case .install: NSWorkspace.shared.open(URL(string: "https://cli.github.com")!)
        case .signIn:
            Task {
                guard let gh = await gh() else { return }
                let script = "tell application \"Terminal\" to do script \"'\(gh)' auth login --web --git-protocol https --hostname github.com\""
                    + "\ntell application \"Terminal\" to activate"
                _ = await Subprocess.run("/usr/bin/osascript", ["-e", script], timeout: 20)
                for _ in 0..<100 {
                    try? await Task.sleep(for: .seconds(3))
                    guard stillNeeded() else { return }
                    if await login(gh: gh) != nil { return signedIn() }
                }
            }
        }
    }

    // MARK: Putting it up

    /// Puts the staged page in `repo` (made, public, if it's new) and turns on Pages; `step` hears what it's doing.
    static func upload(_ staged: Staged, of project: LampProject, to repo: String, gh: String, login: String, isNew: Bool,
                       step: @escaping @Sendable (String) -> Void) async throws -> Page {
        let url = pageURL(repo)
        if isNew {
            step("Making \(repo)…")
            let made = await Subprocess.run(gh, ["repo", "create", repo, "--public", "--homepage", url,
                                                 "--description", AppDescription.description(of: project) ?? "\(project.name), made with Lamp"],
                                            timeout: 60)
            guard made.ok else { throw Failure(message: "GitHub didn't make \(repo): \(made.output.trimmed.suffix(200))") }
            // Kept as soon as it's made, so a publish that fails after this tries the same repository again rather than
            // leaving this one behind and making another.
            keep(Page(repo: repo, url: url), for: project)
        }
        step("Uploading…")
        let git = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/git") ? "/opt/homebrew/bin/git" : "/usr/bin/git"
        let site = staged.folder
        let identity = ["-c", "user.name=\(login)", "-c", "user.email=\(login)@users.noreply.github.com"]
        // A try after a failed one finds the page committed already, and pushes that commit again.
        var committed = false
        if FileManager.default.fileExists(atPath: site.appendingPathComponent(".git").path) {
            committed = await Subprocess.run(git, ["rev-parse", "--verify", "-q", "HEAD"], cwd: site, timeout: 10).ok
        }
        for arguments in committed ? [] : [["init", "-q", "-b", "main"], ["add", "-A"], identity + ["commit", "-q", "-m", "Publish \(project.name)"]] {
            let ran = await Subprocess.run(git, arguments, cwd: site, timeout: 120)
            guard ran.ok else { throw Failure(message: "Couldn't prepare the page: \(ran.output.trimmed.suffix(200))") }
        }
        // Signed in through gh, for this push alone: nothing is kept in a git configuration.
        let pushed = await Subprocess.run(git, ["-c", "credential.helper=", "-c", "credential.helper=!\(gh) auth git-credential",
                                               "push", "-q", "--force", "https://github.com/\(repo).git", "HEAD:main"],
                                          cwd: site, timeout: 600)
        guard pushed.ok else { throw Failure(message: "GitHub didn't take the page: \(pushed.output.trimmed.suffix(200))") }
        let commit = (await Subprocess.run(git, ["rev-parse", "HEAD"], cwd: site, timeout: 10)).output.trimmed

        step("Turning on GitHub Pages…")
        let existing = await Subprocess.run(gh, ["api", "repos/\(repo)/pages"], timeout: 30)
        if !existing.ok {
            let on = await Subprocess.run(gh, ["api", "-X", "POST", "repos/\(repo)/pages", "-f", "source[branch]=main", "-f", "source[path]=/"],
                                          timeout: 30)
            guard on.ok else { throw Failure(message: "GitHub Pages couldn't be turned on: \(on.output.trimmed.suffix(200))") }
        } else {
            _ = await Subprocess.run(gh, ["api", "-X", "POST", "repos/\(repo)/pages/builds"], timeout: 30)
        }
        // Up only once GitHub says it built this very commit: an earlier build's "built" is the page as it was.
        step("Waiting for GitHub to put it up…")
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(5))
            let build = await Subprocess.run(gh, ["api", "repos/\(repo)/pages/builds/latest", "--jq", ".commit + \" \" + .status"],
                                             mergeErrors: false, timeout: 30)
            let parts = build.output.trimmed.split(separator: " ").map(String.init)
            guard parts.count == 2, parts[0] == commit else { continue }
            switch parts[1] {
            case "built": return Page(repo: repo, url: url)
            case "errored": throw Failure(message: "GitHub couldn't put the page up. Try again in a moment.")
            default: continue
            }
        }
        throw Failure(message: "GitHub is still putting the page up. It should be at \(url) in a few minutes; Publish again if it isn't.")
    }

    static func pageURL(_ repo: String) -> String {
        let parts = repo.split(separator: "/")
        return "https://\(parts[0].lowercased()).github.io/\(parts[1])/"
    }
}

/// The Publish card of each wish while it's open, in the chat's place. Preparing it finds `gh` and the person's sign-in
/// and stages the page with its checks, so the card shows exactly what will go up before the person confirms.
@MainActor final class PublishCards: ObservableObject {
    static let shared = PublishCards()

    struct Card {
        var stage: PublishCard.Stage = .preparing
        var repo: String?
        var login: String?
        var gh: String?
        var staged: Publish.Staged?
        var page: Publish.Page?
        var copied = false
        var icon: Data?

        /// Ready, or failed with the page still staged, so Publish tries again.
        var canPublish: Bool {
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
        cards[project.id] = Card(page: Publish.kept(for: project))
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
            let kept = Publish.kept(for: project)
            let repo: String
            if let known = kept?.repo { repo = known } else { repo = await Publish.freeName(for: project, login: login, gh: gh) }
            do {
                let staged = try await Task.detached(priority: .userInitiated) { try Publish.stage(project, url: Publish.pageURL(repo), link: WishLink.kept(for: project)?.url) }.value
                guard cards[project.id] != nil else {
                    try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent())
                    return
                }
                cards[project.id]?.gh = gh
                cards[project.id]?.login = login
                cards[project.id]?.repo = repo
                cards[project.id]?.staged = staged
                cards[project.id]?.stage = .ready
            } catch {
                set(project, .refused(((error as? LocalizedError)?.recoverySuggestion).map { "\(error.localizedDescription) \($0)" } ?? error.localizedDescription))
            }
        }
    }

    private func set(_ project: LampProject, _ stage: PublishCard.Stage) { cards[project.id]?.stage = stage }

    func publish(_ project: LampProject) {
        guard let card = cards[project.id], card.canPublish, let staged = card.staged, let repo = card.repo,
              let gh = card.gh, let login = card.login else { return }
        // A first try that made the repository before failing kept it (`upload`): this goes on with it.
        let isNew = (card.page ?? Publish.kept(for: project))?.repo != repo
        set(project, .publishing("Starting…"))
        Task {
            do {
                let id = project.id
                let page = try await Publish.upload(staged, of: project, to: repo, gh: gh, login: login, isNew: isNew) { step in
                    Task { @MainActor in PublishCards.shared.cards[id]?.stage = .publishing(step) }
                }
                Publish.keep(page, for: project)
                try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent())
                cards[project.id]?.staged = nil
                cards[project.id]?.page = page
                set(project, .published)
            } catch {
                // The page stays staged, so Publish can try again; a repository made on the way is kept (`upload`).
                cards[project.id]?.page = Publish.kept(for: project) ?? cards[project.id]?.page
                set(project, .failed(error.localizedDescription))
            }
        }
    }

    /// Share Link's card in the Publish card's place, for the person to see and change what the link shows before it's
    /// made: Publish never sends the wish's words or picture itself. Publish is opened again once the link is out.
    func makeLink(_ project: LampProject) {
        close(project)
        WishLinkCards.shared.open(project, inSidebar: true)
    }

    func fix(_ project: LampProject) {
        guard case .needsGitHub(let need) = cards[project.id]?.stage else { return }
        Publish.obtain(need, stillNeeded: { [weak self] in
            if case .needsGitHub = self?.cards[project.id]?.stage { return true } else { return false }
        }, signedIn: { [weak self] in self?.prepare(project) })
    }

    func openPage(_ project: LampProject) {
        if let url = cards[project.id]?.page?.url ?? Publish.kept(for: project)?.url, let page = URL(string: url) { NSWorkspace.shared.open(page) }
    }

    func copy(_ project: LampProject) {
        guard let url = cards[project.id]?.page?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        cards[project.id]?.copied = true
    }

    func close(_ project: LampProject) {
        if let staged = cards[project.id]?.staged { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        cards[project.id] = nil
    }

    /// The card as the chat draws it.
    func wire(_ card: Card, of project: LampProject) -> SidebarPublish {
        let credits = card.staged?.credits ?? Credits.load(project)
        var notes = ShareCheck.notes(for: credits)
        if !credits.generated.isEmpty { notes.append(Credits.generatedLine(credits.generated.count) + ", marked as such.") }
        let size = card.staged.map { "\($0.files) files · " + ByteCountFormatter.string(fromByteCount: Int64($0.bytes), countStyle: .file) }
        // Where its Open in Lamp goes: the Share Link the person made, or nothing yet, with a button to make one.
        let link = card.staged?.open.link ?? WishLink.kept(for: project)?.url
        let openInLamp = link.map { url in url.host.map { $0 + url.path } ?? url.absoluteString }
        return SidebarPublish(name: project.name, icon: card.icon, stage: card.stage, repo: card.repo,
                              page: card.page?.url, credit: credits.basedOn, openInLamp: openInLamp, notes: notes, size: size, copied: card.copied,
                              republish: card.page != nil, canPublish: card.canPublish)
    }
}
