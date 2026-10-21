import AppKit
import CryptoKit
import Foundation
import Network
import Security

/// What a Samsung TV asks of an app before it installs it: two signatures, the author's (who made it) and the
/// distributor's (that this TV may run it), in the W3C widget-signing format. The distributor certificate names the
/// TV by its device id, and only Samsung issues it, to a Samsung account: the person signs in once on Samsung's own
/// page, Lamp makes a key and asks Samsung for both certificates (the requests Tizen Studio's certificate manager
/// makes), and from then on signs every package itself. Nothing of Tizen Studio is needed. The key and certificates
/// are Lamp's, in its own folder, which the agent's sandbox closes.
enum TizenSigning {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let folder = Edition.supportFolder.appendingPathComponent("TV/Samsung")
    private static var keyURL: URL { folder.appendingPathComponent("key.der") }
    private static var authorURL: URL { folder.appendingPathComponent("author.der") }
    private static var accountURL: URL { folder.appendingPathComponent("account.json") }
    private static func distributorURL(_ duid: String) -> URL { folder.appendingPathComponent("distributor-\(duid).der") }

    // MARK: What's here

    struct Account: Codable { let userId: String; let email: String }
    static var account: Account? { (try? Data(contentsOf: accountURL)).flatMap { try? JSONDecoder().decode(Account.self, from: $0) } }
    static func hasCertificates(for duid: String) -> Bool {
        FileManager.default.fileExists(atPath: authorURL.path) && FileManager.default.fileExists(atPath: distributorURL(duid).path)
            && FileManager.default.fileExists(atPath: keyURL.path)
    }

    // MARK: Signing in to Samsung and asking for the certificates

    /// Samsung's sign-in page and certificate service, as Tizen Studio's certificate manager uses them. The page hands
    /// the sign-in back by posting it to a page on this Mac, on the port the manager's client is registered for.
    private static let signInGate = "https://account.samsung.com/accounts/be1dce529476c1a6d407c4c7578c31bd/signInGate"
    private static let clientID = "v285zxnl3h"
    private static let callbackPort: UInt16 = 4794
    private static let authorEndpoint = URL(string: "https://svdca.samsungqbe.com/apis/v3/authors")!
    private static let distributorV1 = URL(string: "https://svdca.samsungqbe.com/apis/v1/distributors")!
    private static let distributorV3 = URL(string: "https://svdca.samsungqbe.com/apis/v3/distributors")!

    /// Opens Samsung's sign-in in the browser, waits for it to come back (at most ten minutes), and makes the key and
    /// certificates for the TV with `duid`. A second TV only needs its distributor certificate: the key and author
    /// certificate are kept, so every TV sees the same author.
    static func signInAndCertify(duid: String) async throws {
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let redirect = "http://localhost:\(callbackPort)/signin/callback"
        var components = URLComponents(string: signInGate)!
        components.queryItems = [URLQueryItem(name: "locale", value: ""), URLQueryItem(name: "clientId", value: clientID),
                                 URLQueryItem(name: "redirect_uri", value: redirect), URLQueryItem(name: "state", value: state),
                                 URLQueryItem(name: "tokenType", value: "TOKEN")]
        let listener = try SignInListener(port: callbackPort)
        let page = components.url!
        await MainActor.run { _ = NSWorkspace.shared.open(page) }
        let body = try await listener.waitForSignIn(timeout: 600)
        // The page posts a form whose `code` field holds the sign-in as JSON.
        let fields = Dictionary(body.split(separator: "&").compactMap { pair -> (String, String)? in
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { return nil }
            return (kv[0], kv[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? kv[1])
        }, uniquingKeysWith: { a, _ in a })
        guard let code = fields["code"], let json = try? JSONSerialization.jsonObject(with: Data(code.utf8)) as? [String: Any],
              let token = json["access_token"] as? String, let user = json["userId"] as? String else {
            throw Failure(message: "Samsung's sign-in didn't come back with an account. Try again.")
        }
        if let returned = json["state"] as? String, !returned.isEmpty, returned != state {
            throw Failure(message: "The sign-in that came back wasn't the one Lamp started. Try again.")
        }
        let email = (json["inputEmailID"] as? String) ?? ""
        try await certify(duid: duid, token: token, userId: user, email: email)
    }

    private static func certify(duid: String, token: String, userId: String, email: String) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let key = try loadOrMakeKey()
        guard let publicKey = SecKeyCopyPublicKey(key) else { throw Failure(message: "Lamp couldn't make a key.") }
        if !fm.fileExists(atPath: authorURL.path) {
            let csr = try CSR.make(subject: [(DER.oidCommonName, "Lamp", false)], extensions: nil, publicKey: publicKey, privateKey: key)
            let cert = try await post(authorEndpoint, csr: csr, name: "author.csr",
                                      fields: ["access_token": token, "user_id": userId, "platform": "VD"])
            try write(certificateDER(cert), to: authorURL)
        }
        var subject: [(Data, String, Bool)] = [(DER.oidCommonName, "TizenSDK", false)]
        if !email.isEmpty { subject.append((DER.oidEmail, email, true)) }
        let distributorCSR = try CSR.make(subject: subject, extensions: CSR.tizenDevices([duid]), publicKey: publicKey, privateKey: key)
        let fields = ["access_token": token, "user_id": userId, "privilege_level": "public", "developer_type": "Individual", "platform": "VD"]
        // The first answer is the device profile older TVs are given; the request registers the TV with Samsung either way.
        _ = try? await post(distributorV1, csr: distributorCSR, name: "distributor.csr", fields: fields)
        let distributor = try await post(distributorV3, csr: distributorCSR, name: "distributor.csr", fields: fields)
        try write(certificateDER(distributor), to: distributorURL(duid))
        try write(try JSONEncoder().encode(Account(userId: userId, email: email)), to: accountURL)
    }

