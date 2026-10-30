import Foundation
import AppKit

/// A downloadable model (GGUF from Hugging Face).
struct LocalModelSpec: Identifiable, Hashable {
    let id: String
    let name: String
    let repo: String
    let files: [String]     // model file(s), plus an optional mmproj for image input
    let sizeGB: Double
    let minRAMGB: Int
    let blurb: String
}

/// A model on disk that Lamp can run.
struct InstalledModel: Identifiable, Hashable {
    enum Format: String { case gguf, mlx }

    let id: String          // what pi and the server call it
    let name: String
    let repo: String        // "org/name", or "" if unknown
    let format: Format
    let source: String      // "Hugging Face cache", "Local", "Lamp"
    let files: [URL]        // GGUF: model file(s) + optional mmproj. MLX: the model folder.
    let bytes: Int64
    let vision: Bool
    let deletable: Bool     // Lamp only deletes GGUF models it can see in the shared cache
}

/// Models that run on this Mac. Downloads go into the shared Hugging Face cache
/// (~/.cache/huggingface/hub, the same layout the `hf` CLI and Local use), and Lamp also picks up models
/// already there or in Local's folder:
/// - GGUF models run on llama.cpp's server (router mode on 127.0.0.1:47812), which gets a folder of symlinks into
///   the cache, so nothing is copied. The server isn't in Lamp's bundle: it's fetched the first time a GGUF model is
///   downloaded or picked (`LlamaInstall`), with the model's own progress, or on its own (`getServer`).
/// - MLX models (e.g. ones downloaded for Local) run on `mlx_lm.server` (127.0.0.1:47813) when it's installed.
/// pi reaches both through providers Lamp writes into its `models.json`.
@MainActor
final class LocalModels: ObservableObject {
    static let shared = LocalModels()

    nonisolated static let port = Edition.localModelPort
    nonisolated static let mlxPort = Edition.mlxPort
    nonisolated static let contextSize = 32768
    nonisolated static let mlxProvider = "forge-mlx"

    nonisolated static let hubDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface/hub")
    nonisolated static let localAppDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/LocalAssistant/Models")
    /// Older Lamp builds downloaded here; still read.
    nonisolated static let legacyDir = Edition.supportFolder.appendingPathComponent("Models")
    /// Symlinks for llama-server's router: one folder per GGUF model.
    nonisolated static let routerDir = Edition.supportFolder.appendingPathComponent("Router")

    /// Decision models that run on this Mac: Jev-class (state and a question in, a typed answer out, one
    /// forward pass), scored by Lamp off the label tokens the way their serving shim does. Kept apart from
    /// the text models: they can't write anything.
    nonisolated static let decisionCatalog: [LocalModelSpec] = [
        LocalModelSpec(id: "h2o-lightning-4b", name: "H2O Lightning 4B", repo: "mradermacher/h2o-lightning-4b-GGUF",
                       files: ["h2o-lightning-4b.Q4_K_M.gguf"], sizeGB: 2.5, minRAMGB: 8,
                       blurb: "Decisions on this Mac: free, private, and about as good as Jev."),
    ]

    /// Whether an installed model is one of the decision models, so it isn't offered for text or building.
    nonisolated static func isDecisionModel(_ id: String) -> Bool {
        decisionCatalog.contains { spec in id == spec.id || id == slug(spec.name) || id.hasPrefix(slug(spec.id)) }
    }

