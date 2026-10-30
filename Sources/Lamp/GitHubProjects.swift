import CryptoKit
import Foundation

/// Someone's project on GitHub made into a Lamp app by the agent, when the person asks (the github-projects skill). The
/// agent reads the project in a clone of its own, made with git as the skill says; `lampify` gives the wish what a Lamp
/// app has that the project doesn't, from a copy of Lamp's at one pinned commit that nothing has touched: the credit at
/// that commit, every license and notice file, the manifest, and a check of the whole shape that answers with what's
/// still missing. Nothing here is decided from the person's words, and nothing is fetched unless the agent calls it.
enum GitHubProjects {
    /// Lamp's copy of the project at one commit, in the wish's .lamp (which its versions and its shared file leave out):
    /// ".lamp/lampify/<owner>/<name>@<commit>". Two owners' projects of one name, or two commits of one project, are
    /// never taken for each other.
    struct Snapshot: Equatable {
        let owner: String
        let name: String
        let commit: String
        let folder: URL

        var url: String { "https://github.com/\(owner)/\(name)" }
        static func path(owner: String, name: String, commit: String) -> String { ".lamp/lampify/\(owner)/\(name)@\(commit)" }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// How a project is fetched into a folder at a branch, tag or commit: Lamp's own confined git, then the person's
    /// GitHub sign-in for a project only they can read. Tests put their own in place.
    typealias Fetch = (RepoImport.Source, URL) async throws -> URL
    nonisolated(unsafe) static var fetcher: Fetch = fetchAnyway

    /// Lamp's own confined git first, as Open from GitHub… fetches; a project it can't read (private, or not there)
    /// again with the person's GitHub sign-in (`gh`), as Put on GitHub… pushes, when they have one. The agent's shell
    /// can't see that sign-in, so this is how a private project reaches a wish.
    static func fetchAnyway(_ source: RepoImport.Source, into folder: URL) async throws -> URL {
        do {
            return try await RepoImport.clone(source, into: folder)
        } catch let anonymous {
            guard let gh = await Publish.gh(), await Publish.login(gh: gh) != nil else { throw anonymous }
            return try await cloneSignedIn(source, into: folder, gh: gh)
        }
    }

    /// The fetch with the person's sign-in, for these commands alone (`GitHubRepo.signedIn`): nothing is kept in a git
    /// configuration, and git never asks for anything on its own.
    private static func cloneSignedIn(_ source: RepoImport.Source, into folder: URL, gh: String) async throws -> URL {
        let fm = FileManager.default
        let tree = folder.appendingPathComponent(source.name)
        try? fm.removeItem(at: tree)
        try fm.createDirectory(at: tree, withIntermediateDirectories: true)
        let steps: [[String]] = [
            ["init", "-q"], ["remote", "add", "origin", source.url + ".git"],
            GitHubRepo.signedIn(gh: gh) + ["fetch", "-q", "--depth", "1", "origin", source.ref ?? "HEAD"],
            ["checkout", "-q", "--detach", "FETCH_HEAD"],
        ]
        for step in steps {
            let ran = await Subprocess.run(GitHubRepo.git, step, cwd: tree, env: ["GIT_TERMINAL_PROMPT": "0"], timeout: 600)
            guard ran.ok else {
                throw Failure(message: "Lamp couldn't get \(source.owner)/\(source.name) from GitHub, with or without the person's GitHub sign-in. Check the address and that it's theirs to read.")
            }
        }
        return tree
    }

    /// The commit to make the wish from: the one given; else the one the wish is already credited at, so a later call
    /// never moves a branch on by itself; else the commit the address names; else nil, for the branch, tag or default
    /// branch to be read once. A commit given that isn't the one credited is refused: moving on is an update's.
    static func pin(_ source: RepoImport.Source, given: String?, credits: Credits) throws -> String? {
        let credited = credits.upstream.first { Credits.Source.plain($0.url ?? "") == Credits.Source.plain(source.url) }?.commit
        if let given {
            guard let commit = Credits.validCommit(given), commit.count >= 40 else {
                throw Failure(message: "commit is the full hash of a commit (40 characters), as `git rev-parse HEAD` prints it in your clone.")
            }
            if let credited, credited != commit {
                throw Failure(message: "This wish is made from \(source.owner)/\(source.name) at \(credited). Work from that commit (check it out in your clone); a newer one comes in as the app's update.")
            }
            return commit
        }
        if let credited { return credited }
        if let ref = source.ref, let commit = Credits.validCommit(ref), commit.count >= 40 { return commit }
        return nil
    }