    private static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func post(_ url: URL, csr: Data, name: String, fields: [String: String]) async throws -> Data {
        let boundary = "lamp-\(UUID().uuidString)"
        var body = Data()
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"csr\"; filename=\"\(name)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(csr)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let said = String(decoding: data.prefix(300), as: UTF8.self)
            throw Failure(message: "Samsung didn't issue the certificate (\((response as? HTTPURLResponse)?.statusCode ?? 0)). \(said)")
        }
        return data
    }

    /// A certificate as Samsung sends it, PEM or DER, as DER.
    private static func certificateDER(_ data: Data) throws -> Data {
        let text = String(decoding: data, as: UTF8.self)
        if text.contains("-----BEGIN CERTIFICATE-----") {
            let body = text.components(separatedBy: "-----BEGIN CERTIFICATE-----")[1].components(separatedBy: "-----END CERTIFICATE-----")[0]
            guard let der = Data(base64Encoded: body.filter { !$0.isWhitespace }) else { throw Failure(message: "Samsung's certificate couldn't be read.") }
            return der
        }
        guard SecCertificateCreateWithData(nil, data as CFData) != nil else { throw Failure(message: "Samsung's certificate couldn't be read.") }
        return data
    }

    private static func loadOrMakeKey() throws -> SecKey {
        if let data = try? Data(contentsOf: keyURL),
           let key = SecKeyCreateWithData(data as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate] as CFDictionary, nil) {
            return key
        }
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, &error),
              let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw Failure(message: "Lamp couldn't make a key.")
        }
        try write(data, to: keyURL)
        return key
    }

    // MARK: Signing a package

    /// The two signature files for a package of `files` (paths inside it, and their bytes), for the TV with `duid`.
    static func signatures(for files: [(path: String, data: Data)], duid: String) throws -> [(path: String, data: Data)] {
        guard let keyData = try? Data(contentsOf: keyURL),
              let key = SecKeyCreateWithData(keyData as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate] as CFDictionary, nil),
              let author = try? Data(contentsOf: authorURL), let distributor = try? Data(contentsOf: distributorURL(duid)) else {
            throw Failure(message: "Lamp has no Samsung certificate for this TV yet. Sign in to Samsung in the TV's setup.")
        }
        let authorCA = try bundled("vd_tizen_dev_author_ca"), distributorCA = try bundled("vd_tizen_dev_public2")
        let authorFile = try signatureFile(id: "AuthorSignature", role: "author", files: files, key: key, chain: [author, authorCA])
        let distributorFile = try signatureFile(id: "DistributorSignature", role: "distributor",
                                                files: [("author-signature.xml", authorFile)] + files, key: key, chain: [distributor, distributorCA])
        return [("author-signature.xml", authorFile), ("signature1.xml", distributorFile)]
    }

    private static func bundled(_ name: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "der", subdirectory: "TVCertificates"),
              let data = try? Data(contentsOf: url) else { throw Failure(message: "Lamp's copy of Samsung's certificates is missing. Reinstall Lamp.") }
        return data
    }

    private static let dsig = "http://www.w3.org/2000/09/xmldsig#"

    /// One signature file. Lamp writes the XML itself, already in canonical form, so what it digests and signs is
    /// exactly what's in the file: SignedInfo under exclusive canonicalization, the properties object under
    /// canonicalization 1.1 (the same bytes for what's here), each file by SHA-512, the whole signed with RSA SHA-512.
    static func signatureFile(id: String, role: String, files: [(path: String, data: Data)], key: SecKey, chain: [Data]) throws -> Data {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let object = "<Object Id=\"prop\"><SignatureProperties xmlns:dsp=\"http://www.w3.org/2009/xmldsig-properties\">"
            + "<SignatureProperty Id=\"profile\" Target=\"#\(id)\"><dsp:Profile URI=\"http://www.w3.org/ns/widgets-digsig#profile\"></dsp:Profile></SignatureProperty>"
            + "<SignatureProperty Id=\"role\" Target=\"#\(id)\"><dsp:Role URI=\"http://www.w3.org/ns/widgets-digsig#role-\(role)\"></dsp:Role></SignatureProperty>"
            + "<SignatureProperty Id=\"identifier\" Target=\"#\(id)\"><dsp:Identifier></dsp:Identifier></SignatureProperty>"
            + "</SignatureProperties></Object>"
        // Canonicalized on its own, the object carries the namespace it inherits.
        let objectCanonical = object.replacingOccurrences(of: "<Object Id=\"prop\">", with: "<Object xmlns=\"\(dsig)\" Id=\"prop\">")
        var references = ""
        for file in files {
            references += "<Reference URI=\"\(escape(file.path))\"><DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha512\"></DigestMethod>"
                + "<DigestValue>\(Data(SHA512.hash(data: file.data)).base64EncodedString())</DigestValue></Reference>"
        }
        references += "<Reference URI=\"#prop\"><Transforms><Transform Algorithm=\"http://www.w3.org/2006/12/xml-c14n11\"></Transform></Transforms>"
            + "<DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha512\"></DigestMethod>"
            + "<DigestValue>\(Data(SHA512.hash(data: Data(objectCanonical.utf8))).base64EncodedString())</DigestValue></Reference>"
        let signedInfo = "<SignedInfo><CanonicalizationMethod Algorithm=\"http://www.w3.org/2001/10/xml-exc-c14n#\"></CanonicalizationMethod>"
            + "<SignatureMethod Algorithm=\"http://www.w3.org/2001/04/xmldsig-more#rsa-sha512\"></SignatureMethod>" + references + "</SignedInfo>"
        let signedInfoCanonical = signedInfo.replacingOccurrences(of: "<SignedInfo>", with: "<SignedInfo xmlns=\"\(dsig)\">")
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA512, Data(signedInfoCanonical.utf8) as CFData, &error) as Data? else {
            throw Failure(message: "Lamp couldn't sign the package.")
        }
        let certificates = chain.map { cert -> String in
            let b64 = cert.base64EncodedString()
            let wrapped = stride(from: 0, to: b64.count, by: 76).map { start -> String in
                let from = b64.index(b64.startIndex, offsetBy: start), to = b64.index(from, offsetBy: min(76, b64.count - start))
                return String(b64[from..<to])
            }.joined(separator: "\n")
            return "<X509Certificate>\n\(wrapped)\n</X509Certificate>"
        }.joined()
        let xml = "<Signature xmlns=\"\(dsig)\" Id=\"\(id)\">" + signedInfo + "<SignatureValue>\(signature.base64EncodedString())</SignatureValue>"
            + "<KeyInfo><X509Data>\(certificates)</X509Data></KeyInfo>" + object + "</Signature>"
        return Data(xml.utf8)
    }
}

