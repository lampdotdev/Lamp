import CryptoKit
import Foundation

/// The two primitives that run something: a command on the device over SSH, and a program on this Mac. Both run only
/// after the person has approved the exact text for that device (`DeviceApprovals`), and both are held to what Lamp
/// decides, whatever the integration says: SSH reaches only the device's own address, with its host key pinned the first
/// time and nothing forwarded; a program runs as Lamp only when Lamp's list names it, and anything else is downloaded,
/// checked against its checksum and run in a sandbox of its own.

/// Lamp's folder for what it keeps about devices: their SSH keys and pinned host keys, the approvals, the tools. The
/// agent's sandbox closes every Lamp folder, so nothing the builder runs can read a key or add an approval.
enum DeviceFolder {
    static let root = Edition.supportFolder.appendingPathComponent("Devices")

    static func of(_ deviceID: String) -> URL {
        let folder = root.appendingPathComponent(DeviceFields.owner(deviceID))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return folder
    }

    /// A key the device gave for this Mac to sign in with (kept by a request with `keep: "key"`), used before Lamp's own.
    static func deviceKey(_ deviceID: String) -> URL { of(deviceID).appendingPathComponent("device.key") }
}

// MARK: - HTTPS

/// A device that speaks HTTPS with a certificate of its own (Xbox's Device Portal) can't be checked against any
/// authority, so Lamp does what SSH does: it keeps the certificate's fingerprint the first time it reaches the device,
/// per port, in the device's folder, and from then on refuses one that differs. While a device is only being found and
/// read, nothing is kept and nothing secret is sent (`DeviceHTTP.send`).
enum DeviceTLS {
    enum Judgement: Equatable { case trust, keep, refuse }

    static func fingerprint(_ certificate: Data) -> String {
        SHA256.hash(data: certificate).map { String(format: "%02x", $0) }.joined()
    }

    /// What to do with a certificate: trust it (it's the one kept, or nothing is being kept), keep it (the first for
    /// this device), or refuse it (another than the one kept).
    static func judge(_ fingerprint: String, kept: String?, keeping: Bool) -> Judgement {
        guard keeping else { return .trust }
        guard let kept else { return .keep }
        return kept == fingerprint ? .trust : .refuse
    }

    /// Why a certificate wasn't taken, in words for the setup card.
    enum Refusal: LocalizedError, Equatable {
        case changed, unsaved
        var errorDescription: String? {
            switch self {
            case .changed: return "This device isn't the one Lamp set up at that address: its certificate has changed. If you reset it, set it up again."
            case .unsaved: return "Lamp couldn't keep this device's certificate on this Mac, so it sent nothing to it."
            }
        }
    }

    /// One device's kept certificates.
    struct Pins: Sendable {
        let deviceID: String
        private static let lock = NSLock()
        private var file: URL { DeviceFolder.of(deviceID).appendingPathComponent("certificates.json") }

        /// Whether a certificate is taken, decided and kept under one lock, so two first requests at once can't each
        /// keep their own: the second is judged against what the first kept. It fails closed: a store that's there
        /// but can't be read, or a first certificate that can't be saved, takes nothing.
        func admit(_ fingerprint: String, port: Int) -> Refusal? {
            Self.lock.lock(); defer { Self.lock.unlock() }
            var pins: [String: String] = [:]
            if FileManager.default.fileExists(atPath: file.path) {
                guard let data = try? Data(contentsOf: file), let read = try? JSONDecoder().decode([String: String].self, from: data) else {
                    return .unsaved
                }
                pins = read
            }
            switch judge(fingerprint, kept: pins[String(port)], keeping: true) {
            case .trust: return nil
            case .refuse: return .changed
            case .keep:
                pins[String(port)] = fingerprint
                do { try JSONEncoder().encode(pins).write(to: file, options: .atomic) } catch { return .unsaved }
                return nil
            }
        }

        /// The certificate kept for a port, for tests and the record.
        func kept(port: Int) -> String? {
            Self.lock.lock(); defer { Self.lock.unlock() }
            return (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }?[String(port)]
        }
    }
}

// MARK: - Approvals

/// What the person approved on each device: the exact text of a command template or a tool, so Play doesn't ask each
/// time and a changed template asks again. Kept in Lamp's folder.
enum DeviceApprovals {
    private static var file: URL { DeviceFolder.root.appendingPathComponent("approvals.json") }
    private static let lock = NSLock()

    /// What's approved, as one string per kind of thing: the command template for SSH, or the program, checksum and
    /// arguments of a tool.
    static func subject(of action: IntegrationAction) -> String? {
        if let ssh = action.ssh { return "ssh \(ssh.user)@:\(ssh.port ?? 22) \(ssh.command)" }
        if let tool = action.tool {
            let program = tool.name.map { "listed \($0)" } ?? "download \(tool.download ?? "") \(tool.sha256 ?? "")"
            return "tool \(program) \((tool.arguments ?? []).joined(separator: " "))"
        }
        return nil
    }