    /// Lamp's copy at the pinned commit, fetched only when it isn't in the wish already, and checked to be that commit
    /// of that repository: what's credited is exactly what was read.
    static func snapshot(_ source: RepoImport.Source, commit: String?, in wish: URL, using fetch: Fetch) async throws -> Snapshot {
        let fm = FileManager.default
        if let commit, let kept = await kept(source, commit: commit, in: wish) { return kept }
        let work = RepoImport.cloneFolder()
        defer { try? fm.removeItem(at: work) }
        var wanted = source
        if let commit { wanted.ref = commit }
        let tree = try await fetch(wanted, work)
        guard let at = RepoImport.repository(of: tree), let got = at.commit, got.count >= 40,
              Credits.Source.plain(at.url) == Credits.Source.plain(source.url) else {
            throw Failure(message: "Lamp got \(source.owner)/\(source.name) but couldn't tell which commit it is.")
        }
        if let commit, got != commit {
            throw Failure(message: "GitHub gave \(got) for \(source.owner)/\(source.name), not \(commit). Check the commit is in that repository.")
        }
        let folder = wish.appendingPathComponent(Snapshot.path(owner: source.owner, name: source.name, commit: got))
        // A copy left there that isn't what the commit holds (changed, or with files added) is replaced by this one.
        try? fm.removeItem(at: folder)
        try fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: tree, to: folder)
        return Snapshot(owner: source.owner, name: source.name, commit: got, folder: folder)
    }

    /// The copy already in the wish, when it's still exactly that commit of that repository: every file as the commit
    /// holds it and no file it doesn't. Anything else in the wish can write there, so it's checked before each use.
    private static func kept(_ source: RepoImport.Source, commit: String, in wish: URL) async -> Snapshot? {
        let folder = wish.appendingPathComponent(Snapshot.path(owner: source.owner, name: source.name, commit: commit))
        guard let at = RepoImport.repository(of: folder), at.commit == commit,
              Credits.Source.plain(at.url) == Credits.Source.plain(source.url),
              await untouched(folder) else { return nil }
        return Snapshot(owner: source.owner, name: source.name, commit: commit, folder: folder)
    }

    /// Whether the files in a clone are the ones its commit holds, compared by Lamp itself: git's object ids from the
    /// commit's tree (`ls-tree`, which reads only the repository's objects and runs nothing its configuration names, as
    /// `status` could), against each file's id worked out here. A file changed, added, removed or made a link fails it.
    static func untouched(_ clone: URL) async -> Bool {
        let listed = await Subprocess.run(GitHubRepo.git, ["-c", "core.fsmonitor=false", "ls-tree", "-r", "-z", "--full-tree", "HEAD"],
                                          cwd: clone, env: ["GIT_TERMINAL_PROMPT": "0"], mergeErrors: false, timeout: 120)
        guard listed.ok else { return false }
        var expected: [String: (mode: String, id: String)] = [:]
        for entry in listed.output.split(separator: "\0") {
            // "<mode> <type> <id>\t<path>"
            guard let tab = entry.firstIndex(of: "\t") else { return false }
            let fields = entry[..<tab].split(separator: " ")
            guard fields.count == 3 else { return false }
            if fields[1] == "commit" { continue }   // a submodule, never fetched
            expected[String(entry[entry.index(after: tab)...])] = (String(fields[0]), String(fields[2]))
        }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        guard let items = fm.enumerator(at: clone, includingPropertiesForKeys: keys) else { return false }
        var seen = 0
        for case let item as URL in items {
            let path = Sharing.relativePath(of: item, in: clone)
            if path == ".git" { items.skipDescendants(); continue }
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true, values?.isSymbolicLink != true { continue }
            guard let want = expected[path] else { return false }
            let data: Data?
            if values?.isSymbolicLink == true {
                guard want.mode == "120000" else { return false }
                data = (try? fm.destinationOfSymbolicLink(atPath: item.path)).map { Data($0.utf8) }
            } else {
                guard values?.isRegularFile == true, want.mode != "120000" else { return false }
                data = try? Data(contentsOf: item, options: .mappedIfSafe)
            }
            guard let data, blobID(data) == want.id else { return false }
            seen += 1
        }
        return seen == expected.count
    }

