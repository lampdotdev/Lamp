import Foundation

/// Lamp Dev can act as if things a fresh Mac lacks were missing, so the screens for that Mac can be worked
/// on without a VM. `LAMP_PRETEND_MISSING` is a comma-separated list, read once at launch:
///
///     open --env LAMP_PRETEND_MISSING=bare -a "Lamp Dev"
///
/// - `tools`: the Command Line Tools. Install… opens no installer; they "arrive" `installSeconds` later.
/// - `xcode`: the full Xcode app, so iPhone apps ask for it, and the icon tools that come with it.
/// - any other word: a command Lamp looks for on the PATH (`uv`, `mflux-generate`, `mlx_lm.server`).
/// - `bare`: all of the above that a Mac straight out of the box doesn't have.
///
/// Claude Code and Codex aren't here: Lamp's copies live in its own folder, so `fresh-start.sh` already
/// gives a Lamp without them, and their download is the real one.
///
/// It fools only Lamp's checks: anything that runs `swift` or `xcrun` still finds the real ones. A release
/// build ignores it.
enum Pretend {
    static let bare: Set<String> = ["tools", "xcode", "uv", "mflux-generate", "mlx_lm.server"]
    static let installSeconds: TimeInterval = 30

    static let missing: Set<String> = {
        guard Edition.isDev, let value = ProcessInfo.processInfo.environment["LAMP_PRETEND_MISSING"] else { return [] }
        let words = Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
        let expanded = words.contains("bare") ? words.subtracting(["bare"]).union(bare) : words
        if !expanded.isEmpty { NSLog("Lamp Dev is pretending these are missing: %@", expanded.sorted().joined(separator: ", ")) }
        return expanded
    }()

    static func isMissing(_ thing: String) -> Bool { missing.contains(thing.lowercased()) }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var installStarted: Date?

    /// Stands in for Apple's installer: the first request starts the clock, later ones ("Show Installer
    /// Again") leave it running.
    static func startInstall() {
        lock.withLock { if installStarted == nil { installStarted = Date() } }
    }

    /// The Command Line Tools, as the pretend installer has them: missing until it has run its course.
    static var toolsMissing: Bool {
        guard isMissing("tools") else { return false }
        guard let started = lock.withLock({ installStarted }) else { return true }
        return Date().timeIntervalSince(started) < installSeconds
    }
}
