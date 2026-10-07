import Foundation

/// devicectl --console stays alive after launch. Starting that process, or even a zero exit status, is
/// not a launch acknowledgement. Wait for its explicit confirmation for this bundle, keeping the console.
enum PhoneLaunch {
    /// A yes that one thread sets and another reads.
    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        func isSet() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    static func acknowledged(_ output: String, bundleID: String) -> Bool {
        output.components(separatedBy: .newlines).contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "Launched application with \(bundleID) bundle identifier."
        }
    }

    @MainActor
    static func wait(_ process: Process, bundleID: String, output: URL, offset: UInt64 = 0, timeout: TimeInterval = 60,
                     cancelled: () -> Bool = { false }, drained: () -> Bool = { true }) async throws {
        let reader = try FileHandle(forReadingFrom: output)
        defer { try? reader.close() }
        try reader.seek(toOffset: offset)
        var received = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if cancelled() || Task.isCancelled { throw CancellationError() }
            if let chunk = try reader.readToEnd() { received.append(chunk) }
            // A console that already died cannot represent a running app, even if launch was acknowledged.
            // Its last words may still be on their way to the log: they're the reason, so they're waited for.
            guard process.isRunning else {
                let settle = Date().addingTimeInterval(3)
                while !drained(), Date() < settle { try await Task.sleep(for: .milliseconds(50)) }
                if let chunk = try reader.readToEnd() { received.append(chunk) }
                let text = String(decoding: received, as: UTF8.self)
                throw PhoneFailure(stage: .launch, output: text + "\nThe launch console exited before the app was ready.")
            }
            let text = String(decoding: received, as: UTF8.self)
            if acknowledged(text, bundleID: bundleID) { return }
            guard Date() < deadline else {
                throw PhoneFailure(stage: .launch, output: text + "\nTimed out waiting for launch confirmation.")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
