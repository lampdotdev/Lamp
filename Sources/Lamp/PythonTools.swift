import Foundation
import CryptoKit

/// The Python tools some models on this Mac run on (mflux for pictures, mlx-lm for MLX models), installed
/// by Lamp itself so that nobody is sent to Terminal. They are installed with uv, which brings its own
/// Python. A Mac without uv gets Lamp's own copy, downloaded from uv's releases into Lamp's support folder.
@MainActor
final class PythonTools: ObservableObject {
    static let shared = PythonTools()

    /// The raw value is the package uv installs.
    enum Tool: String {
        case mflux
        case mlx = "mlx-lm"
    }

    @Published var installing: Set<Tool> = []
    @Published var errors: [Tool: String] = [:]

    nonisolated private static let ownUV = Edition.supportFolder.appendingPathComponent("Tools/uv")

    /// The user's own uv if they have one, else the copy Lamp downloaded.
    nonisolated static var uvPath: String? {
        ToolLocator.path(named: "uv") ?? (FileManager.default.isExecutableFile(atPath: ownUV.path) ? ownUV.path : nil)
    }

    /// A few hundred megabytes of Python packages, a minute or two.
    func install(_ tool: Tool) async {
        guard !installing.contains(tool) else { return }
        installing.insert(tool)
        errors[tool] = nil
        defer { installing.remove(tool) }
        do {
            let uv = try await Self.uv()
            // ~/.local/bin is where ToolLocator looks, whatever the user's own setup says.
            let env = ["LAMP_UV": uv, "LAMP_PACKAGE": tool.rawValue,
                       "UV_TOOL_BIN_DIR": FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path]
            var output: [String] = []
            let status = await Shell.run(#""$LAMP_UV" tool install --python 3.12 --upgrade "$LAMP_PACKAGE""#,
                                         cwd: FileManager.default.temporaryDirectory, env: env) { output.append($0) }
            if status != 0 { throw Failure(installing: output) }
        } catch {
            errors[tool] = error.localizedDescription
        }
    }

