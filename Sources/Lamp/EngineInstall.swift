import CryptoKit
import Foundation
import Security

/// The Claude Code and Codex Lamp runs. When the Mac already has one (installed for Terminal, or inside the
/// Claude or ChatGPT app), Lamp runs that copy as it is, with the person's own sign-in and folder (~/.claude,
/// ~/.codex), so someone who already uses it neither downloads nor signs in again. Lamp's runs stay apart from
/// the person's setup by their flags (`Agent.run`: `--restricted`, `--ignore-user-config` and the rest), not by
/// their folder; the copy updates itself, or not, as the person has it.
///
/// When the Mac has none, Lamp downloads its own from Anthropic or OpenAI and keeps it up to date, so building
/// with a Claude or ChatGPT subscription needs nothing else installed: no desktop app, no Terminal. That copy
/// has a sign-in and folder of its own (`configFolder`, through `CLAUDE_CONFIG_DIR` and `CODEX_HOME`): Claude
/// Code keeps the sign-in in the Keychain under a name made from its folder, so it stays apart from any the
/// person makes later. Once the person has a copy of their own, Lamp moves to it (`carryOver` brings each
/// app's conversation along), and stops updating its own.
///
/// What's kept of Lamp's copy: `Engines/<engine>/versions/<version>/` (the program, and for Codex the files it
/// ships with), `Engines/<engine>/current` (the version in use), and `Engines/<engine>/home` (the sign-in and
/// the tool's own state). The version in use and the one before it are kept, so a turn still running when an
/// update lands finishes on the version it started with.
enum EngineInstall {
    /// Lamp's own folder, which the sandbox and the privacy rule keep closed to the agent. A test points it
    /// at a folder of its own.
    private static let lock = NSLock()

    nonisolated(unsafe) static var folder = Edition.supportFolder.appendingPathComponent("Engines") {
        didSet { lock.lock(); current = [:]; lock.unlock() }
    }

    static func root(_ engine: Engine) -> URL { folder.appendingPathComponent(engine.rawValue) }
    static func versionsFolder(_ engine: Engine) -> URL { root(engine).appendingPathComponent("versions") }
    private static func currentFile(_ engine: Engine) -> URL { root(engine).appendingPathComponent("current") }

    /// The engine's settings, sign-in, conversations and caches for the copy in use: the person's own
    /// (~/.claude, ~/.codex) when Lamp runs theirs, else Lamp's copy's.
    static func configFolder(_ engine: Engine) -> URL {
        usesPersonsCopy(engine) ? personsFolder(engine) : ownConfigFolder(engine)
    }

    /// Lamp's copy's folder. Made on first use, readable only by the person.
    static func ownConfigFolder(_ engine: Engine) -> URL { root(engine).appendingPathComponent("home") }

    /// Where the person's own copy keeps its state.
    static func personsFolder(_ engine: Engine, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(engine == .codex ? ".codex" : ".claude")
    }

    /// The program inside a version's folder, as each vendor lays it out.
    private static func entry(_ engine: Engine) -> String { engine == .codex ? "bin/codex" : "claude" }

    /// The copy Lamp runs: the person's own when the Mac has one, else Lamp's (nil until it's downloaded).
    /// Always nil for pi, which comes inside Lamp.
    static func path(for engine: Engine) -> String? {
        guard engine != .pi else { return nil }
        return personsCopy(engine) ?? ownPath(for: engine)
    }

    /// Whether Lamp runs the person's own copy of the engine rather than its own.
    static func usesPersonsCopy(_ engine: Engine) -> Bool { engine != .pi && personsCopy(engine) != nil }

    /// The person's own copy, as the last look found it: nil until a look has run (`lookForPersonsCopies`).
    /// Never looks itself, since looking runs each copy found with --version and can take seconds, and this is
    /// asked whenever a screen redraws.
    static func personsCopy(_ engine: Engine) -> String? {
        // One removed since the look is gone now, not at the next look.
        lock.withLock { found[engine] ?? nil }.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
    }

    /// Whether a look for the person's copies has finished, so Lamp knows whether it needs its own.
    static var hasLooked: Bool { lock.withLock { looked } }

