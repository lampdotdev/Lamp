import Foundation
import AppKit

/// A picture model that runs on this Mac through mflux (MLX), downloaded from Hugging Face.
struct ImageModelSpec: Identifiable, Hashable {
    let id: String
    let name: String
    let repo: String
    let tool: String        // the mflux command that runs it
    let baseModel: String   // mflux's name for the architecture the weights belong to
    let steps: Int
    let sizeGB: Double
    let minRAMGB: Int
    let blurb: String
}

/// Pictures made on the Mac itself: free, private and offline, through mflux and a model from Hugging Face.
/// mflux is a Python tool, installed with uv like mlx-lm; the weights live in the Hugging Face cache beside
/// the text models, and one picture is made at a time, since each run loads the whole model.
@MainActor
final class ImageModels: ObservableObject {
    static let shared = ImageModels()

    nonisolated static let catalog: [ImageModelSpec] = [
        ImageModelSpec(id: "flux2-klein-4b", name: "FLUX.2 klein 4B", repo: "mflux-community/flux2-klein-4b-mflux-q4",
                       tool: "mflux-generate-flux2", baseModel: "flux2-klein-4b", steps: 4, sizeGB: 4.6, minRAMGB: 16,
                       blurb: "Small and quick. Good pictures for its size; the one to start with."),
        ImageModelSpec(id: "z-image-turbo", name: "Z-Image Turbo", repo: "filipstrand/Z-Image-Turbo-mflux-4bit",
                       tool: "mflux-generate-z-image-turbo", baseModel: "z-image-turbo", steps: 8, sizeGB: 5.9, minRAMGB: 16,
                       blurb: "Sharper, more realistic pictures; a little slower."),
        ImageModelSpec(id: "flux1-schnell", name: "FLUX.1 schnell", repo: "dhairyashil/FLUX.1-schnell-mflux-4bit",
                       tool: "mflux-generate", baseModel: "schnell", steps: 4, sizeGB: 9.6, minRAMGB: 24,
                       blurb: "The original fast FLUX. Big, and needs a lot of memory."),
    ]

    @Published var installing = false        // mflux, through uv
    @Published var installError: String?

    /// The model pictures are made with: the chosen one if it's installed, else the first installed.
    nonisolated static var chosen: ImageModelSpec? {
        let saved = UserDefaults.standard.string(forKey: "localImageModel") ?? ""
        let installed = specs.filter { isInstalled($0) }
        return installed.first { $0.id == saved } ?? installed.first
    }

    var chosen: ImageModelSpec? { Self.chosen }

    func choose(_ spec: ImageModelSpec) {
        UserDefaults.standard.set(spec.id, forKey: "localImageModel")
        objectWillChange.send()
    }

    var installed: [ImageModelSpec] { Self.catalog.filter { Self.isInstalled($0) } }