    /// git's id for a file's contents: SHA-1 of "blob <size>\0" and the contents.
    static func blobID(_ data: Data) -> String {
        var hash = Insecure.SHA1()
        hash.update(data: Data("blob \(data.count)\0".utf8))
        hash.update(data: data)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Records the snapshot as work the wish uses: its credit at that commit (through `Credits.add`, Lamp's own record
    /// included) and every license and notice file in it, kept in "Licenses/<owner>/<name>/" as they came. `adapted`
    /// marks it as the project the wish is made from, which the wish's updates follow (`Credits.basis`), or as something
    /// it only uses; a wish is made from one project only. Nothing is written when anything can't be: a credit is never
    /// left without its licenses. Also says how many license and notice files there were beyond the most Lamp keeps.
    @discardableResult
    static func credit(_ snapshot: Snapshot, adapted: Bool, in wish: LampProject) throws -> (source: Credits.Source, beyond: Int) {
        let credits = Credits.load(wish)
        if adapted, let basis = credits.upstream.first(where: { $0.adapted == true }),
           Credits.Source.plain(basis.url ?? "") != Credits.Source.plain(snapshot.url) {
            throw Failure(message: "This wish is already made from \(basis.name) (\(basis.url ?? "")). Lampify \(snapshot.owner)/\(snapshot.name) with adapted false for something it uses, or make a new wish from it.")
        }
        // The owner and the name are folders of their own: "foo-bar/baz" and "foo/bar-baz" never share one.
        let place = "\(RepoLicenses.folder)/\(snapshot.owner)/\(snapshot.name)"
        let terms = try RepoLicenses.keep(from: snapshot.folder, place: place, terms: "\(snapshot.owner).\(snapshot.name)", in: wish.dir)
        let source = Credits.Source(name: snapshot.name, author: snapshot.owner, url: snapshot.url, commit: snapshot.commit,
                                    license: terms.license, licenseFile: terms.licenseFile,
                                    noticeFiles: terms.notices.isEmpty ? nil : terms.notices, adapted: adapted)
        try Credits.add(Credits(upstream: [source]), to: wish)
        return (source, terms.beyond)
    }

    /// The wish as a Lamp repository would hold it, and what it still lacks. The structure, its line and APP.md are looked
    /// for in the wish; then it's made as Put on GitHub… makes one (`GitHubRepo.stage`: lamp-app.json from the shared
    /// file's own manifest, credits.json, the icon, the license files, Lamp's own files) and opened again as Open from
    /// GitHub… opens one (`RepoImport.open`), with nothing put anywhere. Whatever sharing refuses is something missing,
    /// said as it says it. The tree is kept in .lamp/repository for a look.
    struct Shape {
        var manifest: String?
        var missing: [String]
        var route: AppUpdates.Route?
    }

    static func shape(of wish: LampProject) -> Shape {
        let fm = FileManager.default
        var shape = Shape(manifest: nil, missing: [], route: AppUpdates.route(for: Credits.load(wish), own: nil))
        let (root, parts) = Sharing.layout(of: wish)
        guard root.hasScaffold || !parts.isEmpty else {
            shape.missing.append("Its structure: give the wish its app with make_app_for (a game or an app, web or native), then bring the project's code and assets into it.")
            return shape
        }
        let folder = root.dir.standardizedFileURL == wish.dir.standardizedFileURL ? "" : root.dir.lastPathComponent + "/"
        if Sharing.description(of: wish) == nil {
            shape.missing.append("Its line: one plain sentence saying what it is, in \(folder)\(AppDescription.file).")
        }
        let appMd = (try? String(contentsOf: root.dir.appendingPathComponent("APP.md"), encoding: .utf8)) ?? ""
        if let basis = Credits.load(wish).basis, !appMd.localizedCaseInsensitiveContains(basis.name) {
            shape.missing.append("\(folder)APP.md saying what it is and that it's based on \(basis.name) by \(basis.author ?? "its author").")
        }
        do {
            let staged = try GitHubRepo.stage(wish, repo: nil, link: nil)
            defer { try? fm.removeItem(at: staged.folder.deletingLastPathComponent()) }
            let package = try RepoImport.open(folder: staged.folder)
            defer { try? fm.removeItem(at: package.folder) }
            shape.manifest = try? String(contentsOf: staged.folder.appendingPathComponent("lamp-app.json"), encoding: .utf8)
            for path in (package.credits?.upstream ?? []).flatMap(\.termsFiles)
            where !fm.fileExists(atPath: package.folder.appendingPathComponent(path).path) {
                shape.missing.append("\(path), which credits.json names, where Lamp's importer looks for it.")
            }
            let kept = wish.dir.appendingPathComponent(".lamp/repository")
            try? fm.removeItem(at: kept)
            try? fm.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: staged.folder, to: kept)
        } catch {
            shape.missing.append([error.localizedDescription, (error as? LocalizedError)?.recoverySuggestion].compactMap { $0 }.joined(separator: " "))
        }
        return shape
    }

    /// A line with a request that names a project on GitHub, sent with it as Lamp's other notes are: which skill says
    /// how to go about it. It says nothing of what the person wants (the request does), only where the way is.
    static func note(for request: String) -> String {
        let names = request.split(whereSeparator: \.isWhitespace).contains { token in
            let bare = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>()[]{}\"'“”‘’`.,;:!?"))
            return bare.lowercased().contains("github.com/") && RepoImport.source(from: bare) != nil
        }
        guard names else { return "" }
        return "\n\n---\nThis request names a project on GitHub (from Lamp, not part of the request above): open the github-projects skill with `read_skill` before doing anything with it. It says how to read the project in a git clone of your own, and how `lampify` gives an app made from it its credit, its licenses and a Lamp app's shape."
    }
}