// MARK: - The sign-in coming back

/// A page on this Mac, for as long as one sign-in takes, that Samsung's sign-in posts to. It answers only that post.
private final class SignInListener: @unchecked Sendable {
    /// On both of this Mac's own addresses: a browser may take "localhost" for either, and only those, so nothing
    /// on the network reaches it.
    private var listeners: [NWListener] = []
    private let queue = DispatchQueue(label: "lamp.samsung-signin")
    private var continuation: CheckedContinuation<String, Error>?
    private var finished = false

    init(port: UInt16) throws {
        for host in [NWEndpoint.Host.ipv4(.loopback), .ipv6(.loopback)] {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: host, port: NWEndpoint.Port(rawValue: port)!)
            parameters.allowLocalEndpointReuse = true
            if let listener = try? NWListener(using: parameters) { listeners.append(listener) }
        }
        guard !listeners.isEmpty else {
            throw TizenSigning.Failure(message: "Lamp couldn't listen for Samsung's sign-in on this Mac. Another program may be using its port.")
        }
    }

    func waitForSignIn(timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                for listener in self.listeners {
                    listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
                    listener.start(queue: self.queue)
                }
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.finish(.failure(TizenSigning.Failure(message: "The Samsung sign-in wasn't finished in time. Try again.")))
                }
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        for listener in listeners { listener.cancel() }
        continuation?.resume(with: result)
        continuation = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        var received = Data()
        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
                guard let self else { return }
                if let data { received.append(data) }
                let text = String(decoding: received, as: UTF8.self)
                if let headerEnd = text.range(of: "\r\n\r\n") {
                    let head = String(text[..<headerEnd.lowerBound])
                    let length = head.split(separator: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                        .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                    let body = String(text[headerEnd.upperBound...])
                    if body.utf8.count >= length {
                        let page = "<html><body style=\"font: 15px -apple-system; padding: 40px\">You're signed in. You can close this page and go back to Lamp.</body></html>"
                        let reply = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(page.utf8.count)\r\nConnection: close\r\n\r\n\(page)"
                        connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
                        if head.hasPrefix("POST /signin/callback"), body.contains("code=") { self.finish(.success(body)) }
                        return
                    }
                }
                if done || error != nil { connection.cancel(); return }
                readMore()
            }
        }
        readMore()
    }
}