    /// The repo is in the cache under the revision refs/main names, and is whole: either Forge finished
    /// downloading it (its marker names the revision), or every part a picture model needs is there with
    /// its weights present. A download that stopped halfway leaves a text encoder and no transformer, or
    /// links to blobs that never arrived.
    nonisolated static func isInstalled(_ spec: ImageModelSpec) -> Bool {
        let fm = FileManager.default
        let repoDir = LocalModels.hubDir.appendingPathComponent("models--" + spec.repo.replacingOccurrences(of: "/", with: "--"))
        guard let ref = (try? String(contentsOf: repoDir.appendingPathComponent("refs/main"), encoding: .utf8))?.trimmed else { return false }
        let snapshot = repoDir.appendingPathComponent("snapshots/\(ref)")
        guard fm.fileExists(atPath: snapshot.path) else { return false }
        if (try? String(contentsOf: repoDir.appendingPathComponent("forge-complete"), encoding: .utf8))?.trimmed == ref { return true }

        func present(_ relative: String) -> Bool {
            let target = snapshot.appendingPathComponent(relative).resolvingSymlinksInPath()
            return ((try? target.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) > 0
        }
        guard let all = fm.enumerator(at: snapshot, includingPropertiesForKeys: nil)?.allObjects.compactMap({ $0 as? URL }) else { return false }
        let relative = all.map { $0.path.replacingOccurrences(of: snapshot.path + "/", with: "") }
        // Each part the model is made of, with at least one weights file that's really there.
        for part in ["transformer", "vae", "text_encoder", "tokenizer"] {
            let files = relative.filter { $0.hasPrefix(part + "/") && !$0.hasSuffix(".index.json") }
            guard !files.isEmpty, files.allSatisfy(present) else { return false }
            if part != "tokenizer", !files.contains(where: { $0.hasSuffix(".safetensors") }) { return false }
        }
        // Every shard an index names.
        for index in relative where index.hasSuffix(".safetensors.index.json") {
            guard let data = try? Data(contentsOf: snapshot.appendingPathComponent(index)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let map = json["weight_map"] as? [String: String] else { return false }
            let folder = (index as NSString).deletingLastPathComponent
            for shard in Set(map.values) where !present(folder.isEmpty ? shard : folder + "/" + shard) { return false }
        }
        return true
    }

    nonisolated static var uvPath: String? { ToolLocator.path(named: "uv") }
    nonisolated static func toolPath(_ spec: ImageModelSpec) -> String? { ToolLocator.path(named: spec.tool) }
    nonisolated static var hasMflux: Bool { ToolLocator.path(named: "mflux-generate") != nil }

    /// Ready to make pictures: mflux is installed and so is a model.
    nonisolated static var ready: Bool {
        hasMflux && specs.contains { isInstalled($0) && toolPath($0) != nil }
    }

    /// `catalog`, readable off the main actor.
    nonisolated private static let specs = catalog

    func download(_ spec: ImageModelSpec) {
        LocalModels.shared.download(id: "image:" + spec.id, repo: spec.repo, files: nil) { [weak self] in
            // Forge's own record that the whole repo arrived, for the revision it fetched.
            let repoDir = LocalModels.hubDir.appendingPathComponent("models--" + spec.repo.replacingOccurrences(of: "/", with: "--"))
            if let ref = try? String(contentsOf: repoDir.appendingPathComponent("refs/main"), encoding: .utf8) {
                try? ref.write(to: repoDir.appendingPathComponent("forge-complete"), atomically: true, encoding: .utf8)
            }
            self?.objectWillChange.send()
        }
    }

    func delete(_ spec: ImageModelSpec) {
        let repoDir = LocalModels.hubDir.appendingPathComponent("models--" + spec.repo.replacingOccurrences(of: "/", with: "--"))
        try? FileManager.default.removeItem(at: repoDir)
        objectWillChange.send()
    }

    /// `uv tool install mflux`: a few hundred megabytes of Python packages, a minute or two.
    func installMflux() {
        guard !installing, let uv = Self.uvPath else { return }
        installing = true
        installError = nil
        Task {
            defer { installing = false }
            var output: [String] = []
            let status = await Shell.run("\"\(uv)\" tool install --upgrade mflux", cwd: FileManager.default.temporaryDirectory) { output.append($0) }
            if status != 0 { installError = "mflux didn't install: " + (output.suffix(3).joined(separator: " ").nilIfEmpty ?? "see the log.") }
            objectWillChange.send()
        }
    }

    /// Makes one picture. Runs are queued: each loads the whole model, and two at once would double the
    /// memory. About 10–30 seconds on an M-series Pro, plus the load.
    static func generate(prompt: String, width: Int, height: Int) async throws -> Data {
        guard let spec = chosen, let tool = toolPath(spec) else { throw AppAI.Failure(message: AppAI.noImageRoute) }
        return try await queue.run {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("forge-flux-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let env = ["PATH": ToolLocator.userPath, "HF_HUB_OFFLINE": "1", "FORGE_TOOL": tool, "FORGE_PROMPT": prompt,
                       "FORGE_MODEL": spec.repo, "FORGE_BASE": spec.baseModel]
            let command = """
            "$FORGE_TOOL" --model "$FORGE_MODEL" --base-model "$FORGE_BASE" --prompt "$FORGE_PROMPT" \\
              --steps \(spec.steps) --width \(width) --height \(height) --seed \(Int.random(in: 1...1_000_000)) --output image.png
            """
            var lines: [String] = []
            let status = await Shell.run(command, cwd: folder, env: env) { lines.append($0) }
            guard status == 0, let data = try? Data(contentsOf: folder.appendingPathComponent("image.png")), NSImage(data: data) != nil else {
                let detail = lines.last { !$0.trimmed.isEmpty && !$0.contains("%") } ?? "no output"
                throw AppAI.Failure(message: "\(spec.name) couldn't make the picture: \(detail)")
            }
            return data
        }
    }

    private static let queue = SerialQueue()
}

/// One job at a time, in order.
actor SerialQueue {
    private var last: Task<Void, Never>?

    func run<T: Sendable>(_ job: @Sendable @escaping () async throws -> T) async throws -> T {
        let previous = last
        let task = Task<T, Error> {
            await previous?.value
            return try await job()
        }
        last = Task { _ = try? await task.value }
        return try await task.value
    }
}
