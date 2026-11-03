import Foundation

/// The run of versions a shared file carries for mixing (`Mix`), in History/ beside the app: each version's title, when
/// it was saved, and the files it changed as they were after it, so the Mac that opens the file can replay them one at
/// a time. Only what a shared file would carry anyway: Lamp's own files, its records and the chat's attachments are left
/// out (`Upstream.isLeftOut`), and the whole folder goes through the same check for keys the rest of the file does. Code
/// in it reaches an app only through the mix window, after the file's review. An older Lamp never reads the folder.
struct MixHistory: Codable {
    static let folder = "History"
    static let file = "history.json"
    static let picture = "picture.jpg"
    /// The most versions a file carries: the latest, with all before them as one.
    static let limit = 40
    /// Where an origin copy's run starts: the version it was first shared at.
    static let startFile = ".lamp/mix-start"

    /// The version the run starts after, as the wish it began from names it: the commit on the file's chain.
    var base: String
    var versions: [Version]

    struct Version: Codable {
        /// The commit in the sender's history.
        var id: String
        var title: String
        var date: Date
        /// The version of another copy this one brought in by a mix, when it did (`Mix.trailer`).
        var mixed: String?
        /// The version a remix began as (its new name and icon): what the rest is rebuilt on, never offered.
        var began: Bool?
        /// Its folder in History/, holding `changed` as they were after it.
        var folder: String
        var changed: [String]
        var removed: [String]
    }

    // MARK: Sending

