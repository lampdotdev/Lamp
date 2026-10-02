import Foundation
import Security

/// Everything AI goes through OpenRouter: the builder agent (pi), ForgeAI in generated apps, and icon artwork.
enum Provider {
    static var hasKey: Bool { Keychain.openRouterKey != nil }

    static let models: [(id: String, label: String)] = [
        ("anthropic/claude-sonnet-5.5", "Balanced (Claude Sonnet)"),
        ("anthropic/claude-opus-5.5", "Best quality (Claude Opus, pricier)"),
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

/// Stores the OpenRouter key in the login Keychain.
enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.forge.host",
        kSecAttrAccount as String: "openrouter",
    ]

    static var openRouterKey: String? {
        var item: CFTypeRef?
        var q = query
        q[kSecReturnData as String] = true
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static func setOpenRouterKey(_ key: String?) {
        SecItemDelete(query as CFDictionary)
        guard let key = key?.trimmed, !key.isEmpty else { return }
        var q = query
        q[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}
