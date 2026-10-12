import Foundation

/// Apps are installed in ~/Applications/Lamp Apps, which Spotlight, Launchpad and Open With find, but
/// Finder's Applications is the Mac's /Applications, where people look for them. A link there,
/// /Applications/Lamp Apps, shows them in that place without moving them: nothing to migrate, Dock icons
/// and placed widgets keep working, and since Spotlight and Launchpad don't follow links nothing is listed
/// twice. The confined agent can't reach the apps through it either: the sandbox judges the path the link
/// leads to, which it keeps closed.
enum AppsLink {
    static let path = URL(fileURLWithPath: "/Applications").appendingPathComponent(Edition.appsFolder.lastPathComponent)

    /// Once made, the link is never made again: someone who deleted it didn't want it. The value is the
    /// link's path, not a flag, because the development build's settings start as a copy of the installed
    /// Lamp's (scripts/dev-data.sh), and the installed Lamp's link isn't Lamp Dev's.
    private static let madeKey = "appsLinkMade"

    /// Called at launch and after each install. Waits for the apps folder to exist, so the link never
    /// leads nowhere.
    static func ensure() {
        guard UserDefaults.standard.string(forKey: madeKey) != path.path,
              FileManager.default.fileExists(atPath: Edition.appsFolder.path) else { return }
        if link(at: path, to: Edition.appsFolder) { UserDefaults.standard.set(path.path, forKey: madeKey) }
    }

    /// Whether `link` leads to `target` afterwards. Never replaces what's already there (another account's
    /// link, a folder someone made); an account that can't write /Applications simply has no link.
    @discardableResult
    static func link(at link: URL, to target: URL) -> Bool {
        let fm = FileManager.default
        // attributesOfItem doesn't follow a link, so one that leads nowhere still counts as taken.
        if (try? fm.attributesOfItem(atPath: link.path)) != nil {
            return (try? fm.destinationOfSymbolicLink(atPath: link.path)) == target.path
        }
        do {
            try fm.createSymbolicLink(at: link, withDestinationURL: target)
            return true
        } catch {
            print("No link to the apps folder at \(link.path): \(error.localizedDescription)")
            return false
        }
    }
}
