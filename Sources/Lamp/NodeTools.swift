import CryptoKit
import Foundation

/// Node.js and pnpm, for app kinds whose code is TypeScript built with npm packages (a Roku app on Roku's SDK, which
/// needs Node 24 or later and pnpm 11). Nobody is asked to install them: Lamp fetches one pinned copy of each the first
/// time an app needs them (`ensure`), checked against the SHA-256 Lamp keeps for it (Node's own SHASUMS256.txt, and
/// npm's tarball of pnpm), into the developer folder every Lamp shares, which the sandbox lets a command read and run
/// and never write. What they keep (pnpm's store of packages, the settings and state they write under a home folder)
/// is in the shared caches folder, which the sandbox opens, so every app takes a package from one store.
enum NodeTools {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Release {
        let url: URL
        let sha256: String
        let size: Int64
    }

    /// Moved on purpose, with a Roku app built and put on a Roku first.
    static let nodeVersion = "24.22.2"
    static let pnpmVersion = "11.28.9"

    static var node: Release {
        #if arch(arm64)
        Release(url: URL(string: "https://nodejs.org/dist/v\(nodeVersion)/node-v\(nodeVersion)-darwin-arm64.tar.xz")!,
                sha256: "1f5ac075be50bed4780ea3be19a007fda95ea4d527d28d76d0b91de47d915115", size: 27_508_812)
        #else
        Release(url: URL(string: "https://nodejs.org/dist/v\(nodeVersion)/node-v\(nodeVersion)-darwin-x64.tar.xz")!,
                sha256: "6965578fd823e72c1b5387f5ab84cb25368f886e02eb8779e6f0fce6b91c27b7", size: 29_283_332)
        #endif
    }

    static let pnpm = Release(url: URL(string: "https://registry.npmjs.org/pnpm/-/pnpm-\(pnpmVersion).tgz")!,
                              sha256: "e54b07e5634b7bf4352153e0c8c25bcef2930a29e3d1bdc42a9eaf2ffd4436df", size: 5_605_029)

    // MARK: Folders

    static let folder = Edition.sharedDeveloperFolder.appendingPathComponent("Node")
    static var nodeFolder: URL { folder.appendingPathComponent("node-\(nodeVersion)") }
    static var pnpmFolder: URL { folder.appendingPathComponent("pnpm-\(pnpmVersion)") }
    /// Lamp's `pnpm`, which runs pnpm's script with Lamp's Node.
    static var bin: URL { folder.appendingPathComponent("bin-\(nodeVersion)-\(pnpmVersion)") }
    static let caches = Edition.sharedCachesFolder.appendingPathComponent("Node")

    static var isReady: Bool {
        let fm = FileManager.default
        return !Pretend.isMissing("node") && fm.isExecutableFile(atPath: nodeFolder.appendingPathComponent("bin/node").path)
            && fm.fileExists(atPath: pnpmFolder.appendingPathComponent("bin/pnpm.cjs").path)
            && fm.isExecutableFile(atPath: bin.appendingPathComponent("pnpm").path)
    }

    /// What a command needs first in its shell to run with Lamp's Node and pnpm: them first on the path, and a home
    /// folder, a store and caches of their own in the caches folder (the sandbox closes the person's home, where they
    /// would look otherwise). pnpm asks before it empties a node_modules it didn't make, and nobody is there to answer.
    static var shellPrefix: String {
        let home = caches.appendingPathComponent("home").path
        let values = [
            "PATH": bin.path + ":" + nodeFolder.appendingPathComponent("bin").path,
            "HOME": home,
            "XDG_CONFIG_HOME": home + "/.config", "XDG_CACHE_HOME": home + "/.cache", "XDG_DATA_HOME": home + "/.local/share",
            "XDG_STATE_HOME": home + "/.local/state", "PNPM_HOME": home + "/pnpm",
            // pnpm 11 reads its settings from pnpm_config_ variables, not npm's.
            "pnpm_config_store_dir": caches.appendingPathComponent("store").path,
            "pnpm_config_confirm_modules_purge": "false", "pnpm_config_update_notifier": "false",
        ]
        return values.sorted { $0.key < $1.key }.map { key, value in
            key == "PATH" ? "export PATH=\(Sandbox.quoted(value))\":$PATH\"" : "export \(key)=\(Sandbox.quoted(value))"
        }.joined(separator: "; ") + "; "
    }