extension Store {
    /// `lampify`, the same for every engine (`/agent/lampify` for pi, `Store.mcp` for Claude Code and Codex). Its work is
    /// Lamp's own (a confined fetch into the wish's .lamp, files written by Lamp), so it asks no approval; it never runs
    /// anything the project holds, and the agent's own commands, its clone included, go through `/agent/approve` as ever.
    func lampify(_ arguments: [String: Any], for project: LampProject) async -> (Int, [String: Any]) {
        let wish = wish(of: project)
        guard let source = RepoImport.source(from: arguments["url"] as? String ?? "") else {
            return (400, ["error": "url is the project's address on GitHub: https://github.com/owner/name, with /tree/<branch, tag or commit> for one that isn't its default branch."])
        }
        // The address as it was given, branch or tag included, for whatever the answer asks the agent or the person to use.
        let address = source.url + (source.ref.map { "/tree/\($0)" } ?? "")
        do {
            let given = (arguments["commit"] as? String)?.trimmed.nilIfEmpty
            // Reading credits nothing, so it reads the version asked for (the commit given, else the address's), whatever
            // the wish is credited at: the pin to the credited commit is for what the app is made from.
            let reading = arguments["read_only"] as? Bool == true
            let commit = try GitHubProjects.pin(source, given: given, credits: reading ? Credits() : Credits.load(wish))
            let snapshot = try await GitHubProjects.snapshot(source, commit: commit, in: wish.dir, using: GitHubProjects.fetcher)
            if reading {
                return (200, ["text": "Lamp's copy of \(snapshot.owner)/\(snapshot.name) at commit \(snapshot.commit), for reading: \(snapshot.folder.path)\nNothing was credited and nothing was made. To make an app from it, call lampify without read_only, with commit \(snapshot.commit)."])
            }
            guard !RepoImport.holdsWish(snapshot.folder) else {
                return (400, ["error": "\(source.owner)/\(source.name) is a Lamp wish already: don't rebuild it. Tell the person to open it with File → Open from GitHub… and paste \(address)."])
            }
            let adapted = arguments["adapted"] as? Bool ?? true
            let credited = try GitHubProjects.credit(snapshot, adapted: adapted, in: wish)
            reload()
            var shape = GitHubProjects.shape(of: self.wish(of: project))
            if credited.beyond > 0 {
                shape.missing.insert("All of \(snapshot.owner)/\(snapshot.name)'s terms: it has \(credited.beyond) license and notice files beyond the \(RepoLicenses.most) Lamp keeps, so its credit may not hold every term it comes with. Tell the person, and don't say it can be shared.", at: 0)
            }
            return (200, ["text": GitHubProjects.answer(snapshot, credited: credited.source, adapted: adapted, pinnedNow: commit == nil, shape: shape)])
        } catch {
            return (400, ["error": [error.localizedDescription, (error as? LocalizedError)?.recoverySuggestion].compactMap { $0 }.joined(separator: " ")])
        }
    }
}

