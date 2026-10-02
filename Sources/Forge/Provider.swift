import Foundation
import Security

/// Where the agent's model calls go. An OpenRouter key means nobody has to sign in to anything.
enum Provider: String, CaseIterable {
    case openRouter = "openrouter"
    case claudeLogin = "claude"     // fallback: whatever `claude` is already signed in to

    var id: String { rawValue }
    static let all = allCases

    static var current: Provider { Keychain.openRouterKey == nil ? .claudeLogin : .openRouter }

    static var model: String { UserDefaults.standard.string(forKey: "model") ?? "sonnet" }

    static let models: [(id: String, label: String)] = [
        ("sonnet", "Balanced (Claude Sonnet)"),
        ("opus", "Best quality (Claude Opus, pricier)"),
    ]

    /// Forge keeps its own Claude Code config so it never touches the user's own login or settings.
    private static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Forge/claude").path

    var environment: [String: String] {
        switch self {
        case .openRouter:
            return [
                "ANTHROPIC_BASE_URL": "https://openrouter.ai/api",
                "ANTHROPIC_AUTH_TOKEN": Keychain.openRouterKey ?? "",
                "ANTHROPIC_API_KEY": "",
                "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
                "CLAUDE_CONFIG_DIR": Self.configDir,
            ]
        case .claudeLogin:
            return [:]
        }
    }

    static func friendlyError(_ raw: String) -> String {
        let text = raw.lowercased()
        if text.contains("401") || text.contains("authenticat") || text.contains("login") {
            return current == .openRouter
                ? "Your OpenRouter key didn't work. Check it in Forge → Settings (⌘,)."
                : "Forge isn't connected to an AI yet. Add an OpenRouter key in Forge → Settings (⌘,)."
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
