import AppKit

/// Install Command-Line Tool… in Lamp's menu: puts lamp on the person's PATH as a link in /usr/local/bin to the copy
/// inside this app (`cli/lamp`, the launcher on the app's own runtime, cli/lamp.sh), so the command updates with Lamp
/// and needs no Node. /usr/local/bin is on every Mac's PATH and belongs to the system, so the link is made with the
/// person's administrator password when Lamp can't make it itself. Nothing else is changed: no shell profile.
enum CommandLineTool {
    static let folder = "/usr/local/bin"
    static var link: String { "\(folder)/\(Edition.commandName)" }

    /// The launcher this app carries, when it has one (a build from `build.sh` does).
    static var launcher: URL? {
        guard let file = Bundle.main.resourceURL?.appendingPathComponent("cli/lamp"),
              FileManager.default.isExecutableFile(atPath: file.path) else { return nil }
        return file
    }

    enum Found: Equatable {
        case nothing
        /// Already this app's own launcher.
        case ours
        /// Something else by that name: another Lamp's launcher, lamp from npm, or a file that isn't a link.
        case other(String)
    }

    static func found(at path: String = link, launcher: URL? = launcher) -> Found {
        let fm = FileManager.default
        guard let destination = try? fm.destinationOfSymbolicLink(atPath: path) else {
            return fm.fileExists(atPath: path) ? .other(path) : .nothing
        }
        let target = URL(fileURLWithPath: destination, relativeTo: URL(fileURLWithPath: path).deletingLastPathComponent())
            .standardizedFileURL.resolvingSymlinksInPath().path
        if let launcher, target == launcher.resolvingSymlinksInPath().path { return .ours }
        return .other(target)
    }

    @MainActor static func install() {
        let name = Edition.commandName
        guard let launcher else {
            say("This copy of \(Edition.name) has no command-line tool.", "A copy of \(Edition.name) built for the Mac has one.")
            return
        }
        switch found() {
        case .ours:
            say("\(name) is already installed.", "Run \(name) in Terminal. It updates with \(Edition.name).")
            return
        case .other(let elsewhere):
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Replace the \(name) that's already installed?"
            alert.informativeText = "\(link) is another copy of \(name) (\(elsewhere)). \(Edition.name)'s own updates with \(Edition.name)."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        case .nothing:
            break
        }
        guard linked(launcher) else { return }
        say("\(name) is installed.", "Open a new Terminal window and run \(name). It updates with \(Edition.name).")
    }

    /// Makes the link: as Lamp itself where it may write there, otherwise with the person's administrator password.
    /// False when it wasn't made (the person cancelled, or it failed, which is said).
    @MainActor private static func linked(_ launcher: URL) -> Bool {
        let fm = FileManager.default
        if fm.isWritableFile(atPath: folder) {
            try? fm.removeItem(atPath: link)
            if (try? fm.createSymbolicLink(atPath: link, withDestinationPath: launcher.path)) != nil { return true }
        }
        let quoted = { (text: String) in "quoted form of \"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        let script = """
        do shell script "/bin/mkdir -p " & \(quoted(folder)) & " && /bin/ln -sfn " & \(quoted(launcher.path)) & " " & \(quoted(link)) with prompt "\(Edition.name) wants to put \(Edition.commandName) in \(folder), so it runs in Terminal." with administrator privileges
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        guard let error else { return found() == .ours }
        // -128 is the person choosing Cancel in the password prompt.
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return false }
        say("\(Edition.commandName) couldn't be installed.", error[NSAppleScript.errorMessage] as? String ?? "")
        return false
    }

    @MainActor private static func say(_ message: String, _ detail: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}
