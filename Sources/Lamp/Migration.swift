import Foundation
import AppKit
import Security

/// Forge became Lamp. Whatever the old name left on this Mac is moved over once, the first time Lamp
/// starts: the data folders, the settings, keys in the Keychain, and each app's code, which called the
/// support library by its old names.
enum Migration {
    static func fromForge() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        // Apps still running under their old ids would keep their old folder open.
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier?.hasPrefix("dev.forge.app.") == true {
            app.terminate()
        }
        // The support folder is moved one entry at a time: a build script may already have made
        // Lamp/Signing before the first launch, and that mustn't stop the apps coming over.
        let oldSupport = home.appendingPathComponent("Library/Application Support/Forge")
        let newSupport = home.appendingPathComponent("Library/Application Support/Lamp")
        var movedData = false
        for entry in (try? fm.contentsOfDirectory(atPath: oldSupport.path)) ?? [] {
            let from = oldSupport.appendingPathComponent(entry), to = newSupport.appendingPathComponent(entry)
            guard !fm.fileExists(atPath: to.path) else { continue }
            try? fm.createDirectory(at: newSupport, withIntermediateDirectories: true)
            if (try? fm.moveItem(at: from, to: to)) != nil, entry == "Apps" { movedData = true }
        }
        if ((try? fm.contentsOfDirectory(atPath: oldSupport.path)) ?? []).isEmpty { try? fm.removeItem(at: oldSupport) }
        for (old, new) in [("Applications/Forge Apps", "Applications/Lamp Apps"), ("Library/Logs/Forge", "Library/Logs/Lamp")] {
            let from = home.appendingPathComponent(old), to = home.appendingPathComponent(new)
            guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { continue }
            try? fm.moveItem(at: from, to: to)
        }
        settings()
        keys()

        imageMarkers()
        let apps = home.appendingPathComponent("Library/Application Support/Lamp/Apps")
        for dir in (try? fm.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil)) ?? [] {
            normalize(dir)
        }
    }

    /// Settings lived under the old bundle id's defaults domain. Copied once, then the old domain goes, so
    /// a later reset (fresh-start) isn't undone by it.
    private static func settings() {
        guard let old = UserDefaults.standard.persistentDomain(forName: "dev.forge.host"), !old.isEmpty else { return }
        for (key, value) in old where UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(value, forKey: key)
        }
        UserDefaults.standard.removePersistentDomain(forName: "dev.forge.host")
    }

    /// Release builds keep provider keys in the Keychain under the bundle id as the service name. Tried on
    /// every launch until it has worked once: the person can decline the Keychain prompt the first time.
    private static func keys() {
        let done = "keychainMovedFromForge"
        guard !UserDefaults.standard.bool(forKey: done) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.forge.host",
                                    kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: true,
                                    kSecReturnData as String: true]
        var found: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        if status == errSecItemNotFound { UserDefaults.standard.set(true, forKey: done); return }
        guard status == errSecSuccess, let items = found as? [[String: Any]] else { return }   // declined: again next time
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String, let data = item[kSecValueData as String] as? Data else { continue }
            let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.lamp.host",
                                      kSecAttrAccount as String: account, kSecValueData as String: data]
            SecItemAdd(add as CFDictionary, nil)   // a duplicate just fails: the key is already over
        }
        UserDefaults.standard.set(true, forKey: done)
    }

    /// Picture models downloaded before the rename carry the old completion marker.
    private static func imageMarkers() {
        let fm = FileManager.default
        for repoDir in (try? fm.contentsOfDirectory(at: LocalModels.hubDir, includingPropertiesForKeys: nil)) ?? [] {
            let old = repoDir.appendingPathComponent("forge-complete"), new = repoDir.appendingPathComponent("lamp-complete")
            if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) { try? fm.moveItem(at: old, to: new) }
        }
    }

    /// One app: its `.forge` folder becomes `.lamp` (and stays out of version control), and its own code is
    /// rewritten to the support library's new names (`ForgeAI` → `LampAI`, `.forgeDropFiles` →
    /// `.lampDropFiles`, …). The generated support file is removed, since Lamp writes a fresh one before the
    /// next build. At launch the rewrite is committed so the app's history stays whole; after a restore of an
    /// older version it's left for the turn or build that follows to commit.
    static func normalize(_ dir: URL, commit: Bool = true) {
        let fm = FileManager.default
        let old = dir.appendingPathComponent(".forge"), new = dir.appendingPathComponent(".lamp")
        var touched = false
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
            try? fm.moveItem(at: old, to: new)
            touched = true
        }
        let ignore = dir.appendingPathComponent(".gitignore")
        if let text = try? String(contentsOf: ignore, encoding: .utf8), !text.contains(".lamp/") {
            try? (text.replacingOccurrences(of: ".forge/", with: ".lamp/") + (text.contains(".forge/") ? "" : "\n.lamp/\n"))
                .write(to: ignore, atomically: true, encoding: .utf8)
            touched = true
        }
        let support = dir.appendingPathComponent("Sources/ForgeSupport.swift")
        if fm.fileExists(atPath: support.path) {
            try? fm.removeItem(at: support)
            touched = true
        }
        // The app's own build script carries its bundle id; its sources and APP.md the library's names.
        let sources = dir.appendingPathComponent("Sources")
        let files = (fm.enumerator(at: sources, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" } + ["APP.md", "build.sh", "Package.swift"].map { dir.appendingPathComponent($0) }
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var updated = text.replacingOccurrences(of: #"\bForge(?=[A-Z])"#, with: "Lamp", options: .regularExpression)
            updated = updated.replacingOccurrences(of: ".forgeDropFiles", with: ".lampDropFiles")
                .replacingOccurrences(of: "dev.forge.", with: "dev.lamp.")
            if updated != text {
                try? updated.write(to: file, atomically: true, encoding: .utf8)
                touched = true
            }
        }
        guard fm.fileExists(atPath: dir.appendingPathComponent(".git").path) else { return }
        // The folder was committed by an earlier version of this migration: take it back out.
        if !git(["ls-files", ".lamp"], in: dir).isEmpty {
            _ = git(["rm", "-r", "-q", "--cached", ".lamp"], in: dir)
            touched = true
        }
        guard touched, commit else { return }
        _ = git(["add", "-A"], in: dir)
        _ = git(["-c", "user.name=Lamp", "-c", "user.email=lamp@localhost", "commit", "-qm", "Rename to Lamp"], in: dir)
    }

    private static func git(_ arguments: [String], in dir: URL) -> String {
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = arguments
        git.currentDirectoryURL = dir
        let out = Pipe()
        git.standardOutput = out
        git.standardError = FileHandle.nullDevice
        try? git.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmed
    }
}
