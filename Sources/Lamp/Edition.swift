import Foundation

/// Which Lamp this is: the release people install, or the development build made from source. They are
/// separate apps on the Mac: different name and icon, bundle id, folders, ports, URL scheme and Keychain
/// entries, so running the one you're working on never touches the one you use. Everything that names
/// Lamp on disk or on the network goes through here. Built-in choice: build.sh (FLAVOR=dev, the default)
/// and release.sh (FLAVOR=release) set the bundle id, which this reads. A development build from a worktree is
/// an instance of its own, named after the worktree (`instance`), so builds from two worktrees run at once.
enum Edition {
    static let bundleID = Bundle.main.bundleIdentifier ?? "dev.lamp.host"
    static let isDev = bundleID == "dev.lamp.host.dev" || bundleID.hasPrefix("dev.lamp.host.dev.")
    /// A development build from one worktree among others (scripts/instance.sh, build.sh): named after its
    /// worktree, with its own folders, ports, scheme and prefixes, so two can run at once. Empty for the plain
    /// Lamp Dev, and for the release.
    static let instance: String = isDev && bundleID.hasPrefix("dev.lamp.host.dev.") ? String(bundleID.dropFirst("dev.lamp.host.dev.".count)) : ""

    /// What the app is called where a name appears: window title, folders.
    static let name = isDev ? "Lamp Dev" + (instance.isEmpty ? "" : " " + instance) : "Lamp"

    /// The names of every Lamp's folder on this Mac (under Application Support, and "<name> Apps" under
    /// Applications): the release's, the plain development build's, and each instance's. What one Lamp closes to
    /// the agent, it closes for all of them.
    static var lampFolderNames: [String] {
        let support = home.appendingPathComponent("Library/Application Support")
        let instances = ((try? FileManager.default.contentsOfDirectory(atPath: support.path)) ?? [])
            .filter { $0.hasPrefix("Lamp Dev ") && !$0.hasSuffix("-fresh-start") }
        return Array(Set(["Lamp", "Lamp Dev", name] + instances)).sorted()
    }

    static var bugReportEndpoint: URL {
        // An isolated development build can exercise real HTTP delivery to a local stand-in.
        // Installed releases always use lamp.dev; no destination secret belongs in the app.
        if isDev, let value = ProcessInfo.processInfo.environment["LAMP_BUG_REPORT_TEST_ENDPOINT"],
           let url = URL(string: value), url.scheme == "http",
           ["127.0.0.1", "localhost", "[::1]"].contains(url.host ?? "") { return url }
        return URL(string: "https://lamp.dev/api/bug-report")!
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// ~/Library/Application Support/Lamp (Dev): apps, keys, pi's config, models, tools.
    static let supportFolder = home.appendingPathComponent("Library/Application Support/\(name)")
    /// ~/Applications/Lamp (Dev) Apps: where built apps are installed.
    static let appsFolder = home.appendingPathComponent("Applications/\(name) Apps")
    static let logsFolder = home.appendingPathComponent("Library/Logs/\(name)")

    /// An instance's four ports come from its name, in a range of their own above the two fixed sets, so two
    /// worktrees' builds seldom collide; the apps learn them at install (`Template.installValues`).
    private static let firstPort: UInt16 = {
        guard !instance.isEmpty else { return isDev ? 47821 : 47811 }
        var hash: UInt32 = 2166136261
        for byte in instance.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return 48000 + UInt16(hash % 240) * 4
    }()
    static let gatewayPort: UInt16 = firstPort
    static let localModelPort = Int(firstPort) + 1
    static let mlxPort = Int(firstPort) + 2
    /// Where the chat inside each app's window (`Sidebar`) reaches Lamp, on this Mac only.
    static let sidebarPort: UInt16 = firstPort + 3

    /// lamp://edit?app=… (lamp-dev:// for the development build, lamp-dev-<instance>:// for an instance),
    /// registered in Info.plist by build.sh.
    static let urlScheme = isDev ? "lamp-dev" + (instance.isEmpty ? "" : "-" + instance) : "lamp"
    /// The bundle id of every app this Lamp builds: dev.lamp.app.<slug>, dev.lamp.dev.app.<slug>, or
    /// dev.lamp.dev.<instance>.app.<slug>.
    static let appBundlePrefix = isDev ? "dev.lamp.dev." + (instance.isEmpty ? "" : instance + ".") + "app." : "dev.lamp.app."
    /// Distributed notifications between Lamp and its apps carry this prefix, so one Lamp's apps don't hear
    /// another's.
    static let notificationPrefix = isDev ? "dev.lamp.dev." + (instance.isEmpty ? "" : instance + ".") : "dev.lamp."
}
