import Foundation

/// devicectl --console stays alive after launch. Starting that process, or even a zero exit status, is
/// not a launch acknowledgement. Wait for its explicit confirmation for this bundle, keeping the console.
enum PhoneLaunch {
    static func acknowledged(_ output: String, bundleID: String) -> Bool {
        output.components(separatedBy: .newlines).contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "Launched application with \(bundleID) bundle identifier."
        }
    }

    @MainActor
    static func wait(_ process: Process, bundleID: String, output: URL, offset: UInt64 = 0, timeout: TimeInterval = 60,
                     cancelled: () -> Bool = { false }) async throws {
        let reader = try FileHandle(forReadingFrom: output)
        defer { try? reader.close() }
        try reader.seek(toOffset: offset)
        var received = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if cancelled() || Task.isCancelled { throw CancellationError() }
            if let chunk = try reader.readToEnd() { received.append(chunk) }
            let text = String(decoding: received, as: UTF8.self)
            // A console that already died cannot represent a running app, even if launch was acknowledged.
            guard process.isRunning else {
                throw PhoneFailure(stage: .launch, output: text + "\nThe launch console exited before the app was ready.")
            }
            if acknowledged(text, bundleID: bundleID) { return }
            guard Date() < deadline else {
                throw PhoneFailure(stage: .launch, output: text + "\nTimed out waiting for launch confirmation.")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
