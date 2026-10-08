import Foundation

/// Shared apps opened before setup finished. Lamp keeps a copy of each and remembers them on disk, like the
/// requests waiting for setup, so their reviews open by themselves once the person is through setup, in this
/// run or the next.
struct WaitingImport {
    /// The kept copies' paths, in the order the apps were opened.
    static let key = "waitingSharedApps"
    /// What an earlier Lamp saved: the path of the one file it kept.
    static let earlierKey = "waitingSharedApp"
    var defaults = UserDefaults.standard
    /// Where files waiting for setup are kept, each in a folder of its own.
    let folder: URL

    /// When a shared app's review may open: setup really in place (Apple's tools and an AI agent, so the AI
    /// check can read the app before it runs) and the welcome over. Never while the welcome is still up, even
    /// with everything in place: the review would land in the middle of setup, the moment an agent is chosen.
    /// It waits for "Start building", or a launch that needs no welcome.
    static func reviewsCanOpen(setupReady: Bool, welcomeOver: Bool) -> Bool { setupReady && welcomeOver }

    private var paths: [String] {
        if let saved = defaults.stringArray(forKey: Self.key) { return saved }
        return defaults.string(forKey: Self.earlierKey).map { [$0] } ?? []
    }

    private func save(_ paths: [String]) {
        defaults.removeObject(forKey: Self.earlierKey)
        if paths.isEmpty { defaults.removeObject(forKey: Self.key) } else { defaults.set(paths, forKey: Self.key) }
    }

    /// How many shared apps are waiting.
    var count: Int { paths.count }

    /// Keeps a copy, since the file may be a temporary one (opened straight from Mail or Messages), behind
    /// any already kept: each gets its review, none pushes another out. The same file opened again is kept
    /// once. False when no copy could be made (a full disk, say): nothing is remembered then, so Lamp never
    /// promises a file it may not have.
    func keep(_ file: URL) -> Bool {
        let fm = FileManager.default
        let kept = paths
        if kept.contains(where: { URL(fileURLWithPath: $0).lastPathComponent == file.lastPathComponent
            && fm.contentsEqual(atPath: $0, andPath: file.path) }) { return true }
        let home = folder.appendingPathComponent(UUID().uuidString)
        let copy = home.appendingPathComponent(file.lastPathComponent)
        do {
            try fm.createDirectory(at: home, withIntermediateDirectories: true)
            try fm.copyItem(at: file, to: copy)
        } catch {
            try? fm.removeItem(at: home)
            return false
        }
        save(kept + [copy.path])
        return true
    }

    /// Hands over the kept file that has waited longest, once: it leaves the list, so its review can't open
    /// twice. Nothing until reviews may open (`reviewsCanOpen`).
    func take(setupReady: Bool, welcomeOver: Bool) -> URL? {
        guard Self.reviewsCanOpen(setupReady: setupReady, welcomeOver: welcomeOver) else { return nil }
        var waiting = paths
        defer { save(waiting) }
        while !waiting.isEmpty {
            let path = waiting.removeFirst()
            if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// The folders holding the kept copies, which clearing out old waiting files must leave alone. Only ever
    /// folders inside this one, whatever the saved setting says.
    var keptFolders: [String] {
        paths.compactMap { path in
            let home = URL(fileURLWithPath: path).deletingLastPathComponent()
            return home.deletingLastPathComponent().path == folder.path ? home.path : nil
        }
    }
}
