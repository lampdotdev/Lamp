import Foundation
import Network
import Security
import CryptoKit

/// Shared verbatim with the companion. Bonjour locates a Mac; only possession of the QR key
/// authenticates it. No wish, credential, or status is sent before TLS authenticates both ends.
enum PhoneLink {
    static let service = "_lamp-wishes._tcp"
    static let limit = 16_384

    struct Pair: Codable, Equatable {
        let version: Int
        let id: UUID
        let key: Data

        init() throws {
            version = 1
            id = UUID()
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.storage }
            key = Data(bytes)
        }

        var valid: Bool { version == 1 && key.count == 32 }
        var invitation: String { "lamp-pair:" + ((try? JSONEncoder().encode(self)) ?? Data()).base64EncodedString() }
        static func read(_ text: String) -> Pair? {
            guard text.hasPrefix("lamp-pair:"), text.count < 1024,
                  let data = Data(base64Encoded: String(text.dropFirst(10))),
                  let pair = try? JSONDecoder().decode(Pair.self, from: data), pair.valid else { return nil }
            return pair
        }
    }

    struct Request: Codable {
        enum Action: String, Codable { case hello, submit, status }
        let action: Action
        var id: UUID?
        var wish: String?
        var chatID: UUID?
        var revision: UUID?
        var offset: Int?
    }

    struct Status: Codable, Equatable {
        enum Phase: String, Codable {
            case queued, building, approval, installing, waitingPhone, ready, replied, needsMac
            var isFinished: Bool { [.ready, .replied, .needsMac].contains(self) }
            var text: String {
                switch self {
                case .queued: "Waiting for Mac"
                case .building: "Building"
                case .approval: "Approve on Mac"
                case .installing: "Installing"
                case .waitingPhone: "Unlock iPhone on Wi-Fi"
                case .ready: "Ready"
                case .replied: "Replied"
                case .needsMac: "Check Lamp on Mac"
                }
            }
        }
        let id: UUID
        var phase: Phase
        var appURL: String?
        var activity: String?
    }

    struct Reply: Codable {
        var status: Status?
        var error: String?
        var refused: Bool? = nil
        var acceptedID: UUID?
        var chat: ChatChunk?
    }

    struct Chat: Codable, Equatable {
        let id: UUID
        let title: String
        let lines: [ChatLine]
    }

    struct ChatLine: Codable, Equatable, Identifiable {
        enum Kind: String, Codable { case user, agent, status, error, notice }
        let id: UUID
        let kind: Kind
        let text: String
        var attachments = 0
        var queued = false
    }

    struct ChatChunk: Codable {
        let chatID: UUID
        let revision: UUID
        let offset: Int
        let total: Int
        let digest: Data
        let data: Data
    }

    /// A frozen transcript is transferred in small frames. Streaming agent text can change while
    /// these frames travel, so pieces from different revisions must never be stitched together.
    struct ChatTransfer {
        static let maximum = 8 * 1024 * 1024
        static let chunkSize = 8 * 1024
        let chatID: UUID
        let revision = UUID()
        let created = Date()
        let data: Data
        let digest: Data

        init(_ chat: Chat) throws {
            chatID = chat.id
            data = try JSONEncoder().encode(chat)
            guard data.count <= Self.maximum else { throw Failure.full }
            digest = Data(SHA256.hash(data: data))
        }

        func chunk(at offset: Int) throws -> ChatChunk {
            guard offset >= 0, offset < data.count else { throw Failure.invalid }
            return .init(chatID: chatID, revision: revision, offset: offset, total: data.count,
                         digest: digest, data: data.subdata(in: offset..<min(data.count, offset + Self.chunkSize)))
        }
    }

    struct ChatAssembly {
        private(set) var revision: UUID?
        private(set) var data = Data()
        private var total = 0
        private var digest = Data()

        mutating func append(_ chunk: ChatChunk, for chatID: UUID) throws -> Chat? {
            guard chunk.chatID == chatID, chunk.total > 0, chunk.total <= ChatTransfer.maximum,
                  chunk.digest.count == 32, !chunk.data.isEmpty, chunk.data.count <= ChatTransfer.chunkSize else { throw Failure.invalid }
            if chunk.offset == 0 {
                revision = chunk.revision
                data = Data()
                total = chunk.total
                digest = chunk.digest
            }
            guard chunk.revision == revision, chunk.total == total, chunk.offset == data.count,
                  chunk.digest == digest, chunk.data.count <= total - data.count else { throw Failure.invalid }
            data.append(chunk.data)
            guard data.count == total else { return nil }
            guard Data(SHA256.hash(data: data)) == digest else { throw Failure.invalid }
            let chat = try JSONDecoder().decode(Chat.self, from: data)
            guard chat.id == chatID else { throw Failure.invalid }
            self = Self()
            return chat
        }
    }

    enum Failure: LocalizedError {
        case storage, unavailable, invalid, busy, full
        var errorDescription: String? {
            switch self {
            case .storage: "Couldn't save. Try again."
            case .unavailable: "Waiting for Mac on Wi-Fi"
            case .invalid: "Couldn't connect. Pair again on Mac."
            case .busy: "Another wish is still building."
            case .full: "Check Lamp on Mac."
            }
        }
    }

    static func parameters(_ pair: Pair, interface: NWInterface.InterfaceType = .wifi) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        func dispatch(_ data: Data) -> DispatchData { data.withUnsafeBytes { DispatchData(bytes: $0) } }
        sec_protocol_options_add_pre_shared_key(options, dispatch(pair.key) as __DispatchData,
                                                dispatch(Data(pair.id.uuidString.utf8)) as __DispatchData)
        // Apple's Network PSK API supports TLS 1.2. Restrict it to an authenticated AES-GCM suite;
        // there is no certificate bypass, plaintext fallback, or short password to guess.
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.requiredInterfaceType = interface
        parameters.includePeerToPeer = false
        return parameters
    }

    /// A length-prefixed JSON exchange, one request per connection. The cap applies before allocation.
    static func receive<T: Decodable>(_ type: T.Type, on connection: NWConnection,
                                       completion: @escaping (Result<T, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, _, error in
            guard error == nil, let data, data.count == 4 else { completion(.failure(Failure.unavailable)); return }
            let count = data.reduce(0) { ($0 << 8) | Int($1) }
            guard count > 0, count <= limit else { completion(.failure(Failure.invalid)); return }
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { body, _, _, error in
                guard error == nil, let body, body.count == count else { completion(.failure(Failure.unavailable)); return }
                completion(Result { try JSONDecoder().decode(type, from: body) })
            }
        }
    }

    static func send<T: Encodable>(_ value: T, on connection: NWConnection, completion: @escaping (Error?) -> Void) {
        do {
            let body = try JSONEncoder().encode(value)
            guard body.count <= limit else { throw Failure.invalid }
            var size = UInt32(body.count).bigEndian
            var data = withUnsafeBytes(of: &size) { Data($0) }
            data.append(body)
            connection.send(content: data, completion: .contentProcessed { completion($0) })
        } catch { completion(error) }
    }

    /// Keychain is the only home of pairing keys on either device. Do not recover a read error by
    /// silently replacing a key: a locked or temporarily unavailable keychain is not a lost pairing.
    static func loadKey<T: Decodable>(_ type: T.Type, service: String) throws -> T? {
        var query = keyQuery(service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure.storage }
        return try JSONDecoder().decode(type, from: data)
    }

    static func saveKey<T: Encodable>(_ value: T, service: String) throws {
        let data = try JSONEncoder().encode(value)
        let query = keyQuery(service)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw Failure.storage }
        var item = query
        item[kSecValueData as String] = data
        #if os(iOS)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw Failure.storage }
    }

    private static func keyQuery(_ service: String) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: "pair"]
        #if os(iOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        // Native Mac apps use the login Keychain's code-signature ACL. The iOS data protection
        // keychain requires an application-identifier entitlement which local Mac builds don't have.
        return query
    }
}

