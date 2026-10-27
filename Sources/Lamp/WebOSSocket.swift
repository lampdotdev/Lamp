import CryptoKit
import Foundation
import Security

/// An LG TV's second-screen socket, as LG's Connect SDK speaks it: `wss://<address>:3001`, a `register` message with a
/// manifest naming the permissions asked for, which the TV answers by asking the person on its screen the first time
/// and then with a client key, and `request` messages answered by id. Only what a setup's steps need is asked for:
/// opening apps and listing the installed ones.
///
/// The TV signs its own certificate. As the Connect SDK does, the one it shows when the person lets Lamp in is kept with
/// the client key, and the key is offered only to a TV showing that certificate again; one showing another is asked
/// afresh, on its screen, without the old key.
final class WebOSSocket: NSObject, SocketSetupConnection, URLSessionDelegate, @unchecked Sendable {
    static let permissions = ["LAUNCH", "READ_INSTALLED_APPS"]

    static func clientKeyURL(_ id: String) -> URL {
        TVs.folder.appendingPathComponent("LG").appendingPathComponent(id.replacingOccurrences(of: ":", with: "-") + ".client.json")
    }

    struct Kept: Codable, Equatable {
        var key: String
        /// SHA-256 of the certificate the TV showed when it let Lamp in.
        var certificate: String
    }

    let address: String
    let keyURL: URL
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    /// Set by `close`, from the main actor while the steps may be awaiting the socket elsewhere: nothing opens or
    /// sends after it.
    private var closed = false
    private var nextID = 0
    private let lock = NSLock()
    /// What the TV shows on this connection, read during the TLS handshake.
    private var seen: String?
    /// The certificate this connection must show, when a key is kept for the TV.
    private var expected: String?

    init(address: String, keyURL: URL) {
        self.address = address
        self.keyURL = keyURL
    }

    var kept: Kept? { (try? Data(contentsOf: keyURL)).flatMap { try? JSONDecoder().decode(Kept.self, from: $0) } }

    func connect() async throws {
        drop()
        let kept = kept
        do {
            try await open(expecting: kept?.certificate)
            try await register(key: kept?.key)
        } catch SetupConnectionError.unreachable where kept != nil && certificateChanged {
            // Another certificate than the one the person let in: not offered the key, asked again on its screen.
            drop()
            try await open(expecting: nil)
            try await register(key: nil)
        }
    }

    func request(_ uri: String, payload: [String: Any]) async throws -> [String: Any] {
        let id = "request_\(next())"
        try await send(["type": "request", "id": id, "uri": uri, "payload": payload])
        while true {
            let message: [String: Any]
            do { message = try await receive(timeout: 15) } catch is TimedOut { throw SetupConnectionError.unreachable }
            guard message["id"] as? String == id else { continue }
            if message["type"] as? String == "error" { throw SetupConnectionError.failed(message["error"] as? String ?? "an error") }
            let answer = message["payload"] as? [String: Any] ?? [:]
            if answer["returnValue"] as? Bool == false {
                throw SetupConnectionError.failed(answer["errorText"] as? String ?? "it said no")
            }
            return answer
        }
    }

    func close() {
        lock.lock(); closed = true; lock.unlock()
        drop()
    }

    /// Lets the socket go, to open another (a second connection in the steps) or for good (`close`).
    private func drop() {
        lock.lock()
        let (task, session) = (self.task, self.session)
        self.task = nil
        self.session = nil
        lock.unlock()
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }

    /// No message came in time.
    private struct TimedOut: Error {}

    // MARK: The socket

    private var certificateChanged: Bool {
        lock.lock(); defer { lock.unlock() }
        return expected != nil && seen != nil && seen != expected
    }

    private func next() -> Int { nextID += 1; return nextID }

    private func open(expecting certificate: String?) async throws {
        guard let url = URL(string: "wss://\(address):3001") else { throw SetupConnectionError.unreachable }
        lock.lock(); expected = certificate; seen = nil; lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        lock.lock()
        let gone = closed || Task.isCancelled
        if !gone { self.session = session; self.task = task }
        lock.unlock()
        guard !gone else {
            session.invalidateAndCancel()
            throw CancellationError()
        }
        task.resume()
    }

