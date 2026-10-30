import CryptoKit
import Foundation
import Security

/// What every download Lamp runs or builds from must pass: a file of the size and SHA-256 its own bundle pins, and code
/// signed with the very certificate Lamp itself is signed with. Starters' prebuilt apps use it (`StarterDownloads`), so
/// a tampered or swapped download is refused before anything of it runs.
enum Downloads {
    struct Failure: LocalizedError {
        let message: String
        /// The file isn't there any more (an old nightly's assets are removed in time), so trying again won't help.
        var gone = false
        init(_ message: String, gone: Bool = false) { self.message = message; self.gone = gone }
        var errorDescription: String? { message }
    }

    /// What's said when a download didn't come: the person's connection, nearly always.
    static let offline = "Couldn't download it. Check your connection."
    /// What's said when what this Lamp pins isn't there any more (an old nightly's files are removed in time).
    static let gone = "It isn't available for this version of Lamp any more. Update Lamp, then try again."
    /// What's said when one came and wasn't what Lamp asked for.
    static let refused = "The download wasn't right, so Lamp didn't use it."

    /// A pinned file: where it is, and what it must be.
    struct Pinned: Codable, Equatable {
        var url: String
        var sha256: String
        var size: Int64
    }

    /// Downloads `pinned` to a file of the caller's, refusing one of another size or hash. A file URL is read as the same
    /// kind of download, which a build from source points at what it built itself.
    static func fetch(_ pinned: Pinned, to destination: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard let url = URL(string: pinned.url), ["https", "file"].contains(url.scheme) else { throw Failure(refused) }
        let temp: URL
        do {
            if url.isFileURL {
                temp = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-download-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: url, to: temp)
            } else {
                let tracker = progress.map { report in DownloadProgress { written in report(Double(written) / Double(max(pinned.size, 1))) } }
                let (file, response) = try await URLSession.shared.download(from: url, delegate: tracker)
                let status = (response as? HTTPURLResponse)?.statusCode
                guard status == 200 else {
                    try? FileManager.default.removeItem(at: file)
                    let gone = status == 404 || status == 410
                    throw Failure(gone ? Downloads.gone : offline, gone: gone)
                }
                temp = file
            }
        } catch let error as Failure {
            throw error
        } catch {
            throw Failure(offline)
        }
        defer { try? FileManager.default.removeItem(at: temp) }
        guard (try? temp.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) == pinned.size,
              try sha256(of: temp) == pinned.sha256.lowercased() else { throw Failure(refused) }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    /// A file's SHA-256, read a megabyte at a time.
    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Signatures

    /// What downloaded code must satisfy: signed by the certificate that signed this Lamp (the release's Developer ID,
    /// or a build from source's own signing identity), so it's what the same build made. Nil when Lamp itself carries
    /// no certificate (an ad hoc build from source), which can check a download only by its hash.
    static let requirement: SecRequirement? = {
        var me: SecCode?
        var staticMe: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &staticMe) == errSecSuccess, let staticMe,
              SecCodeCopySigningInformation(staticMe, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let certificates = (info as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { return nil }
        let digest = Insecure.SHA1.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02X", $0) }.joined()
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("certificate leaf = H\"\(digest)\"" as CFString, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }()

    /// Whether code on disk (an app, a program, a library) is whole and signed as Lamp is, nested code and all. True
    /// for anything when Lamp can't say (`requirement`), which only a build from source can be.
    static func signedLikeLamp(_ code: URL) -> Bool {
        guard let requirement else { return true }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(code as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidityWithErrors(staticCode, flags, requirement, nil) == errSecSuccess
    }
}

/// Reports bytes written for a URLSession download.
final class DownloadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let onProgress: (Int64) -> Void
    private var observation: NSKeyValueObservation?

    init(onProgress: @escaping (Int64) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.completedUnitCount) { [weak self] progress, _ in
            self?.onProgress(progress.completedUnitCount)
        }
    }
}
