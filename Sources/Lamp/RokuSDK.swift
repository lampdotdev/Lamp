import Foundation

/// What Roku's SDK lets the agent see of an app on the person's Roku, beside the picture Lamp's bridge takes: the
/// app's screen as SceneGraph's tree of nodes (which has focus, every label's text, where each sits), and a crash's
/// stack read back to the app's own TypeScript lines. Both come from the SDK's MCP server, `rk mcp`, from the app's own
/// packages in Lamp's copy of it for the package step (which holds the build's source maps), run in the app's sandbox
/// with Lamp's Node, one call at a time. Lamp calls only these reads, at the device Lamp put the app on: the server's
/// other tools (sideloading, keys, rebooting, signing, the cloud emulator) are never offered to the agent, which presses
/// keys with `use_app` and puts the app on the Roku with `look_at_app`, through Lamp's bridge and its checks.
/// A kind of app asks for this with `app.declared.inspect` "roku-sdk".
enum RokuSDK {
    static let inspector = "roku-sdk"

    static func inspects(_ project: LampProject) -> Bool {
        DeviceApps.integration(for: project)?.app?.declared?.inspect == inspector
    }

    /// What follows the picture in `look_at_app` and `use_app`: the screen's nodes, and the decoded stack of a crash in
    /// what the app logged. Empty when this kind has neither, or neither could be read.
    static func notes(for project: LampProject, on device: Device, log: String?) async -> String {
        guard inspects(project), let address = device.address else { return "" }
        let source = DeviceApps.buildFolder(for: project).appendingPathComponent("source")
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent("node_modules/.bin/rk").path) else { return "" }
        var text = ""
        if Privacy.sharesPictures,
           let tree = await call("ecp", ["command": "query/app-ui", "host": address], in: source, for: project) {
            text += "\n\nThe screen as SceneGraph's nodes (from the Roku's own UI tree):\n" + cut(tree, to: 12_000)
        }
        if Privacy.sharesLog, let log, log.range(of: #"index\.js:\d+:\d+"#, options: .regularExpression) != nil,
           let decoded = await call("decode_stack_trace", ["stackTrace": String(log.suffix(20_000)), "context": 2], in: source, for: project) {
            text += "\n\nThe stack in what it logged, read back to the app's TypeScript:\n" + cut(decoded, to: 6_000)
        }
        return text
    }

    private static func cut(_ text: String, to limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "\n… (cut)"
    }

    /// One tool of `rk mcp`, started for it and stopped after; nil when it couldn't answer.
    private static func call(_ tool: String, _ arguments: [String: Any], in source: URL, for project: LampProject) async -> String? {
        guard NodeTools.isReady else { return nil }
        let command = NodeTools.shellPrefix + "cd " + Sandbox.quoted(source.path) + " && exec node_modules/.bin/rk mcp"
        guard let confined = Sandbox.wrapEngine(command, for: project, opening: [source.path]) else { return nil }
        guard let client = try? MCPClient(executable: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-c", confined],
                                          environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]) else { return nil }
        defer { client.close() }
        do {
            _ = try await client.initialize()
            return try await client.call(tool, arguments: arguments).text.trimmed.nilIfEmpty
        } catch {
            return nil
        }
    }
}
