import Foundation
import Security

/// Everything AI goes through OpenRouter: the builder agent (pi), ForgeAI in generated apps, and icon artwork.
enum Provider {
    static var hasKey: Bool { Keychain.openRouterKey != nil }

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

/// Stores the OpenRouter key in the login Keychain. It's read once per launch and kept in memory,
/// so macOS asks for Keychain access at most once (and never again after "Always Allow").
enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.forge.host",
        kSecAttrAccount as String: "openrouter",
    ]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: String??

    static var openRouterKey: String? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        var item: CFTypeRef?
        var q = query
        q[kSecReturnData as String] = true
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        let key = (item as? Data).flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : $0 }
        // Don't cache a denied or cancelled prompt, so the next use can ask again.
        if status == errSecSuccess || status == errSecItemNotFound { cached = .some(key) }
        return key
    }

    static func setOpenRouterKey(_ key: String?) {
        lock.lock()
        defer { lock.unlock() }
        SecItemDelete(query as CFDictionary)
        let key = key?.trimmed
        cached = .some(key?.isEmpty == false ? key : nil)
        guard let key, !key.isEmpty else { return }
        var q = query
        q[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}
