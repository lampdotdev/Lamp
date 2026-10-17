import Foundation
import AppKit
import Security

/// Forge became Lamp. Whatever the old name left on this Mac is moved over once, the first time Lamp
/// starts: the data folders, the settings, keys in the Keychain, and each app's code, which called the
/// support library by its old names.
enum Migration {
    static func fromForge() {
        guard !Edition.isDev else { return }   // the development build has its own folders; nothing to move
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
            appData(dir.lastPathComponent)
        }
    }

    /// An app keeps its database, files and settings under its bundle id, which changes with the rename.
    private static func appData(_ id: String) {
        let fm = FileManager.default
        let support = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let old = support.appendingPathComponent("dev.forge.app.\(id)"), new = support.appendingPathComponent("dev.lamp.app.\(id)")
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) { try? fm.moveItem(at: old, to: new) }
        if let defaults = UserDefaults.standard.persistentDomain(forName: "dev.forge.app.\(id)"), !defaults.isEmpty {
            var merged = UserDefaults.standard.persistentDomain(forName: "dev.lamp.app.\(id)") ?? [:]
            for (key, value) in defaults where merged[key] == nil { merged[key] = value }
            UserDefaults.standard.setPersistentDomain(merged, forName: "dev.lamp.app.\(id)")
            UserDefaults.standard.removePersistentDomain(forName: "dev.forge.app.\(id)")
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
        // Data can't be returned for many items at once (errSecParam), so: the accounts first, then each one.
        let list: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.forge.host",
                                   kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: true]
        var found: CFTypeRef?
        let status = SecItemCopyMatching(list as CFDictionary, &found)
        if status == errSecItemNotFound { UserDefaults.standard.set(true, forKey: done); return }
        guard status == errSecSuccess, let items = found as? [[String: Any]] else { return }   // declined: again next time
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else { continue }
            let one: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.forge.host",
                                      kSecAttrAccount as String: account, kSecReturnData as String: true]
            var data: CFTypeRef?
            guard SecItemCopyMatching(one as CFDictionary, &data) == errSecSuccess, let secret = data as? Data else { return }
            let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.lamp.host",
                                      kSecAttrAccount as String: account, kSecValueData as String: secret]
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
        // What's read here is written back in place, so it's read as `AppFile` reads: through a link it would bring
        // what that leads to into the app's folder.
        if let text = AppFile.text(ignore, inFolder: dir), !text.contains(".lamp/") {
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
            guard let text = AppFile.text(file, inFolder: dir) else { continue }
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
        if !Versions.gitBlocking("git ls-files .lamp", cwd: dir).output.trimmed.isEmpty {
            _ = Versions.gitBlocking("git rm -r -q --cached .lamp", cwd: dir)
            touched = true
        }
        guard touched, commit else { return }
        _ = Versions.gitBlocking("git add -A && \(Versions.commit) -qm 'Rename to Lamp'", cwd: dir)
    }
}
