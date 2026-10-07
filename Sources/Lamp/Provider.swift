import Foundation
import Security

/// An API-key provider pi supports out of the box.
struct PiProvider: Identifiable, Hashable {
    let id: String          // pi's provider id (`--provider`)
    let name: String
    let envVar: String      // where pi reads the key
    let keyURL: String      // where to get one
}

/// Who builds apps (see Engines.swift), plus the OpenRouter defaults that in-app AI and images use.
enum Provider {
    /// OpenRouter key present: needed for image generation and the default in-app AI.
    static var hasKey: Bool { KeyStore.openRouterKey != nil }

    /// In alphabetical order, as every list of them shows them.
    static let apiProviders: [PiProvider] = [
        PiProvider(id: "openrouter", name: "OpenRouter", envVar: "OPENROUTER_API_KEY", keyURL: "https://openrouter.ai/keys"),
        PiProvider(id: "anthropic", name: "Anthropic", envVar: "ANTHROPIC_API_KEY", keyURL: "https://console.anthropic.com/settings/keys"),
        PiProvider(id: "openai", name: "OpenAI", envVar: "OPENAI_API_KEY", keyURL: "https://platform.openai.com/api-keys"),
        PiProvider(id: "google", name: "Google Gemini", envVar: "GEMINI_API_KEY", keyURL: "https://aistudio.google.com/apikey"),
        PiProvider(id: "deepseek", name: "DeepSeek", envVar: "DEEPSEEK_API_KEY", keyURL: "https://platform.deepseek.com/api_keys"),
        PiProvider(id: "mistral", name: "Mistral", envVar: "MISTRAL_API_KEY", keyURL: "https://console.mistral.ai/api-keys"),
        PiProvider(id: "xai", name: "xAI (Grok)", envVar: "XAI_API_KEY", keyURL: "https://console.x.ai"),
        PiProvider(id: "groq", name: "Groq", envVar: "GROQ_API_KEY", keyURL: "https://console.groq.com/keys"),
        PiProvider(id: "cerebras", name: "Cerebras", envVar: "CEREBRAS_API_KEY", keyURL: "https://cloud.cerebras.ai"),
        PiProvider(id: "together", name: "Together AI", envVar: "TOGETHER_API_KEY", keyURL: "https://api.together.ai/settings/api-keys"),
        PiProvider(id: "fireworks", name: "Fireworks", envVar: "FIREWORKS_API_KEY", keyURL: "https://fireworks.ai/account/api-keys"),
        PiProvider(id: "huggingface", name: "Hugging Face", envVar: "HF_TOKEN", keyURL: "https://huggingface.co/settings/tokens"),
        PiProvider(id: "vercel-ai-gateway", name: "Vercel AI Gateway", envVar: "AI_GATEWAY_API_KEY", keyURL: "https://vercel.com/dashboard/ai-gateway"),
        PiProvider(id: "moonshotai", name: "Moonshot (Kimi)", envVar: "MOONSHOT_API_KEY", keyURL: "https://platform.moonshot.ai"),
        PiProvider(id: "zai", name: "Z.ai (GLM)", envVar: "ZAI_API_KEY", keyURL: "https://z.ai/manage-apikey/apikey-list"),
        PiProvider(id: "minimax", name: "MiniMax", envVar: "MINIMAX_API_KEY", keyURL: "https://www.minimax.io"),
        PiProvider(id: "nvidia", name: "NVIDIA", envVar: "NVIDIA_API_KEY", keyURL: "https://build.nvidia.com"),
    ].sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    static func apiProvider(_ id: String) -> PiProvider? { apiProviders.first { $0.id == id } }

    /// TypeSafe answers apps' typed decisions; it isn't a pi provider, but its key lives alongside theirs.
    static let typesafe = PiProvider(id: "typesafe", name: "TypeSafe", envVar: "TYPESAFE_API_KEY",
                                     keyURL: "https://typesafe.ai")

    /// Every provider Lamp keeps an API key for, as listed in Settings → Providers.
    static let keyProviders = (apiProviders + [typesafe])
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    static func keyProvider(_ id: String) -> PiProvider? { keyProviders.first { $0.id == id } }

    /// Suggested building models when using OpenRouter (any model from the full list also works).
    static let models: [(id: String, label: String)] = [
        ("anthropic/claude-fable-5.1", "Smartest, priciest (Claude Fable)"),
        ("anthropic/claude-opus-5.5", "Best at coding (Claude Opus)"),
        ("anthropic/claude-sonnet-5.5", "Faster & cheaper (Claude Sonnet)"),
    ]

