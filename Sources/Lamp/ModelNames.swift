import Foundation

/// The names OpenRouter gives its models, from the list it publishes, for saying which model did something
/// ("Claude Opus 5.5": the list's "Anthropic: Claude Opus 5.5" without the vendor, see `short`). The list is public and asking for it sends nothing about the person.
///
/// The names are kept in Lamp's support folder and read from there, so nothing that shows one waits on the
/// network or goes without offline. `refresh` brings a newer list when the kept one is over a day old; it is
/// started by whatever is about to name a model, and never awaited by it.
enum ModelNames {
    private static let file = Edition.supportFolder.appendingPathComponent("openrouter-model-names.json")
    private static let source = URL(string: "https://openrouter.ai/api/v1/models")!
    private static let lock = NSLock()
    nonisolated(unsafe) private static var kept: Kept?
    nonisolated(unsafe) private static var refreshing = false

    struct Kept: Codable, Equatable {
        var fetched: Date
        var names: [String: String]
    }

    /// The published name of an OpenRouter model, when the kept list has it.
    static func openRouter(_ id: String) -> String? {
        lock.withLock {
            if kept == nil {
                kept = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Kept.self, from: $0) }
                    ?? Kept(fetched: .distantPast, names: [:])
            }
            return kept?.names[id].map { short($0, id: id) }
        }
    }

    /// A published name without the vendor OpenRouter puts in front of it ("Anthropic: Claude Opus 5.5" is
    /// "Claude Opus 5.5"): the model is what's being named, and its maker is no part of that. The front is
    /// dropped only when it is the vendor, which is the first part of the model's id ("anthropic/…", give or
    /// take spacing and punctuation: "Z.ai" is "z-ai"). A name with no such front, or whose colon is
    /// something else ("Venice: Uncensored"), is kept whole.
    static func short(_ name: String, id: String) -> String {
        guard let colon = name.range(of: ": ") else { return name }
        func plain(_ text: Substring) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
        let front = plain(name[..<colon.lowerBound])
        let vendor = plain(id.prefix { $0 != "/" })
        let rest = name[colon.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !front.isEmpty, !vendor.isEmpty, !rest.isEmpty, front.contains(vendor) || vendor.contains(front) else { return name }
        return rest
    }

    /// Fetches the list when there's none or it's over a day old (or doesn't have `id`), and keeps it.
    /// Failing changes nothing: the names already kept go on being used.
    static func refresh(for id: String? = nil) async {
        let known = id.map { openRouter($0) != nil } ?? true
        let due: Bool = lock.withLock {
            guard !refreshing else { return false }
            let stale = (kept?.fetched ?? .distantPast).timeIntervalSinceNow < -24 * 60 * 60
            guard stale || !known else { return false }
            refreshing = true
            return true
        }
        guard due else { return }
        defer { lock.withLock { refreshing = false } }
        var request = URLRequest(url: source)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        let names = names(inList: data)
        guard !names.isEmpty else { return }
        let fresh = Kept(fetched: Date(), names: names)
        lock.withLock { kept = fresh }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(fresh).write(to: file, options: .atomic)
    }

    /// The id-to-name pairs in OpenRouter's list, as it sends it: `{"data": [{"id": …, "name": …}, …]}`.
    /// A name is shown to the person, so it is kept to one short line; an entry without both is left out.
    static func names(inList data: Data) -> [String: String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["data"] as? [Any] else { return [:] }
        var names: [String: String] = [:]
        for case let model as [String: Any] in models {
            guard let id = model["id"] as? String, let name = model["name"] as? String else { continue }
            let line = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            if !id.isEmpty, !line.isEmpty { names[id] = String(line.prefix(80)) }
        }
        return names
    }
}