    nonisolated(unsafe) private static var found: [Engine: String?] = [:]
    nonisolated(unsafe) private static var looked = false

    /// How the person's copy is found. A test replaces it, so what's installed on the Mac running it doesn't count.
    nonisolated(unsafe) static var finder: (Engine) -> String? = findPersonsCopy {
        didSet { lock.withLock { found = [:]; looked = false } }
    }

    /// Looks for the person's copies now and remembers what's found. Blocking: off the main thread, through
    /// `lookForPersonsCopies`, except in a test.
    static func lookNow() {
        let results = [Engine.claude, .codex].map { ($0, finder($0)) }
        lock.withLock {
            for (engine, path) in results { found[engine] = path }
            looked = true
        }
    }

    /// Looks again off the main thread (at launch, and before Lamp would download its own copy, so one
    /// installed meanwhile is found), then has the screens that show the engines look again.
    static func lookForPersonsCopies() async {
        let before = [Engine.claude, .codex].map(personsCopy)
        await Task.detached(priority: .userInitiated) {
            _ = ToolLocator.userPath
            lookNow()
        }.value
        if [Engine.claude, .codex].map(personsCopy) != before { await EngineDownloads.shared.copiesChanged() }
    }

    /// The newest copy on the person's PATH or inside the desktop app (`ToolLocator`, which remembers it).
    private static func findPersonsCopy(_ engine: Engine) -> String? {
        switch engine {
        case .pi: nil
        case .claude: ToolLocator.path(named: "claude", alsoAt: desktopCopies(of: .claude))
        case .codex: ToolLocator.path(named: "codex", alsoAt: desktopCopies(of: .codex))
        }
    }

