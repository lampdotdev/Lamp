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

    /// The request a link brought with a fetched file, kept beside it (`Store.fetchedRequest`): it goes with the copy.
    static let requestFile = "request.txt"

    /// The wish a repository was fetched to update, kept beside it (`target(beside:)`).
    static let targetFile = "update-target.txt"

    /// The new wish that named a wish on GitHub (`Store.fetchedFromWish`), kept beside it: it goes once this one is in.
    static let fromWishFile = "from-wish.txt"

    /// The wish a kept repository was fetched to update (`Store.copy(of:among:updating:)`), kept beside it so that
    /// after the wait, or a relaunch, the review offers that wish and not another copy of the same repository.
    /// Only in a folder kept for setup, never beside a file opened from anywhere else.
    static func target(beside file: URL) -> String? {
        let home = file.deletingLastPathComponent()
        guard home.deletingLastPathComponent().lastPathComponent == "Waiting" else { return nil }
        return (try? String(contentsOf: home.appendingPathComponent(targetFile), encoding: .utf8))?.trimmed.nilIfEmpty
    }

    /// Keeps a copy, since the file may be a temporary one (opened straight from Mail or Messages), behind
    /// any already kept: each gets its review, none pushes another out. The same file opened again is kept
    /// once. False when no copy could be made (a full disk, say): nothing is remembered then, so Lamp never
    /// promises a file it may not have. A request kept beside a fetched file is copied with it.
    func keep(_ file: URL, updating target: String? = nil) -> Bool {
        let fm = FileManager.default
        let kept = paths
        // The same file again counts as the same only when it's for the same wish: two copies (Keep Both) updated from
        // one repository fetch the same thing, and each still gets its own review.
        if let same = kept.first(where: { URL(fileURLWithPath: $0).lastPathComponent == file.lastPathComponent
            && Self.target(beside: URL(fileURLWithPath: $0)) == target
            && fm.contentsEqual(atPath: $0, andPath: file.path) }) {
            // The same file again, with a request: the newer request is the one meant, so it replaces the kept one.
            let request = file.deletingLastPathComponent().appendingPathComponent(Self.requestFile)
            if Store.fetchedRequest(beside: file) != nil, fm.fileExists(atPath: request.path) {
                let keptRequest = URL(fileURLWithPath: same).deletingLastPathComponent().appendingPathComponent(Self.requestFile)
                try? fm.removeItem(at: keptRequest)
                try? fm.copyItem(at: request, to: keptRequest)
            }
            return true
        }
        let home = folder.appendingPathComponent(UUID().uuidString)
        let copy = home.appendingPathComponent(file.lastPathComponent)
        do {
            try fm.createDirectory(at: home, withIntermediateDirectories: true)
            try fm.copyItem(at: file, to: copy)
            let request = file.deletingLastPathComponent().appendingPathComponent(Self.requestFile)
            if Store.fetchedRequest(beside: file) != nil, fm.fileExists(atPath: request.path) {
                try fm.copyItem(at: request, to: home.appendingPathComponent(Self.requestFile))
            }
            if let target { try target.write(to: home.appendingPathComponent(Self.targetFile), atomically: true, encoding: .utf8) }
            let fromWish = file.deletingLastPathComponent().appendingPathComponent(Self.fromWishFile)
            if Store.fetchedFromWish(beside: file) != nil { try fm.copyItem(at: fromWish, to: home.appendingPathComponent(Self.fromWishFile)) }
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

/// Something Lamp finds out once, a moment after launch, that others may have to wait for: here, its first
/// real look at setup. A shared app that launched Lamp arrives before that look, and waits for it rather than
/// being decided on a guess, so the same file on the same Mac always goes the same way.
@MainActor
final class FirstLook {
    private(set) var isDone = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Returns at once when the look has been made, otherwise when it is.
    func wait() async {
        guard !isDone else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func done() {
        guard !isDone else { return }
        isDone = true
        let resumed = waiting
        waiting = []
        resumed.forEach { $0.resume() }
    }
}
