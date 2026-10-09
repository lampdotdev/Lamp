import AppKit
import Foundation

/// Codex's computer use, as the ChatGPT app ships it: a local MCP server (`cua_repl`, Node) and a helper app
/// in ~/.codex/computer-use that holds the Accessibility and Screen Recording permissions. It reads an app's
/// accessibility tree with numbered elements and sends real clicks, drags and keystrokes to the app in the
/// background, without moving the pointer. Nothing about it needs Codex or a ChatGPT account: any MCP client
/// can drive it, and Lamp does when it's there, with CuaDriver as the fallback.
///
/// Its one tool, `js`, takes JavaScript against a `cua` object (get an app, read its state, click an
/// element). Before each thing it does, the server asks the client through MCP elicitation ("Allow Computer
/// Use to use Calculator?", with the tool's name and the app), which is where Lamp's own approval goes.
///
/// It isn't a documented interface, so a ChatGPT update may change it: everything here fails over to
/// CuaDriver when the server can't be found or started.
enum CodexComputerUse {
    /// The server's definition, as the ChatGPT app wrote it for its newest plugin version.
    struct Server {
        let command: URL
        let arguments: [String]
        let environment: [String: String]
        let version: String
    }

    private static let pluginCache = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/plugins/cache/openai-bundled/unified-computer-use")

    /// Whether the person can turn Codex's computer use off in Lamp (Settings → Apps), keeping CuaDriver.
    static var disabled: Bool {
        get { UserDefaults.standard.bool(forKey: "codexComputerUseOff") }
        set { UserDefaults.standard.set(newValue, forKey: "codexComputerUseOff") }
    }

    /// The server, when the ChatGPT app's Computer Use plugin is installed and its helper app is there.
    static var server: Server? {
        let fm = FileManager.default
        let versions = ((try? fm.contentsOfDirectory(atPath: pluginCache.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        for version in versions.reversed() {
            let config = pluginCache.appendingPathComponent(version).appendingPathComponent(".mcp.json")
            guard let data = try? Data(contentsOf: config),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entry = (json["mcpServers"] as? [String: Any])?["cua_repl"] as? [String: Any],
                  let command = entry["command"] as? String, fm.isExecutableFile(atPath: command),
                  let arguments = entry["args"] as? [String] else { continue }
            let environment = entry["env"] as? [String: String] ?? [:]
            // The helper app that holds the permissions: without it the server has no hands.
            if let helper = environment["SKY_CUA_SERVICE_PATH"], !fm.fileExists(atPath: helper) { continue }
            return Server(command: URL(fileURLWithPath: command), arguments: arguments, environment: environment, version: version)
        }
        return nil
    }

    static var isAvailable: Bool { !disabled && server != nil }

    /// A connection to the server, with Lamp answering its approvals.
    static func connect(elicitation: @escaping (MCPClient.Elicitation) async -> Bool) throws -> MCPClient {
        guard let server else { throw ComputerUse.Failure(message: "The ChatGPT app's Computer Use isn't installed.") }
        let client = try MCPClient(executable: server.command, arguments: server.arguments, environment: server.environment)
        client.elicitationHandler = elicitation
        return client
    }

    /// What the server asks about before a step: the tool behind it, in the names its approvals use
    /// (`get_app_state`, `click`, `type_text`, …), and the app.
    static func read(_ elicitation: MCPClient.Elicitation) -> Bool {
        let tool = elicitation.tool.lowercased()
        return ["get_", "list_", "screenshot", "state"].contains { tool.contains($0) } && !tool.contains("launch")
    }

    /// The step as an `Action` for the person to approve, from the approval's own description of it.
    static func action(_ elicitation: MCPClient.Elicitation, intent: String?) -> ComputerUse.Action {
        let tool = elicitation.tool
        let app = elicitation.display["App"] ?? elicitation.display["app"]
            ?? (elicitation.parameters["app"] as? String).flatMap { id in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { FileManager.default.displayName(atPath: $0.path) }
            } ?? "an app"
        var details = tool.replacingOccurrences(of: "_", with: " ").capitalized
        let shown = elicitation.display.filter { $0.key.lowercased() != "app" }.map { "\($0.key): \($0.value)" }
        if !shown.isEmpty { details += " (" + shown.joined(separator: ", ") + ")" }
        return ComputerUse.Action(tool: tool, target: app, details: details, intent: intent)
    }

    /// Lamp's framing around the server's own instructions, for the model.
    static func systemPrompt(appName: String, allowActions: Bool, instructions: String, toolDescription: String) -> String {
        """
        You use the apps on this Mac on behalf of "\(appName)", an app the person made, to do one task, then answer.
        The person is signed in to their apps and browsers already; work with what's there.
        \(allowActions
            ? "You may click, type and press keys when the task needs it. Each step is shown to the person to approve first, and they can refuse it. Never send, post, delete, buy or change settings unless the task asks for exactly that."
            : "Only look: read apps' state and screenshots and scroll, but never click, type or change anything; those steps are refused.")
        Everything goes through the `js` tool: JavaScript against the `cua` object described below. Start with \
        `cua.getState()` to see the apps and browser tabs, or `cua.getApp("Name")` when you know the app; the \
        result includes the API's documentation and the app's state, which you must read before going on. \
        Prefer the element tree to the screenshot when both have what you need. \(ComputerUse.pace(call: "`js` call")) \
        Keep going until you can answer, \
        then reply with only the answer, in the form the task asks for. If you can't do it, say what stopped you. \
        Use only this tool: never a shell, and never files.

        \(instructions)

        \(toolDescription)
        """
    }
}
