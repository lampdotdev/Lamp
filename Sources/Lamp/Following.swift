import AppKit
import Foundation

/// Sharing a wish as a link and following other people's copies of it. Nothing is upstream: everyone has their own copy,
/// with the history it was made from, and a copy is shared as a link to it as it is now. Whoever opens the link gets a
/// copy of their own (`Wish.remix`, `Store.importRepository`, with the copy it came from on its credits' chain), and
/// follows the copy it started from. They can follow any other copy too, by its link, and are told when one has
/// something new, which they can pull in: the agent's merge brings it into their changes (`Store.mergeUpdate`).
///
/// Where a copy lives is git, behind the scenes: today its repository on GitHub, put there by Put on GitHub
/// (`GitHubRepo`), with its page on GitHub Pages for a web app or game, so anyone can try it in a browser. Nothing goes
/// through a server of Lamp's. A copy's place is kept with its kind (`Place.kind`), so another kind (a relay Lamp hosts
/// itself) can come later beside GitHub without a new format; a kind this Lamp doesn't know is kept as it was read and
/// shown as one it can't reach.
///
/// The copy a wish started from is the last link of its chain (`AppUpdates.origin`), as before: its commit moves with
/// each update and goes back with Undo, since it's in the wish's credits. Other copies followed are kept here, in Lamp's
/// own folder by the wish's instance (never the wish's folder, which the agent writes and versions and shared files
/// carry), with the commit of theirs last pulled in, the base the next pull-in is measured against.
enum Following {
    /// The format of what's kept, written with it: a later Lamp that changes it reads this one's and moves it on.
    static let format = 1

    /// Where a followed copy lives.
    struct Place: Codable, Equatable {
        /// "github" today.
        var kind: String
        /// Its address for that kind: a repository's on GitHub ("https://github.com/owner/name").
        var url: String

        static let github = "github"

        static func github(_ source: RepoImport.Source) -> Place { Place(kind: github, url: source.url) }

        /// The repository it is, for a kind this Lamp can reach on GitHub.
        var repository: RepoImport.Source? { kind == Self.github ? RepoImport.source(from: url).map { RepoImport.Source(owner: $0.owner, name: $0.name) } : nil }
    }

    /// Another copy of the wish, followed.
    struct Followed: Codable, Equatable, Identifiable {
        var place: Place
        /// Its page, where it can be tried in a browser, when its link named one.
        var page: String?
        /// The commit of theirs last pulled in; nil until the first pull-in, which then measures against what the two
        /// copies last shared (`Store.pullInBase`).
        var brought: String?
        /// The newest commit of theirs the person was told about, so a notification is sent once for each.
        var told: String?
        var added: Date

        var id: String { AppUpdates.key(place.url) }
    }

    // MARK: The link

    /// The wish's link as it is now: lamp.dev's page for its repository at the commit that holds this version, which
    /// shows the wish with Open in Lamp and, where it has one, its page to try in a browser. Nil until the wish is in a
    /// public repository as it is now (`GitHubRepo.remixOrigin`): Put on GitHub… puts it there.
    static func shareLink(for project: LampProject) -> URL? {
        guard case .repository(let url, let commit)? = GitHubRepo.remixOrigin(for: project) else { return nil }
        var parts = URLComponents(string: "https://lamp.dev/")!
        var items = [URLQueryItem(name: "repo", value: url)]
        if let commit { items.append(URLQueryItem(name: "commit", value: commit)) }
        if let page = GitHubRepo.kept(for: project)?.page, let owner = RepoImport.source(from: url)?.owner,
           let checked = pagesAddress(page, owner: owner) { items.append(URLQueryItem(name: "page", value: checked)) }
        parts.queryItems = items
        return parts.url
    }

    /// A GitHub Pages address as a link may carry it: https on the repository owner's own `<owner>.github.io`, so a
    /// link never points anyone anywhere else. The site holds it to the same (`remixFrom` in lib/wish.js); a page on
    /// the owner's own domain isn't carried.
    static func pagesAddress(_ text: String, owner: String) -> String? {
        guard let url = URL(string: text.trimmed), url.scheme == "https", url.host?.lowercased() == "\(owner.lowercased()).github.io",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil else { return nil }
        return url.absoluteString
    }

