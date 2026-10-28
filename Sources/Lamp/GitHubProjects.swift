import Foundation

/// Someone's project on GitHub, brought into a wish by the agent when a request needs it (`github_project`, the
/// github-projects skill): Lamp fetches it, records its credit and keeps its license files, opens a wish someone put on
/// GitHub in the import review, and checks what the wish would be as a Lamp repository. Nothing here is decided from
/// the person's words: the agent asks for each step, and nothing is fetched unless it does.
enum GitHubProjects {
    /// A fetched project at one commit, in the wish's .lamp (which its versions and its shared file leave out):
    /// ".lamp/reference/<owner>/<name>@<commit>". Its handle names exactly that, so two owners' projects of one name,
    /// or two commits of one project, are never taken for each other.
    struct Snapshot: Equatable {
        let owner: String
        let name: String
        let commit: String
        let folder: URL

        var handle: String { "\(owner)/\(name)@\(commit)" }
        var url: String { "https://github.com/\(owner)/\(name)" }
        static func path(owner: String, name: String, commit: String) -> String { ".lamp/reference/\(owner)/\(name)@\(commit)" }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// How a project is fetched into a folder: Lamp's own confined git, then the person's GitHub sign-in for a
    /// project only they can read. Tests put their own in place.
    typealias Fetch = (RepoImport.Source, URL) async throws -> URL

    /// Fetches the project at the branch, tag or commit `source` names (its default branch without one), one commit
    /// deep, into the wish. A commit fetched before is kept as it is: the same handle always means the same files.
    static func fetch(_ source: RepoImport.Source, into wish: URL, using fetch: Fetch = fetchAnyway) async throws -> Snapshot {
        let fm = FileManager.default
        let work = RepoImport.cloneFolder()
        defer { try? fm.removeItem(at: work) }
        let tree = try await fetch(source, work)
        guard let commit = RepoImport.repository(of: tree)?.commit, commit.count >= 40 else {
            throw Failure(message: "Lamp got \(source.owner)/\(source.name) but couldn't tell which commit it is.")
        }
        let path = Snapshot.path(owner: source.owner, name: source.name, commit: commit)
        let folder = wish.appendingPathComponent(path)
        if !fm.fileExists(atPath: folder.path) {
            try fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: tree, to: folder)
        }
        return Snapshot(owner: source.owner, name: source.name, commit: commit, folder: folder)
    }

