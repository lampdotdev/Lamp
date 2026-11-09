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
    /// On the version a mix saved first when it left out changes made here: which, so the next lineup shows them out
    /// rather than as kept, and doesn't list that version as a change of its own.
    static let leftOutTrailer = "Lamp-Left-Out"
    /// In Lamp's own folder once anything has been mixed into a wish: its starter's offer of first changes is no longer
    /// made (`Store.offerStarterChanges`).
    static let mixedMark = ".lamp/mixed"

    static func hasMixed(_ project: LampProject) -> Bool {
        FileManager.default.fileExists(atPath: project.dir.appendingPathComponent(mixedMark).path)
    }

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
        struct Yours { var id: String; var date: Date; var mixed: String?; var leftOut: [String]; var title: String; var files: [String] }
        let titles = VersionTitles.saved(in: project)
        var yours: [Yours] = []
        let listing = """
        git rev-list --first-parent --reverse \(base)..HEAD | while read -r c; do
          git log -1 --format="C%x1f%H%x1f%ct%x1f%(trailers:key=\(trailer),valueonly,separator=%x2C)%x1f%(trailers:key=\(leftOutTrailer),valueonly,separator=%x2C)%x1f%s" "$c"
          git -c core.quotePath=false diff-tree -r --no-renames --no-commit-id --name-only "$c^" "$c" | sed 's/^/F /'
        done
        """
        let listed = await run(listing, in: project)
        guard listed.status == 0 else { throw Failure(message: "Lamp couldn't read your copy's versions.") }
        for line in listed.output.split(separator: "\n").map(String.init) {
            if line.hasPrefix("C\u{1f}") {
                let parts = line.split(separator: "\u{1f}", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 6, let id = Credits.validCommit(parts[1]), let seconds = TimeInterval(parts[2]) else { continue }
                yours.append(Yours(id: id, date: Date(timeIntervalSince1970: seconds),
                                   mixed: Credits.validCommit(parts[3].split(separator: ",").first.map(String.init)),
                                   leftOut: parts[4].split(separator: ",").compactMap { Credits.validCommit(String($0).trimmed) },
                                   title: titles[id] ?? parts[5], files: []))
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

        // Your changes, by the trees around each; a version that touched nothing a mix carries isn't one. A version a
        // mix saved to leave changes out isn't one either: those changes are shown out instead, until one is taken back.
        // A change of theirs taken earlier sits where they made it.
        // Each version's word in order, oldest first, so the latest leaving out or taking back of a change wins.
        var leftOut: Set<String> = []
        for version in yours {
            leftOut.formUnion(version.leftOut)
            if let mixed = version.mixed, yourIDs.contains(mixed) { leftOut.remove(mixed) }
        }
        let made = Dictionary(history.versions.map { ($0.id, $0.date) }, uniquingKeysWith: { first, _ in first })
        var changes: [Change] = []
        var previous = base
        for version in yours {
            defer { previous = version.id }
            let side: Side = version.mixed.map(sent.contains) == true ? .them : .you
            // Nor is one that took a left-out change back: that change is in again.
            guard !version.files.isEmpty || side == .them, version.leftOut.isEmpty,
                  !(version.mixed.map(yourIDs.contains) ?? false) else { continue }
            let date = side == .them ? version.mixed.flatMap { made[$0] } ?? version.date : version.date
            changes.append(Change(id: version.id, side: side, title: version.title, date: date, before: previous + "^{tree}",
                                  after: version.id + "^{tree}", files: version.files, here: !leftOut.contains(version.id), picture: nil))
        }

        // Theirs, rebuilt here: each of their versions is the one before it with its files put in place.
        let start = try await treeID(of: base, in: project)
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
        let trees = kept.isEmpty ? [] : try await edit(plan, in: project)
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
        let index = try scratchIndex(in: lineup.project)
        defer { try? FileManager.default.removeItem(at: index) }
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

    /// What a pick comes to, worked out once (`prepare`) and saved exactly so (`apply`): each version it saves, as a
    /// tree, and which of them hold code no review read. Made for one file, at the version this copy was then, from
    /// exactly `picked`: a check of it (`checkInput`) is a check of these trees and no others.
    struct Prepared: Equatable {
        struct Version: Equatable {
            let tree: String
            let message: String
            let title: String
        }
        /// The package's folder: which file this is for.
        let folder: URL
        let head: String
        let picked: Set<String>
        let versions: [Version]
        /// The versions (by their place in `versions`) holding something neither the file's review read nor this copy
        /// already has: a change of theirs taken without a later one, a file both of you changed, what their History/
        /// says that the file's code doesn't. Any version can be gone back to (Undo, the History list), so each is checked,
        /// not only the last.
        let unseen: [Int]
        var needsCheck: Bool { !unseen.isEmpty }
    }

    /// Plays the pick back into the versions a mix saves, without saving any. What a mix doesn't carry stays as this copy
    /// has it: Lamp's own files, and a file a shared copy never carries (`Upstream.stage`), which their changes don't
    /// touch here, as an update's never would.
    static func prepare(_ picked: Set<String>, in lineup: Lineup) async throws -> Prepared {
        let project = lineup.project
        guard await Versions.head(project) == lineup.head else { throw moved }
        let changes = lineup.changes
        let mine = changes.filter { $0.here && picked.contains($0.id) }
        let left = changes.filter { $0.here && !picked.contains($0.id) }
        let coming = changes.filter { !$0.here && picked.contains($0.id) }
        var plans: [(changes: [Change], message: String, title: String, mixed: String?)] = []
        if !left.isEmpty {
            let title = "Left out " + left.map { "“\($0.title)”" }.joined(separator: ", ")
            plans.append((mine, title + "\n\n\(leftOutTrailer): " + left.map(\.id).joined(separator: ","), title, nil))
        }
        for (offset, change) in coming.enumerated() {
            plans.append((mine + coming[...offset], change.title + "\n\n\(trailer): \(change.id)", change.title, change.id))
        }
        let none = Prepared(folder: lineup.package.folder, head: lineup.head, picked: picked, versions: [], unseen: [])
        guard !plans.isEmpty else { return none }

        let ownListed = await run("git -c core.quotePath=false ls-tree -r \(lineup.head)", in: project)
        guard ownListed.status == 0 else { throw Failure(message: "Lamp couldn't read your copy.") }
        let own = ownListed.output.split(separator: "\n").map(String.init).filter { line in
            guard let tab = line.firstIndex(of: "\t") else { return false }
            let path = String(line[line.index(after: tab)...])
            return !path.hasPrefix("\"") && Upstream.isLeftOut(path, in: project)
        }
        let headTree = try await treeID(of: lineup.head, in: project)
        let headEntries = try await entries(of: headTree, in: project)
        let carry = try await Carrying(lineup: lineup, head: headTree)
        defer { carry.clear() }
        var tree = headTree
        var versions: [Prepared.Version] = []
        // Each plan is the one before with one more change of theirs, so it picks up where they part.
        var last: Played? = nil
        for plan in plans {
            let played = try await replay(plan.changes, in: lineup, resuming: last).played
            last = played
            let listed = await run("git -c core.quotePath=false ls-tree -r --name-only \(played.tree)", in: project)
            guard listed.status == 0 else { throw Failure(message: "Lamp couldn't read what the mix came to.") }
            let dropped = listed.output.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("\"") && Upstream.isLeftOut($0, in: project) }
            let lines = dropped.map { "0 0000000000000000000000000000000000000000\t\($0)" } + own
            var whole = lines.isEmpty ? played.tree : try await edit("FROM \(played.tree)\n" + lines.joined(separator: "\n") + "\n@@\n", in: project).first ?? played.tree
            // Their changes to a file no shared copy carries: it stays as yours is.
            let theirs = Set(plan.changes.filter { $0.side == .them && !$0.here }.flatMap(\.files))
            if !theirs.isEmpty {
                let now = try await entries(of: whole, in: project)
                let doubtful = theirs.filter { now[$0] != headEntries[$0] && !carry.carries($0) }
                if !doubtful.isEmpty {
                    let carried = try await carry.paths(of: whole)
                    let back = doubtful.filter { !carried.contains($0) }.sorted().map { path in
                        headEntries[path].map { "\($0)\t\(path)" } ?? "0 0000000000000000000000000000000000000000\t\(path)"
                    }
                    if !back.isEmpty { whole = try await edit("FROM \(whole)\n" + back.joined(separator: "\n") + "\n@@\n", in: project).first ?? whole }
                }
            }
            // A change of theirs a later one of yours wholly replaces still gets its version, and so does leaving out a
            // change a later one had already replaced: the history says what was taken and left out, and the next lineup
            // shows it so.
            guard whole != tree || plan.mixed != nil || plan.message.contains("\n\(leftOutTrailer): ") else { continue }
            versions.append(Prepared.Version(tree: whole, message: plan.message, title: plan.title))
            tree = whole
        }
        guard !versions.isEmpty else { return none }

        // What counts as read: the file's code as its review read it, and what this copy has had at any version since
        // the copies met. A file whose content and mode (or whose absence) is neither is code nobody read.
        let reviewed = try await carry.reviewed()
        var yours: [[String: String]] = [headEntries, try await entries(of: lineup.start, in: project)]
        for change in changes where change.here { yours.append(try await entries(of: change.after, in: project)) }
        var unseen: [Int] = []
        for (index, version) in versions.enumerated() {
            let saved = try await entries(of: version.tree, in: project)
            let touched = Set(saved.keys).union(headEntries.keys).filter { saved[$0] != headEntries[$0] && !Upstream.isLeftOut($0, in: project) }
            if touched.contains(where: { path in saved[path] != reviewed[path] && !yours.contains { $0[path] == saved[path] } }) {
                unseen.append(index)
            }
        }
        return Prepared(folder: lineup.package.folder, head: lineup.head, picked: picked, versions: versions, unseen: unseen)
    }

    /// What a check of a prepared mix reads: the app as the mix leaves it, read as a shared file is, so every file the
    /// mix brings is read under the rules an import's are; and the code of each earlier version it saves that holds
    /// code no review read, under that version's title. One check, however many versions. The package's folder is the
    /// caller's to remove.
    static func checkInput(_ prepared: Prepared, in lineup: Lineup) async throws -> (package: Sharing.Package, inspection: Sharing.Inspection) {
        guard let final = prepared.versions.last else { throw Failure(message: "There's nothing to check.") }
        let package = try await read(final.tree, in: lineup)
        var kept = false
        defer { if !kept { try? FileManager.default.removeItem(at: package.folder) } }
        var found = Sharing.inspect(package)
        var files = found.files
        for index in prepared.unseen where index != prepared.versions.count - 1 {
            let version = prepared.versions[index]
            let earlier = try await read(version.tree, in: lineup)
            defer { try? FileManager.default.removeItem(at: earlier.folder) }
            let more = Sharing.inspect(earlier)
            var theirFiles = more.files
            if let about = more.about, about != found.about { theirFiles.append(("APP.md", about)) }
            for file in theirFiles where !files.contains(where: { $0.name == file.name && $0.text == file.text }) {
                files.append(("\(file.name) (in “\(version.title)”)", file.text))
            }
            for item in more.detected where !found.detected.contains(where: { $0.label == item.label }) { found.detected.append(item) }
            found.truncated = found.truncated || more.truncated
            found.finished = found.finished && more.finished
        }
        found.batches = Sharing.batches(files)
        if found.batches.count > Sharing.batchCount {
            found.batches.removeLast(found.batches.count - Sharing.batchCount)
            found.truncated = true
        }
        kept = true
        return (package, found)
    }

    /// Saves a prepared mix on top of this copy's history, and puts it in the wish's folder. The wish's files are
    /// expected saved. Nothing is saved for a copy that has moved on since, for another file, or for a mix that holds
    /// code no review read without the check that read it (`checked`). Returns how many versions were saved.
    static func apply(_ prepared: Prepared, in lineup: Lineup, checked: ImportReview?) async throws -> Int {
        let project = lineup.project
        guard prepared.folder == lineup.package.folder, prepared.head == lineup.head,
              await Versions.head(project) == prepared.head else { throw moved }
        guard !prepared.needsCheck || checked != nil else { throw Failure(message: "Lamp hasn't checked what this mix brings in.") }
        guard !prepared.versions.isEmpty else { return 0 }
        var parent = prepared.head
        var saved: [(commit: String, title: String)] = []
        for version in prepared.versions {
            let made = await run("printf '%s' \"$LAMP_MESSAGE\" | git -c user.name=Lamp -c user.email=lamp@localhost commit-tree \(version.tree) -p \(parent) -F -",
                                 in: project, env: ["LAMP_MESSAGE": version.message])
            guard made.status == 0, let commit = Credits.validCommit(made.output) else { throw Failure(message: "Lamp couldn't save the mix.") }
            saved.append((commit, version.title))
            parent = commit
        }
        // Once more before anything is touched: the files first, then the history, so a mix that can't put its files in
        // place leaves the copy as it was.
        guard await Versions.head(project) == prepared.head else { throw moved }
        guard let tree = prepared.versions.last?.tree, await run("git read-tree --reset -u \(tree)", in: project).status == 0 else {
            _ = await run("git read-tree --reset -u HEAD", in: project)
            throw Failure(message: "Lamp couldn't put the mixed files in place.")
        }
        guard await run("git update-ref -m mix HEAD \(parent) \(prepared.head)", in: project).status == 0 else {
            _ = await run("git read-tree --reset -u HEAD", in: project)
            throw Failure(message: "Lamp couldn't save the mix.")
        }
        for version in saved { VersionTitles.save(version.title, for: version.commit, in: project) }
        return saved.count
    }

    private static let moved = Failure(message: "Your copy changed while this was open. Drop their copy here again.")

    /// Every file in a tree, by its path byte for byte as it's spelled in History/ and on disk: "<mode> <blob>", so two
    /// trees compare file by file, the mode with the content. git quotes a path with a quote, a backslash or a control
    /// character in it, and any character but NUL can be in a name, so the listing comes NUL-separated and as hex: no
    /// name can be read as two, or as another.
    private static func entries(of tree: String, in project: LampProject) async throws -> [String: String] {
        let listed = await run("set -o pipefail; git ls-tree -r -z --full-tree \(tree) | /usr/bin/xxd -p | /usr/bin/tr -d '\\n'", in: project)
        guard listed.status == 0, let bytes = hexBytes(listed.output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw Failure(message: "Lamp couldn't read what the mix came to.")
        }
        var entries: [String: String] = [:]
        for raw in bytes.split(separator: 0, omittingEmptySubsequences: true) {
            guard let tab = raw.firstIndex(of: 9),
                  let meta = String(bytes: raw[..<tab], encoding: .utf8),
                  let path = String(bytes: raw[raw.index(after: tab)...], encoding: .utf8) else {
                throw Failure(message: "Lamp couldn't read what the mix came to.")
            }
            let fields = meta.split(separator: " ")
            guard fields.count == 3 else { throw Failure(message: "Lamp couldn't read what the mix came to.") }
            entries[path] = "\(fields[0]) \(fields[2])"
        }
        return entries
    }

    private static func hexBytes(_ hex: String) -> [UInt8]? {
        let digits = Array(hex.utf8)
        guard digits.count % 2 == 0 else { return nil }
        func value(_ c: UInt8) -> UInt8? {
            switch c {
            case 48...57: c - 48
            case 97...102: c - 87
            case 65...70: c - 55
            default: nil
            }
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        var index = 0
        while index < digits.count {
            guard let high = value(digits[index]), let low = value(digits[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
            index += 2
        }
        return bytes
    }

    /// A tree of this copy read as a shared file of it would be (`Sharing.open`): unpacked into a folder of its own with
    /// a manifest saying what this copy is, so what's code, what's data and what's never carried are the import's to say.
    private static func read(_ tree: String, in lineup: Lineup) async throws -> Sharing.Package {
        let fm = FileManager.default
        let folder = Sharing.workFolder.appendingPathComponent("lamp-mix-check-\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var opened = false
        defer { if !opened { try? fm.removeItem(at: folder) } }
        // Each file's blob as the tree holds it, never `git archive`, which leaves out whatever the tree's own
        // .gitattributes marks export-ignore and so would hide a file from the check that the mix still saves. Only
        // plain files are written; links and submodules aren't code the reader takes, and their paths come from no
        // History/ (`Mix.lineUp` writes plain files only).
        let script = """
        set -o pipefail
        git ls-tree -r -z --full-tree "$LAMP_TREE" | while IFS= read -r -d '' e; do
          meta="${e%%$'\\t'*}"; p="${e#*$'\\t'}"; mode="${meta%% *}"; sha="${meta##* }"
          case "$mode" in 100644|100755) ;; *) continue ;; esac
          mkdir -p -- "$LAMP_OUT/$(dirname -- "$p")" || exit 3
          git cat-file blob "$sha" > "$LAMP_OUT/$p" || exit 3
          if [ "$mode" = 100755 ]; then chmod +x -- "$LAMP_OUT/$p" || exit 3; fi
        done
        """
        guard await run(script, in: lineup.project, env: ["LAMP_TREE": tree, "LAMP_OUT": folder.path]).status == 0 else {
            throw Failure(message: "Lamp couldn't read what the mix came to.")
        }
        let (root, parts) = Sharing.layout(of: lineup.project)
        let manifest = Sharing.Manifest(format: Sharing.formatVersion, name: lineup.project.name, exportedAt: Date(),
                                        app: lineup.package.identity, platform: root.platform, family: root.hasIOS ? root.family : nil,
                                        parts: parts.isEmpty ? nil : parts.map {
                                            Sharing.Manifest.Part(folder: $0.dir.lastPathComponent, platform: $0.platform, family: $0.hasIOS ? $0.family : nil)
                                        }, site: lineup.package.site ? true : nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: folder.appendingPathComponent("lamp-app.json"))
        do {
            let package = try Sharing.open(unpacked: folder)
            opened = true
            return package
        } catch {
            throw Failure(message: "Lamp couldn't check what this mix comes to: \(error.localizedDescription)")
        }
    }

    /// What a shared copy carries (`Upstream.stage`), for a preparation: the file's, as its review read it, and this
    /// copy's own, by path; and, asked for, a tree's. Its staged folders go when it's cleared.
    private final class Carrying {
        let lineup: Lineup
        private let work = Sharing.workFolder.appendingPathComponent("lamp-mix-carry-\(UUID().uuidString)")
        private var known: Set<String> = []

        init(lineup: Lineup, head: String) async throws {
            self.lineup = lineup
            do {
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                known = Self.files(in: try stage(lineup.package, as: "theirs"))
                if let package = try? await Mix.read(head, in: lineup) {
                    defer { try? FileManager.default.removeItem(at: package.folder) }
                    known.formUnion(Self.files(in: try stage(package, as: "yours")))
                }
            } catch {
                clear()
                throw error
            }
        }

        /// Whether the file's or this copy's carries the path: known without reading any other tree.
        func carries(_ path: String) -> Bool { known.contains(path) }

        func paths(of tree: String) async throws -> Set<String> {
            let package = try await Mix.read(tree, in: lineup)
            defer { try? FileManager.default.removeItem(at: package.folder) }
            return Self.files(in: try stage(package, as: UUID().uuidString))
        }

        /// The file's code as its review read it and an import would install it, by path: "<mode> <blob>".
        func reviewed() async throws -> [String: String] {
            let indexes = work.appendingPathComponent("indexes")
            try FileManager.default.createDirectory(at: indexes, withIntermediateDirectories: true)
            let tree = try await Upstream.tree(of: work.appendingPathComponent("theirs"), in: lineup.project, indexes: indexes)
            return try await Mix.entries(of: tree, in: lineup.project)
        }

        func clear() { try? FileManager.default.removeItem(at: work) }

        private func stage(_ package: Sharing.Package, as name: String) throws -> URL {
            let folder = work.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Upstream.stage(package, for: lineup.project, into: folder)
            return folder
        }

        private static func files(in folder: URL) -> Set<String> {
            guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
            var paths: Set<String> = []
            for case let file as URL in walk where (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                paths.insert(Sharing.relativePath(of: file, in: folder))
            }
            return paths
        }
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

    /// Builds trees in an index of its own (`scratchIndex`): each block of `plan` starts from a tree (`FROM <tree>`, or
    /// `FROM -` for the one before), applies index lines ("<mode> <blob>\t<path>", mode 0 removing the path), and ends at `@@`.
    private static func edit(_ plan: String, in project: LampProject) async throws -> [String] {
        let index = try scratchIndex(in: project)
        defer { try? FileManager.default.removeItem(at: index) }
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

    /// An index file for one piece of the mix's git work, never another's: the window's preview, a preparation and a
    /// save can run at once, and two sharing an index would build trees from each other's entries.
    private static func scratchIndex(in project: LampProject) throws -> URL {
        let folder = project.dir.appendingPathComponent(".lamp/mix")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("index-\(UUID().uuidString)")
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