// MARK: - DER, for the certificate requests

enum DER {
    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        let n = content.count
        if n < 0x80 { out.append(UInt8(n)) } else {
            var bytes: [UInt8] = []
            var v = n
            while v > 0 { bytes.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
            out.append(0x80 | UInt8(bytes.count))
            out.append(contentsOf: bytes)
        }
        return out + content
    }
    static func sequence(_ parts: [Data]) -> Data { tlv(0x30, parts.reduce(Data(), +)) }
    static func set(_ parts: [Data]) -> Data { tlv(0x31, parts.reduce(Data(), +)) }
    static func oid(_ bytes: [UInt8]) -> Data { tlv(0x06, Data(bytes)) }
    static let null = Data([0x05, 0x00])
    static let oidCommonName = oid([0x55, 0x04, 0x03])
    static let oidEmail = oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x01])
    static let oidRSA = oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])
    static let oidSHA256RSA = oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B])
    static let oidExtensionRequest = oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x0E])
    static let oidSubjectAltName = oid([0x55, 0x1D, 0x11])
}

enum CSR {
    /// The subject alternative names a distributor certificate carries: the package (any) and each TV it's for.
    static func tizenDevices(_ duids: [String]) -> Data {
        let names = ["URN:tizen:packageid="] + duids.map { "URN:tizen:deviceid=\($0)" }
        let generalNames = DER.sequence(names.map { DER.tlv(0x86, Data($0.utf8)) })
        let extensionSAN = DER.sequence([DER.oidSubjectAltName, DER.tlv(0x04, generalNames)])
        return DER.sequence([extensionSAN])
    }

    /// A PKCS #10 request in PEM, signed with `privateKey`. Each subject part is (type, value, IA5).
    static func make(subject: [(Data, String, Bool)], extensions: Data?, publicKey: SecKey, privateKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else { throw TizenSigning.Failure(message: "Lamp couldn't read its key.") }
        let spki = DER.sequence([DER.sequence([DER.oidRSA, DER.null]), DER.tlv(0x03, Data([0x00]) + pkcs1)])
        let name = DER.sequence(subject.map { type, value, ia5 in
            DER.set([DER.sequence([type, DER.tlv(ia5 ? 0x16 : 0x0C, Data(value.utf8))])])
        })
        let attributes: Data = extensions.map { ext in
            DER.tlv(0xA0, DER.sequence([DER.oidExtensionRequest, DER.set([ext])]))
        } ?? DER.tlv(0xA0, Data())
        let info = DER.sequence([DER.tlv(0x02, Data([0x00])), name, spki, attributes])
        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, info as CFData, &error) as Data? else {
            throw TizenSigning.Failure(message: "Lamp couldn't sign its certificate request.")
        }
        let request = DER.sequence([info, DER.sequence([DER.oidSHA256RSA, DER.null]), DER.tlv(0x03, Data([0x00]) + signature)])
        let b64 = request.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return Data("-----BEGIN CERTIFICATE REQUEST-----\n\(b64)\n-----END CERTIFICATE REQUEST-----\n".utf8)
    }
}