    /// Lamp's own confined git first, as Open from GitHub… fetches; a project it can't read (private, or not there)
    /// again with the person's GitHub sign-in (`gh`), as Put on GitHub… pushes, when they have one.
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
        let git = GitHubRepo.git
        let steps: [[String]] = [
            ["init", "-q"], ["remote", "add", "origin", source.url + ".git"],
            GitHubRepo.signedIn(gh: gh) + ["fetch", "-q", "--depth", "1", "origin", source.ref ?? "HEAD"],
            ["checkout", "-q", "--detach", "FETCH_HEAD"],
        ]
        for step in steps {
            let ran = await Subprocess.run(git, step, cwd: tree, env: ["GIT_TERMINAL_PROMPT": "0"], timeout: 600)
            guard ran.ok else {
                throw Failure(message: "Lamp couldn't get \(source.owner)/\(source.name) from GitHub, with or without your GitHub sign-in. Check the address and that it's yours to read.")
            }
        }
        return tree
    }

    /// The snapshot a handle names, as it is in the wish: only one Lamp fetched there, still at that commit.
    static func snapshot(_ handle: String, in wish: URL) throws -> Snapshot {
        let parts = handle.trimmed.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, let source = RepoImport.source(from: "github.com/" + parts[0]), source.ref == nil,
              let commit = Credits.validCommit(parts[1]), commit.count >= 40 else {
            throw Failure(message: "That isn't a handle github_project gave: it looks like owner/name@<full commit>.")
        }
        let folder = wish.appendingPathComponent(Snapshot.path(owner: source.owner, name: source.name, commit: commit))
        guard let at = RepoImport.repository(of: folder), at.commit == commit,
              Credits.Source.plain(at.url) == Credits.Source.plain(source.url) else {
            throw Failure(message: "\(handle) isn't fetched in this wish (or was changed). Fetch it with github_project first.")
        }
        return Snapshot(owner: source.owner, name: source.name, commit: commit, folder: folder)
    }

    /// Records the snapshot as work the wish uses: its credit at that commit and its license and notice files, kept in
    /// "Licenses/<owner>-<name>/" each as it came. `adapted` marks it as the project the wish is made from, which the
    /// wish's updates follow (`Credits.basis`); a wish is made from one project only. Nothing is written when anything
    /// can't be: a credit is never left without its licenses.
    @discardableResult
    static func credit(_ snapshot: Snapshot, adapted: Bool, in wish: LampProject) throws -> Credits.Source {
        let credits = Credits.load(wish)
        if adapted, let basis = credits.upstream.first(where: { $0.adapted == true }),
           Credits.Source.plain(basis.url ?? "") != Credits.Source.plain(snapshot.url) {
            throw Failure(message: "This wish is already made from \(basis.name) (\(basis.url ?? "")). Credit \(snapshot.handle) as something it uses (adapted: false), or make a new wish from it.")
        }
        let place = "\(RepoLicenses.folder)/\(snapshot.owner)-\(snapshot.name)"
        let terms = try RepoLicenses.keep(from: snapshot.folder, place: place, in: wish.dir)
        let source = Credits.Source(name: snapshot.name, author: snapshot.owner, url: snapshot.url, commit: snapshot.commit,
                                    license: terms.license, licenseFile: terms.licenseFile,
                                    noticeFiles: terms.notices.isEmpty ? nil : terms.notices, adapted: adapted ? true : nil)
        try Credits.add(Credits(upstream: [source]), to: wish)
        return source
    }

    /// What the wish would be as a Lamp repository, made as Put on GitHub… makes one (`GitHubRepo.stage`: lamp-app.json
    /// from the shared file's own manifest, credits.json with the chain, the icon, the license files, Lamp's own files)
    /// and opened again as Open from GitHub… opens one (`RepoImport.open`), with nothing put anywhere. Kept in the wish's
    /// .lamp/repository for a look; what goes on GitHub is staged afresh when the person chooses to put it there.
    struct Check {
        let manifest: String
        let credits: Credits
        let route: AppUpdates.Route?
        let missing: [String]
        let folder: URL
    }

    static func check(_ wish: LampProject) throws -> Check {
        let fm = FileManager.default
        let staged = try GitHubRepo.stage(wish, repo: nil, link: nil)
        defer { try? fm.removeItem(at: staged.folder.deletingLastPathComponent()) }
        let package = try RepoImport.open(folder: staged.folder)
        defer { try? fm.removeItem(at: package.folder) }
        let credits = package.credits ?? Credits()
        // Every license and notice the credits name, where the importer finds the app's files.
        let missing = credits.upstream.flatMap(\.termsFiles).filter { !fm.fileExists(atPath: package.folder.appendingPathComponent($0).path) }
        let manifest = (try? String(contentsOf: staged.folder.appendingPathComponent("lamp-app.json"), encoding: .utf8)) ?? ""
        let kept = wish.dir.appendingPathComponent(".lamp/repository")
        try? fm.removeItem(at: kept)
        try fm.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: staged.folder, to: kept)
        return Check(manifest: manifest, credits: credits, route: AppUpdates.route(for: credits, own: nil), missing: missing, folder: kept)
    }
}

/// A project's license and notice files, kept in the wish as they came (`Credits.Source.licenseFile` names the license,
/// `noticeFiles` the rest), each a file of its own: a project under two licenses, or with a NOTICE beside its license,
/// keeps them apart.
enum RepoLicenses {
    /// Where they go in the wish: "Licenses/PavelDoGreat-WebGL-Fluid-Simulation/LICENSE".
    static let folder = "Licenses"

