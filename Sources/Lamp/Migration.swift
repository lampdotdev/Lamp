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
        if movedData || UserDefaults.standard.object(forKey: "engine") == nil { settings() }
        if movedData { keys() }

        let apps = home.appendingPathComponent("Library/Application Support/Lamp/Apps")
        for dir in (try? fm.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil)) ?? [] {
            app(dir)
        }
    }

    /// Settings lived under the old bundle id's defaults domain.
    private static func settings() {
        guard let old = UserDefaults.standard.persistentDomain(forName: "dev.forge.host"), !old.isEmpty else { return }
        for (key, value) in old where UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    /// Release builds keep provider keys in the Keychain under the bundle id as the service name.
    private static func keys() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.forge.host",
                                    kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: true,
                                    kSecReturnData as String: true]
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let items = found as? [[String: Any]] else { return }
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String, let data = item[kSecValueData as String] as? Data else { continue }
            let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.lamp.host",
                                      kSecAttrAccount as String: account, kSecValueData as String: data]
            SecItemAdd(add as CFDictionary, nil)   // a duplicate just fails: the key is already over
        }
    }

    /// One app: its `.forge` folder becomes `.lamp`, and its own code is rewritten to the support library's
    /// new names (`ForgeAI` → `LampAI`, `.forgeDropFiles` → `.lampDropFiles`, …). The generated support file
    /// is removed, since Lamp writes a fresh one before the next build, and the rewrite is committed so the
    /// app's history stays whole.
    private static func app(_ dir: URL) {
        let fm = FileManager.default
        let old = dir.appendingPathComponent(".forge"), new = dir.appendingPathComponent(".lamp")
        var touched = false
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
            try? fm.moveItem(at: old, to: new)
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
        guard touched, fm.fileExists(atPath: dir.appendingPathComponent(".git").path) else { return }
        for arguments in [["add", "-A"], ["-c", "user.name=Lamp", "-c", "user.email=lamp@localhost", "commit", "-qm", "Rename to Lamp"]] {
            let git = Process()
            git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            git.arguments = arguments
            git.currentDirectoryURL = dir
            git.standardOutput = FileHandle.nullDevice
            git.standardError = FileHandle.nullDevice
            try? git.run()
            git.waitUntilExit()
        }
    }
}