    private static func digest(_ subject: String) -> String {
        SHA256.hash(data: Data(subject.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func all() -> [String: [String]] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
    }

    static func isApproved(_ subject: String, on deviceID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return all()[DeviceFields.owner(deviceID)]?.contains(digest(subject)) ?? false
    }

    static func approve(_ subject: String, on deviceID: String) {
        lock.lock(); defer { lock.unlock() }
        var approvals = all()
        let owner = DeviceFields.owner(deviceID)
        if !(approvals[owner] ?? []).contains(digest(subject)) { approvals[owner, default: []].append(digest(subject)) }
        try? FileManager.default.createDirectory(at: DeviceFolder.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? JSONEncoder().encode(approvals).write(to: file, options: .atomic)
    }

    /// Takes back everything approved on a device.
    static func forget(_ deviceID: String) {
        lock.lock(); defer { lock.unlock() }
        var approvals = all()
        approvals[DeviceFields.owner(deviceID)] = nil
        try? JSONEncoder().encode(approvals).write(to: file, options: .atomic)
    }
}

// MARK: - ssh

enum DeviceSSH {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Lamp's own key for devices, made the first time it's needed. Its public half is what a step shows as {sshKey}.
    static var key: URL { DeviceFolder.root.appendingPathComponent("lamp_ed25519") }

    static func ensureKey() async throws -> URL {
        if FileManager.default.fileExists(atPath: key.path) { return key }
        try? FileManager.default.createDirectory(at: DeviceFolder.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let result = await Subprocess.run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-C", "Lamp", "-f", key.path])
        guard result.ok else { throw Failure(message: "Lamp couldn't make its key for devices.") }
        return key
    }

    static var publicKey: String? {
        (try? String(contentsOf: key.appendingPathExtension("pub"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The arguments for one command on a device. Only its address (private), its host key pinned in a file of that
    /// device's in Lamp's folder the first time, no config of the person's, no agent, no forwarding of any kind, and
    /// the device's own key or Lamp's. The command is already filled and quoted (`Placeholders.fill(_:_:in: .command)`).
    static func arguments(address: String, port: Int, user: String, command: String, identity: URL, knownHosts: URL) throws -> [String] {
        guard DeviceAddress.isPrivate(address) else { throw DeviceAddress.NotOnNetwork(address: address) }
        guard IntegrationCheck.isPort(port) else { throw Failure(message: "\(port) isn't a port.") }
        guard user.range(of: #"^[a-z_][a-z0-9_-]{0,31}$"#, options: .regularExpression) != nil else { throw Failure(message: "\(user) isn't a user name.") }
        guard !command.contains(where: { $0.isNewline }) else { throw Failure(message: "A command is one line.") }
        return [
            "-F", "/dev/null",
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=\(knownHosts.path)",
            "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "CheckHostIP=no",
            "-o", "IdentitiesOnly=yes",
            "-o", "IdentityAgent=none",
            "-o", "ForwardAgent=no",
            "-o", "ForwardX11=no",
            "-o", "ClearAllForwardings=yes",
            "-o", "PermitLocalCommand=no",
            "-o", "ProxyCommand=none",
            "-o", "ProxyJump=none",
            "-o", "Tunnel=no",
            "-o", "ControlMaster=no",
            "-o", "ControlPath=none",
            "-o", "UpdateHostKeys=no",
            "-o", "ConnectTimeout=10",
            "-o", "HostKeyAlias=device",
            "-i", identity.path,
            "-p", String(port),
            "-l", user,
            "--", address, command,
        ]
    }

    /// Runs one approved command on the device and returns what it printed.
    static func run(_ ssh: IntegrationAction.SSH, address: String, deviceID: String, values: [String: String]) async throws -> String {
        let command = try Placeholders.fill(ssh.command, values, in: .command)
        let own = DeviceFolder.deviceKey(deviceID)
        let identity = FileManager.default.fileExists(atPath: own.path) ? own : try await ensureKey()
        let arguments = try arguments(address: address, port: ssh.port ?? 22, user: ssh.user, command: command, identity: identity,
                                      knownHosts: DeviceFolder.of(deviceID).appendingPathComponent("known_hosts"))
        let result = await Subprocess.run("/usr/bin/ssh", arguments, mergeErrors: true, timeout: 120)
        if result.output.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") || result.output.contains("Host key verification failed") {
            throw Failure(message: "This device isn't the one Lamp set up at that address: its key has changed. If you reset it, set it up again.")
        }
        guard result.ok else { throw Failure(message: "The command didn't work on the device:\n\(result.output.suffix(600))") }
        return result.output
    }
}

// MARK: - tool

enum DeviceTools {
    /// A tool Lamp ships and runs as itself: the program by its full path, its arguments as Lamp's list gives them, and
    /// what goes to its standard input (never a secret in its arguments, which any process can list).
    struct Listed {
        let program: String
        let arguments: [String]
        var input: String?
        /// The fields an integration must ask for to use it.
        var fields: [String] = []
        /// What it does, for the approval card's place in the step.
        let explanation: String
    }

    /// Lamp's list. Only these run unconfined, and only as written here.
    static let listed: [String: Listed] = [
        // LG's developer key comes encrypted with the passphrase the TV shows; Lamp keeps it unlocked in its folder.
        "unlock-device-key": Listed(program: "/usr/bin/openssl",
                                    arguments: ["pkey", "-in", "{deviceKey}", "-out", "{deviceKey}", "-passin", "stdin"],
                                    input: "{field:passphrase}", fields: ["passphrase"],
                                    explanation: "Unlocks the key the device gave this Mac, with the passphrase it showed."),
    ]

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Runs a tool from an integration: a listed one as Lamp, anything else downloaded, checked and confined.
    static func run(_ tool: IntegrationAction.Tool, deviceID: String, values: [String: String]) async throws -> String {
        var values = values
        values["deviceKey"] = DeviceFolder.deviceKey(deviceID).path
        if let name = tool.name {
            guard let listed = listed[name] else { throw Failure(message: "\(name) isn't one of Lamp's tools.") }
            let arguments = try listed.arguments.map { try fillArgument($0, values) }
            let input = try listed.input.map { Data(try Placeholders.fill($0, values, in: .argument).utf8) }
            let result = await Subprocess.run(listed.program, arguments, mergeErrors: true, timeout: 120, input: input)
            guard result.ok else { throw Failure(message: "\(name) didn't work:\n\(result.output.suffix(600))") }
            return result.output
        }
        guard let download = tool.download, let sha256 = tool.sha256 else { throw Failure(message: "The tool names no program.") }
        let program = try await fetch(download, sha256: sha256)
        let folder = program.deletingLastPathComponent()
        let arguments = try (tool.arguments ?? []).map { try fillArgument($0, values) }
        let profile = folder.appendingPathComponent("sandbox.sb")
        try confinement(folder: folder, reads: values["package"].map { [$0] } ?? []).write(to: profile, atomically: true, encoding: .utf8)
        let result = await Subprocess.run(Sandbox.executable, ["-f", profile.path, program.path] + arguments, cwd: folder,
                                          env: ["HOME": folder.path, "TMPDIR": folder.appendingPathComponent("tmp").path],
                                          mergeErrors: true, timeout: 300)
        guard result.ok else { throw Failure(message: "The tool didn't work:\n\(result.output.suffix(600))") }
        return result.output
    }

    /// An argument for a program: Lamp's values as they are (no shell reads them), checked like any other.
    private static func fillArgument(_ template: String, _ values: [String: String]) throws -> String {
        // The device key's path is Lamp's own, with the spaces of "Application Support".
        if template == "{deviceKey}" { return values["deviceKey"] ?? "" }
        return try Placeholders.fill(template, values, in: .argument)
    }

    /// Downloads a program once into a folder named by its checksum, and checks it. A file whose checksum differs is
    /// deleted and refused.
    static func fetch(_ address: String, sha256: String) async throws -> URL {
        guard IntegrationCheck.isWebPage(address), let url = URL(string: address), sha256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw Failure(message: "The tool's download isn't an https address with its checksum.")
        }
        let folder = DeviceFolder.root.appendingPathComponent("Tools").appendingPathComponent(sha256)
        let program = folder.appendingPathComponent(url.lastPathComponent.isEmpty ? "tool" : url.lastPathComponent)
        if let data = try? Data(contentsOf: program), digest(data) == sha256 { return program }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("tmp"), withIntermediateDirectories: true)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure(message: "The tool couldn't be downloaded.") }
        guard digest(data) == sha256 else { throw Failure(message: "The downloaded tool isn't the one the integration names: its checksum differs.") }
        try data.write(to: program, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        return program
    }

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// The sandbox a downloaded tool runs in: its own folder to read and write, the system to read and run, the
    /// network, and nothing of Lamp's or the person's.
    static func confinement(folder: URL, reads: [String]) -> String {
        func quoted(_ path: String) -> String { "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        let own = quoted(folder.resolvingSymlinksInPath().path)
        return """
        (version 1)
        (deny default)
        (allow process-fork)
        (allow process-exec (subpath \(own)) (subpath "/usr/bin") (subpath "/bin") (subpath "/usr/libexec") (subpath "/System"))
        (allow file-read* (subpath \(own)) (subpath "/System") (subpath "/usr") (subpath "/bin") (subpath "/Library/Apple")
               (subpath "/private/var/db/dyld") (subpath "/private/etc") (subpath "/private/var/db/timezone")
               (literal "/dev/null") (literal "/dev/urandom") (literal "/dev/random") (literal "/dev/zero") (literal "/dev/tty")
               (literal "/") (literal "/private") (literal "/private/var") \(reads.map { "(literal \(quoted($0)))" }.joined(separator: " ")))
        (allow file-read-metadata)
        (allow file-write* (subpath \(own)) (literal "/dev/null") (literal "/dev/tty"))
        (allow network*)
        (allow sysctl-read)
        (allow mach-lookup (global-name "com.apple.dnssd.service") (global-name "com.apple.SystemConfiguration.DNSConfiguration")
               (global-name "com.apple.SystemConfiguration.configd") (global-name "com.apple.trustd") (global-name "com.apple.trustd.agent"))
        (allow ipc-posix-shm-read-data (ipc-posix-name "apple.shm.notification_center"))
        (allow signal (target self))
        (allow process-info* (target self))

        """
    }
}
