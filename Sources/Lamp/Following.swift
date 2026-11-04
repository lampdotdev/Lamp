import AppKit
import Foundation

/// Sharing a wish as a link and following other people's copies of it. Nothing is upstream: everyone has their own copy,
/// and a copy is shared as a link to it. Whoever opens the link gets a copy of their own, and follows the copy it
/// started from. They can follow any other copy too, by its link, and are told when one has something new, which they
/// can pull in: the agent's merge brings it into their changes (`Store.mergeUpdate`).
///
/// A copy is shared as its Share Link with the wish itself (`WishLink`: `lamp.dev/w/<id>`, the file kept in lamp.dev's
/// Blob store, sent again with each Update Link). Opening it with Lamp (`lamp://wish?shared=<id>`, `Wish.Shared`) asks the
/// site for the file's latest (`WishLink.latest`), reviews it as any shared file, and the copy follows that link from
/// then on. A wish opened from GitHub follows its repository as before (`AppUpdates.origin`, the chain's last link,
/// whose commit moves with each update and goes back with Undo), and a repository can be followed by its address too.
///
/// What a copy follows is kept here, in Lamp's own folder by the wish's instance (never the wish's folder, which the
/// agent writes and versions and shared files carry), in a format that says its number, each copy with its place's
/// kind (`Place.kind`: `lamp` or `github`), so a kind added later reads beside these; one this Lamp doesn't know is kept
/// as it was read and shown as one it can't reach.
enum Following {
    /// The format of what's kept, written with it: a later Lamp that changes it reads this one's and moves it on.
    static let format = 1

    /// Where a followed copy lives.
    struct Place: Codable, Equatable {
        /// "lamp" for a link on lamp.dev, "github" for a repository.
        var kind: String
        /// Its address: the link ("https://lamp.dev/w/<id>"), or the repository ("https://github.com/owner/name").
        var url: String

        static let lamp = "lamp"
        static let github = "github"

        static func github(_ source: RepoImport.Source) -> Place { Place(kind: github, url: source.url) }
        static func lamp(_ id: String) -> Place { Place(kind: lamp, url: "https://lamp.dev/w/\(id)") }

        /// The repository it is, for a kind this Lamp can reach on GitHub.
        var repository: RepoImport.Source? { kind == Self.github ? RepoImport.source(from: url).map { RepoImport.Source(owner: $0.owner, name: $0.name) } : nil }
        /// The link's id on lamp.dev.
        var link: String? {
            guard kind == Self.lamp, let id = URL(string: url)?.pathComponents.last, Wish.isSharedID(id) else { return nil }
            return id
        }
        var reachable: Bool { repository != nil || link != nil }
    }

    /// Another copy of the wish, followed.
    struct Followed: Codable, Equatable, Identifiable {
        var place: Place
        /// What its sharer named it, as its link last said.
        var name: String?
        /// What of theirs was last pulled in: a link's file version, or a repository's commit. Nil until the first
        /// pull-in, which then measures against what the two copies last shared (`base`).
        var brought: String?
        /// The newest version of theirs the person was told about, so a notification is sent once for each.
        var told: String?
        var added: Date
        /// The copy this wish was made from.
        var startedFrom: Bool?
        /// What's being pulled in now: never kept.
        var pulling: String? = nil

        var id: String { AppUpdates.key(place.url) }

        private enum CodingKeys: String, CodingKey { case place, name, brought, told, added, startedFrom }

        init(place: Place, name: String? = nil, brought: String? = nil, told: String? = nil, added: Date = Date(), startedFrom: Bool? = nil) {
            self.place = place
            self.name = name
            self.brought = brought
            self.told = told
            self.added = added
            self.startedFrom = startedFrom
        }
    }

    // MARK: The link

