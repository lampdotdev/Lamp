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
///
/// The same before an app is deleted: its copy goes to the Trash, where the process would carry on, and an
/// app made later under the same name would be answered for by it.
enum WidgetProcess {
    /// The running processes that are this app's widget: started from exactly this program file, or from
    /// another copy of the same widget, told by the bundle identifier of the widget they were started from.
    /// A copy elsewhere is real: deleting an app moves it to the Trash, and its widget's process goes on
    /// running from there, so a new app made under the same name finds an old process answering for it.
    /// Another app's widget has another identifier and is never matched.
    static func running(from executable: URL, identifier: String? = nil) -> [pid_t] {
        let wanted = executable.resolvingSymlinksInPath().standardizedFileURL.path
        var pids = [pid_t](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 64)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride)))
        guard count > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return pids.prefix(count).filter { pid in
            guard pid > 0, proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
            let path = URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().standardizedFileURL
            if path.path == wanted { return true }
            guard let identifier else { return false }
            // <something>.appex/Contents/MacOS/<program>: the widget it belongs to says who it is.
            let bundle = path.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            guard bundle.pathExtension == "appex",
                  let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) else { return false }
            return info["CFBundleIdentifier"] as? String == identifier
        }
    }

    /// Ends them, the way Lamp quits an app: asked first, given a moment, then stopped. Nothing running is
    /// the usual case and is fine. True when none is left.
    @discardableResult
    static func end(from executable: URL, identifier: String? = nil) async -> Bool {
        let pids = running(from: executable, identifier: identifier)
        guard !pids.isEmpty else { return true }
        for pid in pids { kill(pid, SIGTERM) }
        for _ in 0..<30 where !running(from: executable, identifier: identifier).isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        for pid in running(from: executable, identifier: identifier) { kill(pid, SIGKILL) }
        for _ in 0..<10 where !running(from: executable, identifier: identifier).isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return running(from: executable, identifier: identifier).isEmpty
    }

    /// Ends the widget process of an app Lamp builds, wherever its copy is running from.
    @discardableResult
    static func end(for project: LampProject) async -> Bool {
        let widget = Template.widgetURL(in: project.installedURL, of: project)
        return await end(from: widget.appendingPathComponent("Contents/MacOS/\(project.exe)Widget"),
                         identifier: Template.widgetBundleID(for: project))
    }
}
