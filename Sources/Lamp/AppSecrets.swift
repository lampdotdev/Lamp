import Foundation
import Security
import Darwin

/// What a Mac app keeps secret (a service's sign-in, a token), kept by Lamp for it: `LampSecrets` in the app asks
/// for it at `/app/secrets`. Lamp signs apps with its own certificate, which has no Apple team, so macOS ties a
/// Keychain item an app makes to that one build and asks for the login password after every rebuild. Lamp is the
/// same program from one build of an app to the next, so it keeps them, the way it keeps its own keys: in the
/// Keychain when Lamp is signed for a team (`KeyStore.usesKeychain`), else in a file only this user can read.
/// Each app's are its own (by its instance, which a new app under the same name never inherits — the folder
/// name would be reused), and they go when the app is deleted, so an app made later under the same name starts
/// disconnected. What's left when a folder is deleted outside Lamp stays under an instance no app has again.
enum AppSecrets {
    enum Place {
        case keychain(service: String)
        case file(URL)
    }

    static var place: Place {
        KeyStore.usesKeychain ? .keychain(service: Edition.bundleID + ".app-secrets")
            : .file(Edition.supportFolder.appendingPathComponent("app-secrets.json"))
    }

    /// The names an app may keep things under: short, and nothing that could reach another app's.
    static func isName(_ name: String) -> Bool {
        (1...64).contains(name.count) && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }

    /// How many names one app may keep things under: a sign-in or token for each service it connects to.
    static let limit = 32

    private static let lock = NSLock()

    static func read(_ name: String, app: String, in place: Place = place) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        switch place {
        case .keychain(let service):
            var query = Keychain.query(service, account: app + "/" + name)
            query[kSecReturnData as String] = true
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
            return item as? Data
        case .file(let url):
            return File.read(url)?[app]?[name].flatMap { Data(base64Encoded: $0) }
        }
    }

    static func save(_ data: Data, as name: String, app: String, in place: Place = place) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch place {
        case .keychain(let service):
            let query = Keychain.query(service, account: app + "/" + name)
            var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                guard Keychain.count(service, app: app) < limit else { return false }
                var add = query
                add[kSecValueData as String] = data
                add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(add as CFDictionary, nil)
            }
            return status == errSecSuccess
        case .file(let url):
            // A file that's there but can't be read isn't an empty one: writing over it would lose every app's.
            if FileManager.default.fileExists(atPath: url.path), File.read(url) == nil { return false }
            var all = File.read(url) ?? [:]
            guard all[app]?[name] != nil || (all[app]?.count ?? 0) < limit else { return false }
            all[app, default: [:]][name] = data.base64EncodedString()
            return File.write(all, to: url)
        }
    }

    /// False when it's still kept (the Keychain or the file refused).
    @discardableResult
    static func delete(_ name: String, app: String, in place: Place = place) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch place {
        case .keychain(let service):
            let status = SecItemDelete(Keychain.query(service, account: app + "/" + name) as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        case .file(let url):
            guard FileManager.default.fileExists(atPath: url.path) else { return true }
            // A file that's there but can't be read may still hold it: that isn't forgotten.
            guard var all = File.read(url) else { return false }
            guard all[app]?[name] != nil else { return true }
            all[app]?[name] = nil
            if all[app]?.isEmpty == true { all[app] = nil }
            return File.write(all, to: url)
        }
    }

    /// Everything an app kept, when the app is deleted.
    static func forget(app: String, in place: Place = place) {
        lock.lock()
        defer { lock.unlock() }
        switch place {
        case .keychain(let service):
            var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
            var items: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess else { return }
            query = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
            for item in items as? [[String: Any]] ?? [] {
                guard let account = item[kSecAttrAccount as String] as? String, account.hasPrefix(app + "/") else { continue }
                var one = query
                one[kSecAttrAccount as String] = account
                SecItemDelete(one as CFDictionary)
            }
        case .file(let url):
            guard var all = File.read(url), all[app] != nil else { return }
            all[app] = nil
            File.write(all, to: url)
        }
    }

    private enum Keychain {
        static func query(_ service: String, account: String) -> [String: Any] {
            [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        }

        static func count(_ service: String, app: String) -> Int {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
            var items: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess else { return 0 }
            return (items as? [[String: Any]] ?? []).filter { ($0[kSecAttrAccount as String] as? String)?.hasPrefix(app + "/") == true }.count
        }
    }

    /// `{app: {name: base64}}`, readable and writable only by this user.
    private enum File {
        static func read(_ url: URL) -> [String: [String: String]]? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode([String: [String: String]].self, from: data)
        }

        @discardableResult
        static func write(_ all: [String: [String: String]], to url: URL) -> Bool {
            guard let data = try? JSONEncoder().encode(all) else { return false }
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Created readable only by this user before anything is written, then moved over the old one: never
            // readable by others, and never half written.
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
            let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard fd >= 0 else { return false }
            let written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            close(fd)
            guard written == data.count, rename(temporary.path, url.path) == 0 else { try? fm.removeItem(at: temporary); return false }
            return true
        }
    }
}

