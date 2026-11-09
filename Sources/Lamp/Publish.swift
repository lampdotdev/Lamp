import AppKit
import Foundation
import LampSidebarKit

/// A page to play or use in any browser, a web game's or a web app's: Web/ as the app shows it, with Lamp's credit bar
/// over it ("Based on Slop New York by Mr.doob", Open in Lamp, Remix…), put on GitHub Pages from the person's own GitHub account through GitHub's
/// own command-line tool (`gh`) and their sign-in there. Nothing goes through Lamp's servers: the person's account holds
/// the page, under GitHub's terms, and Lamp pays nothing for its plays.
///
/// Putting the wish on GitHub puts it up beside the wish's code, on the same repository's `gh-pages` branch (`GitHubRepo.stage`,
/// `GitHubRepo.upload`), and a starter's repository gets its page the same way (`StarterRepos.stagePage`). The page
/// carries Lamp's runtime (lamp.js, and a game's lamp-game.js), which is MIT-licensed, so its license goes beside it.
/// What in the page needs Lamp (its AI, the wish's other apps, `LampNative`) isn't there, and lamp.js says so to the
/// page as it does anywhere Lamp can't be reached, so the app goes on working without it (the web-app skill). What's
/// staged is held to the checks every share is (`ShareCheck`), and searched for keys and secrets before anything leaves.
/// This enum holds what both share: the page, its credit bar, its README, the sign-in and turning Pages on.
enum Publish {
    /// Whether a published page is played or used: what its button and its card say.
    enum PageUse: Equatable { case play, use }

    /// A wish whose one app is a page that runs in any browser (a web game, a web app: `Target.publishedPage`): its page
    /// is the whole app, so it can be played or used as a page.
    static func hasPage(_ project: LampProject) -> Bool { pageUse(project) != nil }

    static func pageUse(_ project: LampProject) -> PageUse? {
        pageApp(project).flatMap { $0.platform.target.publishedPage($0) }
    }

    /// The app whose page is played or used: the wish's own, or its one app when that's in a part of its own (a wish
    /// laid out with its game in a folder). Nil for a wish of several apps, whose pages would each need a home.
    static func pageApp(_ project: LampProject) -> LampProject? {
        var wish = project
        wish.partFolders = Parts.folders(in: project.dir)
        if project.isPart || wish.partFolders.isEmpty { return project.holdsApp ? project : nil }
        let apps = (wish.holdsApp ? [wish] : []) + Parts.load(wish)
        return apps.count == 1 ? apps[0] : nil
    }