extension GitHubProjects {
    static func answer(_ snapshot: Snapshot, credited: Credits.Source, adapted: Bool, pinnedNow: Bool, shape: Shape) -> String {
        var lines = ["\(snapshot.owner)/\(snapshot.name) at commit \(snapshot.commit)" + (adapted ? ", the project this wish is made from (its updates come from there)." : ", something the app uses.")]
        if pinnedNow {
            lines.append("Lamp pinned that commit: check it out in your clone (`git -C <clone> checkout \(snapshot.commit)`) so you copy from what's credited, and pass commit \(snapshot.commit) when you call lampify again.")
        }
        lines.append("Lamp's untouched copy at that commit, for reading if your clone can't be made (a private project): \(snapshot.folder.path)")
        if let file = credited.licenseFile {
            lines.append("Credited in credits.json with license \(credited.license ?? "?"), kept in " + ([file] + (credited.noticeFiles ?? [])).joined(separator: ", ") + ". Keep these files and the author's credit on screen; never change them.")
        } else {
            lines.append("Credited in credits.json. It came with no license of its own: it can be used on this Mac but not shared or published. Tell the person.")
        }
        if let manifest = shape.manifest { lines.append("lamp-app.json, as Lamp makes it:\n" + manifest) }
        switch shape.route {
        case .adapted(let source)?: lines.append("Updates follow \(source.url ?? "") from \(source.commit ?? "its commit") (its default branch).")
        case .wish(let remix)?: lines.append("Updates follow the wish it was remixed from, \(remix.url ?? remix.name).")
        case nil: break
        }
        if shape.missing.isEmpty {
            lines.append("Nothing missing: opened again as Lamp's importer opens a repository, it's a whole Lamp app. Nothing was put on GitHub.")
        } else {
            lines.append("Still missing:\n" + shape.missing.map { "- " + $0 }.joined(separator: "\n"))
            lines.append("Bring the project's code and assets into the app's own structure without copying its build scripts or project files over Lamp's (Package.swift, build.sh, Sources/LampSupport.swift, the lamp*.js files), then call lampify again.")
        }
        return lines.joined(separator: "\n")
    }
}

/// A project's license and notice files, kept in the wish as they came (`Credits.Source.licenseFile` names its own
/// license, `noticeFiles` the rest), each a file of its own at its place in the project: a project under two licenses,
/// with a NOTICE beside its license, or with a library's license in that library's folder, keeps them all apart.
enum RepoLicenses {
    /// Where they go in the wish: "Licenses/PavelDoGreat/WebGL-Fluid-Simulation/LICENSE".
    static let folder = "Licenses"
    /// Folders whose licenses are the project's tools', not anything it ships, and the most a project keeps.
    private static let skipped: Set<String> = [".git", "node_modules", ".build", "build", "Pods", ".github"]
    static let most = 200