    /// Lets Lamp in: the first time, the TV asks the person, and answers with a key once they accept.
    private func register(key: String?) async throws {
        var payload: [String: Any] = ["forcePairing": false, "pairingType": "PROMPT",
                                      "manifest": ["manifestVersion": 1, "permissions": Self.permissions]]
        if let key { payload["client-key"] = key }
        let id = "register_\(next())"
        try await send(["type": "register", "id": id, "payload": payload])
        // The person has as long as the TV shows its question; the TV says when they declined or it gave up.
        var asking = false
        while true {
            let message: [String: Any]
            do { message = try await receive(timeout: asking ? 120 : 15) } catch is TimedOut {
                // The question went unanswered as long as the TV shows it; without one, the TV never answered at all.
                throw asking ? SetupConnectionError.refused : SetupConnectionError.unreachable
            }
            guard message["id"] as? String == id else { continue }
            switch message["type"] as? String {
            case "registered":
                guard let key = (message["payload"] as? [String: Any])?["client-key"] as? String, let certificate = currentCertificate else {
                    throw SetupConnectionError.failed("the TV let Lamp in without a key")
                }
                try keep(Kept(key: key, certificate: certificate))
                return
            case "error":
                // The TV refuses a pairing the person declined with a 403; anything else is its own error.
                let words = message["error"] as? String ?? "an error"
                throw words.hasPrefix("403") ? SetupConnectionError.refused : SetupConnectionError.failed(words)
            default:
                asking = ((message["payload"] as? [String: Any])?["pairingType"] as? String) != nil
            }
        }
    }

    private var currentCertificate: String? { lock.lock(); defer { lock.unlock() }; return seen }

    private func keep(_ kept: Kept) throws {
        // A TV that knows Lamp hands back the same key each time: nothing to write.
        guard self.kept != kept else { return }
        try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        // Readable by this user alone from the moment it exists, then moved into place.
        let staged = keyURL.deletingLastPathComponent().appendingPathComponent(".staging-\(UUID().uuidString)")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(kept)
        let file = Darwin.open(staged.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard file >= 0 else { throw SetupConnectionError.failed("Lamp couldn't keep the TV's key") }
        let written = data.withUnsafeBytes { Darwin.write(file, $0.baseAddress, $0.count) }
        Darwin.fsync(file)
        Darwin.close(file)
        guard written == data.count else {
            try? FileManager.default.removeItem(at: staged)
            throw SetupConnectionError.failed("Lamp couldn't keep the TV's key")
        }
        guard Darwin.rename(staged.path, keyURL.path) == 0 else {
            try? FileManager.default.removeItem(at: staged)
            throw SetupConnectionError.failed("Lamp couldn't keep the TV's key")
        }
    }

    private func send(_ message: [String: Any]) async throws {
        try Task.checkCancellation()
        lock.lock(); let task = closed ? nil : self.task; lock.unlock()
        guard let task, let data = try? JSONSerialization.data(withJSONObject: message) else { throw SetupConnectionError.unreachable }
        do { try await task.send(.string(String(decoding: data, as: UTF8.self))) } catch { throw Self.reason(error) }
    }

    /// The next message, or unreachable when none comes in time or the socket closes. Cancelling the work closes it.
    private func receive(timeout: Double) async throws -> [String: Any] {
        lock.lock(); let task = closed ? nil : self.task; lock.unlock()
        guard let task else { throw SetupConnectionError.unreachable }
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: [String: Any]?.self) { group in
                group.addTask {
                    let message = try await task.receive()
                    guard case .string(let text) = message else { return [:] }
                    return (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    return nil
                }
                defer { group.cancelAll() }
                do {
                    guard let first = try await group.next(), let message = first else {
                        // Out of time: the socket goes, which ends the receive still waiting on it.
                        task.cancel(with: .goingAway, reason: nil)
                        throw TimedOut()
                    }
                    return message
                } catch let error as TimedOut {
                    throw error
                } catch {
                    task.cancel(with: .goingAway, reason: nil)
                    throw Task.isCancelled ? CancellationError() : Self.reason(error)
                }
            }
        } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
        }
    }

    private static func reason(_ error: Error) -> Error {
        error is CancellationError ? error : SetupConnectionError.unreachable
    }

    // MARK: The TV's certificate

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == address, let trust = challenge.protectionSpace.serverTrust,
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let fingerprint = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
        lock.lock()
        seen = fingerprint
        let allowed = expected == nil || expected == fingerprint
        lock.unlock()
        if allowed { completionHandler(.useCredential, URLCredential(trust: trust)) } else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
}