    /// The default building model through OpenRouter.
    static let defaultModel = "anthropic/claude-opus-5.5"

    /// The OpenRouter model used to review shared apps and as the default builder.
    static var model: String {
        if Builder.engine == .pi, Builder.piProvider == "openrouter", !Builder.piModel.isEmpty { return Builder.piModel }
        return defaultModel
    }

    static func friendlyError(_ raw: String) -> String {
        let text = raw.lowercased()
        let name = Builder.engine == .pi ? (apiProvider(Builder.piProvider)?.name ?? "AI provider") : Builder.engine.title
        if text.contains("401") || text.contains("authenticat") || text.contains("api key") || text.contains("unauthorized") {
            return "Your \(name) key or sign-in didn't work. Check it in Lamp → Settings (⌘,)."
        }
        if text.contains("402") || text.contains("credit") || text.contains("insufficient") || text.contains("quota") {
            return "Your \(name) account is out of credit or quota. Top it up, or pick another provider in Settings."
        }
        if text.contains("429") || text.contains("rate limit") {
            return "The AI is busy right now. Wait a minute and try again."
        }
        if text.contains("connection refused") || text.contains("econnrefused") {
            return "Couldn't reach the local model server. Check Settings → Providers → Native Mac AI."
        }
        if text.contains("requires a newer version") || text.contains("upgrade") {
            return "\(name) needs updating: \(raw.prefix(160))"
        }
        return "Something went wrong talking to the AI: \(raw.prefix(160))"
    }
}