    /// uv's path, downloading Lamp's own copy first when this Mac has none.
    private static func uv() async throws -> String {
        if let path = uvPath { return path }
        #if arch(arm64)
        let name = "uv-aarch64-apple-darwin"
        #else
        let name = "uv-x86_64-apple-darwin"
        #endif
        let release = "https://github.com/astral-sh/uv/releases/latest/download/\(name).tar.gz"
        let archive: URL, sum: Data
        do {
            let (file, response) = try await URLSession.shared.download(from: URL(string: release)!)
            archive = file
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { try? FileManager.default.removeItem(at: file); throw Failure.unavailable }
        } catch {
            throw Failure(downloading: error)
        }
        defer { try? FileManager.default.removeItem(at: archive) }
        // The release publishes each archive's checksum beside it: a download cut short doesn't get run.
        do {
            let (data, response) = try await URLSession.shared.data(from: URL(string: release + ".sha256")!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.unavailable }
            sum = data
        } catch {
            throw Failure(downloading: error)
        }
        guard let expected = String(data: sum, encoding: .utf8)?.split(separator: " ").first,
              let data = try? Data(contentsOf: archive),
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected else { throw Failure.damaged }

        // Unpacked beside its final place and moved in only when whole: an unpacking cut short (a full disk,
        // say) would otherwise leave half a uv there, and every later try would run that instead of fetching it again.
        let folder = ownUV.deletingLastPathComponent()
        let scratch = folder.appendingPathComponent("unpacking-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        guard (try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)) != nil else { throw Failure(saving: []) }
        var output: [String] = []
        let status = await Shell.run(#"/usr/bin/tar -xzf "$LAMP_ARCHIVE" -C "$LAMP_FOLDER" --strip-components 1"#, cwd: scratch,
                                     env: ["LAMP_ARCHIVE": archive.path, "LAMP_FOLDER": scratch.path]) { output.append($0) }
        let unpacked = scratch.appendingPathComponent("uv")
        guard status == 0, FileManager.default.isExecutableFile(atPath: unpacked.path) else { throw Failure(saving: output) }
        try? FileManager.default.removeItem(at: ownUV)
        guard (try? FileManager.default.moveItem(at: unpacked, to: ownUV)) != nil else { throw Failure(saving: output) }
        return ownUV.path
    }

    /// Why an install stopped, told apart as far as Lamp can, so the message says what to do about it:
    /// a full disk isn't fixed by checking the internet connection.
    enum Failure: LocalizedError {
        case offline, unavailable, damaged, diskFull, saving
        case installing(String)

        var errorDescription: String? {
            switch self {
            case .offline: "Lamp couldn't reach the internet to download this. Check your connection, then click Install again."
            case .unavailable: "The download isn't available right now. The problem is at the other end, not on your Mac. Click Install again in a few minutes."
            case .damaged: "The download arrived damaged. Click Install again."
            case .diskFull: "This Mac is almost out of storage space. Free up about 3 GB (emptying the Trash is a good start), then click Install again."
            case .saving: "Lamp couldn't save what it downloaded. Click Install again."
            case .installing(let detail): "It didn't install. Click Install again." + (detail.isEmpty ? "" : " (What it said: \(detail))")
            }
        }

        /// A download that didn't arrive. Anything that isn't plainly the far end's fault counts as the connection.
        init(downloading error: Error) {
            if let failure = error as? Failure { self = failure; return }
            let code = (error as? URLError)?.code
            if Self.outOfSpace(error) {
                self = .diskFull
            } else if code == .cannotWriteToFile || code == .cannotCreateFile {
                // It arrived and couldn't be written, with room on the disk: a folder Lamp can't write to, say.
                // Freeing space wouldn't help.
                self = .saving
            } else if [.badServerResponse, .cannotParseResponse, .resourceUnavailable, .fileDoesNotExist].contains(code) {
                self = .unavailable
            } else {
                self = .offline
            }
        }

        /// Unpacking or moving what was downloaded, with whatever the unpacking said.
        init(saving output: [String]) {
            self = Self.outOfSpace(output) ? .diskFull : .saving
        }

        /// uv's own failure, with its output: the disk, the far end, the connection, or its last words when
        /// it's none of those.
        init(installing output: [String]) {
            let said = output.joined(separator: " ").lowercased()
            let detail = output.suffix(3).joined(separator: " ")
            if Self.outOfSpace(output) {
                self = .diskFull
            } else if said.contains("http status") {
                // An answer came back, so the connection is fine: the far end is having trouble (or is turning
                // requests away for now), or it's something only uv's own words explain.
                self = said.contains("http status server error") || said.contains("429 too many requests") ? .unavailable : .installing(detail)
            } else if ["dns error", "error sending request", "failed to lookup address", "connection refused", "connection reset",
                       "network is unreachable", "timed out"].contains(where: said.contains) {
                self = .offline
            } else {
                self = .installing(detail)
            }
        }

        /// A failed download or write whose own error, or one beneath it, says the disk is full.
        private static func outOfSpace(_ error: Error) -> Bool {
            var said: [String] = []
            var next: NSError? = error as NSError
            while let current = next {
                if current.domain == NSPOSIXErrorDomain, [Int(ENOSPC), Int(EDQUOT)].contains(current.code) { return true }
                if current.domain == NSCocoaErrorDomain, current.code == NSFileWriteOutOfSpaceError { return true }
                said.append(current.localizedDescription)
                next = current.userInfo[NSUnderlyingErrorKey] as? NSError
            }
            return outOfSpace(said)
        }

        /// The disk is full: something said so, or there's next to nothing left on it.
        private static func outOfSpace(_ output: [String]) -> Bool {
            if output.contains(where: { $0.localizedCaseInsensitiveContains("no space left") || $0.contains("os error 28") }) { return true }
            let home = FileManager.default.homeDirectoryForCurrentUser
            let free = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity
            return free.map { $0 < 200_000_000 } ?? false
        }
    }
}