    /// Copies that come with the desktop apps: the Claude app keeps Claude Code in its support folder (one
    /// folder per version), and the ChatGPT app ships Codex inside its bundle: at first as `codex-cli/bin/codex`,
    /// and since October 2026 as an app of its own there, `codex-cli/CodexCLI.app`. Both are listed, since
    /// `ToolLocator` takes whichever is there (the newest when both are).
    private static func desktopCopies(of engine: Engine) -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        switch engine {
        case .pi:
            return []
        case .claude:
            let root = home + "/Library/Application Support/Claude/claude-code"
            return ((try? fm.contentsOfDirectory(atPath: root)) ?? []).flatMap { version in
                ((try? fm.contentsOfDirectory(atPath: "\(root)/\(version)")) ?? []).map {
                    "\(root)/\(version)/\($0)/claude.app/Contents/MacOS/claude"
                }
            }
        case .codex:
            return ["/Applications/ChatGPT.app", home + "/Applications/ChatGPT.app"].flatMap {
                [$0 + "/Contents/Resources/codex-cli/bin/codex",
                 $0 + "/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"]
            }
        }
    }

    /// Lamp's own copy of the engine's program, nil until one has been downloaded.
    static func ownPath(for engine: Engine) -> String? {
        guard engine != .pi, let version = currentVersion(engine) else { return nil }
        let path = versionsFolder(engine).appendingPathComponent(version).appendingPathComponent(entry(engine)).path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    nonisolated(unsafe) private static var current: [Engine: String] = [:]

    /// The version in use, read once and then kept in memory (it's asked for whenever a screen redraws).
    static func currentVersion(_ engine: Engine) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let known = current[engine] { return known.isEmpty ? nil : known }
        let saved = ((try? String(contentsOf: currentFile(engine), encoding: .utf8)) ?? "").trimmed
        let version = isVersion(saved) ? saved : ""
        current[engine] = version
        return version.isEmpty ? nil : version
    }

    private static func setCurrent(_ version: String, for engine: Engine) throws {
        try Data(version.utf8).write(to: currentFile(engine), options: .atomic)
        lock.lock()
        current[engine] = version
        lock.unlock()
    }

    /// What every run of the engine gets, whoever starts it: nothing for the person's own copy, which runs as
    /// it does for them; for Lamp's, its own folder for sign-in and state, and Claude Code's self-updater off,
    /// since Lamp is what updates it.
    static func environment(for engine: Engine) -> [String: String] {
        usesPersonsCopy(engine) ? [:] : ownEnvironment(for: engine)
    }

    static func ownEnvironment(for engine: Engine) -> [String: String] {
        switch engine {
        case .pi: return [:]
        case .claude:
            return ["CLAUDE_CONFIG_DIR": ensureConfigFolder(.claude), "DISABLE_AUTOUPDATER": "1"]
        case .codex:
            return ["CODEX_HOME": ensureConfigFolder(.codex)]
        }
    }

    /// Codex refuses a CODEX_HOME that isn't there, so the folder is made before anything names it.
    private static func ensureConfigFolder(_ engine: Engine) -> String {
        let url = ownConfigFolder(engine)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url.path
    }

    // MARK: Conversations kept by the other copy

    /// Whether the engine can resume conversation `session`, bringing it over first when the other copy has
    /// the latest of it: an app's conversation lives in the folder of the copy that had it (Claude Code's in
    /// projects/<folder>/<id>.jsonl, Codex's in sessions/<date>/rollout-…-<id>.jsonl), and Lamp moves between
    /// its own copy and the person's as one appears or goes. Without this an app's next request would try to
    /// resume a conversation its engine can't find and fail. Going back to a copy that ran the conversation
    /// before, the transcript there is older than the one the other copy went on with, so whichever was
    /// written last is the conversation: it replaces the other, and the request goes on from every turn.
    /// False when it's nowhere: the caller then starts a new conversation. Only that one conversation is
    /// copied, and the folder it came from is only read.
    static func carryOver(session: String, for engine: Engine,
                          from home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        guard engine != .pi, !session.isEmpty,
              session.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") })
        else { return false }
        let fm = FileManager.default
        let persons = personsFolder(engine, home: home)
        let (mine, other) = usesPersonsCopy(engine) ? (persons, ownConfigFolder(engine)) : (ownConfigFolder(engine), persons)
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        /// Puts `source` where `target` is, in place of whatever is there.
        func replace(_ target: URL, with source: URL) {
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: source, to: target)
        }
        switch engine {
        case .pi:
            return false
        case .claude:
            // The conversation and the folder beside it (its long outputs, its subagents), under the folder
            // Claude Code names after the app's.
            func find(in root: URL) -> URL? {
                ((try? fm.contentsOfDirectory(at: root.appendingPathComponent("projects"), includingPropertiesForKeys: nil)) ?? [])
                    .first { fm.fileExists(atPath: $0.appendingPathComponent(session + ".jsonl").path) }
            }
            let here = find(in: mine)
            guard let folder = find(in: other) else { return here != nil }
            let transcript = session + ".jsonl"
            if let here, modified(here.appendingPathComponent(transcript)) >= modified(folder.appendingPathComponent(transcript)) {
                return true
            }
            let target = mine.appendingPathComponent("projects").appendingPathComponent(folder.lastPathComponent)
            for name in [transcript, session] {
                if fm.fileExists(atPath: folder.appendingPathComponent(name).path) {
                    replace(target.appendingPathComponent(name), with: folder.appendingPathComponent(name))
                } else {
                    try? fm.removeItem(at: target.appendingPathComponent(name))   // nothing stale left beside it
                }
            }
            return fm.fileExists(atPath: target.appendingPathComponent(transcript).path)
        case .codex:
            // Each conversation is one file, under the date it began.
            func find(in root: URL) -> String? {
                for folder in ["sessions", "archived_sessions"] {
                    let base = root.appendingPathComponent(folder)
                    guard let walk = fm.enumerator(atPath: base.path) else { continue }
                    for case let path as String in walk where path.hasSuffix("-\(session).jsonl") { return folder + "/" + path }
                }
                return nil
            }
            let here = find(in: mine)
            guard let path = find(in: other) else { return here != nil }
            if let here, modified(mine.appendingPathComponent(here)) >= modified(other.appendingPathComponent(path)) { return true }
            // Where Codex will look for it: where it was here, or else where the other copy kept it.
            let target = mine.appendingPathComponent(here ?? path)
            replace(target, with: other.appendingPathComponent(path))
            return fm.fileExists(atPath: target.path)
        }
    }

    /// "2.1.287" or "0.162.1": digits and dots, and nothing that could step out of a folder.
    static func isVersion(_ text: String) -> Bool {
        text.range(of: #"^[0-9]+(\.[0-9]+){1,3}$"#, options: .regularExpression) != nil
    }

    /// Versions compared number by number ("2.1.10" is after "2.1.9").
    static func isOlder(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedAscending
    }

    // MARK: Releases

    /// One release of an engine for this Mac: where to get it and what it must hash to.
    struct Release: Equatable {
        let version: String
        let url: URL
        let sha256: String
        let size: Int64?
        /// A .tar.gz to unpack (Codex), rather than the program itself (Claude Code).
        let isArchive: Bool
    }

    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The Developer ID team that signs each vendor's programs. A download signed by anyone else is refused.
    static func team(_ engine: Engine) -> String {
        engine == .claude ? "Q6L2SF6YDW" : "2DC432GLL2"   // Anthropic PBC, OpenAI OpCo
    }

    /// Claude Code's releases, as Anthropic's installer reads them: a channel file naming a version, and a
    /// manifest for each version with every platform's checksum and size.
    static let claudeReleases = URL(string: "https://downloads.claude.ai/claude-code-releases")!
    /// Codex's releases on GitHub, each with a package for each Mac (the program, the ripgrep it searches
    /// with, and its resources: what the ChatGPT app ships).
    static let codexReleases = URL(string: "https://api.github.com/repos/openai/codex/releases")!
    /// A brake of Lamp's own: the newest version of each engine Lamp should use, set only when a release
    /// breaks Lamp. Normally it names nothing, and each engine follows its vendor.
    static let holdURL = URL(string: "https://updates.lamp.dev/engines.json")!

    private static var isArm: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    /// The release to be on now: the vendor's newest (Claude Code's stable channel, Codex's latest release),
    /// or the version Lamp's brake holds it to when that's older.
    static func target(_ engine: Engine) async throws -> Release {
        let hold = await held()[engine.rawValue]
        switch engine {
        case .pi:
            throw Failure(message: "Lamp's built-in agent comes with Lamp.")
        case .claude:
            let stable = try await text(claudeReleases.appendingPathComponent("stable"))
            guard isVersion(stable) else { throw Failure(message: "Claude's download page didn't say which version is current.") }
            let version = hold.flatMap { isVersion($0) && isOlder($0, than: stable) ? $0 : nil } ?? stable
            return try await claudeRelease(version)
        case .codex:
            let latest = try await codexRelease(nil)
            guard let hold, isVersion(hold), isOlder(hold, than: latest.version) else { return latest }
            return try await codexRelease(hold)
        }
    }

    private static func claudeRelease(_ version: String) async throws -> Release {
        let base = claudeReleases.appendingPathComponent(version)
        let data = try await fetch(base.appendingPathComponent("manifest.json"))
        let platform = isArm ? "darwin-arm64" : "darwin-x64"
        guard let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              manifest["version"] as? String == version,
              let entry = (manifest["platforms"] as? [String: Any])?[platform] as? [String: Any],
              let checksum = entry["checksum"] as? String, checksum.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
        else { throw Failure(message: "Claude \(version) has no download for this Mac.") }
        let size = (entry["size"] as? NSNumber)?.int64Value
        return Release(version: version, url: base.appendingPathComponent(platform).appendingPathComponent("claude"),
                       sha256: checksum, size: size, isArchive: false)
    }

    /// The newest release, or the one for `version`.
    private static func codexRelease(_ version: String?) async throws -> Release {
        let url = version.map { codexReleases.appendingPathComponent("tags/rust-v\($0)") } ?? codexReleases.appendingPathComponent("latest")
        let data = try await fetch(url, accept: "application/vnd.github+json")
        guard let release = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = release["tag_name"] as? String, tag.hasPrefix("rust-v"),
              release["draft"] as? Bool != true, release["prerelease"] as? Bool != true
        else { throw Failure(message: "ChatGPT's release page didn't say which version is current.") }
        let found = String(tag.dropFirst("rust-v".count))
        guard isVersion(found), version == nil || version == found else {
            throw Failure(message: "ChatGPT's release page named a version Lamp doesn't recognize.")
        }
        let name = "codex-package-\(isArm ? "aarch64" : "x86_64")-apple-darwin.tar.gz"
        guard let asset = (release["assets"] as? [[String: Any]])?.first(where: { $0["name"] as? String == name }),
              let link = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)), link.scheme == "https",
              let digest = asset["digest"] as? String, digest.hasPrefix("sha256:")
        else { throw Failure(message: "ChatGPT \(found) has no download for this Mac.") }
        let checksum = String(digest.dropFirst("sha256:".count))
        guard checksum.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw Failure(message: "ChatGPT \(found) has no checksum Lamp can check.")
        }
        return Release(version: found, url: link, sha256: checksum, size: (asset["size"] as? NSNumber)?.int64Value, isArchive: true)
    }

    /// Lamp's brake: {"hold": {"claude": "2.1.287"}}. Anything else, or no answer, holds nothing back.
    private static func held() async -> [String: String] {
        guard let data = try? await fetch(holdURL, timeout: 10),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hold = json["hold"] as? [String: Any] else { return [:] }
        return hold.compactMapValues { $0 as? String }
    }

    private static func fetch(_ url: URL, accept: String? = nil, timeout: TimeInterval = 30) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Failure(message: "\(url.host ?? "The download site") answered \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
        return data
    }

    private static func text(_ url: URL) async throws -> String {
        String(decoding: try await fetch(url), as: UTF8.self).trimmed
    }

    // MARK: Installing

    /// Downloads, checks and puts in place one release, then makes it the version in use. Nothing reaches
    /// `versions/` until its checksum, its signature and a first run have all passed; the folder it's
    /// unpacked into is removed whatever happens.
    static func install(_ release: Release, for engine: Engine, progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: versionsFolder(engine), withIntermediateDirectories: true)
        let destination = versionsFolder(engine).appendingPathComponent(release.version)
        // Already here, from before (the brake moved back to it, say): it passed every check then.
        if fm.isExecutableFile(atPath: destination.appendingPathComponent(entry(engine)).path) {
            try setCurrent(release.version, for: engine)
            prune(engine, keeping: release.version)
            return
        }
        let staging = root(engine).appendingPathComponent(".staging-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let download = staging.appendingPathComponent("download")
        try await Download.file(from: release.url, to: download, expected: release.size, progress: progress)
        if let size = release.size, (try? fm.attributesOfItem(atPath: download.path)[.size] as? Int64) != size {
            throw Failure(message: "The download was cut short. Try again.")
        }
        guard try sha256(of: download) == release.sha256 else {
            throw Failure(message: "The download didn't match what \(engine == .claude ? "Anthropic" : "OpenAI") published, so Lamp didn't use it.")
        }

        let unpacked = staging.appendingPathComponent("unpacked")
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        if release.isArchive {
            let tar = await Subprocess.run("/usr/bin/tar", ["-xzf", download.path, "-C", unpacked.path], timeout: 300)
            guard tar.ok else { throw Failure(message: "Lamp couldn't unpack the download.") }
            // The package says what it is; anything but the version asked for, laid out as expected, is refused.
            let info = (try? Data(contentsOf: unpacked.appendingPathComponent("codex-package.json")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard info?["version"] as? String == release.version, info?["entrypoint"] as? String == entry(engine) else {
                throw Failure(message: "The download wasn't the version Lamp asked for.")
            }
        } else {
            try fm.moveItem(at: download, to: unpacked.appendingPathComponent(entry(engine)))
        }

        // Every program in it signed by the vendor, the main one first.
        let program = unpacked.appendingPathComponent(entry(engine))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        for file in [program] + executables(in: unpacked).filter({ $0.standardizedFileURL != program.standardizedFileURL }) {
            guard isSigned(file, by: team(engine)) else {
                throw Failure(message: "The download wasn't signed by \(engine == .claude ? "Anthropic" : "OpenAI"), so Lamp didn't use it.")
            }
        }

        // It starts, and is the version it says.
        let check = await Subprocess.run(program.path, ["--version"], env: ownEnvironment(for: engine), mergeErrors: false, timeout: 60)
        guard check.ok, check.output.contains(release.version) else {
            throw Failure(message: "\(engine.title) \(release.version) didn't start on this Mac.")
        }

        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: unpacked, to: destination)
        try setCurrent(release.version, for: engine)
        prune(engine, keeping: release.version)
    }

    /// Keeps the version in use and the newest other one (what was in use until now, so a turn on it can
    /// finish), and removes the rest, along with anything a download left half done.
    static func prune(_ engine: Engine, keeping version: String) {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: versionsFolder(engine).path)) ?? []
        let others = names.filter { $0 != version && isVersion($0) }.sorted { isOlder($1, than: $0) }
        for name in names where name != version && name != others.first {
            try? fm.removeItem(at: versionsFolder(engine).appendingPathComponent(name))
        }
        for name in (try? fm.contentsOfDirectory(atPath: root(engine).path)) ?? [] where name.hasPrefix(".staging-") {
            // A staging folder of a download still running is younger than an hour; older ones were left behind.
            let url = root(engine).appendingPathComponent(name)
            let made = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if made < Date().addingTimeInterval(-3600) { try? fm.removeItem(at: url) }
        }
    }

    private static func executables(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let walk = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return [] }
        var found: [URL] = []
        for case let url as URL in walk {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true, fm.isExecutableFile(atPath: url.path) else { continue }
            // Mach-O programs and libraries only: a script needs no signature, and an executable bit on a
            // text file says nothing.
            if let handle = try? FileHandle(forReadingFrom: url), let magic = try? handle.read(upToCount: 4), magic.count == 4 {
                try? handle.close()
                let value = magic.withUnsafeBytes { $0.load(as: UInt32.self) }
                if [0xFEEDFACF, 0xCFFAEDFE, 0xCAFEBABE, 0xBEBAFECA].contains(value) { found.append(url) }
            }
        }
        return found
    }

    /// Signed with a Developer ID certificate of `team`, and intact.
    static func isSigned(_ file: URL, by team: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(file as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// One download to a file, with its progress: URLSession's own, since the files are hundreds of megabytes.
final class Download: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expected: Int64?
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var moved: Error?
    private var status = 0

    private init(destination: URL, expected: Int64?, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.expected = expected
        self.progress = progress
    }

    static func file(from url: URL, to destination: URL, expected: Int64?, progress: @escaping @Sendable (Double) -> Void) async throws {
        let download = Download(destination: destination, expected: expected, progress: progress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        let session = URLSession(configuration: configuration, delegate: download, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                download.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = expected ?? (totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
        if let total, total > 0 { progress(min(1, Double(totalBytesWritten) / Double(total))) }
    }

    /// The file URLSession wrote is removed when this returns, so it's moved now.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200   // a file: URL, in the tests
        do { try FileManager.default.moveItem(at: location, to: destination) } catch { moved = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let continuation = self.continuation
        self.continuation = nil
        if let error {
            continuation?.resume(throwing: EngineInstall.Failure(message: ErrorMessages.isCancelled(error) ? "The download was stopped."
                : ErrorMessages.isConnectivity(error) ? ErrorMessages.noConnection
                : "The download didn't finish: \(error.localizedDescription)"))
        } else if status != 200 {
            continuation?.resume(throwing: EngineInstall.Failure(message: "The download site answered \(status)."))
        } else if let moved {
            continuation?.resume(throwing: moved)
        } else {
            continuation?.resume()
        }
    }
}

/// Getting Lamp's copies and keeping them current, for the screens to follow: how far a download has got,
/// and why the last one failed. One download per engine at a time; asking again joins it. An engine the
/// person has a copy of is never downloaded: there is already a copy (`EngineInstall.path`).
@MainActor
final class EngineDownloads: ObservableObject {
    static let shared = EngineDownloads()

    /// How far each download has got (0–1), while the engine has no copy yet. Updates happen out of sight.
    @Published private(set) var progress: [Engine: Double] = [:]
    /// Why getting a first copy failed, until it's tried again.
    @Published private(set) var failure: [Engine: String] = [:]
    /// Bumped whenever a copy is put in place, so what shows whether an engine is there looks again.
    @Published private(set) var revision = 0

    private var running: [Engine: Task<Bool, Never>] = [:]

    func isDownloading(_ engine: Engine) -> Bool { running[engine] != nil && EngineInstall.path(for: engine) == nil }

    /// A copy of the engine, downloading one if there isn't one yet. True once there is. The person's own copy
    /// is looked for first, so one installed since the last look is used rather than downloaded past.
    @discardableResult
    func ensure(_ engine: Engine) async -> Bool {
        if EngineInstall.path(for: engine) != nil { return true }
        await EngineInstall.lookForPersonsCopies()
        if EngineInstall.path(for: engine) != nil { return true }
        return await run(engine)
    }

    /// Starts getting a copy without waiting for it (choosing Claude Code or ChatGPT in a menu, say).
    func start(_ engine: Engine) {
        guard engine != .pi, EngineInstall.path(for: engine) == nil else { return }
        Task { await ensure(engine) }
    }

    /// The person's copies were found, or went: what shows whether an engine is there looks again.
    func copiesChanged() async {
        revision += 1
        await Store.shared.recheckSetup()
    }

    /// Moves to the release that should be in use when it differs from the one that is. Failure leaves the
    /// copy in use as it was. Only Lamp's own copy: the person's updates itself, or not, as they have it.
    func update(_ engine: Engine) async {
        guard !EngineInstall.usesPersonsCopy(engine), EngineInstall.ownPath(for: engine) != nil else { return }
        _ = await run(engine)
    }

    private func run(_ engine: Engine) async -> Bool {
        guard engine != .pi else { return true }
        if let task = running[engine] { return await task.value }
        let first = EngineInstall.path(for: engine) == nil
        if first {
            failure[engine] = nil
            progress[engine] = 0
        }
        let task = Task<Bool, Never> {
            do {
                let release = try await EngineInstall.target(engine)
                if release.version != EngineInstall.currentVersion(engine) || EngineInstall.ownPath(for: engine) == nil {
                    try await EngineInstall.install(release, for: engine) { fraction in
                        guard first else { return }
                        Task { @MainActor in EngineDownloads.shared.progress[engine] = fraction }
                    }
                }
                UserDefaults.standard.set(Date(), forKey: Self.checkedKey(engine))
                return true
            } catch {
                if first { await MainActor.run { EngineDownloads.shared.failure[engine] = Self.message(error) } }
                return EngineInstall.path(for: engine) != nil
            }
        }
        running[engine] = task
        let done = await task.value
        running[engine] = nil
        progress[engine] = nil
        revision += 1
        if first, done { await Store.shared.recheckSetup() }
        return done
    }

    static func message(_ error: Error) -> String {
        if let failure = error as? EngineInstall.Failure { return failure.message }
        return ErrorMessages.reason(error) ?? "The download was stopped."
    }

    private static func checkedKey(_ engine: Engine) -> String { "engineChecked.\(engine.rawValue)" }

    /// Engines Lamp is set to use: what builds apps, and a sign-in chosen to answer inside them.
    private static func inUse(_ engine: Engine) -> Bool {
        if Builder.engine == engine { return true }
        let prefix = "engine:\(engine.rawValue)"
        return UserDefaults.standard.string(forKey: "appModel")?.hasPrefix(prefix) == true
    }

    private var timer: Timer?

    /// At launch: a copy for each engine in use that doesn't have one (someone who built with Claude Code
    /// from before Lamp kept its own), and an update check for each copy at most once a day, again every
    /// few hours while Lamp stays open.
    func startKeepingCurrent() {
        guard timer == nil else { return }
        Task { await keepCurrent() }
        timer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { _ in
            Task { @MainActor in await EngineDownloads.shared.keepCurrent() }
        }
    }

    private func keepCurrent() async {
        await EngineInstall.lookForPersonsCopies()
        for engine in [Engine.claude, .codex] {
            if EngineInstall.path(for: engine) == nil {
                if Self.inUse(engine) { await ensure(engine) }
                continue
            }
            let last = UserDefaults.standard.object(forKey: Self.checkedKey(engine)) as? Date ?? .distantPast
            if Date().timeIntervalSince(last) > 20 * 3600 { await update(engine) }
        }
    }
}
