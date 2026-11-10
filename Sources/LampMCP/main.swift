import AppKit
import Foundation
import LampOutsideKit

// Lamp's MCP server as a person's own coding agent starts it, set up by that agent from what `lamp-mcp --help` says
// (`setupSteps`), so the person never opens a Terminal. It speaks MCP over stdio (one JSON-RPC message a line) and carries each message,
// unchanged, to the Lamp it was shipped inside, over that Lamp's private socket (`OutsideKit.socketPath`), and each
// answer back. It knows nothing of the tools: Lamp answers `initialize`, `tools/list` and every call itself.
//
// Lamp not running is started, in the background, from this helper's own bundle. Lamp quitting or crashing while a call
// is under way answers that call as interrupted; the next message reconnects, starting Lamp again if need be.

setvbuf(stdout, nil, _IOFBF, 1 << 16)

/// Lamp.app, three folders up from Contents/Helpers/lamp-mcp.
let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let appBundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let bundleID = (NSDictionary(contentsOf: appBundle.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String) ?? ""

let output = NSLock()
func send(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    output.lock()
    FileHandle.standardOutput.write(data + Data("\n".utf8))
    output.unlock()
}
func say(_ text: String) { FileHandle.standardError.write(Data(("lamp-mcp: " + text + "\n").utf8)) }

func failure(_ id: Any, _ code: Int, _ message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

/// The connection to Lamp, and the calls sent over it and not yet answered, by their JSON-RPC id (as JSON text).
final class Link {
    private let lock = NSLock()
    private var socket: Int32 = -1
    private var pending: [String: Any] = [:]
    /// Why the last connection couldn't be made, said to the agent with each call until one can.
    private(set) var refusal: String?
    /// Takes Lamp's answers instead of standard output, for `--check`.
    var onLine: ((Data) -> Void)?

    func idKey(_ id: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: ["k": id])).map { String(decoding: $0, as: UTF8.self) } ?? "\(id)"
    }

    /// Sends a message to Lamp, connecting first. False when there's no Lamp to send it to (`refusal` says why).
    func forward(_ line: Data, id: Any?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if socket < 0, !connect() { return false }
        if let id { pending[idKey(id)] = id }
        if !writeAll(socket, line + Data("\n".utf8)) {
            if let id { pending[idKey(id)] = nil }
            close(socket)
            socket = -1
            refusal = "Lamp closed the connection."
            return false
        }
        return true
    }

    private func connect() -> Bool {
        guard OutsideKit.isLamp(bundleID: bundleID) else {
            refusal = "lamp-mcp has to run from inside Lamp.app (Contents/Helpers); this copy isn't in one."
            return false
        }
        let path = OutsideKit.socketPath(bundleID: bundleID)
        guard path.utf8.count <= OutsideKit.maxSocketPath else {
            refusal = "This Lamp's folder path is too long for its socket (\(path.utf8.count) bytes, at most \(OutsideKit.maxSocketPath))."
            return false
        }
        var fd = open(path)
        if fd < 0 {
            // Not running: started from this helper's own bundle, by its path (never by bundle id, which could be
            // another copy), in the background, and waited for.
            launchLamp()
            let deadline = Date().addingTimeInterval(45)
            while fd < 0, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.5)
                fd = open(path)
            }
        }
        guard fd >= 0 else {
            refusal = "Lamp didn't start, or didn't open its socket, within 45 seconds."
            return false
        }
        // The handshake: each side says its version; Lamp refuses a helper it can't speak to.
        let hello: [String: Any] = [OutsideKit.helloKey: ["protocol": OutsideKit.protocolVersion, "bundle": bundleID]]
        guard let data = try? JSONSerialization.data(withJSONObject: hello), writeAll(fd, data + Data("\n".utf8)),
              let answer = readLine(fd), let object = try? JSONSerialization.jsonObject(with: answer) as? [String: Any],
              let said = object[OutsideKit.helloKey] as? [String: Any] else {
            close(fd)
            refusal = "Lamp didn't answer the handshake."
            return false
        }
        if let error = said["error"] as? String {
            close(fd)
            refusal = error
            return false
        }
        socket = fd
        refusal = nil
        let reading = fd
        Thread.detachNewThread { self.read(reading) }
        return true
    }

    private func open(_ path: String) -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: Array(path.utf8.prefix(OutsideKit.maxSocketPath)) + [0])
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, size) } }
        if result != 0 { close(fd); return -1 }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    private func launchLamp() {
        let done = DispatchSemaphore(value: 0)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: appBundle, configuration: configuration) { _, error in
            if let error { say("couldn't start Lamp: \(error.localizedDescription)") }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 20)
    }

    /// Lamp's answers, passed on as they come. When the connection ends, every call still waiting is answered as
    /// interrupted: Lamp never ran it to its end for this helper, and doesn't run it again by itself.
    private func read(_ fd: Int32) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 1 << 16)
        while true {
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count <= 0 { break }
            buffer.append(contentsOf: chunk[0..<count])
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer = Data(buffer[buffer.index(after: newline)...])
                guard !line.isEmpty else { continue }
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = object["id"], object["method"] == nil {
                    lock.lock()
                    pending[idKey(id)] = nil
                    lock.unlock()
                }
                if let onLine { onLine(Data(line)); continue }
                output.lock()
                FileHandle.standardOutput.write(Data(line) + Data("\n".utf8))
                output.unlock()
            }
        }
        lock.lock()
        if socket == fd { socket = -1 }
        close(fd)
        let waiting = Array(pending.values)
        pending.removeAll()
        lock.unlock()
        for id in waiting {
            failure(id, -32001, "interrupted: Lamp closed before this call finished. Nothing will run it again; call look_at_app to see where the app is before applying again.")
        }
    }
}