    /// Writes the run into `stage` (a shared file's folder). Nothing for a wish with no history, or one whose run can't
    /// be read: the file goes as it always has.
    static func write(for project: LampProject, credits: Credits, identity: String?, into stage: URL) {
        let fm = FileManager.default
        guard let start = start(of: project, credits: credits, identity: identity) else { return }
        let out = stage.appendingPathComponent(folder)
        try? fm.createDirectory(at: out, withIntermediateDirectories: true)
        // One sandboxed run for the whole history: each version's line, what it changed, and its changed files
        // unpacked into its folder. A run longer than the limit keeps its latest versions, and everything before them
        // goes as one version ("E"), from where the copies met to the last one left out, so the run still starts there.
        // A remix's first version ("R") always goes on its own, ahead of them.
        let script = """
        out=\(Sandbox.quoted(out.path)); n=0
        all=$(git rev-list --first-parent --reverse \(start.began ?? start.commit)..HEAD); count=$(printf '%s\\n' "$all" | grep -c .)
        {
          \(start.began.map { "echo \"\($0)^ \($0) R\"" } ?? ":")
          if [ "$count" -gt \(limit) ]; then
            echo "\(start.began ?? start.commit) $(printf '%s\\n' "$all" | sed -n "$((count - \(limit)))p") E"
            printf '%s\\n' "$all" | tail -n \(limit) | while read -r c; do echo "$c^ $c -"; done
          else
            printf '%s\\n' "$all" | while read -r c; do [ -n "$c" ] && echo "$c^ $c -"; done
          fi
        } | while read -r p c kind; do
          n=$((n+1)); d="$out/$n"; mkdir -p "$d"
          git log -1 --format="V%x1f$n%x1f%H%x1f%ct%x1f%(trailers:key=\(Mix.trailer),valueonly,separator=%x2C)%x1f$kind%x1f%s" "$c"
          git -c core.quotePath=false diff-tree -r --no-renames --no-commit-id --name-status "$p" "$c"
          git diff-tree -r --no-renames --no-commit-id --name-only -z --diff-filter=AMT "$p" "$c" > "$d.paths"
          if [ -s "$d.paths" ]; then xargs -0 git archive --format=tar "$c" -- < "$d.paths" | /usr/bin/tar -x -C "$d"; fi
          rm -f "$d.paths"
        done
        """
        let listed = Versions.gitBlocking(script, cwd: project.dir)
        guard listed.ok else { try? fm.removeItem(at: out); return }
        let titles = VersionTitles.saved(in: project)
        var versions: [Version] = []
        for line in listed.output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if line.hasPrefix("V\u{1f}") {
                let parts = line.split(separator: "\u{1f}", maxSplits: 6, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 7, let id = Credits.validCommit(parts[2]), let seconds = TimeInterval(parts[3]) else { continue }
                let title = parts[5] == "E" ? "Earlier changes" : titles[id] ?? parts[6]
                versions.append(Version(id: id, title: title, date: Date(timeIntervalSince1970: seconds),
                                        mixed: parts[5] == "E" ? nil : Credits.validCommit(parts[4].split(separator: ",").first.map(String.init)),
                                        began: parts[5] == "R" ? true : nil, folder: parts[1], changed: [], removed: []))
            } else if !versions.isEmpty, let tab = line.firstIndex(of: "\t") {
                let status = line[..<tab], path = String(line[line.index(after: tab)...])
                guard isSafe(path), !Upstream.isLeftOut(path, in: project) else { continue }
                if status.hasPrefix("D") { versions[versions.count - 1].removed.append(path) } else { versions[versions.count - 1].changed.append(path) }
            }
        }
        // Only plain files go; a version that changed nothing a shared file carries isn't one to mix.
        for index in versions.indices {
            let base = out.appendingPathComponent(versions[index].folder)
            versions[index].changed = versions[index].changed.filter { isPlainFile(base.appendingPathComponent($0)) }
        }
        let kept = versions.filter { !$0.changed.isEmpty || !$0.removed.isEmpty }
        // Each folder holds what its version listed and nothing else: whatever else the unpacking brought is removed.
        for version in versions {
            let base = out.appendingPathComponent(version.folder)
            guard kept.contains(where: { $0.folder == version.folder }) else { try? fm.removeItem(at: base); continue }
            let wanted = Set(version.changed)
            for case let file as URL in fm.enumerator(at: base, includingPropertiesForKeys: nil) ?? FileManager.DirectoryEnumerator() {
                let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isDirectory == true, values?.isSymbolicLink != true { continue }
                if !wanted.contains(Sharing.relativePath(of: file, in: base)) { try? fm.removeItem(at: file) }
            }
        }
        // The latest picture of the app, so the other copy can be seen before it's mixed.
        if let picture = ([start.head] + kept.reversed().map(\.id)).lazy.map({ Versions.pictureURL(in: project, for: $0) })
            .first(where: { fm.fileExists(atPath: $0.path) }) {
            try? fm.copyItem(at: picture, to: out.appendingPathComponent(Self.picture))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(MixHistory(base: start.base, versions: kept)),
              (try? data.write(to: out.appendingPathComponent(file))) != nil else {
            try? fm.removeItem(at: out)
            return
        }
    }

    /// Where the run starts. A copy (its chain names a version of this wish that isn't in its own history: the one it
    /// was given) starts at the version it arrived as, and names the given one. A wish that began here starts at the
    /// version it was first shared at, kept from then on. A remix made from another wish on this Mac (its chain ends at
    /// that wish, and its history is that wish's) starts where it was remixed: the original has that version, and its
    /// first version, the new name and icon, is sent as the one the rest is rebuilt on.
    private static func start(of project: LampProject, credits: Credits, identity: String?) -> (commit: String, base: String, head: String, began: String?)? {
        let head = Versions.gitBlocking("git rev-parse HEAD", cwd: project.dir)
        guard head.ok, let now = Credits.validCommit(head.output) else { return nil }
        let link = Credits.Remix(name: project.name, wish: identity)
        if identity != nil, let given = credits.remixOf.last(where: { $0.sameWish(as: link) })?.commit.flatMap(Credits.validCommit),
           !isAncestor(given, in: project), let arrival = arrival(in: project) {
            return (arrival, given, now, nil)
        }
        if let identity, let original = credits.remixOf.last, original.wish != nil, original.wish != identity,
           let remixed = remixed(from: original.name, in: project) {
            return (remixed.parent, remixed.parent, now, remixed.commit)
        }
        let file = project.dir.appendingPathComponent(startFile)
        if let kept = (try? String(contentsOf: file, encoding: .utf8)).flatMap(Credits.validCommit), isAncestor(kept, in: project) {
            return (kept, kept, now, nil)
        }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? now.write(to: file, atomically: true, encoding: .utf8)
        return (now, now, now, nil)
    }

    /// The version a remix began as (Store's "Remix of …"), and the original's version before it.
    private static func remixed(from name: String, in project: LampProject) -> (commit: String, parent: String)? {
        let listed = Versions.gitBlocking("git log --first-parent --format='%H %P%x1f%s'", cwd: project.dir)
        guard listed.ok else { return nil }
        for line in listed.output.split(separator: "\n") {
            let parts = line.split(separator: "\u{1f}", maxSplits: 1).map(String.init)
            let ids = parts.first?.split(separator: " ").map(String.init) ?? []
            if parts.count == 2, parts[1] == "Remix of \(name)", ids.count >= 2,
               let commit = Credits.validCommit(ids[0]), let parent = Credits.validCommit(ids[1]) {
                return (commit, parent)
            }
        }
        return nil
    }

    /// The latest version that came in a shared file (Store's arrival messages, but not a starter's).
    static func arrival(in project: LampProject) -> String? {
        let listed = Versions.gitBlocking("git log --first-parent --format='%H%x1f%s'", cwd: project.dir)
        guard listed.ok else { return nil }
        for line in listed.output.split(separator: "\n") {
            let parts = line.split(separator: "\u{1f}", maxSplits: 1).map(String.init)
            if parts.count == 2, ["Imported from a shared file", "Updated from a shared file"].contains(parts[1]) { return Credits.validCommit(parts[0]) }
        }
        return nil
    }

    static func isAncestor(_ commit: String, in project: LampProject) -> Bool {
        Versions.gitBlocking("git merge-base --is-ancestor \(commit) HEAD", cwd: project.dir).ok
    }

    // MARK: Receiving

    /// The run a shared file carries, read from its unpacked folder; nil for a file with none, or one that doesn't read
    /// as one. Paths are the sender's word, so only plain relative ones are taken, and only to plain files.
    static func read(in package: URL) -> MixHistory? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let out = package.appendingPathComponent(folder)
        guard let data = try? Data(contentsOf: out.appendingPathComponent(file)),
              var history = try? decoder.decode(MixHistory.self, from: data),
              let base = Credits.validCommit(history.base) else { return nil }
        history.base = base
        history.versions = history.versions.compactMap { version in
            var version = version
            guard let id = Credits.validCommit(version.id), Int(version.folder) != nil else { return nil }
            version.id = id
            version.mixed = Credits.validCommit(version.mixed)
            let base = out.appendingPathComponent(version.folder)
            version.changed = version.changed.filter { isSafe($0) && isPlainFile(base.appendingPathComponent($0)) }
            version.removed = version.removed.filter(isSafe)
            return version
        }
        return history
    }

    /// A relative path inside the wish, with nothing git or a line-by-line plan would read otherwise.
    static func isSafe(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.hasPrefix("\"") && !path.contains("\n") && !path.contains("\t")
            && !path.split(separator: "/").contains { $0 == ".." || $0 == "." || $0 == ".git" }
    }

    /// A plain file, reached through no link.
    private static func isPlainFile(_ url: URL) -> Bool {
        var walked = url
        while walked.path.count > 1 {
            guard let values = try? walked.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink != true else { return false }
            if walked.lastPathComponent == folder { break }
            walked.deleteLastPathComponent()
        }
        return (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

    /// The picture the file carries of the sender's app, when it has one.
    static func pictureURL(in package: URL) -> URL? {
        let url = package.appendingPathComponent(folder).appendingPathComponent(picture)
        return isPlainFile(url) ? url : nil
    }

    /// Where a version's copy of a file is in the unpacked file.
    static func url(of path: String, in version: Version, package: URL) -> URL {
        package.appendingPathComponent(folder).appendingPathComponent(version.folder).appendingPathComponent(path)
    }
}
