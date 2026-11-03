import Foundation

/// Mixing two copies of one wish (an experiment, Settings → Experimental): the changes each made since they last met,
/// on one timeline by when they were made, each one in or out. What's in is played back in order from where they met,
/// a later change winning wherever two touch the same lines (`git merge-tree -X theirs`), and what that comes to is
/// saved on top of this copy's history: one version leaving out what of yours was taken out, then one for each change
/// of theirs taken in, under its own title, so the history reads as the timeline did. Never a merge commit, and nothing
/// of the history is rewritten: Undo takes a mix back a version at a time.
///
/// Their changes come in the shared file (`MixHistory`); yours are this wish's own versions. Only what a shared file
/// carries is mixed: Lamp's own files, its records and the chat's attachments stay as this copy has them
/// (`Upstream.isLeftOut`). Every git command runs as Lamp's own git does (`Versions.git`).
enum Mix {
    /// The experiment's switch.
    static let switchKey = "mixCopies"
    static var isOn: Bool { Edition.isDev && UserDefaults.standard.bool(forKey: switchKey) }
    /// On a version a mix saved, the version of the other copy it brought in, so neither copy offers it again.
    static let trailer = "Lamp-Mixed"
    /// In Lamp's own folder once anything has been mixed into a wish: its starter's offer of first changes is no longer
    /// made (`Store.offerStarterChanges`).
    static let mixedMark = ".lamp/mixed"

    enum Side { case you, them }

    struct Change: Identifiable, Equatable {
        /// The commit: this wish's, or the sender's.
        let id: String
        let side: Side
        let title: String
        let date: Date
        /// The trees before and after it.
        let before: String
        let after: String
        /// What it touched that a mix carries.
        let files: [String]
        /// In this copy's history already: yours, or theirs from an earlier mix.
        let here: Bool
        /// A picture it added or changed, to show by its title.
        var picture: URL?
    }

    /// Two copies lined up: where they met, and every change since, by date.
    struct Lineup {
        let project: LampProject
        let package: Sharing.Package
        /// This copy's version when they were lined up: a mix onto a copy that has moved on since isn't one.
        let head: String
        /// The tree of the version they met at.
        let start: String
        let changes: [Change]
        let theirPicture: URL?
        let yourPicture: URL?
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// What a selection comes to, as the window shows it before mixing: each change that a later one replaces in part,
    /// with that later one's title.
    struct Preview: Equatable {
        var replaced: [String: String] = [:]
    }

    // MARK: Lining up

    /// The wish on this Mac a file is mixed into: the same wish's copy; for a remix's file, the wish it was remixed from
    /// (the latest in its chain that's here); else a remix made here of the file's wish. By the wish alone, whatever its
    /// layout: a file's history is the whole wish's, so a wish whose apps are in folders of its own (which an import
    /// opens as a new wish, `Store.copy(of:among:)`) is mixed as it is.
    static func copy(of package: Sharing.Package, among projects: [LampProject]) -> LampProject? {
        let candidates = projects.filter { !$0.isPart }
        if let identity = package.identity, let same = candidates.first(where: { Sharing.identity(of: $0, create: false) == identity }) {
            return same
        }
        for link in (package.credits?.remixOf ?? []).reversed() {
            if let wish = link.wish, let original = candidates.first(where: { Sharing.identity(of: $0, create: false) == wish }) { return original }
        }
        guard let identity = package.identity else { return nil }
        return candidates.first { Credits.load($0).remixOf.last?.wish == identity }
    }

    /// Where they met, and their versions since: the version their run starts after, when it's one of this copy's (the
    /// file came back from a copy of this one); else this copy's arrival, when the run starts at the version it was
    /// given or passes it. Nil for copies with no such version, which can't be mixed.
    static func meeting(_ package: Sharing.Package, history: MixHistory, with project: LampProject) async -> (base: String, theirs: [MixHistory.Version])? {
        if await isAncestor(history.base, in: project) { return (history.base, history.versions) }
        guard let identity = package.identity,
              let given = Credits.load(project).remixOf.last(where: { $0.sameWish(as: Credits.Remix(name: project.name, wish: identity)) })?.commit,
              let arrival = MixHistory.arrival(in: project) else { return nil }
        if history.base == given { return (arrival, history.versions) }
        guard let index = history.versions.firstIndex(where: { $0.id == given }) else { return nil }
        return (arrival, Array(history.versions[(index + 1)...]))
    }