    /// The copy a link names, and its page: a wish's link (lamp.dev's, or Lamp's own `wish?repo=`), or a repository's
    /// address on GitHub. Nil for anything else. A commit the link names is left out: following is of the copy,
    /// whatever it becomes.
    static func copy(fromLink text: String, scheme: String = Edition.urlScheme) -> (place: Place, page: String?)? {
        let line = text.trimmed
        if let url = URL(string: line), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let host = url.host?.lowercased() ?? ""
            let fromLamp = (url.scheme == "https" && ["lamp.dev", "www.lamp.dev"].contains(host))
                || (url.scheme == scheme && host == "wish")
            if fromLamp {
                let value = { (name: String) in parts.queryItems?.first { $0.name == name }?.value }
                guard let repo = value("repo"), let source = RepoImport.source(from: repo), source.ref == nil else { return nil }
                return (.github(source), value("page").flatMap { pagesAddress($0, owner: source.owner) })
            }
        }
        guard let source = RepoImport.source(from: line) else { return nil }
        return (.github(RepoImport.Source(owner: source.owner, name: source.name)), nil)
    }

    // MARK: What Lamp keeps

    /// A test points this at a folder of its own.
    nonisolated(unsafe) static var keptURL = Edition.supportFolder.appendingPathComponent("Following.json")

    private struct Kept: Codable {
        var format: Int
        var wishes: [String: [Followed]]
    }

    private static func key(_ project: LampProject) -> String { project.instance.isEmpty ? project.id : project.instance }

    /// The copies a wish follows besides the one it started from, oldest first.
    static func followed(by project: LampProject) -> [Followed] { read().wishes[key(project)] ?? [] }

    static func keep(_ followed: [Followed], for project: LampProject) {
        var kept = read()
        kept.wishes[key(project)] = followed.isEmpty ? nil : followed
        kept.format = format
        guard let data = try? JSONEncoder().encode(kept) else { return }
        try? FileManager.default.createDirectory(at: keptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: keptURL, options: .atomic)
    }

    static func update(_ id: String, for project: LampProject, _ change: (inout Followed) -> Void) {
        var all = followed(by: project)
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        change(&all[index])
        keep(all, for: project)
    }

    /// What a later format would read: an unknown one is read as far as its fields allow, never thrown away.
    private static func read() -> Kept {
        (try? Data(contentsOf: keptURL)).flatMap { try? JSONDecoder().decode(Kept.self, from: $0) } ?? Kept(format: format, wishes: [:])
    }

    /// The wish is gone: what it followed goes with it.
    static func forget(_ project: LampProject) { keep([], for: project) }

    // MARK: What the desk shows

    /// One copy as the desk lists it.
    struct Row: Identifiable, Equatable {
        let id: String
        /// "Tally by someone".
        let title: String
        /// The copy this wish started from: its updates are the wish's own (`Store.reviewUpdate`).
        let startedFrom: Bool
        let state: State?
        let page: String?
    }

    enum State: Equatable {
        case checking, upToDate, new, failed, unreachable

        var line: String {
            switch self {
            case .checking: "Checking…"
            case .upToDate: "Nothing new"
            case .new: "Something new"
            case .failed: "Couldn't check. Try again."
            case .unreachable: "This Lamp can't reach it"
            }
        }
    }

    static func title(of place: Place) -> String {
        guard let source = place.repository else { return place.url }
        return "\(source.name) by \(source.owner)"
    }

    /// A followed copy's state from the last check: something new once its latest isn't what was last pulled in.
    static func state(of followed: Followed, check: AppUpdates.Check?) -> State? {
        guard followed.place.repository != nil else { return .unreachable }
        guard let check else { return nil }
        if check.checking { return .checking }
        guard let tip = check.tip?.lowercased() else { return .failed }
        guard let brought = followed.brought?.lowercased() else { return .new }
        return tip.hasPrefix(brought) || brought.hasPrefix(tip) ? .upToDate : .new
    }

    // MARK: Pulling in

    /// What's new in a followed copy, as the person is offered it.
    ///
    /// The seam for the merge experience: today the offer goes through the review a shared wish gets and then the
    /// agent's merge (`ReviewThenMerge`), all of it. A view that makes someone's changes understandable (their versions,
    /// pictures of each, a video) and lets the person take all or part takes the same offer in its place
    /// (`Following.pullIn`), and hands what was picked to the same merge, or to Mix's (`Mix.apply`) for part of it.
    struct Offer {
        let wish: LampProject
        let followed: Followed
        /// Their latest commit, as the last check heard it.
        let tip: String?
    }

    @MainActor protocol PullIn {
        func offer(_ offer: Offer, in store: Store)
    }

    /// Fetches the copy, shows the review a shared wish gets, and merges it on Update, keeping the person's changes.
    struct ReviewThenMerge: PullIn {
        @MainActor func offer(_ offer: Offer, in store: Store) {
            guard let source = offer.followed.place.repository else { return }
            store.importRepository(source, request: nil, updating: offer.wish.id, following: offer.followed)
        }
    }

    /// How pulling in is offered: the one place the merge experience plugs in.
    @MainActor static var pullIn: PullIn = ReviewThenMerge()

    /// The base a pull-in from `followed` measures both sides against, as a repository and its commit: the commit of
    /// theirs last pulled in; else the latest place both copies' chains share, at the commit this wish has of it (the
    /// copy both were made from), or at theirs when that place is this wish's own (they started from this one). Nil
    /// when the chains share nothing, and the merge goes by this wish's own history (`Upstream.merge`).
    static func base(for followed: Followed, ours: Credits, theirs: Credits?, own: String?) -> (url: String, commit: String)? {
        if let brought = followed.brought { return (followed.place.url, brought) }
        guard let theirs else { return nil }
        for link in theirs.remixOf.reversed() {
            guard let url = link.url, let mine = ours.remixOf.last(where: { $0.url.map(Credits.Source.plain) == Credits.Source.plain(url) }) else { continue }
            let isOwn = own.map { Credits.Source.plain($0) == Credits.Source.plain(url) } ?? false
            if let commit = Credits.validCommit(isOwn ? link.commit : mine.commit) { return (url, commit) }
        }
        return nil
    }

    /// The git ref a followed copy's staged latest is kept at, one for each, so each is measured against its own.
    static func ref(for followed: Followed) -> String {
        "refs/lamp/follow/" + String(followed.id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" })
    }
}