    /// The top-level files of a tree that hold its terms (LICENSE, LICENCE, COPYING, UNLICENSE and NOTICE, with or
    /// without an extension or suffix), as the credits can name them (`Credits.isLicenceFile`). Regular files only,
    /// none larger than a license would be, so a link or a folder of that name brings nothing in.
    static func files(in tree: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: tree, includingPropertiesForKeys: Array(keys))) ?? []
        return items.filter { item in
            guard Credits.isLicenceFile(item.lastPathComponent),
                  let values = try? item.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 512 * 1024 else { return false }
            return true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func isNotice(_ name: String) -> Bool { name.uppercased().hasPrefix("NOTICE") }

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

    /// Copies the tree's license and notice files into the wish at `place`, each under its own name, and says what the
    /// credit records: the license's SPDX id when there's one license file Lamp can tell for certain; terms of their own
    /// (`LicenseRef-`, which says the text is the authority) when the text is there but its id can't be told for
    /// certain; none when there's no license file. Throws when a file can't be written: no credit goes without them.
    static func keep(from tree: URL, place: String, in wish: URL) throws -> (license: String?, licenseFile: String?, notices: [String]) {
        let found = files(in: tree)
        guard !found.isEmpty else { return (nil, nil, []) }
        let fm = FileManager.default
        let target = wish.appendingPathComponent(place)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        for file in found {
            let copy = target.appendingPathComponent(file.lastPathComponent)
            if fm.fileExists(atPath: copy.path) { try fm.removeItem(at: copy) }
            try fm.copyItem(at: file, to: copy)
        }
        let licenses = found.filter { !isNotice($0.lastPathComponent) }
        let paths = found.map { "\(place)/\($0.lastPathComponent)" }
        guard let first = licenses.first else { return (nil, nil, paths) }
        let firstPath = "\(place)/\(first.lastPathComponent)"
        // Several licenses (MIT and Apache, say) may be a choice or both at once: only the project says which.
        let certain = licenses.count == 1 ? (try? String(contentsOf: first, encoding: .utf8)).flatMap(Self.id(of:)) : nil
        let own = "LicenseRef-" + String((place.split(separator: "/").last ?? "Terms").map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") ? $0 : "-" })
        return (certain ?? own, firstPath, paths.filter { $0 != firstPath })
    }
}

extension GitHubProjects {
    /// How `github_project` fetches, and opens a wish found on GitHub: Lamp's own, which tests replace.
    nonisolated(unsafe) static var fetcher: Fetch = fetchAnyway
    @MainActor static var openImport: (@MainActor (URL) -> Void)?
}

extension Store {
    /// `github_project`, the same for every engine (`/agent/github` for pi, `Store.mcp` for Claude Code and Codex). Its
    /// work is Lamp's own (a confined fetch into the wish's .lamp, files written by Lamp), so it asks no approval; it
    /// never runs anything the project holds, and the agent's own commands go through `/agent/approve` as ever.
    func githubProject(_ arguments: [String: Any], for project: LampProject) async -> (Int, [String: Any]) {
        let wish = wish(of: project)
        do {
            switch arguments["action"] as? String ?? "" {
            case "fetch":
                guard let source = RepoImport.source(from: arguments["url"] as? String ?? "") else {
                    return (400, ["error": "That isn't a repository on GitHub: give its address, like https://github.com/owner/name, with /tree/<branch, tag or commit> after it if one is meant."])
                }
                let snapshot = try await GitHubProjects.fetch(source, into: wish.dir, using: GitHubProjects.fetcher)
                return (200, ["text": GitHubProjects.fetched(snapshot)])
            case "build_from":
                let snapshot = try GitHubProjects.snapshot(arguments["handle"] as? String ?? "", in: wish.dir)
                guard !RepoImport.holdsWish(snapshot.folder) else {
                    return (400, ["error": "\(snapshot.handle) is a Lamp wish already: hand it to Lamp with action open_wish instead of rebuilding it."])
                }
                let adapted = arguments["adapted"] as? Bool ?? true
                let source = try GitHubProjects.credit(snapshot, adapted: adapted, in: wish)
                reload()
                return (200, ["text": GitHubProjects.credited(source, adapted: adapted)])
            case "open_wish":
                let snapshot = try GitHubProjects.snapshot(arguments["handle"] as? String ?? "", in: wish.dir)
                guard RepoImport.holdsWish(snapshot.folder) else {
                    return (400, ["error": "\(snapshot.handle) isn't a Lamp wish (no lamp-app.json or shared file at its top). Make the app from it with build_from instead."])
                }
                // A copy in a folder of Lamp's, as a fetched wish's is, with the request beside it for the new wish's box.
                let folder = RepoImport.cloneFolder()
                let tree = folder.appendingPathComponent(snapshot.name)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: snapshot.folder, to: tree)
                if let request = Wish.tidy(arguments["request"] as? String) {
                    try request.write(to: folder.appendingPathComponent(WaitingImport.requestFile), atomically: true, encoding: .utf8)
                }
                if let open = GitHubProjects.openImport { open(tree) } else { importApp(from: tree) }
                return (200, ["text": "Lamp opened \(snapshot.name)'s review for the person, with the request kept for the new wish's box. Tell them to look it over and choose; there's nothing to build here."])
            case "check":
                let check = try GitHubProjects.check(wish)
                return (200, ["text": GitHubProjects.checked(check, in: wish)])
            default:
                return (400, ["error": "action is fetch, build_from, open_wish or check."])
            }
        } catch {
            return (400, ["error": [error.localizedDescription, (error as? LocalizedError)?.recoverySuggestion].compactMap { $0 }.joined(separator: " ")])
        }
    }
}

