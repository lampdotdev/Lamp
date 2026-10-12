import Foundation

/// Lamp Dev can act as if things a fresh Mac lacks were missing, so the screens for that Mac can be worked
/// on without a VM. `LAMP_PRETEND_MISSING` is a comma-separated list, read once at launch:
///
///     open --env LAMP_PRETEND_MISSING=bare -a "Lamp Dev"
///
/// - `tools`: the Command Line Tools. Install… opens no installer: a stand-in for Apple's window is "open"
///   for `installSeconds`, the person "comes back" to Lamp from it after `backSeconds`, and the tools
///   arrive as it closes.
/// - `tools-fail`: as `tools`, but the first install closes halfway with nothing installed; trying again works.
/// - `xcode`: the full Xcode app and every step of setting it up for iPhone apps (below), and the icon
///   tools that come with it.
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
    static let backSeconds: TimeInterval = 8

    static let missing: Set<String> = {
        guard Edition.isDev, let value = ProcessInfo.processInfo.environment["LAMP_PRETEND_MISSING"] else { return [] }
        let words = Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
        var expanded = words.contains("bare") ? words.subtracting(["bare"]).union(bare) : words
        if expanded.contains("tools-fail") { expanded.insert("tools") }
        if !expanded.isEmpty { NSLog("Lamp Dev is pretending these are missing: %@", expanded.sorted().joined(separator: ", ")) }
        return expanded
    }()

    static func isMissing(_ thing: String) -> Bool { missing.contains(thing.lowercased()) }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var installStarted: Date?
    nonisolated(unsafe) private static var attempts = 0

    /// How long the stand-in installer has been going, and whether this go is the one that fails.
    private static var install: (elapsed: TimeInterval, fails: Bool)? {
        lock.withLock {
            installStarted.map { (Date().timeIntervalSince($0), attempts == 1 && missing.contains("tools-fail")) }
        }
    }

    /// Stands in for Apple's installer. Asking again while it's open leaves it running; asking after it
    /// closed starts it over.
    static func startInstall() {
        let open = installerOpen
        lock.withLock {
            guard !open else { return }
            installStarted = Date()
            attempts += 1
        }
    }

    /// The stand-in installer's window is open. On success it stays a moment after the tools arrive, as
    /// Apple's does, so a look between the two never reads as a failure.
    static var installerOpen: Bool {
        guard let install else { return false }
        return install.elapsed < (install.fails ? installSeconds / 2 : installSeconds + 2)
    }

    /// The person has been through the stand-in window's buttons and come back to Lamp.
    static var backFromInstaller: Bool { (install?.elapsed ?? 0) >= backSeconds }

    /// The Command Line Tools, as the pretend installer has them: missing until it has run its course.
    static var toolsMissing: Bool {
        guard isMissing("tools") else { return false }
        guard let install, !install.fails else { return true }
        return install.elapsed < installSeconds
    }

    // MARK: Xcode, one step at a time

    /// With `xcode`, iPhone setup starts from no Xcode at all and goes through each step a new Mac goes
    /// through (`PhoneTools.Step`, by name): the step's button opens nothing and the step is done a little
    /// later, as if the person had done what it asked. The Xcode really on this Mac answers from there on,
    /// so it has to be fully set up for the later steps to pass.
    nonisolated(unsafe) private static var xcodeDone: [String: Date] = [:]

    static func xcodeSeconds(_ step: String) -> TimeInterval { step == "xcode" ? 45 : 10 }

    /// The person did what the step asked; it passes `xcodeSeconds` from now.
    static func finish(xcodeStep step: String) {
        lock.withLock { if xcodeDone[step] == nil { xcodeDone[step] = Date().addingTimeInterval(xcodeSeconds(step)) } }
    }

    static func xcodeMissing(_ step: String) -> Bool {
        guard isMissing("xcode") else { return false }
        guard let done = lock.withLock({ xcodeDone[step] }) else { return true }
        return Date() < done
    }
}