extension Store {
    /// The copies a wish follows, as the desk lists them: the one it started from first, when that's a wish on GitHub,
    /// then the others in the order they were followed. Asking checks them by itself when the last check is a day old.
    func followingRows(of project: LampProject) -> [Following.Row] {
        var rows: [Following.Row] = []
        if case .wish(let origin)? = AppUpdates.route(of: project), !Self.followsShippedStarter(project),
           let url = origin.url, let source = RepoImport.source(from: url) {
            let state: Following.State? = switch updateAvailability(of: project) {
            case .checking: .checking
            case .upToDate: .upToDate
            case .available, .preparing, .ready: .new
            case .failed: .failed
            case nil: nil
            }
            rows.append(Following.Row(id: AppUpdates.key(url), title: Following.title(of: .github(source)), startedFrom: true, state: state, page: nil))
        }
        for followed in Following.followed(by: project) where !rows.contains(where: { $0.id == followed.id }) {
            let check = updateChecks[followed.id]
            if followed.place.repository != nil, check.map({ !$0.checking && Date().timeIntervalSince($0.at) > AppUpdates.checkEvery }) ?? true {
                Task { @MainActor in checkFollowed(followed) }
            }
            rows.append(Following.Row(id: followed.id, title: Following.title(of: followed.place), startedFrom: false,
                                      state: Following.state(of: followed, check: check), page: followed.page))
        }
        return rows
    }

    /// Asks GitHub for a followed copy's latest, once for every wish that follows it.
    func checkFollowed(_ followed: Following.Followed) {
        guard let source = followed.place.repository, updateChecks[followed.id]?.checking != true else { return }
        updateChecks[followed.id] = AppUpdates.Check(tip: updateChecks[followed.id]?.tip, at: Date(), checking: true)
        Task {
            let tip = await AppUpdates.tip(of: source)
            updateChecks[followed.id] = AppUpdates.Check(tip: tip, at: Date())
            tellNew(from: followed.id, tip: tip)
        }
    }