    /// The copy a link names: a wish's Share Link (`lamp.dev/w/<id>`, with `-<name>` after it or not, or Lamp's own `wish?shared=<id>`), lamp.dev's
    /// remix of a repository (`?repo=`), or a repository's address. Nil for anything else.
    static func copy(fromLink text: String, scheme: String = Edition.urlScheme) -> Place? {
        let line = text.trimmed
        if let url = URL(string: line), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let host = url.host?.lowercased() ?? ""
            let value = { (name: String) in parts.queryItems?.first { $0.name == name }?.value }
            let onSite = url.scheme == "https" && ["lamp.dev", "www.lamp.dev"].contains(host)
            // The link carries the wish's name after its id and a dash (`lamp.dev/w/<id>-<name>`), only for reading.
            if onSite, url.pathComponents.count == 3, url.pathComponents[1] == "w" {
                let part = url.pathComponents[2], id = String(part.prefix(10))
                let named = part.count == 10 || part.dropFirst(10).first == "-"
                return Wish.isSharedID(id) && named ? .lamp(id) : nil
            }
            if url.scheme == scheme, host == "wish", let id = value("shared") { return Wish.isSharedID(id) ? .lamp(id) : nil }
            if onSite || (url.scheme == scheme && host == "wish") {
                guard let repo = value("repo"), let source = RepoImport.source(from: repo), source.ref == nil else { return nil }
                return .github(source)
            }
        }
        guard let source = RepoImport.source(from: line) else { return nil }
        return .github(RepoImport.Source(owner: source.owner, name: source.name))
    }

    // MARK: What Lamp keeps

    /// A test points this at a folder of its own.
    nonisolated(unsafe) static var keptURL = Edition.supportFolder.appendingPathComponent("Following.json")

    private struct Kept: Codable {
        var format: Int
        var wishes: [String: [Followed]]
        /// A pull-in left to the agent to settle, by wish: what it brings in counts once its turn finished well.
        var pending: [String: Pending]? = nil
        /// The newest version of the repository a wish came from that the person was told about, by wish.
        var told: [String: String]? = nil
    }

    /// A pull-in whose conflicts went to the agent as `request`, bringing `version` of `followed`. `cards` are the
    /// questions that agent asked: the turns that answer them settle it too.
    struct Pending: Codable, Equatable {
        var followed: Followed
        var version: String
        var request: String
        var cards: [String]? = nil

        func isItsTurn(_ messages: [QueuedMessage]) -> Bool {
            let cards = Set(cards ?? [])
            return messages.contains { $0.text == request || $0.card.map { cards.contains($0.uuidString) } == true }
        }
    }

    static func pending(for project: LampProject) -> Pending? { read().pending?[key(project)] }

    static func setPending(_ pending: Pending?, for project: LampProject) {
        var kept = read()
        var all = kept.pending ?? [:]
        all[key(project)] = pending
        kept.pending = all.isEmpty ? nil : all
        write(kept)
    }

    static func originTold(_ project: LampProject) -> String? { read().told?[key(project)] }

    static func setOriginTold(_ tip: String, for project: LampProject) {
        var kept = read()
        var all = kept.told ?? [:]
        all[key(project)] = tip
        kept.told = all
        write(kept)
    }

    private static func write(_ kept: Kept) {
        var kept = kept
        kept.format = format
        guard let data = try? JSONEncoder().encode(kept) else { return }
        try? FileManager.default.createDirectory(at: keptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: keptURL, options: .atomic)
    }

    private static func key(_ project: LampProject) -> String { project.instance.isEmpty ? project.id : project.instance }

    /// The copies a wish follows, oldest first: besides the repository it came from, which its credits name.
    static func followed(by project: LampProject) -> [Followed] { read().wishes[key(project)] ?? [] }

    static func keep(_ followed: [Followed], for project: LampProject) {
        var kept = read()
        kept.wishes[key(project)] = followed.isEmpty ? nil : followed
        write(kept)
    }

    static func update(_ id: String, for project: LampProject, _ change: (inout Followed) -> Void) {
        var all = followed(by: project)
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        change(&all[index])
        keep(all, for: project)
    }

    /// What of `followed` was just brought into the wish, followed from now on if it wasn't yet.
    static func brought(_ version: String, from followed: Followed, into project: LampProject) {
        var all = Following.followed(by: project)
        if !all.contains(where: { $0.id == followed.id }) { all.append(followed) }
        keep(all, for: project)
        update(followed.id, for: project) { $0.brought = version; $0.told = version; if let name = followed.name { $0.name = name } }
    }

    /// What a later format would read: an unknown one is read as far as its fields allow, never thrown away.
    private static func read() -> Kept {
        (try? Data(contentsOf: keptURL)).flatMap { try? JSONDecoder().decode(Kept.self, from: $0) } ?? Kept(format: format, wishes: [:])
    }

    /// The wish is gone: what it followed goes with it.
    static func forget(_ project: LampProject) {
        var kept = read()
        kept.wishes[key(project)] = nil
        kept.pending?[key(project)] = nil
        kept.told?[key(project)] = nil
        write(kept)
    }

    // MARK: What the desk shows

    /// One copy as the desk lists it.
    struct Row: Identifiable, Equatable {
        let id: String
        /// "Tally by someone".
        let title: String
        /// The copy this wish started from: its updates are the wish's own (`Store.reviewUpdate`).
        let startedFrom: Bool
        let state: State?
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

    static func title(of followed: Followed) -> String {
        if let source = followed.place.repository { return "\(source.name) by \(source.owner)" }
        return followed.name ?? "A shared copy"
    }

    /// A followed copy's state from the last check: something new once its latest isn't what was last pulled in.
    /// A link's version is its own count: 0 while it carries no file, which has nothing to pull in. A commit written
    /// short is the same as the one it begins.
    static func state(of followed: Followed, check: AppUpdates.Check?) -> State? {
        guard followed.place.reachable else { return .unreachable }
        guard let check else { return nil }
        if check.checking { return .checking }
        guard let tip = check.tip?.lowercased() else { return .failed }
        if followed.place.link != nil {
            return tip == "0" || tip == followed.brought ? .upToDate : .new
        }
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
        /// Their latest, as the last check heard it: a link's file version or a repository's commit.
        let tip: String?
    }

    @MainActor protocol PullIn {
        func offer(_ offer: Offer, in store: Store)
    }

    /// Fetches the copy, shows the review a shared wish gets, and merges it on Update, keeping the person's changes.
    struct ReviewThenMerge: PullIn {
        @MainActor func offer(_ offer: Offer, in store: Store) {
            if let id = offer.followed.place.link {
                store.takeShared(Wish.Shared(id: id, text: nil), updating: offer.wish.id, following: offer.followed)
            } else if let source = offer.followed.place.repository {
                store.importRepository(source, request: nil, updating: offer.wish.id, following: offer.followed)
            }
        }
    }

    /// How pulling in is offered: the one place the merge experience plugs in.
    @MainActor static var pullIn: PullIn = ReviewThenMerge()

    /// The base a pull-in from `followed` measures both sides against, as a repository and its commit: the commit of
    /// theirs last pulled in; else the latest place both copies' chains share, at the commit this wish has of it (the
    /// copy both were made from), or at theirs when that place is this wish's own (they started from this one). Nil
    /// when the chains share nothing, and the merge goes by this wish's own history (`Upstream.merge`).
    /// A link's copy has no repository: what was last pulled from it is kept at its ref (`ref`), which the merge reads
    /// as its base, and before the first pull-in, the version this wish arrived as.
    /// This wish's own repository is on their chain only: Put on GitHub keeps it apart from the wish's credits.
    static func base(for followed: Followed, ours: Credits, theirs: Credits?, own: String?) -> (url: String, commit: String)? {
        if let brought = followed.brought { return followed.place.repository != nil ? (followed.place.url, brought) : nil }
        guard let theirs else { return nil }
        for link in theirs.remixOf.reversed() {
            guard let url = link.url else { continue }
            if let own, Credits.Source.plain(own) == Credits.Source.plain(url) {
                if let commit = Credits.validCommit(link.commit) { return (url, commit) }
                continue
            }
            if let mine = ours.remixOf.last(where: { $0.url.map(Credits.Source.plain) == Credits.Source.plain(url) }),
               let commit = Credits.validCommit(mine.commit) { return (url, commit) }
        }
        return nil
    }

    /// The git ref what was last brought in from a followed copy is kept at, one for each, so each is measured against
    /// its own. It moves only once a pull-in has succeeded (`promote`); until then the latest staged is at
    /// `incomingRef`, which the merge and the agent's note on conflicts name.
    static func acceptedRef(for followed: Followed) -> String { "refs/lamp/follow/" + refName(followed) }
    static func incomingRef(for followed: Followed) -> String { "refs/lamp/follow-incoming/" + refName(followed) }

    private static func refName(_ followed: Followed) -> String {
        String(followed.id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" })
    }

    /// A pull-in from `followed` succeeded: what it brought is the base the next one is measured against.
    static func promote(_ followed: Followed, in project: LampProject) async {
        _ = await Versions.git("git update-ref \(acceptedRef(for: followed)) \(incomingRef(for: followed))", cwd: project.dir) { _ in }
    }
}

extension Store {
    /// The copies a wish follows, as the desk lists them: the one it started from first, then the others in the order
    /// they were followed. Asking checks them by itself when the last check is a day old.
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
            rows.append(Following.Row(id: AppUpdates.key(url), title: Following.title(of: Following.Followed(place: .github(source))),
                                      startedFrom: true, state: state))
        }
        let followed = Following.followed(by: project).sorted { ($0.startedFrom == true ? 0 : 1) < ($1.startedFrom == true ? 0 : 1) }
        for copy in followed where !rows.contains(where: { $0.id == copy.id }) {
            let check = updateChecks[copy.id]
            if copy.place.reachable, check.map({ !$0.checking && Date().timeIntervalSince($0.at) > AppUpdates.checkEvery }) ?? true {
                Task { @MainActor in checkFollowed(copy) }
            }
            rows.append(Following.Row(id: copy.id, title: Following.title(of: copy), startedFrom: copy.startedFrom == true,
                                      state: Following.state(of: copy, check: check)))
        }
        return rows
    }

    /// Asks for a followed copy's latest, once for every wish that follows it: a link's of lamp.dev, a repository's of
    /// GitHub. A link's name comes with it, and is kept.
    func checkFollowed(_ followed: Following.Followed) {
        guard followed.place.reachable, updateChecks[followed.id]?.checking != true else { return }
        updateChecks[followed.id] = AppUpdates.Check(tip: updateChecks[followed.id]?.tip, at: Date(), checking: true)
        Task {
            var tip: String?
            if let id = followed.place.link {
                let latest = await WishLink.latest(id)
                tip = latest.map { String($0.version) }
                if let name = latest?.name {
                    for project in projects where Following.followed(by: project).contains(where: { $0.id == followed.id }) {
                        Following.update(followed.id, for: project) { $0.name = name }
                    }
                }
            } else if let source = followed.place.repository {
                tip = await AppUpdates.tip(of: source)
            }
            updateChecks[followed.id] = AppUpdates.Check(tip: tip, at: Date())
            tellNew(from: followed.id, tip: tip)
        }
    }

    /// Check Again on a row: the repository it came from as its updates are checked, any other copy as above.
    func checkFollowing(_ id: String, of project: LampProject) {
        if let followed = Following.followed(by: project).first(where: { $0.id == id }) { return checkFollowed(followed) }
        checkForUpdates(project)
    }

    /// Every copy any wish follows, checked: once a launch, and a day after the last check. The repository a wish came
    /// from too, as Check for Updates asks it (`checkForUpdates`), so its new versions are told as well (`tellNew`).
    func checkAllFollowed() {
        var seen: Set<String> = []
        for project in projects where !project.isPart {
            if !Self.followsShippedStarter(project), case .wish(let origin)? = AppUpdates.route(of: project),
               let url = origin.url, seen.insert(AppUpdates.key(url)).inserted,
               updateChecks[AppUpdates.key(url)].map({ Date().timeIntervalSince($0.at) >= AppUpdates.checkEvery }) ?? true {
                checkForUpdates(project)
            }
            for followed in Following.followed(by: project) where seen.insert(followed.id).inserted {
                if let check = updateChecks[followed.id], Date().timeIntervalSince(check.at) < AppUpdates.checkEvery { continue }
                checkFollowed(followed)
            }
        }
    }

    /// One notification for each newer version of a followed copy, or of the repository a wish came from, for each
    /// wish that follows it.
    func tellNew(from id: String, tip: String?) {
        guard let tip else { return }
        for project in projects where !project.isPart {
            if let followed = Following.followed(by: project).first(where: { $0.id == id }) {
                guard followed.told != tip, Following.state(of: followed, check: updateChecks[id]) == .new else { continue }
                Following.update(id, for: project) { $0.told = tip }
                Notifier.shared.post(for: project, subtitle: "\(Following.title(of: followed)) has something new",
                                     body: "Pull it in from \(project.name) on Lamp's desk.")
            } else if !Self.followsShippedStarter(project), let route = AppUpdates.route(of: project), case .wish(let origin) = route,
                      let url = origin.url, let source = RepoImport.source(from: url), AppUpdates.key(url) == id,
                      AppUpdates.availability(of: route, check: updateChecks[id]) == .available, Following.originTold(project) != tip {
                Following.setOriginTold(tip, for: project)
                Notifier.shared.post(for: project, subtitle: "\(Following.title(of: Following.Followed(place: .github(source)))) has something new",
                                     body: "Pull it in from \(project.name) on Lamp's desk.")
            }
        }
    }

    /// After a turn: a pull-in left to the agent (`Following.Pending`) counts once the turn that settled it finished
    /// well, and is dropped if it didn't, so Pull In offers it again.
    /// A turn that answers one of its questions settles it the same way (`Pending.cards`, as `settleUpdate` does).
    func settlePull(_ project: LampProject, messages: [QueuedMessage], end: TurnEnd, asked: Bool) async {
        guard var pending = Following.pending(for: project), pending.isItsTurn(messages) else { return }
        let turnLines = (logs[project.id] ?? []).reversed().prefix { $0.kind != .user }
        let asking = asked || Talk.open(in: logs[project.id] ?? []) != nil || (queued[project.id] ?? []).contains { $0.card != nil }
        switch AppUpdates.settle(end: end, errors: turnLines.contains { $0.kind == .error }, asking: asking) {
        case .waiting:
            let cards = [Talk.open(in: logs[project.id] ?? [])?.id].compactMap { $0 } + (queued[project.id] ?? []).compactMap(\.card)
            if !cards.isEmpty {
                pending.cards = Array(Set((pending.cards ?? []) + cards.map(\.uuidString)))
                Following.setPending(pending, for: project)
            }
            return
        case .ready:
            await Following.promote(pending.followed, in: project)
            Following.brought(pending.version, from: pending.followed, into: project)
        case .failed: break
        }
        Following.setPending(nil, for: project)
        followingRevision += 1
    }

    /// Follow a Copy…: asks for the copy's link, then follows it. Its latest is asked for at once.
    func askToFollow(for project: LampProject) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Follow a copy of “\(project.name)”"
        alert.informativeText = "Paste the link someone shared. You'll see when their copy has something new, and can pull it into yours."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "https://lamp.dev/w/…"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Follow")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let place = Following.copy(fromLink: field.stringValue) else {
            let refusal = NSAlert()
            refusal.messageText = "That isn't a link to a copy"
            refusal.informativeText = "Ask for a link made with the wish itself included."
            refusal.runModal()
            return
        }
        follow(place, for: project)
    }

    /// Follows a copy, unless it's this wish's own link or repository, or one it follows already.
    func follow(_ place: Following.Place, for project: LampProject) {
        let id = AppUpdates.key(place.url)
        if let own = GitHubRepo.kept(for: project)?.url, AppUpdates.key(own) == id { return }
        if let own = WishLink.kept(for: project), AppUpdates.key(Following.Place.lamp(own.id).url) == id { return }
        if let origin = AppUpdates.origin(of: project)?.url, AppUpdates.key(origin) == id { return }
        var all = Following.followed(by: project)
        guard !all.contains(where: { $0.id == id }) else { return }
        let followed = Following.Followed(place: place)
        all.append(followed)
        Following.keep(all, for: project)
        followingRevision += 1
        checkFollowed(followed)
    }

    func unfollow(_ id: String, for project: LampProject) {
        Following.keep(Following.followed(by: project).filter { $0.id != id }, for: project)
        followingRevision += 1
    }

    /// Pull In on a row: the repository it came from as its updates are reviewed, any other copy through the pull-in seam.
    func pullIn(_ id: String, into project: LampProject) {
        guard let followed = Following.followed(by: project).first(where: { $0.id == id }) else { return reviewUpdate(project) }
        guard !busy.contains(project.id), (queued[project.id] ?? []).isEmpty else {
            log(project, .status, "\(project.name) is busy with a change. Pull it in again when it's done.")
            return showChat(project.id)
        }
        Following.pullIn.offer(Following.Offer(wish: project, followed: followed, tip: updateChecks[id]?.tip), in: self)
    }
}