    static let catalog: [LocalModelSpec] = [
        LocalModelSpec(id: "qwen3.6-35b-a3b", name: "Qwen3.6 35B-A3B", repo: "unsloth/Qwen3.6-35B-A3B-GGUF",
                       files: ["Qwen3.6-35B-A3B-UD-Q4_K_M.gguf", "mmproj-F16.gguf"], sizeGB: 23.0, minRAMGB: 48,
                       blurb: "Best local option. Fast for its size, and can see screenshots."),
        LocalModelSpec(id: "qwen3.8-27b", name: "Qwen3.8 27B", repo: "unsloth/Qwen3.8-27B-GGUF",
                       files: ["Qwen3.8-27B-UD-Q4_K_M.gguf", "mmproj-F16.gguf"], sizeGB: 17.4, minRAMGB: 32,
                       blurb: "Strong and careful, but slower. Can see screenshots."),
        LocalModelSpec(id: "qwen3.5-9b", name: "Qwen3.5 9B", repo: "unsloth/Qwen3.5-9B-GGUF",
                       files: ["Qwen3.5-9B-Q4_K_M.gguf", "mmproj-F16.gguf"], sizeGB: 6.6, minRAMGB: 16,
                       blurb: "Good for small apps on 16 GB Macs."),
        LocalModelSpec(id: "qwen3.5-4b", name: "Qwen3.5 4B", repo: "unsloth/Qwen3.5-4B-GGUF",
                       files: ["Qwen3.5-4B-Q4_K_M.gguf", "mmproj-F16.gguf"], sizeGB: 3.4, minRAMGB: 8,
                       blurb: "Fast and small. Fine for simple changes, struggles with whole apps."),
    ]

