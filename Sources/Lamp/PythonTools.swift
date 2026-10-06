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
            if status != 0 {
                throw Failure(message: "It didn't install: " + (output.suffix(3).joined(separator: " ").nilIfEmpty ?? "no reason was given.")
                              + " Check your internet connection and try again.")
            }
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
        let failure = Failure(message: "Lamp couldn't download what it needs to install this. Check your internet connection and try again.")
        guard let (archive, response) = try? await URLSession.shared.download(from: URL(string: release)!),
              (response as? HTTPURLResponse)?.statusCode == 200 else { throw failure }
        defer { try? FileManager.default.removeItem(at: archive) }
        // The release publishes each archive's checksum beside it: a download cut short doesn't get run.
        guard let (sum, _) = try? await URLSession.shared.data(from: URL(string: release + ".sha256")!),
              let expected = String(data: sum, encoding: .utf8)?.split(separator: " ").first,
              let data = try? Data(contentsOf: archive),
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected else { throw failure }

        // Unpacked beside its final place and moved in only when whole: an unpacking cut short (a full disk,
        // say) would otherwise leave half a uv there, and every later try would run that instead of fetching it again.
        let folder = ownUV.deletingLastPathComponent()
        let scratch = folder.appendingPathComponent("unpacking-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        guard (try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)) != nil else { throw failure }
        let status = await Shell.run(#"/usr/bin/tar -xzf "$LAMP_ARCHIVE" -C "$LAMP_FOLDER" --strip-components 1"#, cwd: scratch,
                                     env: ["LAMP_ARCHIVE": archive.path, "LAMP_FOLDER": scratch.path]) { _ in }
        let unpacked = scratch.appendingPathComponent("uv")
        guard status == 0, FileManager.default.isExecutableFile(atPath: unpacked.path) else { throw failure }
        try? FileManager.default.removeItem(at: ownUV)
        guard (try? FileManager.default.moveItem(at: unpacked, to: ownUV)) != nil else { throw failure }
        return ownUV.path
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