final class PhoneLinkServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "lamp.phone.listener")
    private var connections: [UUID: NWConnection] = [:]
    private let handler: (PhoneLink.Request) async -> PhoneLink.Reply
    var port: NWEndpoint.Port? { listener.port }

    init(pair: PhoneLink.Pair, interface: NWInterface.InterfaceType = .wifi,
         handler: @escaping (PhoneLink.Request) async -> PhoneLink.Reply) throws {
        self.handler = handler
        listener = try NWListener(using: PhoneLink.parameters(pair, interface: interface))
        listener.service = .init(name: pair.id.uuidString, type: PhoneLink.service)
    }

    func start(changed: @escaping (NWListener.State) -> Void) {
        listener.stateUpdateHandler = changed
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.connections.count < 8 else { connection.cancel(); return }
            let id = UUID()
            self.connections[id] = connection
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .cancelled: self?.close(id)
                default: break
                }
            }
            connection.start(queue: self.queue)
            self.queue.asyncAfter(deadline: .now() + 20) { [weak self] in self?.close(id) }
            PhoneLink.receive(PhoneLink.Request.self, on: connection) { [weak self] result in
                guard let self else { return }
                guard case .success(let request) = result else { self.close(id); return }
                Task {
                    let reply = await self.handler(request)
                    self.queue.async {
                        guard self.connections[id] != nil else { return }
                        PhoneLink.send(reply, on: connection) { _ in self.close(id) }
                    }
                }
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
        queue.async { [self] in
            for id in Array(connections.keys) { close(id) }
        }
    }

    private func close(_ id: UUID) {
        let connection = connections.removeValue(forKey: id)
        connection?.stateUpdateHandler = nil
        connection?.cancel()
    }
}

/// Owns a bounded exchange until its reply or deadline. All callbacks run on its serial queue.
final class PhoneLinkExchange {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "lamp.phone.exchange")
    private var finished = false
    private var completion: ((Result<PhoneLink.Reply, Error>) -> Void)?

    init(endpoint: NWEndpoint, pair: PhoneLink.Pair, interface: NWInterface.InterfaceType = .wifi) {
        connection = NWConnection(to: endpoint, using: PhoneLink.parameters(pair, interface: interface))
    }

    func start(_ request: PhoneLink.Request, completion: @escaping (Result<PhoneLink.Reply, Error>) -> Void) {
        self.completion = completion
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                PhoneLink.send(request, on: connection) { [self] error in
                    if let error { finish(.failure(error)); return }
                    PhoneLink.receive(PhoneLink.Reply.self, on: connection) { [self] in finish($0) }
                }
            case .failed(let error): finish(.failure(error))
            case .cancelled: finish(.failure(PhoneLink.Failure.unavailable))
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 15) { [self] in finish(.failure(PhoneLink.Failure.unavailable)) }
    }

    func cancel() { queue.async { [self] in finish(.failure(PhoneLink.Failure.unavailable)) } }

    private func finish(_ result: Result<PhoneLink.Reply, Error>) {
        guard !finished else { return }
        finished = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        let callback = completion
        completion = nil
        callback?(result)
    }
}
