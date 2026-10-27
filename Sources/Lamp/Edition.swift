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
    /// ~/Library/Developer/Lamp: tools too large to keep a copy of for each Lamp (Android's SDK, a Java runtime),
    /// shared by every Lamp on this Mac on purpose, as the app-signing keychain is. The agent's sandbox lets a
    /// build read the person's developer folder and never write it, so what Lamp runs from here is what Lamp put
    /// there.
    static let sharedDeveloperFolder = home.appendingPathComponent("Library/Developer/Lamp")
    /// ~/Library/Caches/Lamp: what a build fetches and may fetch again (Gradle's dependencies), shared the same way;
    /// the sandbox opens the caches folder to every command.
    static let sharedCachesFolder = home.appendingPathComponent("Library/Caches/Lamp")

    /// An instance's four ports come from its name, in a range of their own above the two fixed sets, so two
    /// worktrees' builds seldom collide; the apps learn them at install (`Template.installValues`).
    private static let firstPort: UInt16 = instance.isEmpty ? (isDev ? 47821 : 47811) : 48000 + slot(of: instance) * 4

    /// Where an instance's ports go among the others', from its name.
    private static func slot(of instance: String) -> UInt16 {
        var hash: UInt32 = 2166136261
        for byte in instance.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return UInt16(hash % 240)
    }

    /// The ports of Lamp's own adb server and of the emulator it starts (`AndroidTools.environment`, `Emulator.start`).
    /// Neither is adb's usual: the server on 5037 takes any program on this Mac as its client, and an emulator on
    /// 5554–5585 is found by every adb server, so with them a command of the agent's could reach the emulator, or
    /// the person's phone through Lamp's server, by running `adb`. On ports of each Lamp's own the agent's sandbox
    /// refuses them by number (`Sandbox.profile`), and an adb started anywhere else doesn't come across the
    /// emulator.
    struct AndroidPorts: Equatable {
        let server: Int
        let console: Int
        /// The emulator's adb port, which Android has as the one after its console's.
        var bridge: Int { console + 1 }
        /// The emulator's control interface (gRPC), which it always starts: it drives the screen for whoever holds
        /// the token the emulator leaves in the caches folder, which the sandbox opens, so it's refused by port too.
        let control: Int
        /// The same two for the TV emulator, which runs beside the phone on ports of its own, so a screen can be open
        /// in both at once and opening one never closes the other.
        let tvConsole: Int
        var tvBridge: Int { tvConsole + 1 }
        let tvControl: Int
        /// Every one of them, for the sandbox to close.
        var all: [Int] { [server, console, bridge, control, tvConsole, tvBridge, tvControl] }
    }
    static let androidPorts = androidPorts(isDev: isDev, instance: instance)

    static func androidPorts(isDev: Bool, instance: String) -> AndroidPorts {
        guard isDev else { return AndroidPorts(server: 47815, console: 47818, control: 47816, tvConsole: 47880, tvControl: 47882) }
        guard !instance.isEmpty else { return AndroidPorts(server: 47825, console: 47828, control: 47826, tvConsole: 47884, tvControl: 47886) }
        // A range of each for the instances, a pair for each emulator's two: instances whose names land on different
        // slots never share a port, so never an emulator. The TV's are above the phone pages' (`phonePagePorts`).
        let slot = Int(slot(of: instance))
        return AndroidPorts(server: 49000 + slot, console: 49600 + 2 * slot, control: 49300 + slot,
                            tvConsole: 54000 + 2 * slot, tvControl: 54500 + slot)
    }

    /// The same for the Lamp whose folder has this name (`lampFolderNames`), so each Lamp's sandbox closes every
    /// Lamp's; nil for a folder that isn't a Lamp's.
    static func androidPorts(folder name: String) -> AndroidPorts? {
        if name == "Lamp" { return androidPorts(isDev: false, instance: "") }
        if name == "Lamp Dev" { return androidPorts(isDev: true, instance: "") }
        guard name.hasPrefix("Lamp Dev ") else { return nil }
        return androidPorts(isDev: true, instance: String(name.dropFirst("Lamp Dev ".count)))
    }
    /// The ports a TV app's phone page is served on, one app to a port while its page is served (`PhoneSites`), so each
    /// app's page is an origin of its own in the phone's browser and one app's page can never read what another's
    /// keeps. Sixteen of each Lamp's own, in a range clear of the others'.
    static let phonePagePorts = phonePagePorts(isDev: isDev, instance: instance)

    static func phonePagePorts(isDev: Bool, instance: String) -> ClosedRange<UInt16> {
        guard isDev else { return 47840...47855 }
        guard !instance.isEmpty else { return 47860...47875 }
        let start = 50100 + slot(of: instance) * 16
        return start...(start + 15)
    }
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
