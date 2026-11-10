import Compression
import CryptoKit
import Foundation

/// Windows app packages (MSIX), made and signed by Lamp itself, for a device whose integration declares its apps are
/// wrapped this way (`Integration.AppKind.Declared.wrap`, "msix"): an Xbox in Developer Mode takes them through its
/// Device Portal. The package step leaves a plain zip of the app's files, which is read here. The package is made of
/// them by lamp's own package maker (`cli/msix.mjs`, which Lamp's app has do it: `LampCLI`): it writes the manifest (so
/// the package's identity and publisher are Lamp's), the logos, the block map and content types, lays it out as Zip64
/// (Windows opens nothing else) and signs it with a certificate of Lamp's own, which Developer Mode accepts once it's
/// installed beside the package. The key and certificate are in Lamp's folder, which the agent's sandbox closes. A web
/// app's package is neutral and starts at its page; a native game's (`GameKit`) is for x64 and starts its App.exe.
enum MSIX {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The package's identity, from which Windows names it: what the bridge launches it by.
    struct Identity: Codable, Equatable {
        var name: String
        var publisher: String
        var version: String
        /// "x64" for a native game; nil (neutral) for a web app, as identities saved before games were.
        var architecture: String?
        var fullName: String { "\(name)_\(version)_\(architecture ?? "neutral")__\(MSIX.publisherID(publisher))" }
        var familyName: String { "\(name)_\(MSIX.publisherID(publisher))" }
        var appUserModelID: String { familyName + "!App" }
    }