    static func lineUp(_ package: Sharing.Package, history: MixHistory, with project: LampProject) async throws -> Lineup {
        guard let head = await Versions.head(project) else { throw Failure(message: "Your copy has no versions to mix yet.") }
        guard let (base, theirs) = await meeting(package, history: history, with: project) else {
            throw Failure(message: "These two copies don't share a version Lamp can find.")
        }

        // Yours: each version since, with what it touched and the change of theirs it brought in, if any.
        struct Yours { var id: String; var date: Date; var mixed: String?; var title: String; var files: [String] }
        let titles = VersionTitles.saved(in: project)
        var yours: [Yours] = []
        let listing = """
        git rev-list --first-parent --reverse \(base)..HEAD | while read -r c; do
          git log -1 --format="C%x1f%H%x1f%ct%x1f%(trailers:key=\(trailer),valueonly,separator=%x2C)%x1f%s" "$c"
          git -c core.quotePath=false diff-tree -r --no-renames --no-commit-id --name-only "$c^" "$c" | sed 's/^/F /'
        done
        """
        let listed = await run(listing, in: project)
        guard listed.status == 0 else { throw Failure(message: "Lamp couldn't read your copy's versions.") }
        for line in listed.output.split(separator: "\n").map(String.init) {
            if line.hasPrefix("C\u{1f}") {
                let parts = line.split(separator: "\u{1f}", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 5, let id = Credits.validCommit(parts[1]), let seconds = TimeInterval(parts[2]) else { continue }
                yours.append(Yours(id: id, date: Date(timeIntervalSince1970: seconds),
                                   mixed: Credits.validCommit(parts[3].split(separator: ",").first.map(String.init)),
                                   title: titles[id] ?? parts[4], files: []))
            } else if line.hasPrefix("F "), !yours.isEmpty {
                let path = String(line.dropFirst(2))
                if MixHistory.isSafe(path), !Upstream.isLeftOut(path, in: project) { yours[yours.count - 1].files.append(path) }
            }
        }
        // What's in both histories already is shown once: a change of theirs this copy brought in earlier stays on
        // their side, lit; one of yours they brought in, or one of theirs that came from here, isn't offered again.
        let yourIDs = Set(yours.map(\.id))
        let mixedHere = Set(yours.compactMap(\.mixed))
        let sent = Set(history.versions.map(\.id))
        // Only which are offered: every one of theirs is still rebuilt below, since each is the one before it with its
        // files put in place, and one left out of the chain would leave its changes in the next one's.
        func offered(_ version: MixHistory.Version) -> Bool {
            version.began != true && !yourIDs.contains(version.id) && !mixedHere.contains(version.id) && !(version.mixed.map(yourIDs.contains) ?? false)
        }

        // Your changes, by the trees around each; a version that touched nothing a mix carries isn't one.
        var changes: [Change] = []
        var previous = base
        for version in yours {
            defer { previous = version.id }
            let side: Side = version.mixed.map(sent.contains) == true ? .them : .you
            guard !version.files.isEmpty || side == .them else { continue }
            changes.append(Change(id: version.id, side: side, title: version.title, date: version.date, before: previous + "^{tree}",
                                  after: version.id + "^{tree}", files: version.files, here: true, picture: nil))
        }

        // Theirs, rebuilt here: each of their versions is the one before it with its files put in place.
        let start = try await treeID(of: base, in: project)
        let indexes = project.dir.appendingPathComponent(".lamp/mix")
        try? FileManager.default.createDirectory(at: indexes, withIntermediateDirectories: true)
        let index = indexes.appendingPathComponent("index")
        var files: [URL] = []
        for version in theirs {
            for path in version.changed where !Upstream.isLeftOut(path, in: project) {
                files.append(MixHistory.url(of: path, in: version, package: package.folder))
            }
        }
        var blobs: [String] = []
        if !files.isEmpty {
            let hashed = await run("printf '%s\\n' \"$LAMP_FILES\" | git hash-object -w --stdin-paths", in: project,
                                   env: ["LAMP_FILES": files.map(\.path).joined(separator: "\n")])
            blobs = hashed.output.split(separator: "\n").compactMap { Credits.validCommit(String($0)) }
            guard hashed.status == 0, blobs.count == files.count else { throw Failure(message: "Lamp couldn't read their changes.") }
        }
        var plan = ""
        var next = 0
        var kept: [MixHistory.Version] = []
        for version in theirs {
            var lines: [String] = []
            for path in version.changed where !Upstream.isLeftOut(path, in: project) {
                let file = MixHistory.url(of: path, in: version, package: package.folder)
                let mode = FileManager.default.isExecutableFile(atPath: file.path) ? "100755" : "100644"
                lines.append("\(mode) \(blobs[next])\t\(path)")
                next += 1
            }
            for path in version.removed where !Upstream.isLeftOut(path, in: project) {
                lines.append("0 0000000000000000000000000000000000000000\t\(path)")
            }
            guard !lines.isEmpty else { continue }
            kept.append(version)
            plan += "FROM \(kept.count == 1 ? start : "-")\n" + lines.joined(separator: "\n") + "\n@@\n"
        }
        let trees = kept.isEmpty ? [] : try await edit(plan, index: index, in: project)
        var before = start
        for (version, after) in zip(kept, trees) {
            defer { before = after }
            guard offered(version) else { continue }
            let paths = (version.changed + version.removed).filter { !Upstream.isLeftOut($0, in: project) }
            let picture = version.changed.first(where: isPicture).map { MixHistory.url(of: $0, in: version, package: package.folder) }
            changes.append(Change(id: version.id, side: .them, title: version.title, date: version.date, before: before, after: after,
                                  files: paths, here: false, picture: picture))
        }
        // Your pictures, from your versions, into a folder of the window's.
        for (offset, change) in changes.enumerated() where change.here {
            guard let path = change.files.first(where: isPicture) else { continue }
            let out = package.folder.appendingPathComponent("mine-\(offset)-" + (path as NSString).lastPathComponent)
            if await run("git cat-file blob \(Sandbox.quoted(change.after.replacingOccurrences(of: "^{tree}", with: "") + ":" + path)) > \(Sandbox.quoted(out.path))",
                         in: project).status == 0 {
                changes[offset].picture = out
            }
        }
        changes.sort { $0.date < $1.date }
        let yourPicture = Versions.pictureURL(in: project, for: head)
        return Lineup(project: project, package: package, head: head, start: start, changes: changes,
                      theirPicture: MixHistory.pictureURL(in: package.folder),
                      yourPicture: FileManager.default.fileExists(atPath: yourPicture.path) ? yourPicture : nil)
    }

    private static func isPicture(_ path: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains((path as NSString).pathExtension.lowercased())
    }

    // MARK: Playing back

    /// A playback: the changes in the order played, and the tree before the first and after each.
    struct Played {
        var ordered: [Change]
        var trees: [String]
        var tree: String { trees.last ?? "" }
    }

    /// The changes picked, played back in order from where the copies met: what it comes to, and for each change the
    /// files it couldn't take as they were because an earlier one changed them too. `resuming` is an earlier playback
    /// whose first changes are the same: those aren't played again, and their overlaps aren't said again.
    static func replay(_ picked: [Change], in lineup: Lineup, resuming: Played? = nil) async throws -> (played: Played, overlaps: [String: [String]]) {
        let ordered = picked.sorted { $0.date < $1.date }
        var shared = 0
        if let resuming {
            while shared < ordered.count, shared < resuming.ordered.count, shared + 1 < resuming.trees.count,
                  ordered[shared].id == resuming.ordered[shared].id { shared += 1 }
        }
        let first = resuming.map { $0.trees[shared] } ?? lineup.start
        let index = lineup.project.dir.appendingPathComponent(".lamp/mix/index")
        let script = """
        I="$LAMP_INDEX"; t="$LAMP_START"; echo "T $t"
        # An older git merges commits only, merge base included: each tree goes in as a commit of its own.
        mk() { git -c user.name=Lamp -c user.email=lamp@localhost commit-tree "$1" -m mix < /dev/null; }
        while IFS=' ' read -r id p c; do
          [ -z "$c" ] && continue
          echo "S $id"
          pc=$(mk "$p") && tc=$(mk "$t") && cc=$(mk "$c") || exit 3
          out=$(git merge-tree --write-tree --name-only --no-messages --merge-base="$pc" "$tc" "$cc"); s=$?
          if [ $s -eq 1 ]; then
            printf '%s\n' "$out" | sed -n '2,$p' | while IFS= read -r f; do [ -n "$f" ] && echo "O $f"; done
            # The later change wins: line by line where git can (-X theirs), else whole files. A git too old for -X
            # leaves the first answer's conflicts to the whole-file way.
            later=$(git merge-tree --write-tree --name-only --no-messages -X theirs --merge-base="$pc" "$tc" "$cc"); s=$?
            if [ $s -le 1 ]; then out="$later"; else s=1; fi
            if [ $s -eq 1 ]; then
              GIT_INDEX_FILE="$I" git read-tree "$(printf '%s\n' "$out" | head -n 1)" || exit 3
              printf '%s\n' "$out" | sed -n '2,$p' | while IFS= read -r f; do
                [ -z "$f" ] && continue
                e=$(git ls-tree "$c" -- "$f")
                if [ -n "$e" ]; then printf '%s\n' "$e" | GIT_INDEX_FILE="$I" git update-index --index-info
                else GIT_INDEX_FILE="$I" git update-index --force-remove -- "$f"; fi
              done
              out=$(GIT_INDEX_FILE="$I" git write-tree) || exit 3
            fi
          elif [ $s -ne 0 ]; then exit 3; fi
          t=$(printf '%s\n' "$out" | head -n 1)
          echo "T $t"
        done <<< "$LAMP_STEPS"
        """
        let steps = ordered[shared...].map { "\($0.id) \($0.before) \($0.after)" }.joined(separator: "\n")
        let ran = await run(script, in: lineup.project, env: ["LAMP_INDEX": index.path, "LAMP_START": first, "LAMP_STEPS": steps])
        guard ran.status == 0 else { throw Failure(message: "Lamp couldn't play the changes back.") }
        var trees = Array(resuming?.trees.prefix(shared) ?? [])
        var overlaps: [String: [String]] = [:]
        var current = ""
        for line in ran.output.split(separator: "\n").map(String.init) {
            if line.hasPrefix("T "), let id = Credits.validCommit(String(line.dropFirst(2))) { trees.append(id) }
            if line.hasPrefix("S ") { current = String(line.dropFirst(2)) }
            if line.hasPrefix("O ") {
                let path = String(line.dropFirst(2))
                if !Upstream.isLeftOut(path, in: lineup.project), !(overlaps[current]?.contains(path) ?? false) { overlaps[current, default: []].append(path) }
            }
        }
        guard trees.count == ordered.count + 1 else { throw Failure(message: "Lamp couldn't play the changes back.") }
        return (Played(ordered: ordered, trees: trees), overlaps)
    }

    /// What a selection comes to: each change in it that a later one in it overlaps, with the later one's title.
    static func preview(_ picked: [Change], in lineup: Lineup) async -> Preview {
        guard let (_, overlaps) = try? await replay(picked, in: lineup) else { return Preview() }
        let ordered = picked.sorted { $0.date < $1.date }
        // Which earlier change of the other side the later one overlaps: of those that touched the same file, the ones
        // whose own edit clashes with the later one's, each carried onto where the later one began.
        var pairs: [(earlier: Change, later: Change)] = []
        for (offset, later) in ordered.enumerated() {
            let paths = Set(overlaps[later.id] ?? [])
            for earlier in ordered[..<offset] where earlier.side != later.side && !paths.isDisjoint(with: earlier.files)
                && !pairs.contains(where: { $0.earlier.id == earlier.id && $0.later.id == later.id }) {
                pairs.append((earlier, later))
            }
        }
        guard !pairs.isEmpty else { return Preview() }
        let script = """
        mk() { git -c user.name=Lamp -c user.email=lamp@localhost commit-tree "$1" -m mix < /dev/null; }
        while IFS=' ' read -r n ep ea lp la; do
          [ -z "$la" ] && continue
          e1=$(mk "$ep") && e2=$(mk "$ea") && l1=$(mk "$lp") && l2=$(mk "$la") || exit 3
          x=$(git merge-tree --write-tree --name-only --no-messages -X theirs --merge-base="$e1" "$l1" "$e2"); s=$?
          # A clash carrying it over (one git leaves even with -X, an edit against a removal, or any with a git too old
          # for -X) is in the files the later one touched too: a clash with it.
          if [ $s -ne 0 ]; then echo "C $n"; continue; fi
          xc=$(mk "$(printf '%s\n' "$x" | head -n 1)") || exit 3
          git merge-tree --write-tree --name-only --no-messages --merge-base="$l1" "$l2" "$xc" > /dev/null; s=$?
          [ $s -eq 1 ] && echo "C $n"
        done <<< "$LAMP_PAIRS"
        exit 0
        """
        let lines = pairs.enumerated().map { "\($0.offset) \($0.element.earlier.before) \($0.element.earlier.after) \($0.element.later.before) \($0.element.later.after)" }
        let ran = await run(script, in: lineup.project, env: ["LAMP_PAIRS": lines.joined(separator: "\n")])
        guard ran.status == 0 else { return Preview() }
        var preview = Preview()
        for line in ran.output.split(separator: "\n") where line.hasPrefix("C ") {
            if let n = Int(line.dropFirst(2)), pairs.indices.contains(n) { preview.replaced[pairs[n].earlier.id] = pairs[n].later.title }
        }
        return preview
    }

    // MARK: Mixing

    /// Saves what the picked changes come to on top of this copy's history, and puts it in the wish's folder. The wish's
    /// files are expected saved. Returns how many versions were saved, none when the pick changes nothing.
    static func apply(_ picked: Set<String>, in lineup: Lineup) async throws -> Int {
        let project = lineup.project
        guard await Versions.head(project) == lineup.head else {
            throw Failure(message: "Your copy changed while this was open. Drop their copy here again.")
        }
        let changes = lineup.changes
        let mine = changes.filter { $0.here && picked.contains($0.id) }
        let left = changes.filter { $0.here && !picked.contains($0.id) }
        let coming = changes.filter { !$0.here && picked.contains($0.id) }
        var plans: [(changes: [Change], message: String, title: String, mixed: String?)] = []
        if !left.isEmpty {
            let title = "Left out " + left.map { "“\($0.title)”" }.joined(separator: ", ")
            plans.append((mine, title, title, nil))
        }
        for (offset, change) in coming.enumerated() {
            plans.append((mine + coming[...offset], change.title + "\n\n\(trailer): \(change.id)", change.title, change.id))
        }
        guard !plans.isEmpty else { return 0 }

        // What a mix doesn't carry stays as this copy has it now.
        let index = project.dir.appendingPathComponent(".lamp/mix/index")
        let ownListed = await run("git -c core.quotePath=false ls-tree -r HEAD", in: project)
        guard ownListed.status == 0 else { throw Failure(message: "Lamp couldn't read your copy.") }
        let own = ownListed.output.split(separator: "\n").map(String.init).filter { line in
            guard let tab = line.firstIndex(of: "\t") else { return false }
            let path = String(line[line.index(after: tab)...])
            return !path.hasPrefix("\"") && Upstream.isLeftOut(path, in: project)
        }
        let headTree = try await treeID(of: "HEAD", in: project)
        var parent = lineup.head
        var tree = headTree
        var saved: [(commit: String, title: String)] = []
        // Each plan is the one before with one more change of theirs, so it picks up where they part.
        var last: Played? = nil
        for plan in plans {
            let played = try await replay(plan.changes, in: lineup, resuming: last).played
            last = played
            let listed = await run("git -c core.quotePath=false ls-tree -r --name-only \(played.tree)", in: project)
            guard listed.status == 0 else { throw Failure(message: "Lamp couldn't read what the mix came to.") }
            let dropped = listed.output.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("\"") && Upstream.isLeftOut($0, in: project) }
            let lines = dropped.map { "0 0000000000000000000000000000000000000000\t\($0)" } + own
            let whole = lines.isEmpty ? played.tree : try await edit("FROM \(played.tree)\n" + lines.joined(separator: "\n") + "\n@@\n", index: index, in: project).first ?? played.tree
            // A change of theirs a later one of yours wholly replaces still gets its version: the history says it was
            // taken, and the next lineup doesn't offer it again.
            guard whole != tree || plan.mixed != nil else { continue }
            let made = await run("printf '%s' \"$LAMP_MESSAGE\" | git -c user.name=Lamp -c user.email=lamp@localhost commit-tree \(whole) -p \(parent) -F -",
                                 in: project, env: ["LAMP_MESSAGE": plan.message])
            guard made.status == 0, let commit = Credits.validCommit(made.output) else { throw Failure(message: "Lamp couldn't save the mix.") }
            saved.append((commit, plan.title))
            parent = commit
            tree = whole
        }
        guard !saved.isEmpty else { return 0 }
        // The files first, then the history: a mix that can't put its files in place leaves the copy as it was.
        guard await run("git read-tree --reset -u \(tree)", in: project).status == 0 else {
            _ = await run("git read-tree --reset -u HEAD", in: project)
            throw Failure(message: "Lamp couldn't put the mixed files in place.")
        }
        guard await run("git update-ref -m mix HEAD \(parent) \(lineup.head)", in: project).status == 0 else {
            _ = await run("git read-tree --reset -u HEAD", in: project)
            throw Failure(message: "Lamp couldn't save the mix.")
        }
        for version in saved { VersionTitles.save(version.title, for: version.commit, in: project) }
        return saved.count
    }

