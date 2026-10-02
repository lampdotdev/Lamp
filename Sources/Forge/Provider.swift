import Foundation
import Security

/// Everything AI goes through OpenRouter: the builder agent (pi), ForgeAI in generated apps, and icon artwork.
enum Provider {
    static var hasKey: Bool { KeyStore.openRouterKey != nil }

    static let models: [(id: String, label: String)] = [
        ("anthropic/claude-opus-5.5", "Best quality (Claude Opus)"),
        ("anthropic/claude-sonnet-5.5", "Faster & cheaper (Claude Sonnet)"),
    ]

    /// The OpenRouter model that builds apps.
    static var model: String {
        let saved = UserDefaults.standard.string(forKey: "model") ?? ""
        return models.contains { $0.id == saved } ? saved : models[0].id
    }

    static func friendlyError(_ raw: String) -> String {
        let text = raw.lowercased()
        if text.contains("401") || text.contains("authenticat") || text.contains("api key") {
            return hasKey
                ? "Your OpenRouter key didn't work. Check it in Forge → Settings (⌘,)."
                : "Forge needs an OpenRouter key. Add one in Forge → Settings (⌘,)."
        }
        if text.contains("402") || text.contains("credit") || text.contains("insufficient") {
            return "Your OpenRouter account is out of credit. Top it up at openrouter.ai/credits, then try again."
        }
        if text.contains("429") || text.contains("rate limit") {
            return "The AI is busy right now. Wait a minute and try again."
        }
        return "Something went wrong talking to the AI. Try again in a moment."
    }
}

/// Stores the OpenRouter key.
///
/// Builds signed with an Apple Team ID (Developer ID releases) use the login Keychain. Local builds
/// have no Team ID, and macOS ties Keychain approval to each exact build, so every rebuild would ask
/// again. Those builds keep the key in a file only your user account can read instead:
/// ~/Library/Application Support/Forge/openrouter-key. Either way it's read once per launch.
enum KeyStore {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: String??

    /// True when this copy of Forge is signed with an Apple Team ID.
    static let usesKeychain: Bool = {
        var code: SecCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              let staticCode = { var s: SecStaticCode?; SecCodeCopyStaticCode(code, [], &s); return s }(),
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
        else { return false }
        return !team.isEmpty
    }()

    static var openRouterKey: String? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        if usesKeychain {
            let (status, key) = KeychainItem.read()
            // Don't cache a denied or cancelled prompt, so the next use can ask again.
            if status == errSecSuccess || status == errSecItemNotFound { cached = .some(key) }
            return key
        }
        if let key = KeyFile.read() {
            cached = .some(key)
            return key
        }
        // Moving from an older build that kept the key in the Keychain: copy it over once.
        let (status, key) = KeychainItem.read()
        if let key {
            KeyFile.write(key)
            KeychainItem.delete()
        }
        if status == errSecSuccess || status == errSecItemNotFound { cached = .some(key) }
        return key
    }

    static func setOpenRouterKey(_ key: String?) {
        lock.lock()
        defer { lock.unlock() }
        let key = key?.trimmed.isEmpty == false ? key!.trimmed : nil
        cached = .some(key)
        if usesKeychain {
            KeychainItem.delete()
            if let key { KeychainItem.write(key) }
        } else {
            KeyFile.delete()
            if let key { KeyFile.write(key) }
        }
    }

    private enum KeychainItem {
        static let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.forge.host",
            kSecAttrAccount as String: "openrouter",
        ]

        static func read() -> (OSStatus, String?) {
            var item: CFTypeRef?
            var q = query
            q[kSecReturnData as String] = true
            let status = SecItemCopyMatching(q as CFDictionary, &item)
            let key = (item as? Data).flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : $0 }
            return (status, key)
        }

        static func write(_ key: String) {
            var q = query
            q[kSecValueData as String] = Data(key.utf8)
            SecItemAdd(q as CFDictionary, nil)
        }

        static func delete() { SecItemDelete(query as CFDictionary) }
    }

    private enum KeyFile {
        static let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Forge/openrouter-key")

        static func read() -> String? {
            (try? String(contentsOf: url, encoding: .utf8))?.trimmed.nilIfEmpty
        }

        static func write(_ key: String) {
            let fm = FileManager.default
            let folder = url.deletingLastPathComponent()
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            // Create it private first, then write, so the key is never briefly readable by others.
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try? Data(key.utf8).write(to: url, options: [])
        }

        static func delete() { try? FileManager.default.removeItem(at: url) }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
