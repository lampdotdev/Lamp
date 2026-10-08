import Foundation

/// Which Lamp this is: the release people install, or the development build made from source. They are
/// separate apps on the Mac: different name and icon, bundle id, folders, ports, URL scheme and Keychain
/// entries, so running the one you're working on never touches the one you use. Everything that names
/// Lamp on disk or on the network goes through here. Built-in choice: build.sh (FLAVOR=dev, the default)
/// and release.sh (FLAVOR=release) set the bundle id, which this reads.
/// Features that are in but not yet for everyone, switched on in Settings → Experimental.
enum Experiments {
    /// iPhone and iPad apps: built and tried in the iOS Simulator. Needs Xcode and an Accessibility grant.
    /// With it, an app can go on the person's own iPhone or iPad too (chosen under Try On), signed with their
    /// Apple account through Xcode, with Lamp answering its AI over the local network and the app keeping a
    /// copy of the person's OpenRouter key for when it's away from the Mac.
    static var iosApps: Bool { UserDefaults.standard.bool(forKey: "experimentIOSApps") }
    /// What Lamp remembers (Memory): notes about the person and about each app, kept between requests. Off,
    /// nothing is noted and the agent has no rule, tools or word about notes.
    static var memory: Bool { UserDefaults.standard.bool(forKey: Memory.switchKey) }
}

enum Edition {
    static let bundleID = Bundle.main.bundleIdentifier ?? "dev.lamp.host"
    static let isDev = bundleID.hasSuffix(".dev")

    /// What the app is called where a name appears: window title, folders.
    static let name = isDev ? "Lamp Dev" : "Lamp"

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

    static let gatewayPort: UInt16 = isDev ? 47821 : 47811
    static let localModelPort = isDev ? 47822 : 47812
    static let mlxPort = isDev ? 47823 : 47813

    /// lamp://edit?app=… (lamp-dev:// for the development build), registered in Info.plist by build.sh.
    static let urlScheme = isDev ? "lamp-dev" : "lamp"
    /// The bundle id of every app this Lamp builds: dev.lamp.app.<slug>, or dev.lamp.dev.app.<slug>.
    static let appBundlePrefix = isDev ? "dev.lamp.dev.app." : "dev.lamp.app."
    /// Distributed notifications between Lamp and its apps carry this prefix, so the two Lamps' apps
    /// don't hear each other.
    static let notificationPrefix = isDev ? "dev.lamp.dev." : "dev.lamp."
}