    /// The files anywhere in a tree that hold terms (LICENSE, LICENCE, COPYING, UNLICENSE and NOTICE, with or without an
    /// extension or suffix, as the credits can name them: `Credits.isLicenceFile`), by their paths in it. Regular files
    /// only, none larger than a license would be, so a link or a folder of that name brings nothing in. The project's own
    /// at its top come first, then the rest by path, every one of them: `keep` decides how many it takes.
    static func files(in tree: URL) -> [String] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey]
        guard let items = FileManager.default.enumerator(at: tree, includingPropertiesForKeys: keys) else { return [] }
        var found: [String] = []
        for case let item as URL in items {
            let values = try? item.resourceValues(forKeys: Set(keys))
            // A link brings nothing in, and isn't followed. Only a folder's own contents are skipped: skipping at a file
            // would skip the last folder entered instead.
            if values?.isSymbolicLink == true { continue }
            if values?.isDirectory == true { if skipped.contains(item.lastPathComponent) { items.skipDescendants() }; continue }
            guard values?.isRegularFile == true, (values?.fileSize ?? 0) <= 512 * 1024, Credits.isLicenceFile(item.lastPathComponent) else { continue }
            found.append(Sharing.relativePath(of: item, in: tree))
        }
        return found.sorted { ($0.contains("/") ? 1 : 0, $0) < ($1.contains("/") ? 1 : 0, $1) }
    }

    static func isNotice(_ path: String) -> Bool { (path as NSString).lastPathComponent.uppercased().hasPrefix("NOTICE") }

    /// The SPDX id of a license text Lamp can tell for certain; nil for anything else. GPL, LGPL and AGPL texts are
    /// never named: the text is the same for "only" and "or later", which only the project's own files say.
    static func id(of text: String) -> String? {
        let plain = text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        func has(_ phrase: String) -> Bool { plain.contains(phrase) }
        if has("gnu general public license") || has("gnu lesser general public license") || has("gnu affero general public license") { return nil }
        if has("permission is hereby granted, free of charge, to any person obtaining a copy")
            && has("the above copyright notice and this permission notice shall be included") { return "MIT" }
        if has("apache license") && has("version 2.0, january 2004") { return "Apache-2.0" }
        if has("mozilla public license version 2.0") { return "MPL-2.0" }
        if has("this is free and unencumbered software released into the public domain") { return "Unlicense" }
        if has("cc0 1.0 universal") { return "CC0-1.0" }
        if has("permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted") { return "ISC" }
        if has("redistribution and use in source and binary forms, with or without modification, are permitted") {
            // The advertising clause makes it the four-clause license, which is named here no more than any other.
            if has("advertising materials") { return nil }
            return has("neither the name") || has("may be used to endorse or promote products") ? "BSD-3-Clause" : "BSD-2-Clause"
        }
        return nil
    }

    /// Copies the tree's license and notice files into the wish at `place`, each at its path in the project, and says what
    /// the credit records. The project's own license is one at its top: its SPDX id when there's one such file Lamp can
    /// tell for certain; terms of their own (`LicenseRef-`, the text the authority) when its id can't be told for
    /// certain; none when there's no license at its top (its libraries' licenses are still kept, as notices). At most
    /// `most` are kept, its own first, and `beyond` says how many more there were, never silently left out. Throws when
    /// a file can't be written: no credit goes without them. `terms` names terms of its own: "LicenseRef-<terms>".
    static func keep(from tree: URL, place: String, terms: String, in wish: URL) throws -> (license: String?, licenseFile: String?, notices: [String], beyond: Int) {
        let all = files(in: tree)
        let found = Array(all.prefix(most))
        guard !found.isEmpty else { return (nil, nil, [], 0) }
        let fm = FileManager.default
        for path in found {
            let copy = wish.appendingPathComponent("\(place)/\(path)")
            try fm.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: copy.path) { try fm.removeItem(at: copy) }
            try fm.copyItem(at: tree.appendingPathComponent(path), to: copy)
        }
        let own = found.filter { !$0.contains("/") && !isNotice($0) }
        let paths = found.map { "\(place)/\($0)" }
        let beyond = all.count - found.count
        guard let first = own.first else { return (nil, nil, paths, beyond) }
        let firstPath = "\(place)/\(first)"
        // Several licenses at its top (MIT and Apache, say) may be a choice or both at once: only the project says which.
        let certain = own.count == 1 ? (try? String(contentsOf: tree.appendingPathComponent(first), encoding: .utf8)).flatMap(Self.id(of:)) : nil
        let reference = "LicenseRef-" + String(terms.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") ? $0 : "-" })
        return (certain ?? reference, firstPath, paths.filter { $0 != firstPath }, beyond)
    }
}
