import Foundation
import Darwin

/// The process macOS runs an app's widget in.
///
/// It is a program of its own, started by macOS from the widget inside the installed app, and it can stay
/// alive for as long as the widget keeps being redrawn. Replacing the app on disk under it leaves an old
/// process that macOS no longer takes for the widget now installed: every reload fails ("Bundle version did
/// not match") and the widget stays as it was until that process happens to end. So Lamp ends it at the same
/// point it would never replace a running app: just before the installed copy is swapped. macOS starts a
/// new one, from the new copy, the next time the widget is drawn.
enum WidgetProcess {
    /// The running processes started from exactly this program file. Found by the file's place on disk, so
    /// only the widget inside this one app is ever matched, never another app's.
    static func running(from executable: URL) -> [pid_t] {
        let wanted = executable.resolvingSymlinksInPath().standardizedFileURL.path
        var pids = [pid_t](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 64)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride)))
        guard count > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return pids.prefix(count).filter { pid in
            guard pid > 0, proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
            return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().standardizedFileURL.path == wanted
        }
    }

    /// Ends them, the way Lamp quits an app: asked first, given a moment, then stopped. Nothing running is
    /// the usual case and is fine. True when none is left.
    @discardableResult
    static func end(from executable: URL) async -> Bool {
        let pids = running(from: executable)
        guard !pids.isEmpty else { return true }
        for pid in pids { kill(pid, SIGTERM) }
        for _ in 0..<30 where !running(from: executable).isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        for pid in running(from: executable) { kill(pid, SIGKILL) }
        for _ in 0..<10 where !running(from: executable).isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return running(from: executable).isEmpty
    }
}
