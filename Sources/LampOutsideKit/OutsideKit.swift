import Foundation

/// What Lamp and its MCP helper (`lamp-mcp`, in Lamp's Helpers) agree on: which Lamp a bundle id names, where that
/// Lamp's socket is, and the version of what they say over it. The helper is the program a person's own coding agent
/// (Claude Code, Codex) starts as a local MCP server, over stdio; it only carries each message to the Lamp it belongs to
/// and back. Edition reads its name from here, so the two can never disagree about a Lamp's folders.
public enum OutsideKit {
    /// The version of the helper's handshake and framing. Lamp answers a helper whose version is within
    /// `oldestProtocol...protocolVersion`, and tells any other which side to update.
    public static let protocolVersion = 1
    public static let oldestProtocol = 1

    /// The MCP versions Lamp's server speaks, newest first. A client asking for another is answered with the newest.
    public static let mcpVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    /// What a Lamp is called where its name appears, folders included, from its bundle id: the release, Lamp Nightly,
    /// the development build, or a development build from one worktree among others ("Lamp Dev <instance>").
    public static func editionName(bundleID: String) -> String {
        let isDev = bundleID == "dev.lamp.host.dev" || bundleID.hasPrefix("dev.lamp.host.dev.")
        if isDev {
            let instance = bundleID.hasPrefix("dev.lamp.host.dev.") ? String(bundleID.dropFirst("dev.lamp.host.dev.".count)) : ""
            return "Lamp Dev" + (instance.isEmpty ? "" : " " + instance)
        }
        return bundleID == "dev.lamp.host.nightly" ? "Lamp Nightly" : "Lamp"
    }

    /// Whether a bundle id is one of Lamp's: the helper serves only the Lamp it was shipped inside.
    public static func isLamp(bundleID: String) -> Bool { bundleID == "dev.lamp.host" || bundleID.hasPrefix("dev.lamp.host.") }

    /// The folder only this Lamp's socket is in, inside its own support folder: made private to the person (0700),
    /// so nobody else on the Mac can reach the socket, whatever its own mode.
    public static func socketFolder(bundleID: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/\(editionName(bundleID: bundleID))/MCP")
    }

    public static func socketPath(bundleID: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        socketFolder(bundleID: bundleID, home: home).appendingPathComponent("lamp.sock").path
    }

    /// A Unix socket's path is at most this many bytes on macOS (`sun_path` is 104, with its terminating zero). A
    /// longer one is refused with this said, never shortened into some other folder.
    public static let maxSocketPath = 103

    /// The handshake's key: the first line each side sends is `{"lamp_hello": {...}}`.
    public static let helloKey = "lamp_hello"
}
