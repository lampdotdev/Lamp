import AppKit
import Foundation
import LampOutsideKit

// Lamp's MCP server as a person's own coding agent starts it: `claude mcp add lamp -- "<Lamp.app>/Contents/Helpers/lamp-mcp"`,
// or `codex mcp add lamp -- …`. It speaks MCP over stdio (one JSON-RPC message a line) and carries each message,
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