/// Which program is on the other end of a connection to one of Lamp's ports on this Mac, and whether it's the app
/// Lamp built. An app's token is in its folder, which the agent building it can read, so the token alone says
/// only that the asker could read that folder; the app itself is told apart by its code.
enum PeerProcess {
    /// The process whose TCP connection goes out from `port` to Lamp's `lampPort` on this Mac (both in host order),
    /// among those whose program's path passes `path`.
    static func find(connectedFrom port: UInt16, to lampPort: UInt16, path: (String) -> Bool) -> pid_t? {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let found = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        for pid in pids.prefix(Int(max(found, 0))) where pid > 0 {
            var buffer = [CChar](repeating: 0, count: 4096)
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0, path(String(cString: buffer)) else { continue }
            let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard size > 0 else { continue }
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.size)
            let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, size)
            for fd in fds.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.size) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
                var info = socket_fdinfo()
                guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size)) > 0,
                      info.psi.soi_kind == SOCKINFO_TCP else { continue }
                // The kernel keeps both ports in network order.
                let tcp = info.psi.soi_proto.pri_tcp.tcpsi_ini
                if in_port_t(truncatingIfNeeded: tcp.insi_lport) == port.bigEndian,
                   in_port_t(truncatingIfNeeded: tcp.insi_fport) == lampPort.bigEndian {
                    return pid
                }
            }
        }
        return nil
    }

    /// Whether the connection from `port` comes from the app installed at `app`: a process running that app's own
    /// program, valid by the app's designated requirement as it is on disk. Where Lamp installs apps is closed to
    /// the agent's commands, and the requirement names the certificate Lamp (or the person's team) signed with,
    /// so a copy of the program elsewhere, a re-signed one, or `curl` with the app's token is not the app.
    static func isApp(at app: URL, connectedFrom port: UInt16, to lampPort: UInt16) -> Bool {
        // The kernel gives a program's real path; Foundation's own resolving drops "/private" from it, so `realpath`.
        guard let real = realpath(app.path, nil) else { return false }
        let bundle = String(cString: real) + "/Contents/MacOS/"
        free(real)
        guard let pid = find(connectedFrom: port, to: lampPort, path: { $0.hasPrefix(bundle) }) else { return false }
        var onDisk: SecStaticCode?
        var requirement: SecRequirement?
        var running: SecCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &onDisk) == errSecSuccess, let onDisk,
              SecCodeCopyDesignatedRequirement(onDisk, [], &requirement) == errSecSuccess, let requirement,
              SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &running) == errSecSuccess,
              let running else { return false }
        return SecCodeCheckValidity(running, [], requirement) == errSecSuccess
    }
}