    /// What of their credits joins this copy's when their work is taken: the work it uses (its sources, licenses and
    /// generated pictures), never the chain. A link's commit there is the version their file was made at, and taking it
    /// would tell this copy's next file it starts from there, when it was taken only in part.
    static func creditsTaken(_ credits: Credits) -> Credits {
        var credits = credits
        credits.remixOf = []
        return credits
    }

    // MARK: Git

    /// Builds trees in an index of the mix's own: each block of `plan` starts from a tree (`FROM <tree>`, or `FROM -`
    /// for the one before), applies index lines ("<mode> <blob>\t<path>", mode 0 removing the path), and ends at `@@`.
    private static func edit(_ plan: String, index: URL, in project: LampProject) async throws -> [String] {
        let script = """
        I="$LAMP_INDEX"; t=""; buf=""; from=""
        while IFS= read -r line; do
          case "$line" in
            "FROM "*) from="${line#FROM }"; [ "$from" = "-" ] && from="$t"; buf="" ;;
            "@@") rm -f "$I"; GIT_INDEX_FILE="$I" git read-tree "$from" || exit 3
                  if [ -n "$buf" ]; then printf '%s' "$buf" | GIT_INDEX_FILE="$I" git update-index --index-info || exit 3; fi
                  t=$(GIT_INDEX_FILE="$I" git write-tree) || exit 3; echo "T $t" ;;
            *) buf="$buf$line"$'\\n' ;;
          esac
        done <<< "$LAMP_PLAN"
        """
        let ran = await run(script, in: project, env: ["LAMP_INDEX": index.path, "LAMP_PLAN": plan])
        let trees = ran.output.split(separator: "\n").compactMap { $0.hasPrefix("T ") ? Credits.validCommit(String($0.dropFirst(2))) : nil }
        guard ran.status == 0 else { throw Failure(message: "Lamp couldn't rebuild their changes.") }
        return trees
    }

    private static func treeID(of commit: String, in project: LampProject) async throws -> String {
        let said = await run("git rev-parse \(commit)^{tree}", in: project)
        guard said.status == 0, let tree = Credits.validCommit(said.output) else { throw Failure(message: "Lamp couldn't read your copy.") }
        return tree
    }

    private static func isAncestor(_ commit: String, in project: LampProject) async -> Bool {
        await run("git merge-base --is-ancestor \(commit) HEAD", in: project).status == 0
    }

    /// A git command in the wish's folder, as Lamp's git runs (`Versions.git`), with what it printed.
    private static func run(_ command: String, in project: LampProject, env: [String: String] = [:]) async -> (status: Int32, output: String) {
        let said = Said()
        let status = await Versions.git(command, cwd: project.dir, env: env) { said.add($0) }
        return (status, said.lines.joined(separator: "\n"))
    }

    private final class Said: @unchecked Sendable {
        private let lock = NSLock()
        private var kept: [String] = []
        func add(_ line: String) { lock.lock(); kept.append(line); lock.unlock() }
        var lines: [String] { lock.lock(); defer { lock.unlock() }; return kept }
    }
}