    /// Windows' short id for a publisher: the first 8 bytes of SHA-256 of its name in UTF-16LE, in Crockford's base 32.
    static func publisherID(_ publisher: String) -> String {
        let digest = Array(SHA256.hash(data: Data(publisher.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })))
        let bits = digest.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let alphabet = Array("0123456789abcdefghjkmnpqrstvwxyz")
        // 64 bits as 13 digits of 5 bits: the last digit takes the lowest 4 bits shifted up one.
        return String((0..<13).map { index -> Character in
            let shift = 64 - 5 * (index + 1)
            let value = shift >= 0 ? (bits >> UInt64(shift)) & 31 : (bits << UInt64(-shift)) & 31
            return alphabet[Int(value)]
        })
    }

    // MARK: Making a package

    /// What a package's app starts: a web app's page in the system's EdgeHTML host, a native program, or Lamp's own
    /// WebView2 host (`WebHost`), which shows the app's pages from its Web folder.
    enum Start: Equatable {
        case page(String)
        case program(String)
        case webHost
        var path: String {
            switch self {
            case .page(let path), .program(let path): path
            case .webHost: WebHost.program
            }
        }
        /// As lamp's package maker is given it.
        var given: Any {
            switch self {
            case .page(let path): ["page": path]
            case .program(let path): ["program": path]
            case .webHost: "webHost"
            }
        }
    }

    /// Where lamp's key and its own certificate for packages are kept, made the first time a package is. Settable so
    /// a test signs with a key of its own, never Lamp's.
    nonisolated(unsafe) static var signerFolder = DeviceFolder.root.appendingPathComponent("MSIX")

    /// Makes a signed package of the app's files (`payload`, read from the package step's zip) at `package`, started at
    /// `entry`, with the certificate a device installs beside it at `certificate`. It's named for the app (`slug`) and
    /// is a newer version than `previous`, so each build replaces the last (Windows refuses a changed package under a
    /// version it has); the identity it was given comes back. The files are laid out in `work`, a folder of Lamp's own
    /// that's emptied before and after, for lamp's package maker to read: each must be a plain path inside it.
    static func make(payload: [(path: String, data: Data)], displayName: String, slug: String, after previous: String?,
                     architecture: String?, entry: Start, icon: Data?, in work: URL, package: URL, certificate: URL) async throws -> Identity {
        let fm = FileManager.default
        try? fm.removeItem(at: work)
        defer { try? fm.removeItem(at: work) }
        let tree = work.appendingPathComponent("payload")
        try fm.createDirectory(at: tree, withIntermediateDirectories: true)
        for (path, data) in payload {
            guard IntegrationCheck.isAppPath(path) else { throw Failure(message: "The package holds a file Lamp can't send: \(path).") }
            let url = tree.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        var given: [String: Any] = ["payload": tree.path, "out": package.path, "certificate": certificate.path, "displayName": displayName,
                                    "slug": slug, "entry": entry.given, "signer": signerFolder.path]
        if let previous { given["after"] = previous }
        if let architecture { given["architecture"] = architecture }
        if let icon {
            let picture = work.appendingPathComponent("icon.png")
            try icon.write(to: picture)
            given["icon"] = picture.path
        }
        let done: [String: Any]
        do {
            done = try await LampCLI.call("msix", given)
        } catch let error as LampCLI.Failure {
            throw Failure(message: error.message)
        }
        guard let said = done["identity"], JSONSerialization.isValidJSONObject(said),
              let identity = try? JSONDecoder().decode(Identity.self, from: JSONSerialization.data(withJSONObject: said)) else {
            throw Failure(message: "Lamp couldn't read the package it made.")
        }
        return identity
    }

    // MARK: Reading the package step's zip

    /// The files in a zip the package step made: stored or deflated, plain paths only (no link, nothing above the
    /// zip's top, no folder entries), and a total Lamp is willing to hold.
    static func files(inZip zip: Data) throws -> [(path: String, data: Data)] {
        let bytes = [UInt8](zip)
        func u16(_ at: Int) -> Int { at >= 0 && at + 1 < bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 : 0 }
        let unreadable = Failure(message: "The package step's zip can't be read.")
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        guard bytes.count >= 22, let end = stride(from: bytes.count - 22, through: max(0, bytes.count - 22 - 65535), by: -1)
            .first(where: { u32($0) == 0x06054b50 }) else { throw Failure(message: "The package step's output isn't a zip.") }
        var at = u32(end + 16)
        var files: [(String, Data)] = []
        var total = 0
        for _ in 0..<u16(end + 10) {
            // The fixed header and each part after it must be inside the zip before anything is read from them.
            guard at >= 0, at + 46 <= bytes.count, u32(at) == 0x02014b50 else { throw unreadable }
            let method = u16(at + 10), compressed = u32(at + 20), size = u32(at + 24)
            let nameLength = u16(at + 28), extraLength = u16(at + 30), commentLength = u16(at + 32)
            let attributes = u32(at + 38), offset = u32(at + 42)
            guard at + 46 + nameLength + extraLength + commentLength <= bytes.count else { throw unreadable }
            let name = String(decoding: bytes[(at + 46)..<(at + 46 + nameLength)], as: UTF8.self)
            at += 46 + nameLength + extraLength + commentLength
            if name.hasSuffix("/") { continue }
            let mode = attributes >> 16
            guard mode & 0o170000 != 0o120000 else { throw Failure(message: "The package step's zip holds a link (\(name)), which Lamp doesn't package.") }
            let parts = name.split(separator: "/")
            guard !name.hasPrefix("/"), !name.contains("\\"), !parts.contains(".."), !parts.isEmpty else {
                throw Failure(message: "The package step's zip holds \(name), which isn't a plain path.")
            }
            guard offset + 30 <= bytes.count, u32(offset) == 0x04034b50 else { throw unreadable }
            let dataStart = offset + 30 + u16(offset + 26) + u16(offset + 28)
            guard dataStart <= bytes.count, compressed <= bytes.count - dataStart else { throw Failure(message: "The package step's zip is cut short.") }
            total += size
            guard total <= DeviceApps.packageLimit else { throw Failure(message: "The app is bigger than Lamp sends to a device (\(DeviceApps.packageLimit >> 30) GB).") }
            let raw = Data(bytes[dataStart..<(dataStart + compressed)])
            switch method {
            case 0: files.append((name, raw))
            case 8: files.append((name, try inflate(raw, size: size)))
            default: throw Failure(message: "The package step's zip uses a kind of compression Lamp doesn't read.")
            }
        }
        return files
    }

    private static func inflate(_ data: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, size,
                                          source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw Failure(message: "A file in the package step's zip couldn't be read.") }
        return out
    }
}