    // MARK: Fetching

    @MainActor private static var fetching: Task<Void, Error>?

    /// Fetches what isn't here yet; a second caller while it comes waits for the same download.
    @MainActor static func ensure() async throws {
        if isReady { return }
        if let fetching { return try await fetching.value }
        let task = Task.detached { try await install() }
        fetching = task
        defer { fetching = nil }
        try await task.value
    }

    private static func install() async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.createDirectory(at: caches.appendingPathComponent("home"), withIntermediateDirectories: true)
        let staging = folder.appendingPathComponent(".staging-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        if !fm.isExecutableFile(atPath: nodeFolder.appendingPathComponent("bin/node").path) {
            let archive = staging.appendingPathComponent("node.tar.xz")
            try await fetch(node, to: archive, name: "Node.js")
            let unpacked = staging.appendingPathComponent("node")
            try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
            // Node itself and npm beside it; its headers and manual pages are for building Node add-ons by hand.
            let result = await Subprocess.run("/usr/bin/tar", ["-xf", archive.path, "-C", unpacked.path, "--strip-components", "1",
                                                               "--exclude", "*/include", "--exclude", "*/share"], timeout: 600)
            guard result.ok else { throw Failure(message: "Lamp couldn't unpack Node.js.\n\n" + result.output.suffix(400)) }
            guard await Subprocess.run(unpacked.appendingPathComponent("bin/node").path, ["--version"], timeout: 60).ok else {
                throw Failure(message: "Node.js didn't start on this Mac.")
            }
            if fm.fileExists(atPath: nodeFolder.path) { try fm.removeItem(at: nodeFolder) }
            try fm.moveItem(at: unpacked, to: nodeFolder)
        }
        if !fm.fileExists(atPath: pnpmFolder.appendingPathComponent("bin/pnpm.cjs").path) {
            let archive = staging.appendingPathComponent("pnpm.tgz")
            try await fetch(pnpm, to: archive, name: "pnpm")
            let unpacked = staging.appendingPathComponent("pnpm")
            try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
            let result = await Subprocess.run("/usr/bin/tar", ["-xzf", archive.path, "-C", unpacked.path, "--strip-components", "1"], timeout: 300)
            guard result.ok else { throw Failure(message: "Lamp couldn't unpack pnpm.\n\n" + result.output.suffix(400)) }
            if fm.fileExists(atPath: pnpmFolder.path) { try fm.removeItem(at: pnpmFolder) }
            try fm.moveItem(at: unpacked, to: pnpmFolder)
        }
        let shims = staging.appendingPathComponent("bin")
        try fm.createDirectory(at: shims, withIntermediateDirectories: true)
        let node = nodeFolder.appendingPathComponent("bin/node").path
        for (name, script) in [("pnpm", "pnpm.cjs"), ("pnpx", "pnpx.cjs")] {
            let text = "#!/bin/sh\n# Written by Lamp: pnpm with Lamp's Node.js.\nexec \(Sandbox.quoted(node)) \(Sandbox.quoted(pnpmFolder.appendingPathComponent("bin/" + script).path)) \"$@\"\n"
            let url = shims.appendingPathComponent(name)
            try text.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        if fm.fileExists(atPath: bin.path) { try fm.removeItem(at: bin) }
        try fm.moveItem(at: shims, to: bin)
    }

    private static func fetch(_ release: Release, to file: URL, name: String) async throws {
        try await Download.file(from: release.url, to: file, expected: release.size) { _ in }
        guard try sha256(of: file) == release.sha256 else {
            try? FileManager.default.removeItem(at: file)
            throw Failure(message: "The download of \(name) didn't match the copy Lamp expects, so Lamp didn't use it.")
        }
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