/// Stores API keys, one per provider.
///
/// Builds signed with an Apple Team ID (Developer ID releases) use the login Keychain. Local builds
/// have no Team ID, and macOS ties Keychain approval to each exact build, so every rebuild would ask
/// again. Those builds keep keys in a file only your user account can read instead:
/// keys.json in Lamp's support folder. A signed build that finds that file (left by a build from source,
/// which shared this folder until Lamp Dev got its own) moves its keys into the Keychain and removes it.
/// Keys are read once per launch.
enum KeyStore {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String?] = [:]

    /// True when this copy of Lamp is signed with an Apple Team ID.
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

    /// Done once per launch, before a signed build first reads or changes a key.
    private static let movedFileToKeychain: Void = KeyFile.moveToKeychain()

    static var openRouterKey: String? { key(for: "openrouter") }

    static func key(for provider: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[provider] { return cached }
        let value: String?
        if usesKeychain {
            _ = movedFileToKeychain
            let (status, key) = KeychainItem.read(provider)
            value = key
            // Don't cache a denied or cancelled prompt, so the next use can ask again.
            guard status == errSecSuccess || status == errSecItemNotFound else { return key }
        } else {
            value = KeyFile.read()[provider]
        }
        cache[provider] = .some(value)
        return value
    }

    static func setKey(_ key: String?, for provider: String) {
        lock.lock()
        defer { lock.unlock() }
        let key = key?.trimmed.nilIfEmpty
        cache[provider] = .some(key)
        if usesKeychain {
            _ = movedFileToKeychain
            KeychainItem.delete(provider)
            // Unless the new key couldn't be saved: then the file's is the only one there is.
            if key.map({ KeychainItem.write($0, provider) }) ?? true { KeyFile.forget(provider) }
        } else {
            var all = KeyFile.read()
            all[provider] = key
            KeyFile.write(all)
        }
        Agent.keyChanged(for: provider, present: key != nil)   // pi's note of where to ask for it
    }

    /// Takes in a key found outside the store (pi's auth file, where Lamp used to keep a copy) if this
    /// provider has none. True once the store holds a key for the provider; false when the store couldn't be
    /// read or written, so the caller keeps its copy.
    static func adopt(_ key: String, for provider: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if usesKeychain {
            let status = KeychainItem.read(provider).0
            if status == errSecSuccess { return true }
            guard status == errSecItemNotFound else { return false }
            KeychainItem.write(key, provider)
            guard KeychainItem.read(provider).0 == errSecSuccess else { return false }
        } else {
            // A keys file that's there but can't be read isn't an empty one: writing a new file over it
            // would lose whatever it holds.
            if FileManager.default.fileExists(atPath: KeyFile.url.path),
               (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: KeyFile.url))) == nil { return false }
            var all = KeyFile.read()
            if all[provider] != nil { return true }
            all[provider] = key
            KeyFile.write(all)
            guard KeyFile.read()[provider] == key else { return false }
        }
        cache[provider] = .some(key)
        return true
    }

    static func setOpenRouterKey(_ key: String?) { setKey(key, for: "openrouter") }

    private enum KeychainItem {
        static func query(_ account: String) -> [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: Edition.bundleID,
             kSecAttrAccount as String: account]
        }

        static func read(_ account: String) -> (OSStatus, String?) {
            var item: CFTypeRef?
            var q = query(account)
            q[kSecReturnData as String] = true
            let status = SecItemCopyMatching(q as CFDictionary, &item)
            return (status, (item as? Data).flatMap { String(data: $0, encoding: .utf8) }?.nilIfEmpty)
        }

        @discardableResult
        static func write(_ key: String, _ account: String) -> Bool {
            var q = query(account)
            q[kSecValueData as String] = Data(key.utf8)
            return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
        }

        static func delete(_ account: String) { SecItemDelete(query(account) as CFDictionary) }
    }

    /// keys.json, readable only by this user. Also takes in the older single-key file, and a key an earlier
    /// build left in the Keychain: that one is copied, not moved, so a signed Lamp on the same Mac keeps it.
    private enum KeyFile {
        static let folder = Edition.supportFolder
        static let url = folder.appendingPathComponent("keys.json")
        static let legacy = folder.appendingPathComponent("openrouter-key")

        static func read() -> [String: String] {
            if let data = try? Data(contentsOf: url),
               let keys = try? JSONDecoder().decode([String: String].self, from: data) { return keys }
            var keys: [String: String] = [:]
            if let old = (try? String(contentsOf: legacy, encoding: .utf8))?.trimmed.nilIfEmpty {
                keys["openrouter"] = old
            } else if let old = KeychainItem.read("openrouter").1 {
                keys["openrouter"] = old
            }
            if !keys.isEmpty {
                write(keys)
                try? FileManager.default.removeItem(at: legacy)
            }
            return keys
        }

        /// What a signed build does with the file. Each key goes into the Keychain, unless that provider
        /// already has one there (the one Lamp has been using wins), and leaves the file as soon as it's
        /// over; the file goes with its last key. A key that couldn't be moved (the Keychain is locked, or
        /// the person declined) stays in the file for the next launch. A file that's there but can't be read
        /// is left alone: removing it would lose keys that could still be recovered.
        static func moveToKeychain() {
            let fm = FileManager.default
            var keys: [String: String] = [:]
            if fm.fileExists(atPath: url.path) {
                guard let data = try? Data(contentsOf: url),
                      let stored = try? JSONDecoder().decode([String: String].self, from: data) else { return }
                keys = stored
                let left = keys.filter { !moved($0.value, to: $0.key) }
                if left.isEmpty { try? fm.removeItem(at: url) } else if left.count < keys.count { write(left) }
            }
            // The single-key file is older than keys.json: its key matters only if keys.json has none for
            // OpenRouter, and it goes once OpenRouter's key is in the Keychain either way.
            if fm.fileExists(atPath: legacy.path) {
                guard let text = try? String(contentsOf: legacy, encoding: .utf8) else { return }
                let key = keys["openrouter"] ?? text.trimmed.nilIfEmpty
                if key.map({ moved($0, to: "openrouter") }) ?? true { try? fm.removeItem(at: legacy) }
            }
        }

        /// True once the Keychain holds a key for the provider: its own, or this one.
        private static func moved(_ key: String, to provider: String) -> Bool {
            switch KeychainItem.read(provider).0 {
            case errSecSuccess: return true
            case errSecItemNotFound: return KeychainItem.write(key, provider)
            default: return false
            }
        }

        /// A key set or removed in a signed build is the last word on that provider: whatever the file
        /// still holds for it (a key that couldn't be moved yet) goes, so it can't come back at the next launch.
        static func forget(_ provider: String) {
            let fm = FileManager.default
            if let data = try? Data(contentsOf: url),
               var keys = try? JSONDecoder().decode([String: String].self, from: data), keys[provider] != nil {
                keys[provider] = nil
                if keys.isEmpty { try? fm.removeItem(at: url) } else { write(keys) }
            }
            if provider == "openrouter" { try? fm.removeItem(at: legacy) }
        }

        static func write(_ keys: [String: String]) {
            let fm = FileManager.default
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(keys) else { return }
            // Written beside the file, private from the start, then put in its place in one step: the keys
            // are never readable by others, and a write that fails leaves the file as it was.
            let fresh = folder.appendingPathComponent("keys.json.\(UUID().uuidString)")
            guard fm.createFile(atPath: fresh.path, contents: data, attributes: [.posixPermissions: 0o600]),
                  rename(fresh.path, url.path) == 0 else {
                try? fm.removeItem(at: fresh)
                return
            }
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
