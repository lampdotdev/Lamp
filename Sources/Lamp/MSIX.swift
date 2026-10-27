import AppKit
import Compression
import CryptoKit
import Foundation
import Security

/// Windows app packages (MSIX), made and signed by Lamp itself, for a device whose integration declares its apps are
/// wrapped this way (`Integration.AppKind.Declared.wrap`, "msix"): an Xbox in Developer Mode takes them through its
/// Device Portal. The package step leaves a plain zip of the app's files; Lamp writes the manifest (so the package's
/// identity and publisher are Lamp's), the logos, the block map and content types, lays it out as Zip64 (Windows opens
/// nothing else) and signs it with a certificate of Lamp's own, which Developer Mode accepts once it's installed
/// beside the package. The key and certificate are in Lamp's folder, which the agent's sandbox closes. A web app's
/// package is neutral and starts at its page; a native game's (`GameKit`) is for x64 and starts its App.exe.
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

    /// Lamp's publisher name; a package's manifest must name exactly its certificate's subject.
    static let publisher = "CN=Lamp"

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

    /// An identity name for an app: Windows takes letters, digits, dots and dashes, 3 to 50 of them.
    static func identityName(for slug: String) -> String {
        let plain = slug.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        return "Lamp." + String((plain.isEmpty ? "app" : plain).prefix(40))
    }

    /// A version newer than `previous`, so each build replaces the last (Windows refuses a changed package under a
    /// version it has): minutes since 2026 in two of the four parts, or the previous one's next revision when two builds
    /// fall in the same minute.
    static func version(at date: Date = Date(), after previous: String? = nil) -> String {
        let minutes = max(0, Int(date.timeIntervalSince1970 - 1_767_225_600) / 60)
        let byTime = [1, minutes >> 16, minutes & 0xFFFF, 0]
        var next = previous?.split(separator: ".").compactMap { Int($0) } ?? []
        guard next.count == 4, !next.lexicographicallyPrecedes(byTime) else { return byTime.map(String.init).joined(separator: ".") }
        for index in stride(from: 3, through: 0, by: -1) {
            if next[index] < 0xFFFF { next[index] += 1; break }
            next[index] = 0
        }
        return next.map(String.init).joined(separator: ".")
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
    }

    /// A signed package of the app's files (`payload`, read from the package step's zip), started at `entry`.
    static func package(payload: [(path: String, data: Data)], displayName: String, identity: Identity, entry: Start,
                        icon: NSImage?, signer: Signer? = nil) throws -> Data {
        guard payload.contains(where: { $0.path == entry.path }) else {
            throw Failure(message: "The package has no \(entry.path) for the app to start at.")
        }
        var files = payload.filter { !reserved.contains($0.path.lowercased()) && !$0.path.lowercased().hasPrefix("lamplogos/") }
        for (name, width, height) in logos {
            files.append((path: "LampLogos/\(name).png", data: logo(icon, width: width, height: height)))
        }
        files.append((path: "AppxManifest.xml", data: Data(manifest(identity: identity, displayName: displayName, entry: entry).utf8)))
        return try assemble(files, signer: try signer ?? Signer.lamp())
    }

    /// Lamp's own certificate, as the device installs it beside a package (DER).
    static func certificate() throws -> Data { try Signer.lamp().certificate }

    private static let reserved: Set<String> = ["appxmanifest.xml", "appxblockmap.xml", "[content_types].xml", "appxsignature.p7x"]

    private static let logos: [(String, Int, Int)] = [("StoreLogo", 50, 50), ("Square150x150Logo", 150, 150), ("Square44x44Logo", 44, 44),
                                                      ("Wide310x150Logo", 310, 150), ("SplashScreen", 620, 300)]

    static func manifest(identity: Identity, displayName: String, entry: Start) -> String {
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let name = escaped(String(displayName.prefix(80)))
        // A web app runs in the system's web host and may reach the network; a game is its own program, which asks
        // for nothing, on the Windows that first ran apps like it on the Xbox.
        let application: String, minimum: String, capabilities: String
        switch entry {
        case .page(let start):
            application = "StartPage=\"\(escaped(start))\""
            minimum = "10.0.10240.0"
            capabilities = "<Capabilities><Capability Name=\"internetClient\"/><Capability Name=\"privateNetworkClientServer\"/></Capabilities>"
        case .program(let program):
            application = "Executable=\"\(escaped(program.replacingOccurrences(of: "/", with: "\\")))\" EntryPoint=\"App.App\""
            minimum = "10.0.17763.0"
            capabilities = ""
        case .webHost:
            // WebView2's WinRT classes come from the copy of its core library in the package, which Windows finds
            // only by these registrations; the browser itself is the console's.
            application = "Executable=\"\(WebHost.program)\" EntryPoint=\"App.App\""
            minimum = "10.0.19041.0"
            let classes = WebHost.activatableClasses.map { "<ActivatableClass ActivatableClassId=\"\($0)\" ThreadingModel=\"both\"/>" }.joined()
            capabilities = "<Capabilities><Capability Name=\"internetClient\"/><Capability Name=\"privateNetworkClientServer\"/></Capabilities>"
                + "<Extensions><Extension Category=\"windows.activatableClass.inProcessServer\"><InProcessServer><Path>\(WebHost.library)</Path>\(classes)</InProcessServer></Extension></Extensions>"
        }
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10" xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10" IgnorableNamespaces="uap">
          <Identity Name="\(identity.name)" Publisher="\(escaped(identity.publisher))" Version="\(identity.version)" ProcessorArchitecture="\(identity.architecture ?? "neutral")"/>
          <Properties><DisplayName>\(name)</DisplayName><PublisherDisplayName>Lamp</PublisherDisplayName><Logo>LampLogos\\StoreLogo.png</Logo></Properties>
          <Dependencies><TargetDeviceFamily Name="Windows.Universal" MinVersion="\(minimum)" MaxVersionTested="10.0.22621.0"/></Dependencies>
          <Resources><Resource Language="en-us"/></Resources>
          <Applications>
            <Application Id="App" \(application)>
              <uap:VisualElements DisplayName="\(name)" Description="\(name)" BackgroundColor="#1b1b3a" Square150x150Logo="LampLogos\\Square150x150Logo.png" Square44x44Logo="LampLogos\\Square44x44Logo.png">
                <uap:DefaultTile Wide310x150Logo="LampLogos\\Wide310x150Logo.png"/>
                <uap:SplashScreen Image="LampLogos\\SplashScreen.png"/>
              </uap:VisualElements>
            </Application>
          </Applications>
          \(capabilities)
        </Package>

        """
    }

    /// The app's icon centered on its tile's color at a logo's size, or the color alone: the same picture a declared
    /// kind's icons are (`DeviceSupport.iconPNG`).
    private static func logo(_ icon: NSImage?, width: Int, height: Int) -> Data {
        DeviceSupport.iconPNG(icon, width: width, height: height)
    }

    // MARK: The container

    private struct Entry { let name: String; let data: Data }

    /// The files laid out as an MSIX: each stored (so the block map's hashes are of what's in the zip), the block map and
    /// content types after them, then the signature, then a Zip64 central directory.
    static func assemble(_ files: [(path: String, data: Data)], signer: Signer) throws -> Data {
        var entries = files.map { Entry(name: $0.path, data: $0.data) }
        entries.append(Entry(name: "AppxBlockMap.xml", data: blockMap(entries)))
        entries.append(Entry(name: "[Content_Types].xml", data: contentTypes(for: files.map(\.path))))
        // What's signed is the package without its signature: its records, its directory and the two files' contents.
        let unsigned = layout(entries)
        var blob = Data("APPX".utf8)
        blob += Data("AXPC".utf8) + Data(SHA256.hash(data: unsigned.records))
        blob += Data("AXCD".utf8) + Data(SHA256.hash(data: unsigned.directory))
        blob += Data("AXCT".utf8) + Data(SHA256.hash(data: entries[entries.count - 1].data))
        blob += Data("AXBM".utf8) + Data(SHA256.hash(data: entries[entries.count - 2].data))
        let signature = Data("PKCX".utf8) + (try signer.sign(appxDigest: blob))
        entries.append(Entry(name: "AppxSignature.p7x", data: signature))
        let signed = layout(entries)
        return signed.records + signed.directory
    }

    static func lfhSize(_ name: String) -> Int { 30 + name.utf8.count + 20 }

    /// Little-endian fields appended one after another.
    private struct Writer {
        var data = Data()
        mutating func u16(_ v: Int) { withUnsafeBytes(of: UInt16(truncatingIfNeeded: v).littleEndian) { data.append(contentsOf: $0) } }
        mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        mutating func u64(_ v: Int) { withUnsafeBytes(of: UInt64(v).littleEndian) { data.append(contentsOf: $0) } }
        mutating func bytes(_ d: Data) { data.append(d) }
    }

    /// Local records and the central directory (with its Zip64 end records), each Zip64 throughout.
    private static func layout(_ entries: [Entry]) -> (records: Data, directory: Data) {
        var records = Writer(), central = Writer()
        for entry in entries {
            let name = Data(entry.name.utf8), crc = crc32(entry.data), offset = records.data.count, size = entry.data.count
            // The signature is the one plain, deflated record, as Windows' own packager writes it: it opens nothing else.
            if entry.name == "AppxSignature.p7x", let deflated = deflate(entry.data) {
                records.u32(0x04034b50); records.u16(20); records.u16(0); records.u16(8); records.u16(0); records.u16(0x21)
                records.u32(crc); records.u32(UInt32(deflated.count)); records.u32(UInt32(size)); records.u16(name.count); records.u16(0)
                records.bytes(name); records.bytes(deflated)
                central.u32(0x02014b50); central.u16(45); central.u16(20); central.u16(0); central.u16(8); central.u16(0); central.u16(0x21)
                central.u32(crc); central.u32(UInt32(deflated.count)); central.u32(UInt32(size)); central.u16(name.count); central.u16(0)
                central.u16(0); central.u16(0); central.u16(0); central.u32(0); central.u32(UInt32(offset))
                central.bytes(name)
                continue
            }
            // Local header: Zip64, stored, sizes in the extra field.
            records.u32(0x04034b50); records.u16(45); records.u16(0); records.u16(0); records.u16(0); records.u16(0x21)
            records.u32(crc); records.u32(0xFFFFFFFF); records.u32(0xFFFFFFFF); records.u16(name.count); records.u16(20)
            records.bytes(name)
            records.u16(1); records.u16(16); records.u64(size); records.u64(size)
            records.bytes(entry.data)
            // Its central entry, with the offset in the extra field too.
            central.u32(0x02014b50); central.u16(45); central.u16(45); central.u16(0); central.u16(0); central.u16(0); central.u16(0x21)
            central.u32(crc); central.u32(0xFFFFFFFF); central.u32(0xFFFFFFFF); central.u16(name.count); central.u16(28)
            central.u16(0); central.u16(0); central.u16(0); central.u32(0); central.u32(0xFFFFFFFF)
            central.bytes(name)
            central.u16(1); central.u16(24); central.u64(size); central.u64(size); central.u64(offset)
        }
        var end = Writer()
        end.u32(0x06064b50); end.u64(44); end.u16(45); end.u16(45); end.u32(0); end.u32(0)
        end.u64(entries.count); end.u64(entries.count); end.u64(central.data.count); end.u64(records.data.count)
        end.u32(0x07064b50); end.u32(0); end.u64(records.data.count + central.data.count); end.u32(1)
        // The disk numbers are written as zeros: the signature is checked over them as zeros.
        end.u32(0x06054b50); end.u16(0); end.u16(0); end.u16(0xFFFF); end.u16(0xFFFF); end.u32(0xFFFFFFFF); end.u32(0xFFFFFFFF); end.u16(0)
        return (records.data, central.data + end.data)
    }

    private static func blockMap(_ entries: [Entry]) -> Data {
        let files = entries.map { entry -> String in
            let blocks = stride(from: 0, to: entry.data.count, by: 65536).map { start -> String in
                let block = entry.data[entry.data.startIndex + start ..< entry.data.startIndex + min(start + 65536, entry.data.count)]
                return "<Block Hash=\"\(Data(SHA256.hash(data: block)).base64EncodedString())\"/>"
            }.joined()
            let name = entry.name.replacingOccurrences(of: "/", with: "\\").replacingOccurrences(of: "&", with: "&amp;")
            return "<File Name=\"\(name)\" Size=\"\(entry.data.count)\" LfhSize=\"\(lfhSize(entry.name))\">\(blocks)</File>"
        }.joined()
        return Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?><BlockMap xmlns=\"http://schemas.microsoft.com/appx/2010/blockmap\" "
                     + "HashMethod=\"http://www.w3.org/2001/04/xmlenc#sha256\">" + files + "</BlockMap>").utf8)
    }

    /// Every part needs a content type: by its extension, or, for a file with none Windows can take (a LICENSE), one of
    /// its own. Windows refuses a package with an untyped part, saying its block map is invalid.
    static func contentTypes(for paths: [String]) -> Data {
        var extensions: Set<String> = [], untyped: [String] = []
        for path in paths where path != "AppxManifest.xml" {
            let parts = (path.split(separator: "/").last.map(String.init) ?? "").split(separator: ".", omittingEmptySubsequences: false)
            if parts.count > 1, let last = parts.last, !last.isEmpty, last.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
                extensions.insert(last.lowercased())
            } else {
                untyped.append(path)
            }
        }
        return contentTypes(extensions, untyped: untyped)
    }

    private static func contentTypes(_ extensions: Set<String>, untyped: [String]) -> Data {
        let known = ["exe": "application/x-msdownload", "dll": "application/x-msdownload", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "svg": "image/svg+xml",
                     "html": "text/html", "htm": "text/html", "js": "application/javascript", "css": "text/css", "json": "application/json",
                     "txt": "text/plain", "woff": "font/woff", "woff2": "font/woff2", "mp3": "audio/mpeg", "mp4": "video/mp4", "wav": "audio/wav"]
        let defaults = extensions.sorted().filter { $0.allSatisfy { $0.isLetter || $0.isNumber } }.map {
            "<Default Extension=\"\($0)\" ContentType=\"\(known[$0] ?? "application/octet-stream")\"/>"
        }.joined()
        let overrides = untyped.sorted().map { path -> String in
            let part = "/" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path).replacingOccurrences(of: "&", with: "&amp;")
            return "<Override PartName=\"\(part)\" ContentType=\"application/octet-stream\"/>"
        }.joined()
        return Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
                     + defaults + overrides
                     + "<Override PartName=\"/AppxManifest.xml\" ContentType=\"application/vnd.ms-appx.manifest+xml\"/>"
                     + "<Override PartName=\"/AppxBlockMap.xml\" ContentType=\"application/vnd.ms-appx.blockmap+xml\"/>"
                     + "<Override PartName=\"/AppxSignature.p7x\" ContentType=\"application/vnd.ms-appx.signature\"/></Types>").utf8)
    }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in data { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
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
            guard total <= DeviceHTTP.limit else { throw Failure(message: "The app is bigger than Lamp sends to a device.") }
            let raw = Data(bytes[dataStart..<(dataStart + compressed)])
            switch method {
            case 0: files.append((name, raw))
            case 8: files.append((name, try inflate(raw, size: size)))
            default: throw Failure(message: "The package step's zip uses a kind of compression Lamp doesn't read.")
            }
        }
        return files
    }

    /// Raw deflate, as a zip stores it.
    private static func deflate(_ data: Data) -> Data? {
        var out = Data(count: data.count + 1024)
        let written = out.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_encode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, destination.count,
                                          source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written > 0 ? out.prefix(written) : nil
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

// MARK: - Signing

extension MSIX {
    /// Lamp's key and its own certificate for packages, made the first time and kept in Lamp's folder.
    struct Signer {
        let key: SecKey
        let certificate: Data
        let issuer: Data
        let serial: Data

        static var folder: URL { DeviceFolder.root.appendingPathComponent("MSIX") }

        static func lamp() throws -> Signer {
            let keyURL = folder.appendingPathComponent("key.der"), certificateURL = folder.appendingPathComponent("certificate.der")
            let attributes = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate] as CFDictionary
            if let keyData = try? Data(contentsOf: keyURL), let key = SecKeyCreateWithData(keyData as CFData, attributes, nil),
               let certificate = try? Data(contentsOf: certificateURL), let made = try? from(certificate: certificate, key: key) {
                return made
            }
            var error: Unmanaged<CFError>?
            guard let key = SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, &error),
                  let keyData = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
                throw Failure(message: "Lamp couldn't make its key for app packages.")
            }
            let certificate = try selfSigned(key: key)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try keyData.write(to: keyURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
            try certificate.write(to: certificateURL, options: .atomic)
            return try from(certificate: certificate, key: key)
        }

        /// A signer with a key of its own that's kept nowhere: for trying the format without touching Lamp's folder.
        static func throwaway() throws -> Signer {
            var error: Unmanaged<CFError>?
            guard let key = SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, &error) else {
                throw Failure(message: "Lamp couldn't make a key.")
            }
            return try from(certificate: try selfSigned(key: key), key: key)
        }

        /// The issuer and serial a signature names, read back out of the certificate Lamp made.
        private static func from(certificate: Data, key: SecKey) throws -> Signer {
            guard let (serial, issuer) = issuerAndSerial(certificate) else { throw Failure(message: "Lamp's package certificate can't be read.") }
            return Signer(key: key, certificate: certificate, issuer: issuer, serial: serial)
        }

        /// Signs the APPX digest blob as Authenticode does: the blob is the "digest" in an SpcIndirectDataContent,
        /// whose own SHA-256 (of its contents, without its outer header) is the signed message digest.
        func sign(appxDigest blob: Data) throws -> Data {
            let sipInfo = DER.sequence([integer(0x01010000), DER.tlv(0x04, Data(MSIX.appxSIP)), integer(0), integer(0), integer(0), integer(0), integer(0)])
            let indirect = DER.sequence([
                DER.sequence([oid("1.3.6.1.4.1.311.2.1.30"), sipInfo]),
                DER.sequence([DER.sequence([oid("2.16.840.1.101.3.4.2.1"), DER.null]), DER.tlv(0x04, blob)]),
            ])
            let indirectContents = contents(of: indirect)
            let attributes = [
                DER.sequence([oid("1.2.840.113549.1.9.3"), DER.set([oid("1.3.6.1.4.1.311.2.1.4")])]),
                DER.sequence([oid("1.2.840.113549.1.9.4"), DER.set([DER.tlv(0x04, Data(SHA256.hash(data: indirectContents)))])]),
                DER.sequence([oid("1.3.6.1.4.1.311.2.1.11"), DER.set([DER.sequence([oid("1.3.6.1.4.1.311.2.1.21")])])]),
                DER.sequence([oid("1.3.6.1.4.1.311.2.1.12"), DER.set([DER.sequence([])])]),
            ].sorted { $0.lexicographicallyPrecedes($1) }
            var error: Unmanaged<CFError>?
            guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, DER.set(attributes) as CFData, &error) as Data? else {
                throw Failure(message: "Lamp couldn't sign the app package.")
            }
            let sha256 = DER.sequence([oid("2.16.840.1.101.3.4.2.1"), DER.null])
            let signerInfo = DER.sequence([
                integer(1), DER.sequence([issuer, DER.tlv(0x02, serial)]), sha256,
                DER.tlv(0xA0, attributes.reduce(Data(), +)),
                DER.sequence([DER.oidRSA, DER.null]), DER.tlv(0x04, signature),
            ])
            let signedData = DER.sequence([
                integer(1), DER.set([sha256]),
                DER.sequence([oid("1.3.6.1.4.1.311.2.1.4"), DER.tlv(0xA0, indirect)]),
                DER.tlv(0xA0, certificate),
                DER.set([signerInfo]),
            ])
            return DER.sequence([oid("1.2.840.113549.1.7.2"), DER.tlv(0xA0, signedData)])
        }

        /// A certificate for Lamp's publisher name, signed by its own key, for code signing only.
        private static func selfSigned(key: SecKey) throws -> Data {
            var error: Unmanaged<CFError>?
            guard let publicKey = SecKeyCopyPublicKey(key), let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
                throw Failure(message: "Lamp couldn't read its key for app packages.")
            }
            let name = DER.sequence([DER.set([DER.sequence([DER.oidCommonName, DER.tlv(0x0C, Data("Lamp".utf8))])])])
            let spki = DER.sequence([DER.sequence([DER.oidRSA, DER.null]), DER.tlv(0x03, Data([0x00]) + pkcs1)])
            var serial = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
            serial[0] &= 0x7F
            serial[0] |= 0x01
            let now = Date().addingTimeInterval(-86_400)
            let validity = DER.sequence([time(now), time(now.addingTimeInterval(20 * 365 * 86_400))])
            let keyID = Data(Insecure.SHA1.hash(data: pkcs1))
            let extensions = DER.sequence([
                DER.sequence([oid("2.5.29.19"), DER.tlv(0x01, Data([0xFF])), DER.tlv(0x04, DER.sequence([]))]),
                DER.sequence([oid("2.5.29.15"), DER.tlv(0x01, Data([0xFF])), DER.tlv(0x04, DER.tlv(0x03, Data([0x07, 0x80])))]),
                DER.sequence([oid("2.5.29.37"), DER.tlv(0x04, DER.sequence([oid("1.3.6.1.5.5.7.3.3")]))]),
                DER.sequence([oid("2.5.29.14"), DER.tlv(0x04, DER.tlv(0x04, keyID))]),
            ])
            let algorithm = DER.sequence([DER.oidSHA256RSA, DER.null])
            let tbs = DER.sequence([DER.tlv(0xA0, integer(2)), DER.tlv(0x02, serial), algorithm, name, validity, name, spki, DER.tlv(0xA3, extensions)])
            guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, tbs as CFData, &error) as Data? else {
                throw Failure(message: "Lamp couldn't sign its certificate for app packages.")
            }
            return DER.sequence([tbs, algorithm, DER.tlv(0x03, Data([0x00]) + signature)])
        }

        private static func time(_ date: Date) -> Data {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            let year = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date).year ?? 2026
            formatter.dateFormat = year < 2050 ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
            return DER.tlv(year < 2050 ? 0x17 : 0x18, Data(formatter.string(from: date).utf8))
        }

        /// The serial's content and the issuer's whole encoding, read from a certificate's TBS.
        private static func issuerAndSerial(_ certificate: Data) -> (Data, Data)? {
            guard let tbs = DERReader.children(of: certificate).first, case let parts = DERReader.children(of: tbs), parts.count > 3 else { return nil }
            let versioned = parts[0].first == 0xA0
            let serial = parts[versioned ? 1 : 0], issuer = parts[versioned ? 3 : 2]
            return (contents(of: serial), issuer)
        }
    }

    /// The APPX signature's SIP GUID, as Windows lays it out in an SpcSipInfo.
    static let appxSIP: [UInt8] = [0x4B, 0xDF, 0xC5, 0x0A, 0x07, 0xCE, 0xE2, 0x4D, 0xB7, 0x6E, 0x23, 0xC8, 0x39, 0xA0, 0x9F, 0xD1]
}

/// A DER element's contents without its tag and length.
private func contents(of element: Data) -> Data {
    let bytes = [UInt8](element)
    guard bytes.count >= 2 else { return Data() }
    var start = 2
    if bytes[1] & 0x80 != 0 { start = 2 + Int(bytes[1] & 0x7F) }
    return Data(bytes[min(start, bytes.count)...])
}

private func integer(_ value: Int) -> Data {
    var bytes: [UInt8] = []
    var v = value
    repeat { bytes.insert(UInt8(v & 0xFF), at: 0); v >>= 8 } while v > 0
    if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
    return DER.tlv(0x02, Data(bytes))
}

/// A dotted object identifier in DER.
private func oid(_ dotted: String) -> Data {
    let parts = dotted.split(separator: ".").compactMap { UInt64($0) }
    var bytes: [UInt8] = [UInt8(parts[0] * 40 + parts[1])]
    for part in parts.dropFirst(2) {
        var chunk: [UInt8] = [UInt8(part & 0x7F)]
        var v = part >> 7
        while v > 0 { chunk.insert(UInt8(v & 0x7F) | 0x80, at: 0); v >>= 7 }
        bytes += chunk
    }
    return DER.tlv(0x06, Data(bytes))
}

/// Just enough DER reading to find a certificate's parts.
private enum DERReader {
    static func children(of element: Data) -> [Data] {
        let bytes = [UInt8](element)
        guard bytes.count >= 2 else { return [] }
        var at = headerLength(bytes, 0)
        var out: [Data] = []
        while at < bytes.count {
            let header = headerLength(bytes, at)
            let length = contentLength(bytes, at)
            guard header > 0, at + header + length <= bytes.count else { break }
            out.append(Data(bytes[at..<(at + header + length)]))
            at += header + length
        }
        return out
    }

    private static func headerLength(_ bytes: [UInt8], _ at: Int) -> Int {
        guard at + 1 < bytes.count else { return 0 }
        return bytes[at + 1] & 0x80 == 0 ? 2 : 2 + Int(bytes[at + 1] & 0x7F)
    }

    private static func contentLength(_ bytes: [UInt8], _ at: Int) -> Int {
        guard at + 1 < bytes.count else { return 0 }
        let first = bytes[at + 1]
        if first & 0x80 == 0 { return Int(first) }
        let count = Int(first & 0x7F)
        return (0..<count).reduce(0) { $0 << 8 | Int(at + 2 + $1 < bytes.count ? bytes[at + 2 + $1] : 0) }
    }
}