extension GitHubProjects {
    /// A line with a request that names a project on GitHub, sent with it as Lamp's other notes are: which skill says
    /// how to go about it. It says nothing of what the person wants (the request does), only where the way is.
    static func note(for request: String) -> String {
        let names = request.split(whereSeparator: \.isWhitespace).contains { token in
            let bare = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>()[]{}\"'“”‘’`.,;:!?"))
            return bare.lowercased().contains("github.com/") && RepoImport.source(from: bare) != nil
        }
        guard names else { return "" }
        return "\n\n---\nThis request names a project on GitHub (from Lamp, not part of the request above): open the github-projects skill with `read_skill` before doing anything with it, and take its code and assets only through `github_project`."
    }

    static func fetched(_ snapshot: Snapshot) -> String {
        let terms = RepoLicenses.files(in: snapshot.folder)
        let licenses = terms.filter { !RepoLicenses.isNotice($0.lastPathComponent) }
        var lines = ["Fetched \(snapshot.owner)/\(snapshot.name) at commit \(snapshot.commit), read-only reference in \(snapshot.folder.path).",
                     "Handle: \(snapshot.handle)"]
        if licenses.isEmpty {
            lines.append("It has no license file: it can be used on this Mac but not shared or published. Say so to the person if you build from it.")
        } else {
            let id = licenses.count == 1 ? (try? String(contentsOf: licenses[0], encoding: .utf8)).flatMap(RepoLicenses.id(of:)) : nil
            lines.append("Terms: " + terms.map(\.lastPathComponent).joined(separator: ", ") + (id.map { " (\($0))" } ?? " (read them: Lamp can't name them for certain)") + ".")
        }
        if RepoImport.holdsWish(snapshot.folder) {
            lines.append("It's a Lamp wish someone put on GitHub: don't rebuild it. Hand it to Lamp with action open_wish, this handle and the person's request.")
        } else {
            lines.append("Nothing is credited yet. Before using any of its code or assets in the app, call build_from with this handle.")
        }
        return lines.joined(separator: "\n")
    }

    static func credited(_ source: Credits.Source, adapted: Bool) -> String {
        var lines = ["Credited \(source.name) by \(source.author ?? "?") at commit \(source.commit ?? "?") in credits.json" + (adapted ? ", as the project this wish is made from: its updates come from there." : ", as something the app uses.")]
        if source.licenseFile != nil {
            lines.append("License \(source.license ?? "?"), kept in " + source.termsFiles.joined(separator: ", ") + ". Keep these files and the author's credit on screen; never change them.")
        } else {
            lines.append("It came with no license: the app can't be shared or published. Tell the person.")
        }
        lines.append("Bring its code and assets into the app's own structure (make_app_for gives it): never copy its build scripts or project files over Lamp's (Package.swift, build.sh, Sources/LampSupport.swift, Web/lamp*.js). When the app works, call check.")
        return lines.joined(separator: "\n")
    }

    static func checked(_ check: Check, in wish: LampProject) -> String {
        var lines = ["lamp-app.json, as Lamp makes it:", check.manifest]
        if let basis = check.credits.basis {
            lines.append("Based on \(basis.name) at \(basis.commit ?? "no commit"), license \(basis.license ?? "none").")
        }
        switch check.route {
        case .adapted(let source)?: lines.append("Updates follow \(source.url ?? "") from that commit (its default branch).")
        case .wish(let remix)?: lines.append("Updates follow the wish it was remixed from, \(remix.url ?? remix.name).")
        case nil: lines.append("No updates: nothing it's based on is on GitHub at a commit.")
        }
        lines.append(check.missing.isEmpty ? "Every license and notice file is there, where Lamp's importer finds it."
                     : "Missing once opened again: " + check.missing.joined(separator: ", ") + ". Put them back where credits.json says.")
        lines.append("Opened again as Open from GitHub… opens a wish: it reads as a Lamp app. Nothing was put on GitHub; Put on GitHub… does that when the person chooses.")
        return lines.joined(separator: "\n")
    }
}
