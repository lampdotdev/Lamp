import Foundation
import Darwin

/// Installs of an app's new icon that are waiting for the app to close.
///
/// Lamp never replaces an app on disk while it's running. Replacing deletes the copy the running app was
/// started from, and macOS then no longer takes the app for the owner of its own widget: every request to
/// redraw the widget is refused until the app is opened again, so the widget stays as it was. A build quits
/// the app before installing; a new icon doesn't need the app to quit, so its install waits here instead,
/// and happens when the app closes or with the next build, whichever comes first.
struct HeldInstalls {
    private(set) var waiting: Set<String> = []

    /// Asked before an install that isn't part of a build. True to install now; false keeps it for later.
    mutating func mayInstall(_ app: String, running: Bool) -> Bool {
        guard running else {
            waiting.remove(app)
            return true
        }
        waiting.insert(app)
        return false
    }

    /// The apps among these that have an install waiting and can take it now: closed, with a build to
    /// install. One that can't isn't due, however often it's asked about: an app with no build gets its icon
    /// with the next build, and asking again in the meantime must find nothing to do.
    func due(amongClosed closed: Set<String>, where installable: (String) -> Bool = { _ in true }) -> Set<String> {
        waiting.intersection(closed).filter(installable)
    }

    /// A build installed the app, icon and all: nothing is waiting for it any more.
    mutating func installed(_ app: String) { waiting.remove(app) }
}

/// The programs running from inside an installed app, as the kernel has them: the last word before the app is
/// replaced. NSWorkspace's list of running apps lags behind a launch, so a copy opened a moment ago can be missing
/// from it, and replacing the bundle under it leaves its chat refused for good (its program's path is gone, so
/// Lamp can't tell it's the app's).
enum RunningFromBundle {
    struct Running { let pid: pid_t; let path: String }

    /// Every process whose program is inside `bundle`.
    static func processes(inside bundle: URL) -> [Running] {
        // The kernel gives a program's real path; Foundation's own resolving drops "/private" from it, so `realpath`.
        guard let real = realpath(bundle.path, nil) else { return [] }
        let prefix = String(cString: real) + "/"
        free(real)
        var pids = [pid_t](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 64)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride)))
        guard count > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return pids.prefix(count).compactMap { pid in
            guard pid > 0, proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
            let path = String(cString: buffer)
            return path.hasPrefix(prefix) ? Running(pid: pid, path: path) : nil
        }
    }

    /// Whether the app itself is running from `bundle`: its own program, or a helper beside it, rather than one of
    /// its extensions (the chat beside it, a widget, a share extension), which can outlive the app by a moment.
    static func isAppOpen(among processes: [Running]) -> Bool {
        processes.contains { !$0.path.contains(".appex/") }
    }

    /// Clears `bundle` for replacing: false while the app itself runs from it. Extensions left from an app that has
    /// quit are given a moment to go, then ended, the way Lamp ends a widget's process: they have no app to be part of.
    static func clear(_ bundle: URL) async -> Bool {
        var left = processes(inside: bundle)
        for _ in 0..<20 where !left.isEmpty && !isAppOpen(among: left) {
            try? await Task.sleep(for: .milliseconds(100))
            left = processes(inside: bundle)
        }
        guard !isAppOpen(among: left) else { return false }
        guard !left.isEmpty else { return true }
        for process in left { kill(process.pid, SIGTERM) }
        for _ in 0..<20 where !processes(inside: bundle).isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        let stubborn = processes(inside: bundle)
        guard !isAppOpen(among: stubborn) else { return false }
        for process in stubborn { kill(process.pid, SIGKILL) }
        return true
    }
}