    static var ramGB: Int { Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) }

    @Published var installed: [InstalledModel] = LocalModels.scan()
    @Published var progress: [String: Double] = [:]          // catalog/spec id → 0…1 while downloading
    @Published var errors: [String: String] = [:]
    @Published var serverRunning = false
    /// llama.cpp's server is on this Mac (`LlamaInstall`). Fetching it on its own shows under `serverID`.
    @Published private(set) var serverInstalled = LlamaInstall.isInstalled
    static let serverID = "llama-server"
    @Published var mlxModel: String?                         // the model mlx_lm.server is serving

    private var server: Process?
    private var mlxServer: Process?
    private var downloads: [String: Task<Void, Never>] = [:]

    init() {
        // A newer Lamp that pins another build of the server fetches it for someone who has used local models.
        if LlamaInstall.hasOlder { getServer() }
    }

    /// Fetches llama.cpp's server on its own, with progress and errors under `serverID`: for a GGUF model that came
    /// from elsewhere (another app's download), picked to run here.
    func getServer() {
        guard !LlamaInstall.isInstalled, downloads[Self.serverID] == nil else { return }
        errors[Self.serverID] = nil
        progress[Self.serverID] = 0
        downloads[Self.serverID] = Task {
            defer { downloads[Self.serverID] = nil; progress[Self.serverID] = nil }
            do { try await installServer(as: Self.serverID) } catch is CancellationError {
            } catch {
                errors[Self.serverID] = error.localizedDescription
            }
        }
    }

    /// The server's fetch, reporting into `progress[id]` over its first `share`, for a model downloaded with it. One
    /// fetch at a time, which every caller (a pick, a model's download, a request) waits on, each seeing its progress:
    /// two at once would put the same folder in place over each other.
    private func installServer(as id: String, share: Double = 1) async throws {
        serverWatchers[id] = share
        defer { serverWatchers[id] = nil }
        let install = serverInstall ?? Task { [weak self] in
            try await LlamaInstall.install { fraction in
                Task { @MainActor in
                    guard let self else { return }
                    for (id, share) in self.serverWatchers { self.progress[id] = fraction * share }
                }
            }
        }
        serverInstall = install
        // Done with either way, so a try after a failure fetches afresh.
        defer { if serverInstall == install { serverInstall = nil } }
        try await install.value
        serverInstalled = LlamaInstall.isInstalled
    }
    private var serverInstall: Task<Void, Error>?
    /// Who waits on the server's fetch, with the share of their progress it fills.
    private var serverWatchers: [String: Double] = [:]

    // MARK: Finding models

    nonisolated static func installedIDs() -> [String] { scan().map(\.id) }

    nonisolated static func model(_ id: String) -> InstalledModel? { scan().first { $0.id == id } }

    nonisolated static func hasVision(_ id: String) -> Bool { model(id)?.vision ?? false }

    /// The pi provider for a local model: llama.cpp for GGUF, mlx_lm for MLX.
    nonisolated static func piProvider(for id: String) -> String {
        model(id)?.format == .mlx ? mlxProvider : Builder.localProvider
    }

    /// `mlx_lm.server`, if installed (`PythonTools` installs it from Settings).
    nonisolated static var mlxServerPath: String? { ToolLocator.path(named: "mlx_lm.server") }

    /// The tool-call parser mlx-lm picks for the MLX model in this folder, read as mlx-lm 0.30.4 reads it
    /// (`_infer_tool_parser` in its tokenizer_utils.py): the model's own `tool_parser_type`, else marks in its chat
    /// template. Nil when it has none. Later versions recognize more templates; a model only they know is asked for
    /// the JSON plan instead, which every model can give.
    nonisolated static func mlxToolParser(in folder: URL) -> String? {
        let config = (try? JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("tokenizer_config.json")))) as? [String: Any] ?? [:]
        if let named = config["tool_parser_type"] as? String, !named.isEmpty { return named }
        // Where transformers finds the template: its own file, else tokenizer_config.json, as text or as named
        // templates of which "default" is the one used.
        var template = try? String(contentsOf: folder.appendingPathComponent("chat_template.jinja"), encoding: .utf8)
        if template == nil {
            if let text = config["chat_template"] as? String { template = text }
            else if let named = config["chat_template"] as? [[String: Any]] {
                template = named.first { $0["name"] as? String == "default" }?["template"] as? String
            }
        }
        guard let template else { return nil }
        if template.contains("<minimax:tool_call>") { return "minimax_m2" }
        if template.contains("<start_function_call>") { return "function_gemma" }
        if template.contains("<arg_key>") { return "glm47" }
        if template.contains("<tool_call>\n<function=") { return "qwen3_coder" }
        if template.contains("<tool_call>"), template.contains("tool_call.name") { return "json_tools" }
        return nil
    }

    /// The mlx-lm version behind `mlx_lm.server`, read off the package in the environment uv installed it into
    /// (`bin/mlx_lm.server` beside `lib/python3.x/site-packages/mlx_lm-<version>.dist-info`); nil when it can't tell.
    nonisolated static var mlxVersion: String? {
        guard let path = mlxServerPath else { return nil }
        let env = URL(fileURLWithPath: path).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let lib = env.appendingPathComponent("lib")
        let fm = FileManager.default
        for python in (try? fm.contentsOfDirectory(atPath: lib.path)) ?? [] where python.hasPrefix("python") {
            let packages = lib.appendingPathComponent(python).appendingPathComponent("site-packages")
            for name in (try? fm.contentsOfDirectory(atPath: packages.path)) ?? [] where name.hasPrefix("mlx_lm-") && name.hasSuffix(".dist-info") {
                return String(name.dropFirst("mlx_lm-".count).dropLast(".dist-info".count))
            }
        }
        return nil
    }

    /// Every runnable model in the Hugging Face cache, Local's folder and Lamp's old folder.
    nonisolated static func scan() -> [InstalledModel] {
        let fm = FileManager.default
        var models: [InstalledModel] = []
        var ids = Set<String>()
        func add(_ model: InstalledModel) { if ids.insert(model.id).inserted { models.append(model) } }

        // Hugging Face cache: models--org--name/snapshots/<rev>/ (refs/main names the current revision).
        for repoDir in (try? fm.contentsOfDirectory(at: hubDir, includingPropertiesForKeys: nil)) ?? []
        where repoDir.lastPathComponent.hasPrefix("models--") {
            let repo = repoDir.lastPathComponent.dropFirst("models--".count).replacingOccurrences(of: "--", with: "/")
            let snapshots = repoDir.appendingPathComponent("snapshots")
            let ref = (try? String(contentsOf: repoDir.appendingPathComponent("refs/main"), encoding: .utf8))?.trimmed
            let revisions = ((try? fm.contentsOfDirectory(atPath: snapshots.path)) ?? []).sorted { a, b in a == ref || (b != ref && a < b) }
            guard let revision = revisions.first else { continue }
            for model in runnable(in: snapshots.appendingPathComponent(revision), repo: repo, source: "Hugging Face cache", deletable: true) {
                add(model)
            }
        }
        // Local's own downloads: LocalAssistant/Models/org--name/ (complete when .download-complete exists).
        for dir in (try? fm.contentsOfDirectory(at: localAppDir, includingPropertiesForKeys: nil)) ?? []
        where fm.fileExists(atPath: dir.appendingPathComponent(".download-complete").path) {
            let repo = dir.lastPathComponent.replacingOccurrences(of: "--", with: "/")
            for model in runnable(in: dir, repo: repo, source: "Local", deletable: false) { add(model) }
        }
        // Lamp's older download folder.
        for dir in (try? fm.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil)) ?? []
        where fm.fileExists(atPath: dir.appendingPathComponent(".complete").path) {
            for model in runnable(in: dir, repo: "", source: "Lamp", deletable: false, preferredID: dir.lastPathComponent) { add(model) }
        }
        return models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The runnable models in one folder: each GGUF quant (shards grouped, with an mmproj if present),
    /// or the folder itself if it's an MLX model.
    private nonisolated static func runnable(in dir: URL, repo: String, source: String, deletable: Bool,
                                           preferredID: String? = nil) -> [InstalledModel] {
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        func size(_ name: String) -> Int64 {
            let url = dir.appendingPathComponent(name).resolvingSymlinksInPath()
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        let repoName = repo.split(separator: "/").last.map(String.init) ?? dir.lastPathComponent
        let ggufs = names.filter { $0.hasSuffix(".gguf") && !$0.lowercased().hasPrefix("mmproj") }
        if !ggufs.isEmpty {
            let mmproj = names.first { $0.lowercased().hasPrefix("mmproj") && $0.contains("F16") && !$0.contains("BF16") }
                ?? names.first { $0.lowercased().hasPrefix("mmproj") }
            let shard = #"-\d{5}-of-\d{5}\.gguf$"#
            var groups: [String: [String]] = [:]
            for file in ggufs {
                let key = file.range(of: shard, options: .regularExpression).map { String(file[..<$0.lowerBound]) }
                    ?? String(file.dropLast(5))
                groups[key, default: []].append(file)
            }
            let base = repoName.replacingOccurrences(of: "-GGUF", with: "").replacingOccurrences(of: "-gguf", with: "")
            return groups.keys.sorted().map { key in
                var files = groups[key]!.sorted()
                if let mmproj { files.append(mmproj) }
                let quant = groups.count > 1 ? "-" + (key.split(separator: "-").last.map(String.init) ?? key) : ""
                let id = preferredID ?? Self.slug(base + quant)
                return InstalledModel(id: id, name: base + quant.replacingOccurrences(of: "-", with: " "), repo: repo,
                                      format: .gguf, source: source, files: files.map { dir.appendingPathComponent($0) },
                                      bytes: files.reduce(0) { $0 + size($1) }, vision: mmproj != nil, deletable: deletable)
            }
        }
        // MLX: a config.json with quantization (or an mlx-community repo) plus safetensors weights.
        if names.contains("config.json"), names.contains(where: { $0.hasSuffix(".safetensors") }) {
            let config = (try? JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("config.json")))) as? [String: Any]
            let isMLX = repo.lowercased().hasPrefix("mlx-community/") || repo.lowercased().contains("mlx")
                || config?["quantization"] != nil
            guard isMLX else { return [] }
            let bytes = names.filter { $0.hasSuffix(".safetensors") }.reduce(0) { $0 + size($1) }
            // In the HF cache, mlx_lm finds the model by repo id; elsewhere it needs the folder path.
            let id = source == "Hugging Face cache" ? repo : dir.path
            return [InstalledModel(id: id, name: repoName, repo: repo, format: .mlx, source: source, files: [dir],
                                   bytes: bytes, vision: config?["vision_config"] != nil, deletable: false)]
        }
        return []
    }

    private nonisolated static func slug(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber || ".-_".contains($0) }
    }

    func refresh() {
        installed = Self.scan()
        rebuildRouter()
        writePiModels()
    }

    /// llama-server's models folder: one subfolder per GGUF model, symlinking the real files.
    private func rebuildRouter() {
        let fm = FileManager.default
        try? fm.removeItem(at: Self.routerDir)
        try? fm.createDirectory(at: Self.routerDir, withIntermediateDirectories: true)
        for model in installed where model.format == .gguf {
            let dir = Self.routerDir.appendingPathComponent(model.id)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for file in model.files {
                try? fm.createSymbolicLink(at: dir.appendingPathComponent(file.lastPathComponent),
                                           withDestinationURL: file.resolvingSymlinksInPath())
            }
        }
    }

    /// Deletes a GGUF model's files from the Hugging Face cache (blobs only if nothing else uses them).
    func delete(_ id: String) {
        guard let model = installed.first(where: { $0.id == id }), model.deletable else { return }
        let fm = FileManager.default
        for file in model.files {
            let blob = file.resolvingSymlinksInPath()
            try? fm.removeItem(at: file)
            try? fm.removeItem(at: blob)
        }
        // Remove the repo folder if no model files are left in it.
        if let repoDir = model.files.first?.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
           repoDir.lastPathComponent.hasPrefix("models--") {
            let left = fm.enumerator(at: repoDir.appendingPathComponent("snapshots"), includingPropertiesForKeys: nil)?
                .allObjects.compactMap { $0 as? URL }.filter { $0.pathExtension == "gguf" || $0.pathExtension == "safetensors" } ?? []
            if left.isEmpty { try? fm.removeItem(at: repoDir) }
        }
        refresh()
        restartServerIfRunning()
    }

    /// Whether a catalog entry is already on disk (in any of the places Lamp looks).
    func isInstalled(_ spec: LocalModelSpec) -> Bool {
        guard let file = spec.files.first else { return false }
        return installed.contains { model in model.repo == spec.repo && model.files.contains { $0.lastPathComponent == file } }
            || installed.contains { $0.id == spec.id && $0.format == .gguf }
    }

    func installedID(for spec: LocalModelSpec) -> String? {
        guard let file = spec.files.first else { return nil }
        return installed.first { model in model.repo == spec.repo && model.files.contains { $0.lastPathComponent == file } }?.id
    }

    // MARK: Downloads (into the Hugging Face cache layout)

    func download(_ spec: LocalModelSpec) {
        download(id: spec.id, repo: spec.repo, files: spec.files, withServer: spec.files.contains { $0.hasSuffix(".gguf") },
                 sizeGB: spec.sizeGB) { [weak self] in
            self?.refresh()
            self?.restartServerIfRunning()
        }
    }

    /// Downloads `files` from a repo (every file when nil) into the Hugging Face cache, with progress and
    /// errors under `id`. Image models use this too; `done` runs after a complete download. A GGUF model brings
    /// llama.cpp's server with it the first time (`withServer`), in the same progress, by its share of the bytes.
    func download(id: String, repo: String, files: [String]?, withServer: Bool = false, sizeGB: Double = 0,
                  done: @escaping @MainActor () -> Void = {}) {
        guard downloads[id] == nil else { return }
        errors[id] = nil
        progress[id] = 0
        downloads[id] = Task {
            defer { downloads[id] = nil; progress[id] = nil }
            do {
                var share = 0.0
                if withServer, !LlamaInstall.isInstalled, let size = LlamaInstall.pin?.asset.size {
                    share = Double(size) / (Double(size) + max(sizeGB * 1e9, 1))
                    try await installServer(as: id, share: share)
                }
                try await fetch(id: id, repo: repo, files: files, after: share)
                done()
            } catch is CancellationError {
            } catch {
                errors[id] = error.localizedDescription
            }
        }
    }

    func cancel(_ id: String) { downloads[id]?.cancel() }

    /// Writes blobs/<sha256>, snapshots/<commit>/<file> → ../../blobs/<sha256> and refs/main,
    /// exactly as huggingface_hub does, so other tools reuse the download.
    private func fetch(id: String, repo: String, files wanted: [String]?, after share: Double = 0) async throws {
        let fm = FileManager.default
        let (commit, tree) = try await Self.repoInfo(repo)
        let files = wanted ?? tree.keys.sorted()
        let repoDir = Self.hubDir.appendingPathComponent("models--" + repo.replacingOccurrences(of: "/", with: "--"))
        let blobs = repoDir.appendingPathComponent("blobs")
        let snapshot = repoDir.appendingPathComponent("snapshots/\(commit)")
        try fm.createDirectory(at: blobs, withIntermediateDirectories: true)
        try fm.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try fm.createDirectory(at: repoDir.appendingPathComponent("refs"), withIntermediateDirectories: true)

        let total = files.reduce(0) { $0 + (tree[$1]?.size ?? 0) }
        let free = (try? Self.hubDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? .max
        if Int64(total) + 2_000_000_000 > free {
            throw LocalError("Not enough disk space: this model needs \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)).")
        }

        var done = 0
        for file in files {
            guard let entry = tree[file] else { throw LocalError("\(file) isn't in \(repo).") }
            let blob = blobs.appendingPathComponent(entry.oid)
            if (try? blob.resourceValues(forKeys: [.fileSizeKey]))?.fileSize != entry.size {
                let url = URL(string: "https://huggingface.co/\(repo)/resolve/\(commit)/\(file)")!
                let base = done
                let tracker = DownloadProgress { [weak self] written in
                    guard total > 0 else { return }
                    Task { @MainActor in self?.progress[id] = share + (1 - share) * Double(base + Int(written)) / Double(total) }
                }
                let (temp, response) = try await URLSession.shared.download(from: url, delegate: tracker)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw LocalError("Hugging Face returned an error for \(file).")
                }
                try? fm.removeItem(at: blob)
                try fm.moveItem(at: temp, to: blob)
            }
            let link = snapshot.appendingPathComponent(file)
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: link)
            let depth = file.split(separator: "/").count   // blobs are ../../blobs from a top-level file
            try fm.createSymbolicLink(atPath: link.path,
                                      withDestinationPath: String(repeating: "../", count: depth + 1) + "blobs/" + entry.oid)
            done += entry.size
        }
        try commit.write(to: repoDir.appendingPathComponent("refs/main"), atomically: true, encoding: .utf8)
    }

    /// Picks a model from any Hugging Face GGUF repo ("owner/repo" or its URL): the Q4_K_M file
    /// (or the smallest Q4), all of its shards, and an F16 vision projector if there is one.
    func spec(forRepo input: String) async throws -> LocalModelSpec {
        var repo = input.trimmed
        if let range = repo.range(of: "huggingface.co/") { repo = String(repo[range.upperBound...]) }
        repo = repo.split(separator: "/").prefix(2).joined(separator: "/")
        guard repo.contains("/") else { throw LocalError("Enter a Hugging Face repo like owner/Model-GGUF.") }
        let tree = try await Self.repoInfo(repo).1
        let sizes = tree.mapValues(\.size)
        let ggufs = sizes.keys.filter { $0.hasSuffix(".gguf") && !$0.lowercased().contains("mmproj") }.sorted()
        guard !ggufs.isEmpty else { throw LocalError("That repo has no GGUF files. Look for a repo ending in -GGUF.") }
        let pick = ggufs.first { $0.contains("Q4_K_M") }
            ?? ggufs.filter { $0.contains("Q4") }.min { sizes[$0]! < sizes[$1]! }
            ?? ggufs.min { sizes[$0]! < sizes[$1]! }!
        var files = [pick]
        if let shard = pick.range(of: #"-\d{5}-of-\d{5}\.gguf$"#, options: .regularExpression) {
            let prefix = String(pick[..<shard.lowerBound])
            files = ggufs.filter { $0.hasPrefix(prefix) && $0.range(of: #"-\d{5}-of-\d{5}\.gguf$"#, options: .regularExpression) != nil }
        }
        if let mmproj = sizes.keys.first(where: { $0.lowercased().hasPrefix("mmproj") && $0.contains("F16") && !$0.contains("BF16") })
            ?? sizes.keys.first(where: { $0.lowercased().hasPrefix("mmproj") }) {
            files.append(mmproj)
        }
        let bytes = files.reduce(0) { $0 + (sizes[$1] ?? 0) }
        let name = repo.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "-GGUF", with: "") ?? repo
        return LocalModelSpec(id: Self.slug(name), name: name, repo: repo, files: files, sizeGB: Double(bytes) / 1e9,
                              minRAMGB: Int((Double(bytes) / 1e9 * 1.4).rounded(.up)), blurb: "From \(repo)")
    }

    /// The repo's current commit and its files (size, and the blob id the cache stores them under).
    static func repoInfo(_ repo: String) async throws -> (String, [String: (size: Int, oid: String)]) {
        let infoURL = URL(string: "https://huggingface.co/api/models/\(repo)")!
        let treeURL = URL(string: "https://huggingface.co/api/models/\(repo)/tree/main?recursive=true")!
        let (infoData, infoResponse) = try await URLSession.shared.data(from: infoURL)
        let (treeData, _) = try await URLSession.shared.data(from: treeURL)
        guard (infoResponse as? HTTPURLResponse)?.statusCode == 200,
              let info = try JSONSerialization.jsonObject(with: infoData) as? [String: Any],
              let commit = info["sha"] as? String,
              let items = try JSONSerialization.jsonObject(with: treeData) as? [[String: Any]] else {
            throw LocalError("Couldn't find \(repo) on Hugging Face.")
        }
        var tree: [String: (size: Int, oid: String)] = [:]
        for item in items where item["type"] as? String == "file" {
            guard let path = item["path"] as? String else { continue }
            let lfs = item["lfs"] as? [String: Any]
            // LFS files are stored under their sha256; small files under their git blob id.
            tree[path] = (lfs?["size"] as? Int ?? item["size"] as? Int ?? 0,
                          lfs?["oid"] as? String ?? item["oid"] as? String ?? UUID().uuidString)
        }
        return (commit, tree)
    }

    // MARK: Servers

    /// llama.cpp's server, once it's on this Mac (`LlamaInstall`).
    nonisolated static var serverBinary: URL? { LlamaInstall.isInstalled ? LlamaInstall.server : nil }

    nonisolated static var baseURL: String { "http://127.0.0.1:\(port)" }
    nonisolated static var mlxBaseURL: String { "http://127.0.0.1:\(mlxPort)" }

    /// Starts whichever server runs this model, waits until it answers, and returns its base URL.
    @discardableResult
    func ensureServer(for id: String) async throws -> String {
        if Self.model(id)?.format == .mlx {
            try await ensureMLX(id)
            return Self.mlxBaseURL
        }
        try await ensureLlama()
        return Self.baseURL
    }

    private func logFile(_ name: String) -> FileHandle? {
        let logs = Edition.logsFolder
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appendingPathComponent(name)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        return try? FileHandle(forWritingTo: log)
    }

    private func ensureLlama() async throws {
        if await Self.healthy("\(Self.baseURL)/health") { serverRunning = true; return }
        // Fetched the first time a model needs it, as when one is picked; checked as Lamp's own each time it starts.
        if Self.serverBinary == nil {
            do { try await installServer(as: Self.serverID) } catch {
                errors[Self.serverID] = error.localizedDescription
                throw LocalError("Lamp couldn't get what runs models on this Mac. \(error.localizedDescription)")
            }
        }
        guard let binary = Self.serverBinary, let folder = LlamaInstall.folder, LlamaInstall.verified(folder) else {
            if let folder = LlamaInstall.folder { try? FileManager.default.removeItem(at: folder) }
            serverInstalled = false
            throw LocalError("What runs models on this Mac wasn't right, so Lamp removed it. Try again to download it afresh.")
        }
        rebuildRouter()
        let process = Process()
        process.executableURL = binary
        process.arguments = ["--models-dir", Self.routerDir.path, "--jinja", "--host", "127.0.0.1",
                             "--port", String(Self.port), "-ngl", "999", "-c", String(Self.contextSize)]
        process.standardOutput = logFile("llama-server.log")
        process.standardError = process.standardOutput
        process.standardInput = FileHandle.nullDevice
        try process.run()
        server = process
        for _ in 0..<60 {
            if await Self.healthy("\(Self.baseURL)/health") { serverRunning = true; return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw LocalError("The local model server didn't start. See llama-server.log in \(Edition.logsFolder.path).")
    }

    /// mlx_lm.server serves one model; switching models restarts it.
    private func ensureMLX(_ id: String) async throws {
        if mlxModel == id, await Self.healthy("\(Self.mlxBaseURL)/v1/models") { return }
        guard let path = Self.mlxServerPath else {
            throw LocalError("This model needs a one-time install before it can run. In Lamp, open Settings → AI Providers, double-click Native Mac AI and click Install beside the model, then try again.")
        }
        stopMLX()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--model", id, "--host", "127.0.0.1", "--port", String(Self.mlxPort)]
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_OFFLINE"] = "1"   // it's already in the cache; don't check for updates
        env["PATH"] = ToolLocator.userPath
        process.environment = env
        process.standardOutput = logFile("mlx-server.log")
        process.standardError = process.standardOutput
        process.standardInput = FileHandle.nullDevice
        try process.run()
        mlxServer = process
        for _ in 0..<240 {   // loading a large model can take a while
            if !process.isRunning { break }
            if await Self.healthy("\(Self.mlxBaseURL)/v1/models") { mlxModel = id; return }
            try await Task.sleep(for: .milliseconds(500))
        }
        stopMLX()
        throw LocalError("The MLX server didn't start. See mlx-server.log in \(Edition.logsFolder.path).")
    }

    private func stopMLX() {
        mlxServer?.terminate()
        mlxServer = nil
        mlxModel = nil
    }

    func stopServer() {
        server?.terminate()
        server = nil
        serverRunning = false
        stopMLX()
    }

    private func restartServerIfRunning() {
        guard server != nil else { return }   // only restart one Lamp started; it rescans the router folder
        server?.terminate()
        server = nil
        serverRunning = false
        Task { try? await ensureLlama() }
    }

    nonisolated static func healthy(_ url: String) async -> Bool {
        var request = URLRequest(url: URL(string: url)!)
        request.timeoutInterval = 1
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Registers local models with Lamp's pi through `models.json` (OpenAI-compatible endpoints).
    func writePiModels() {
        var providers: [String: Any] = [:]
        let gguf = installed.filter { $0.format == .gguf }
        if !gguf.isEmpty {
            providers[Builder.localProvider] = [
                "baseUrl": "\(Self.baseURL)/v1", "api": "openai-completions", "apiKey": "local",
                "models": gguf.map { ["id": $0.id, "contextWindow": Self.contextSize,
                                      "input": $0.vision ? ["text", "image"] : ["text"]] as [String: Any] },
            ]
        }
        let mlx = installed.filter { $0.format == .mlx }
        if !mlx.isEmpty {
            providers[Self.mlxProvider] = [
                "baseUrl": "\(Self.mlxBaseURL)/v1", "api": "openai-completions", "apiKey": "local",
                "models": mlx.map { ["id": $0.id, "contextWindow": 65536, "input": ["text"]] as [String: Any] },
            ]
        }
        let dir = URL(fileURLWithPath: Agent.configDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: ["providers": providers], options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("models.json"))
        }
    }

    struct LocalError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

