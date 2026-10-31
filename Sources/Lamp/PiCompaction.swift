import Foundation

/// Where pi compacts, for a conversation that reaches `Conversation.compactAt`. pi's automatic compaction is the one
/// way it compacts that leaves a running turn alone: asking it to compact (`ctx.compact`, its `/compact`) stops what
/// the agent is doing first, and doesn't carry on. It compacts on its own when the context passes the model's window
/// less `compaction.reserveTokens`, so each model that would otherwise wait longer than Lamp's size gets its own
/// reserve in Lamp's pi settings. A model pi doesn't list keeps pi's own reserve and compacts near its window.
enum PiCompaction {
    /// What pi reserves unless told otherwise. A model whose window is this close to Lamp's size needs no override.
    static let ownReserve = 16_384
    /// Which models' reserves in the settings are Lamp's, so it can take them away when they go stale and leave
    /// any other alone.
    static let ownedKey = "lampCompactionModels"
    /// What the settings were written for (`stamp`).
    static let stampKey = "lampCompactionStamp"

    /// What to reserve for a model with this window, nil when pi's own reserve already compacts in time.
    static func reserve(window: Int, compactAt: Int) -> Int? {
        let reserve = window - compactAt
        return reserve > ownReserve ? reserve : nil
    }

    /// The window of each model, as `provider/id`, in pi's answer to `get_available_models` (nil for any other line).
    static func windows(inAnswer line: String) -> [String: Int]? {
        guard let data = line.data(using: .utf8),
              let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              answer["command"] as? String == "get_available_models", answer["success"] as? Bool == true,
              let models = (answer["data"] as? [String: Any])?["models"] as? [[String: Any]] else { return nil }
        var windows: [String: Int] = [:]
        for model in models {
            guard let provider = model["provider"] as? String, let id = model["id"] as? String,
                  let window = model["contextWindow"] as? Int else { continue }
            windows["\(provider)/\(id)"] = window
        }
        return windows
    }

    /// pi's settings with Lamp's reserves in them: the last ones taken out, the ones for these models put in, and
    /// everything else as it was. A reserve Lamp didn't write stays. Compaction is kept on, or the reserves do nothing.
    static func settings(_ current: [String: Any], windows: [String: Int], compactAt: Int) -> [String: Any] {
        var settings = current
        var compaction = settings["compaction"] as? [String: Any] ?? [:]
        var overrides = compaction["modelOverrides"] as? [String: Any] ?? [:]
        for key in settings[ownedKey] as? [String] ?? [] {
            guard var entry = overrides[key] as? [String: Any] else { continue }
            entry["reserveTokens"] = nil
            overrides[key] = entry.isEmpty ? nil : entry
        }
        var owned: [String] = []
        for (key, window) in windows.sorted(by: { $0.key < $1.key }) {
            guard let reserve = reserve(window: window, compactAt: compactAt) else { continue }
            var entry = overrides[key] as? [String: Any] ?? [:]
            guard entry["reserveTokens"] == nil else { continue }
            entry["reserveTokens"] = reserve
            overrides[key] = entry
            owned.append(key)
        }
        compaction["enabled"] = true
        compaction["modelOverrides"] = overrides.isEmpty ? nil : overrides
        settings["compaction"] = compaction
        settings[ownedKey] = owned.isEmpty ? nil : owned
        return settings
    }

    /// Asks pi for its models' windows, nil if it can't say in time. pi runs without a shell, so a pi that hangs is
    /// ended with everything it started and the wait stays bounded.
    static func discover(pi: URL, env: [String: String], timeout: TimeInterval = 10) async -> [String: Int]? {
        let result = await Subprocess.run(pi.path, ["--mode", "rpc", "--no-session", "--no-extensions", "--no-skills", "--no-prompt-templates",
                                                    "--no-context-files", "--no-approve"],
                                          cwd: URL(fileURLWithPath: NSTemporaryDirectory()), env: env, mergeErrors: false, timeout: timeout,
                                          input: Data("{\"type\":\"get_available_models\"}\n".utf8))
        return result.output.split(separator: "\n").lazy.compactMap { windows(inAnswer: String($0)) }.first
    }

    /// What the models and their windows depend on: Lamp's size, the copy of pi, and the files in pi's folder that say
    /// which models it has. While this is the same as when the settings were written, there's no need to ask pi again.
    static func stamp(pi: URL, folder: URL, compactAt: Int) -> String {
        let files = [pi] + ["models.json", "auth.json", "models-store.json"].map { folder.appendingPathComponent($0) }
        let marks = files.map { file -> String in
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            return "\((attributes?[.size] as? Int) ?? -1)@\((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        }
        return ([String(compactAt)] + marks).joined(separator: " ")
    }

    /// Brings Lamp's pi settings up to date before a run, since the models pi can use change with keys and providers.
    /// pi reads them as it starts.
    @MainActor static func prepare(for project: LampProject) async {
        guard let pi = Agent.executable else { return }
        await update(pi: pi, folder: URL(fileURLWithPath: Agent.configDir), env: Agent.catalogEnvironment, compactAt: Conversation.compactAt) {
            Conversation.note(project, engine: .pi, $0)
        }
    }

    /// Asks pi only when the settings' stamp is out of date, or compaction was turned off, since asking costs each
    /// turn the start of a pi. The file is read and written in one go on the main actor, so runs starting together
    /// can't undo each other's. If pi can't say, the last settings stand.
    @MainActor static func update(pi: URL, folder: URL, env: [String: String], compactAt: Int, timeout: TimeInterval = 10,
                                  note: (String) -> Void) async {
        let file = folder.appendingPathComponent("settings.json")
        guard let before = read(file) else {
            note("pi's settings unreadable: compaction settings left as they were")
            return
        }
        let stamp = stamp(pi: pi, folder: folder, compactAt: compactAt)
        let enabled = (before["compaction"] as? [String: Any])?["enabled"] as? Bool
        if before[stampKey] as? String == stamp, enabled == true { return }
        guard let windows = await discover(pi: pi, env: env, timeout: timeout) else {
            note("pi's models unknown: compaction settings left as they were")
            return
        }
        guard let current = read(file) else { return }
        var updated = settings(current, windows: windows, compactAt: compactAt)
        updated[stampKey] = stamp
        guard !NSDictionary(dictionary: updated).isEqual(to: current),
              let data = try? JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// The settings in this file, empty if there is none yet, nil if there's something in it that can't be read.
    private static func read(_ file: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
