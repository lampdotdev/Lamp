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
            return ErrorMessages.authenticationFailed(name)
        }
        if text.contains("402") || text.contains("credit") || text.contains("insufficient") || text.contains("quota") {
            return ErrorMessages.quotaExceeded(name)
        }
        if text.contains("429") || text.contains("rate limit") {
            return ErrorMessages.providerBusy
        }
        if text.contains("connection refused") || text.contains("econnrefused") {
            return ErrorMessages.localServerUnreachable
        }
        if text.contains("requires a newer version") || text.contains("upgrade") {
            return "\(name) needs updating: \(raw.prefix(160))"
        }
        return ErrorMessages.aiFailed(String(raw.prefix(160)))
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
    /// Serialises the Keychain and file work; `cacheLock` guards only the cache, so a look at it never waits
    /// behind a Keychain prompt.
    private static let lock = NSLock()
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String?] = [:]

    /// True when this copy of Lamp is signed with an Apple Team ID.
    static let usesKeychain: Bool = teamID != nil

    /// The Apple Team ID this copy of Lamp is signed with, or nil for a local build.
    static let teamID: String? = {
        var code: SecCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              let staticCode = { var s: SecStaticCode?; SecCodeCopyStaticCode(code, [], &s); return s }(),
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty
        else { return nil }
        return team
    }()

    /// Done once per launch, before a signed build first reads or changes a key.
    private static let movedFileToKeychain: Void = KeyFile.moveToKeychain()

    static var openRouterKey: String? { key(for: "openrouter") }

    /// Posted on the main thread once the keys have been read at launch: what was drawn without them draws again.
    static let loaded = Notification.Name("LampKeysLoaded")
    nonisolated(unsafe) private static var preloaded = false

    /// Reads every provider's key once, off the main thread, so the Keychain's questions (a password, when
    /// an item isn't Lamp's own) come at launch and not in the middle of drawing a view: a Keychain prompt
    /// inside a layout pass runs the event loop inside the layout, which AppKit answers by crashing.
    /// Until it's done, a read on the main thread says there's no key rather than ask.
    static func preload() {
        DispatchQueue.global(qos: .userInitiated).async {
            if usesKeychain { for provider in Provider.keyProviders { _ = key(for: provider.id) } }
            DispatchQueue.main.async {
                preloaded = true
                NotificationCenter.default.post(name: loaded, object: nil)
            }
        }
    }

    private static func cached(_ provider: String) -> String?? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[provider]
    }

    private static func remember(_ value: String?, for provider: String) {
        cacheLock.lock()
        cache[provider] = .some(value)
        cacheLock.unlock()
    }

    static func key(for provider: String) -> String? {
        if let cached = cached(provider) { return cached }
        // Before the launch-time read is in, the main thread is told there's no key rather than made to ask,
        // or to wait for a question being asked on the other thread.
        if usesKeychain, Thread.isMainThread, !preloaded { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached = cached(provider) { return cached }
        let value: String?
        if usesKeychain {
            _ = movedFileToKeychain
            let (status, key) = KeychainItem.read(provider)
            // Don't cache a denied or cancelled prompt, so the next use can ask again.
            guard status == errSecSuccess || status == errSecItemNotFound else { return key }
            if let key { KeychainItem.adopt(key, provider) }
            // A key the Keychain wouldn't take stays in the file (moveToKeychain tries again each launch).
            value = key ?? (status == errSecItemNotFound ? KeyFile.stored()?[provider] : nil)
        } else {
            value = KeyFile.read()[provider]
        }
        remember(value, for: provider)
        return value
    }

    static func setKey(_ key: String?, for provider: String) {
        lock.lock()
        defer { lock.unlock() }
        let key = key?.trimmed.nilIfEmpty
        remember(key, for: provider)
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
            _ = movedFileToKeychain   // the keys file first: its key is the saved one, pi's copy may be older
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
        remember(key, for: provider)
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

        /// An item that isn't Lamp's own, as one put there with the `security` tool (its partition is
        /// "apple-tool:", not Lamp's team), makes macOS ask for the login password at every read, however
        /// often Allow is clicked. Once a read has got through, the item is made Lamp's: written afresh,
        /// so its access list is this app's and no one is asked again.
        static func adopt(_ key: String, _ account: String) {
            guard let team = teamID, let partitions = partitions(account),
                  !partitions.contains("teamid:\(team)"), !partitions.contains("apple:") else { return }
            // The key is kept in the file, and read back, before the old item goes: if the new one can't be
            // added (or Lamp dies between the two), the file is what's read until it can be.
            var all: [String: String] = [:]
            if FileManager.default.fileExists(atPath: KeyFile.url.path) {
                guard let stored = KeyFile.stored() else { return }   // a file that can't be read isn't written over
                all = stored
            }
            all[account] = key
            guard KeyFile.write(all), KeyFile.stored()?[account] == key else { return }
            delete(account)
            if write(key, account) { KeyFile.forget(account) }
        }

        /// The partitions an item's access list admits ("apple-tool:", "teamid:…", "apple:"): a hex-encoded
        /// plist in the partition ACL's description. Nil when it can't be read.
        private static func partitions(_ account: String) -> [String]? {
            var ref: CFTypeRef?
            var q = query(account)
            q[kSecReturnRef as String] = true
            guard SecItemCopyMatching(q as CFDictionary, &ref) == errSecSuccess, let ref else { return nil }
            let item = ref as! SecKeychainItem
            var access: SecAccess?
            guard SecKeychainItemCopyAccess(item, &access) == errSecSuccess, let access,
                  let acl = (SecAccessCopyMatchingACLList(access, kSecACLAuthorizationPartitionID) as? [SecACL])?.first else { return nil }
            var apps: CFArray?
            var description: CFString?
            var selector = SecKeychainPromptSelector()
            guard SecACLCopyContents(acl, &apps, &description, &selector) == errSecSuccess, let hex = description as String? else { return nil }
            var bytes = [UInt8]()
            var index = hex.startIndex
            while index < hex.endIndex, let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
                guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
                bytes.append(byte)
                index = next
            }
            let plist = try? PropertyListSerialization.propertyList(from: Data(bytes), format: nil)
            return (plist as? [String: Any])?["Partitions"] as? [String]
        }
    }

    /// keys.json, readable only by this user. Also takes in the older single-key file, and a key an earlier
    /// build left in the Keychain: that one is copied, not moved, so a signed Lamp on the same Mac keeps it.
    private enum KeyFile {
        static let folder = Edition.supportFolder
        static let url = folder.appendingPathComponent("keys.json")
        static let legacy = folder.appendingPathComponent("openrouter-key")

        /// The file as it is: nil when there's none, or when it can't be read or decoded (which is left
        /// alone, never written over).
        static func stored() -> [String: String]? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode([String: String].self, from: data)
        }

        static func read() -> [String: String] {
            if let keys = stored() { return keys }
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

        @discardableResult
        static func write(_ keys: [String: String]) -> Bool {
            let fm = FileManager.default
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(keys) else { return false }
            // Written beside the file, private from the start, then put in its place in one step: the keys
            // are never readable by others, and a write that fails leaves the file as it was.
            let fresh = folder.appendingPathComponent("keys.json.\(UUID().uuidString)")
            guard fm.createFile(atPath: fresh.path, contents: data, attributes: [.posixPermissions: 0o600]),
                  rename(fresh.path, url.path) == 0 else {
                try? fm.removeItem(at: fresh)
                return false
            }
            return true
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