    /// The shape a page plays in, which the link's page frames it in: a web game is drawn on its fixed stage
    /// (`GameKit.width` by `height`, fitted to any window with bars around it), so its frame is that shape and it shows
    /// none; a web app or a screen lays itself out for whatever room it has, so it fills the frame. Nil without a page.
    enum PageShape: Equatable { case ratio(Double), fill }
    static func pageShape(_ project: LampProject) -> PageShape? {
        switch pageUse(project) {
        case .play: .ratio(Double(GameKit.width) / Double(GameKit.height))
        case .use: .fill
        case nil: nil
        }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: GitHub

    /// Where `gh` is: Homebrew's, or wherever the person's shell finds it. Lamp Dev takes `LAMP_GH` from its environment
    /// in its place, a stand-in to try putting a wish on GitHub with against a local repository (git's own `insteadOf` sends the
    /// pushes there), so nothing reaches GitHub itself.
    static func gh() async -> String? {
        if Edition.isDev, let path = ProcessInfo.processInfo.environment["LAMP_GH"], path.hasPrefix("/"),
           FileManager.default.isExecutableFile(atPath: path) { return path }
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
    /// Lamp (Download Lamp carries the wish into its welcome) and with it ("Open Lamp with it"). `origin` is what the page is a copy of, when that's somewhere
    /// Lamp can copy it from again: the starter a starter's own page is (`StarterRepos.stagePage`), or the repository the
    /// page was put up with, at the commit pushed with it (`GitHubRepo.upload`). The Remix panel's request goes with it
    /// (`RemixLink.Origin`), so Lamp starts from a copy rather than its own version, and with no Share Link, Open in Lamp
    /// goes there too.
    /// `plays` is that the Share Link plays or opens the page itself (`WishLink.Shared.plays`): the page on GitHub then
    /// sends whoever opens it there, where the wish is shown whole with its ways to get it and change it, unless they
    /// have saves under `saves` (the page's `LAMP_PAGE_SCOPE`) on GitHub, which the link's own page can't read.
    struct OpenInLamp: Equatable {
        var link: URL?
        var origin: RemixLink.Origin? = nil
        var plays = false
        var saves: String? = nil
    }

    /// Gives a published copy of lamp.js the repository's name to keep what the page saves under (`LAMP_PAGE_SCOPE`).
    static func scope(_ runtime: URL, to scope: String) throws {
        guard let text = try? String(contentsOf: runtime, encoding: .utf8) else { return }
        try Data(text.replacingOccurrences(of: "/*LAMP_PAGE_SCOPE*/null", with: GamePage.json([scope]).dropFirst().dropLast()).utf8).write(to: runtime)
    }

    /// The license Lamp's runtime in the page is under, beside it, as MIT asks of a copy.
    static let runtimeLicense = "LAMP-LICENSE.txt"

    /// Copies the page as the app shows it into `site` (Web/: its own files and Lamp's runtime beside them, never a
    /// hidden file or a link), a game's told it's in no one device (`GamePage.anyBrowser`), with what lamp-game.js needs
    /// beside it (lamp-device.js, lamp-build.js), and Lamp's license. Returns its index.html as it is, for the credit bar
    /// (`withCreditBar`) to go over.
    /// `scope` is the repository's name, which what the page saves is kept under (lamp.js's `LAMP_PAGE_SCOPE`): every page
    /// of an account shares one origin, on github.io or the account's own domain.
    static func copyPage(of project: LampProject, into site: URL, scope: String) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: site, withIntermediateDirectories: true)
        let web = (pageApp(project) ?? project).dir.appendingPathComponent(GameKit.webFolder)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let items = fm.enumerator(at: web, includingPropertiesForKeys: keys) else { throw Failure(message: "\(project.name) has no page to play.") }
        for case let file as URL in items {
            if file.lastPathComponent.hasPrefix(".") { Sharing.skip(file, in: items); continue }
            let values = try? file.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
            let target = site.appendingPathComponent(Sharing.relativePath(of: file, in: web))
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: file, to: target)
        }
        try Publish.scope(site.appendingPathComponent("lamp.js"), to: scope)
        let anyBrowser = GamePage.anyBrowser
        try GamePage.stage(site, in: site) { try GamePage.descriptor(id: anyBrowser.id, name: anyBrowser.name, input: anyBrowser.input) }
        guard let html = try? String(contentsOf: site.appendingPathComponent("index.html"), encoding: .utf8) else {
            throw Failure(message: "\(project.name) has no page to play.")
        }
        try Data(GitHubRepo.mitLicense(holder: "Roo Code, Inc.", year: 2026).utf8).write(to: site.appendingPathComponent(runtimeLicense))
        // Served as files are, with nothing taken out for Jekyll (folders that start with _ included).
        try Data().write(to: site.appendingPathComponent(".nojekyll"))
        return html
    }

    /// The page's README, on its branch: where it plays, where the wish is, what it's based on, and whose its runtime
    /// is, naming only the runtime's files and libraries the page in `site` has.
    static func pageReadme(for project: LampProject, credits: Credits, repo: String, site: URL) -> String {
        func has(_ path: String) -> Bool { FileManager.default.fileExists(atPath: site.appendingPathComponent(path).path) }
        let plays = pageUse(project) != .use
        var text = "# \(project.name), \(plays ? "to play" : "to use")\n\n"
        if let line = AppDescription.description(of: project) { text += line + "\n\n" }
        text += "**\(plays ? "Play" : "Open") it:** \(pageURL(repo))\n\n"
        text += "The app itself, to open in [Lamp](https://lamp.dev) and change, is on the [main branch](\(GitHubRepo.url(repo))).\n\n"
        text += creditsSection(credits)
        let runtime = ["lamp-game.js", "lamp-phaser.js", "lamp-controllers.js", GamePage.deviceFile, GamePage.buildFile, "lamp.js"].filter(has)
        if !runtime.isEmpty {
            let named = runtime.map { "`\($0)`" }
            text += (named.count == 1 ? named[0] + " is" : named.dropLast().joined(separator: ", ") + " and " + named.last! + " are")
                + " \(plays ? "the game's" : "the app's") runtime, written by Lamp under the MIT license (`\(runtimeLicense)`)."
        }
        let libraries = [("three/LICENSE", "three.js is MIT (`three/LICENSE`)."), ("phaser/LICENSE.md", "Phaser is MIT (`phaser/LICENSE.md`)."),
                         ("lamp.js", "The QR code encoder inside `lamp.js` is MIT (its license is there)."),
                         ("rapier/LICENSE", "`rapier/` is Rapier, its physics, under the Apache License 2.0 (`rapier/LICENSE`).")]
        for (path, line) in libraries where has(path) { text += " " + line }
        return text + "\n"
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
        // The work it's built on, else the first thing it uses: a library is credited, never as what it's based on.
        if let source = credits.basis ?? credits.upstream.first {
            let name = source.url.map { "<a href=\"\(escaped($0))\" target=\"_blank\" rel=\"noopener\">\(escaped(source.name))</a>" } ?? escaped(source.name)
            parts.append((credits.basis != nil ? "Based on " : "Uses ") + name + (source.author.map { " by \(escaped($0))" } ?? ""))
        }
        if !credits.generated.isEmpty { parts.append(escaped(Credits.generatedLine(credits.generated.count))) }
        if let link = open.link {
            parts.append("<a href=\"\(escaped(link.absoluteString))\" target=\"_blank\" rel=\"noopener\">Open in Lamp</a>")
        } else if let origin = open.origin {
            // Lamp's site opens Lamp on a fresh copy of what the page is.
            parts.append("<a href=\"\(escaped(RemixLink.site(for: origin, from: "page").absoluteString))\" target=\"_blank\" rel=\"noopener\">Open in Lamp</a>")
        } else {
            parts.append("<a href=\"https://lamp.dev\" target=\"_blank\" rel=\"noopener\">Made with Lamp</a>")
        }
        // Remix…: a panel over the page with three things to change and a box for the player's own words. Continue with
        // Lamp goes where `RemixLink.url` sends the panel beside an app: Lamp's site with what to copy (a starter, or the
        // repository the wish is on) and the request; else the wish's Share Link page with the request (which gives this
        // exact wish, with Lamp or by getting it); else Lamp's site with a request that names the game. Nothing leaves
        // the page until that press.
        parts.append("<a href=\"#\" id=\"lamp-remix-open\">Remix…</a>")
        let offer = RemixOffer(name: name, about: about, suggestions: suggestions, shareLink: open.link, origin: open.origin)
        let target: [String: Any] = ["link": open.link?.absoluteString as Any, "origin": open.origin?.json as Any,
                                     "request": RemixLink.request(for: offer, ask: "{ask}")]
        // Keys sorted, so the same page is the same file and an unchanged page makes no new commit.
        let targetJSON = (try? JSONSerialization.data(withJSONObject: target, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let buttons = offer.suggestions.map { "<button type=\"button\" class=\"lamp-remix-pick\">\(escaped($0.text))</button>" }.joined()
        let panel = """
            <div id="lamp-remix" hidden>
              <div class="lamp-remix-head">Make \(escaped(name.isEmpty ? "it" : name)) yours<button type="button" id="lamp-remix-close" aria-label="Close">×</button></div>
              <p>Say what you'd change. Lamp makes the change and keeps your data.</p>
              \(buttons)
              <textarea id="lamp-remix-ask" rows="3" placeholder="Or say it your way"></textarea>
              <button type="button" id="lamp-remix-go" disabled>Continue with Lamp</button>
              <p class="lamp-remix-note">\(escaped(RemixLink.note(for: offer)))</p>
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
              var f=t.origin&&typeof t.origin==='object'?t.origin:null,u=new URL(f?'https://lamp.dev/':(t.link||'https://lamp.dev/'));
              if(f)for(var k in f)u.searchParams.set(k,String(f[k]));u.searchParams.set('from','page');
              u.searchParams.set('ask',f||t.link?ask:String(t.request||'{ask}').replace('{ask}',ask));window.open(u.href,'_blank','noopener');});})();
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
        var page = html
        if let end = page.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            page.replaceSubrange(end.lowerBound..<end.lowerBound, with: bar)
        } else {
            page += bar
        }
        // Where the Share Link plays it, the page opened on its own goes there. It stays, playing here as before, when it's
        // framed (something is showing it on purpose), when this browser has saves of it here (the link's page plays
        // from its own address, which can't read them), and when the link's card doesn't answer within a few seconds
        // (the link taken down since: its card is gone with it).
        guard open.plays, let link = open.link, let host = link.host, let scheme = link.scheme,
              let id = link.lastPathComponent.split(separator: "-").first, !id.isEmpty else { return page }
        let values = [link.absoluteString, "\(scheme)://\(host)/w/\(id)/card.png", "lamp:" + (open.saves.map { $0.isEmpty ? "" : $0 + ":" } ?? "")]
        guard let json = (try? JSONSerialization.data(withJSONObject: values, options: [.withoutEscapingSlashes])).flatMap({ String(data: $0, encoding: .utf8) })
        else { return page }
        let away = """
            <script>(function(t){if(window.top!==window)return;try{for(var i=0;i<localStorage.length;i++)if((localStorage.key(i)||'').indexOf(t[2])===0)return;}catch(e){return}
            var c=new Image(),s=0;c.onload=function(){if(!s){s=1;location.replace(t[0])}};c.onerror=function(){s=1};setTimeout(function(){s=1},4000);c.src=t[1];})(\(json.replacingOccurrences(of: "<", with: "\\u003c")))</script>
            """
        if let head = page.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            page.insert(contentsOf: "\n" + away, at: head.upperBound)
            return page
        }
        return away + "\n" + page
    }

    /// What a README says of the wish's credits: what it's based on and under which licenses, what else it uses, the
    /// pictures made with AI and the wishes it was remixed from. Empty for a wish with none.
    static func creditsSection(_ credits: Credits) -> String {
        var text = ""
        if !credits.upstream.isEmpty {
            text += "## Credits\n\n"
            for (index, source) in credits.basisFirst.enumerated() {
                let name = source.url.map { "[\(source.name)](\($0))" } ?? source.name
                var line = (index == 0 && credits.basis != nil ? "Based on " : "Uses ") + name + (source.author.map { " by \($0)" } ?? "")
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
            text += "Remixed from " + credits.remixOf.map { remix in
                (remix.url.map { "[\(remix.name)](\($0))" } ?? remix.name) + (remix.starter != nil ? " (a Lamp starter)" : "")
            }.joined(separator: ", then ") + ".\n\n"
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
    @MainActor static func obtain(_ need: GitHubNeed, stillNeeded: @escaping @MainActor () -> Bool, signedIn: @escaping @MainActor () -> Void) {
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

    // MARK: GitHub Pages

    /// The branch GitHub Pages serves the page from, beside the wish's code on main.
    static let pageBranch = "gh-pages"

    /// Puts `site` on `repo`'s page branch as one commit of the difference on top of what's there, or none when it's the
    /// same, signed in through gh for these commands alone. Returns the branch's commit, which Pages builds, and whether
    /// it's a new one.
    static func pushPage(_ site: URL, to repo: String, gh: String, login: String, authors shown: [GitHubRepo.Author]? = nil, message: String) async throws -> (commit: String, changed: Bool) {
        let git = GitHubRepo.git
        let signedIn = GitHubRepo.signedIn(gh: gh)
        let remote = "https://github.com/\(repo).git"
        // A try after a failed one starts afresh: the page's files are what's staged, whatever was committed then.
        try? FileManager.default.removeItem(at: site.appendingPathComponent(".git"))
        func run(_ arguments: [String]) async throws -> String {
            let ran = await Subprocess.run(git, arguments, cwd: site, mergeErrors: false, timeout: 120)
            guard ran.ok else { throw Failure(message: "Couldn't prepare the page: \(ran.output.trimmed.suffix(200))") }
            return ran.output.trimmed
        }
        _ = try await run(["init", "-q", "-b", pageBranch])
        _ = try await run(["add", "-A"])
        let tree = try await run(["write-tree"])
        var parent: String?
        if await Subprocess.run(git, signedIn + ["fetch", "-q", "--depth", "1", remote, pageBranch], cwd: site, timeout: 600).ok {
            let head = try await run(["rev-parse", "FETCH_HEAD"])
            if try await run(["rev-parse", "FETCH_HEAD^{tree}"]) == tree { return (head, false) }
            parent = head
        }
        let author = try await GitHubRepo.author(login: login, git: git, in: site)
        let commit = try await GitHubRepo.commit(["commit-tree", tree] + (parent.map { ["-p", $0] } ?? []) + ["-m", message], as: author, shown: shown,
                                                 git: git, in: site)
        let pushed = await Subprocess.run(git, signedIn + ["push", "-q", remote, "\(commit):refs/heads/\(pageBranch)"], cwd: site, timeout: 600)
        guard pushed.ok else { throw Failure(message: "GitHub didn't take the page: \(pushed.output.trimmed.suffix(200))") }
        return (commit, true)
    }

    /// Turns GitHub Pages on for `repo`'s page branch (`branch`: a plain site's is main, served from its root), or asks
    /// for a build when it's on, unless the page didn't change and that commit is built or building already (a failed
    /// build is asked for again, so trying again can mend it); then waits until GitHub says it built `commit`: an
    /// earlier build's "built" is the page as it was. Pages set by the person to serve another branch are left as they
    /// are, and said so.
    static func servePage(_ repo: String, commit: String, changed: Bool, gh: String, branch pageBranch: String = pageBranch,
                          step: @escaping @Sendable (String) -> Void) async throws {
        let url = pageURL(repo)
        step("Turning on GitHub Pages…")
        let existing = await Subprocess.run(gh, ["api", "repos/\(repo)/pages", "--jq", ".source.branch"], mergeErrors: false, timeout: 30)
        let branch = existing.output.trimmed
        if !existing.ok {
            let on = await Subprocess.run(gh, ["api", "-X", "POST", "repos/\(repo)/pages", "-f", "source[branch]=\(pageBranch)", "-f", "source[path]=/"],
                                          timeout: 30)
            // GitHub turns Pages on by itself for a gh-pages branch just pushed, so "already enabled" can answer the ask
            // made a moment after: Pages showing the page's branch is what was asked for.
            if !on.ok {
                let now = await Subprocess.run(gh, ["api", "repos/\(repo)/pages", "--jq", ".source.branch"], mergeErrors: false, timeout: 30)
                guard now.ok, now.output.trimmed == pageBranch else {
                    throw Failure(message: "GitHub Pages couldn't be turned on: \(on.output.trimmed.suffix(200))")
                }
            }
        } else if branch != pageBranch {
            throw Failure(message: "GitHub Pages for \(repo) shows its \(branch.isEmpty ? "own" : branch) branch, not the page. Choose \(pageBranch) in its Pages settings to play it.")
        } else {
            let latest = await Subprocess.run(gh, ["api", "repos/\(repo)/pages/builds/latest", "--jq", ".commit + \" \" + .status"],
                                              mergeErrors: false, timeout: 30)
            let parts = latest.output.trimmed.split(separator: " ").map(String.init)
            let underway = !changed && parts.count == 2 && parts[0] == commit && parts[1] != "errored"
            if !underway { _ = await Subprocess.run(gh, ["api", "-X", "POST", "repos/\(repo)/pages/builds"], timeout: 30) }
        }
        step("Waiting for GitHub to put the page up…")
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(5))
            let build = await Subprocess.run(gh, ["api", "repos/\(repo)/pages/builds/latest", "--jq", ".commit + \" \" + .status"],
                                             mergeErrors: false, timeout: 30)
            let parts = build.output.trimmed.split(separator: " ").map(String.init)
            guard parts.count == 2, parts[0] == commit else { continue }
            switch parts[1] {
            case "built": return
            case "errored": throw Failure(message: "GitHub couldn't put the page up. Try again in a moment.")
            default: continue
            }
        }
        throw Failure(message: "GitHub is still putting the page up. It should be at \(url) in a few minutes; try again if it isn't.")
    }

    /// Where GitHub Pages serves `repo` ("owner/name"): an account's own site, a repository named owner.github.io in any
    /// case, is served at the account's root; any other repository's under its name.
    static func pageURL(_ repo: String) -> String {
        let parts = repo.split(separator: "/")
        let host = "\(parts[0].lowercased()).github.io"
        return parts[1].lowercased() == host ? "https://\(host)/" : "https://\(host)/\(parts[1])/"
    }
}