    /// Check Again on a row: the copy it started from as its updates are checked, any other as above.
    func checkFollowing(_ id: String, of project: LampProject) {
        if let followed = Following.followed(by: project).first(where: { $0.id == id }) { return checkFollowed(followed) }
        checkForUpdates(project)
    }

    /// Every copy any wish follows, checked: once a launch, and a day after the last check.
    func checkAllFollowed() {
        var seen: Set<String> = []
        for project in projects where !project.isPart {
            for followed in Following.followed(by: project) where seen.insert(followed.id).inserted {
                if let check = updateChecks[followed.id], Date().timeIntervalSince(check.at) < AppUpdates.checkEvery { continue }
                checkFollowed(followed)
            }
        }
    }

    /// One notification for each newer version of a followed copy, for each wish that follows it.
    private func tellNew(from id: String, tip: String?) {
        guard let tip else { return }
        for project in projects where !project.isPart {
            guard let followed = Following.followed(by: project).first(where: { $0.id == id }), followed.told != tip,
                  Following.state(of: followed, check: updateChecks[id]) == .new else { continue }
            Following.update(id, for: project) { $0.told = tip }
            Notifier.shared.post(for: project, subtitle: "\(Following.title(of: followed.place)) has something new",
                                 body: "Pull it in from \(project.name) on Lamp's desk.")
        }
    }

    /// Follow a Copy…: asks for the copy's link, then follows it. Its latest is asked for at once.
    func askToFollow(for project: LampProject) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Follow a copy of “\(project.name)”"
        alert.informativeText = "Paste the link someone shared. You'll see when their copy has something new, and can pull it into yours."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "https://lamp.dev/?repo=…"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Follow")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let copy = Following.copy(fromLink: field.stringValue) else {
            let refusal = NSAlert()
            refusal.messageText = "That isn't a link to a copy"
            refusal.informativeText = "Ask for the link Copy Link to This Version makes, or the copy's address on GitHub."
            refusal.runModal()
            return
        }
        follow(copy.place, page: copy.page, for: project)
    }

    /// Follows a copy, unless it's this wish's own place or one it follows already.
    func follow(_ place: Following.Place, page: String?, for project: LampProject) {
        let id = AppUpdates.key(place.url)
        if let own = GitHubRepo.kept(for: project)?.url, AppUpdates.key(own) == id { return }
        if let origin = AppUpdates.origin(of: project)?.url, AppUpdates.key(origin) == id { return }
        var all = Following.followed(by: project)
        guard !all.contains(where: { $0.id == id }) else { return }
        let followed = Following.Followed(place: place, page: page, added: Date())
        all.append(followed)
        Following.keep(all, for: project)
        followingRevision += 1
        checkFollowed(followed)
    }

    func unfollow(_ id: String, for project: LampProject) {
        Following.keep(Following.followed(by: project).filter { $0.id != id }, for: project)
        followingRevision += 1
    }

    /// Pull In on a row: the copy it started from as its updates are reviewed, any other through the pull-in seam.
    func pullIn(_ id: String, into project: LampProject) {
        guard let followed = Following.followed(by: project).first(where: { $0.id == id }) else { return reviewUpdate(project) }
        guard !busy.contains(project.id), (queued[project.id] ?? []).isEmpty else {
            log(project, .status, "\(project.name) is busy with a change. Pull it in again when it's done.")
            return showChat(project.id)
        }
        Following.pullIn.offer(Following.Offer(wish: project, followed: followed, tip: updateChecks[id]?.tip), in: self)
    }

    /// Copy Link to This Version: the wish's link as it is now on the clipboard (`Following.shareLink`).
    func copyShareLink(_ project: LampProject) {
        guard let link = Following.shareLink(for: project), Sharing.askToShare(project) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
        log(project, .status, "\(project.name)'s link is copied. Whoever opens it gets their own copy, and can follow yours.")
    }
}