func writeAll(_ fd: Int32, _ data: Data) -> Bool {
    data.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
            let wrote = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
            if wrote <= 0 { return false }
            offset += wrote
        }
        return true
    }
}

/// One line from a socket, byte by byte: only for the handshake, before the reading thread takes over.
func readLine(_ fd: Int32) -> Data? {
    var line = Data()
    var byte: UInt8 = 0
    while Darwin.read(fd, &byte, 1) == 1 {
        if byte == 0x0A { return line }
        line.append(byte)
        if line.count > 1 << 20 { return nil }
    }
    return nil
}

/// What an agent asked to "set up Lamp" reads and does, for the clients people run it in: Claude Code (the Claude
/// desktop app's Code tab and the command line read the same `~/.claude.json`) and Codex (the ChatGPT desktop app and
/// the command line read the same `~/.codex/config.toml`). It names this very helper, so the Lamp set up is the one
/// it came in. The desktop apps come first; the command line's own command is the last line of each.
func setupSteps() -> String {
    let path = executable.path
    let name = OutsideKit.editionName(bundleID: bundleID)
    let quoted = path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    return """
    lamp-mcp lets your coding agent work with \(name): it builds and opens the app in a folder, puts each change into it \
    while it runs, and shares it. It's a local MCP server over stdio; there's no port, key or sign-in.

    To set it up, the agent does all of this itself; the person needs no Terminal.

    Claude Code (the Claude desktop app's Code tab, or the command line):
      In ~/.claude.json, add this to the top-level "mcpServers" object (make the object if there isn't one), and keep
      everything else in the file as it is:
        "lamp": {"type": "stdio", "command": "\(quoted)", "args": []}
      In the desktop app, make the change with your file-editing tool, which asks the person to allow it: the app's
      sandbox stops a shell command writing that file. In Auto mode, Claude Code's safety check stops any edit of that
      file, even one the person agrees to; ask them first to set the session's permission mode, under the message box,
      to Manual, then allow the edit.
      Lamp's tools are in sessions started after this, so tell the person to start a new session (New, in the desktop
      app) and ask there.
      On the command line, the same in one step: claude mcp add --scope user lamp -- "\(quoted)"

    Codex (the ChatGPT desktop app's Codex, or the command line):
      In ~/.codex/config.toml, add this table (make the file if there isn't one), and keep everything else as it is:
        [mcp_servers.lamp]
        command = "\(quoted)"
        tool_timeout_sec = 1800
        default_tools_approval_mode = "approve"
      The timeout lets a call wait while the person looks over what Lamp shows them; without the approval line Codex
      asks before each of Lamp's calls, and refuses them under approval_policy = "never". Lamp's tools are in chats
      started after this, so tell the person to start a new chat (New chat, in the desktop app) and ask there.
      On the command line, the same in one step: codex mcp add lamp -- "\(quoted)", then the two lines above in its table.

    To check it: "\(quoted)" --check starts \(name) in the background if it isn't running and lists its tools. A
    sandboxed shell, such as the desktop apps', may not be allowed to start \(name): then the new session or chat is
    the check, since the app starts the helper itself.

    Then the person asks, in the new session or chat: "Open this folder in Lamp" (an app in Lamp's format, or a
    plain site with index.html at its top). Lamp shows them what it found, and builds it after Build & Open.

    """
}

/// `--check`: connects as the agent's client would, asks for the tools, and says what came back.
func check() -> Int32 {
    let name = OutsideKit.editionName(bundleID: bundleID)
    let link = Link()
    let answered = DispatchSemaphore(value: 0)
    var tools: [String]?
    var error: String?
    link.onLine = { line in
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], (object["id"] as? Int) == 2 else { return }
        tools = ((object["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        error = (object["error"] as? [String: Any])?["message"] as? String
        answered.signal()
    }
    let initialize: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
        "protocolVersion": OutsideKit.mcpVersions[0], "capabilities": [:], "clientInfo": ["name": "lamp-mcp --check", "version": "1"]]]
    let list: [String: Any] = ["jsonrpc": "2.0", "id": 2, "method": "tools/list"]
    for message in [initialize, ["jsonrpc": "2.0", "method": "notifications/initialized"], list] {
        guard let data = try? JSONSerialization.data(withJSONObject: message), link.forward(data, id: message["id"]) else {
            print("Couldn't reach \(name): \(link.refusal ?? "unknown reason.")")
            return 1
        }
    }
    guard answered.wait(timeout: .now() + 60) == .success, let tools, !tools.isEmpty else {
        print("\(name) didn't list its tools\(error.map { ": " + $0 } ?? " within 60 seconds.")")
        return 1
    }
    print("Connected to \(name). Its tools: \(tools.joined(separator: ", ")).")
    return 0
}

// Run by a person or an agent rather than by an MCP client: the steps, or the check. A Terminal's standard input is
// what tells the two apart when nothing is asked for, so the helper never sits waiting for JSON there.
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--check") { exit(check()) }
if !arguments.isEmpty || isatty(STDIN_FILENO) != 0 {
    print(setupSteps(), terminator: "")
    exit(arguments.allSatisfy { ["--help", "-h", "help", "setup", "--setup"].contains($0) } ? 0 : 2)
}

let link = Link()
while let text = Swift.readLine(strippingNewline: true) {
    guard !text.isEmpty, let data = text.data(using: .utf8) else { continue }
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    let id = object?["id"]
    let isRequest = object?["method"] != nil && id != nil
    if !link.forward(data, id: isRequest ? id : nil), isRequest, let id {
        failure(id, -32002, "Lamp can't be reached: " + (link.refusal ?? "unknown reason."))
    }
}
exit(0)
