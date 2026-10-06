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
/// - GGUF models run on the bundled llama.cpp server (router mode on 127.0.0.1:47812), which gets a folder
///   of symlinks into the cache, so nothing is copied.
/// - MLX models (e.g. ones downloaded for Local) run on `mlx_lm.server` (127.0.0.1:47813) when it's installed.
/// pi reaches both, plus any running Ollama / LM Studio, through providers Lamp writes into its `models.json`.
@MainActor
final class LocalModels: ObservableObject {
    static let shared = LocalModels()

    nonisolated static let port = 47812
    nonisolated static let mlxPort = 47813
    nonisolated static let contextSize = 32768
    nonisolated static let mlxProvider = "forge-mlx"

    nonisolated static let hubDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface/hub")
    nonisolated static let localAppDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/LocalAssistant/Models")
    /// Older Lamp builds downloaded here; still read.
    nonisolated static let legacyDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Lamp/Models")
    /// Symlinks for llama-server's router: one folder per GGUF model.
    nonisolated static let routerDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Lamp/Router")

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
    @Published var mlxModel: String?                         // the model mlx_lm.server is serving
    @Published var external: [String: [String]] = [:]       // "ext-ollama" → model ids

    private var server: Process?
    private var mlxServer: Process?
    private var downloads: [String: Task<Void, Never>] = [:]

    // MARK: Finding models

    nonisolated static func installedIDs() -> [String] { scan().map(\.id) }

    nonisolated static func model(_ id: String) -> InstalledModel? { scan().first { $0.id == id } }

    nonisolated static func hasVision(_ id: String) -> Bool { model(id)?.vision ?? false }

    /// The pi provider for a local model: llama.cpp for GGUF, mlx_lm for MLX.
    nonisolated static func piProvider(for id: String) -> String {
        model(id)?.format == .mlx ? mlxProvider : Builder.localProvider
    }

    /// Model servers Lamp looks for: Ollama and LM Studio.
    nonisolated static let externalIDs = ["ext-lmstudio", "ext-ollama"]   // alphabetical by name

    nonisolated static func externalName(_ id: String) -> String {
        id == "ext-ollama" ? "Ollama" : id == "ext-lmstudio" ? "LM Studio" : id
    }

    /// `mlx_lm.server`, if installed (e.g. `uv tool install mlx-lm`).
    nonisolated static var mlxServerPath: String? { ToolLocator.path(named: "mlx_lm.server") }

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
        download(id: spec.id, repo: spec.repo, files: spec.files) { [weak self] in
            self?.refresh()
            self?.restartServerIfRunning()
        }
    }

    /// Downloads `files` from a repo (every file when nil) into the Hugging Face cache, with progress and
    /// errors under `id`. Image models use this too; `done` runs after a complete download.
    func download(id: String, repo: String, files: [String]?, done: @escaping @MainActor () -> Void = {}) {
        guard downloads[id] == nil else { return }
        errors[id] = nil
        progress[id] = 0
        downloads[id] = Task {
            defer { downloads[id] = nil; progress[id] = nil }
            do {
                try await fetch(id: id, repo: repo, files: files)
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
    private func fetch(id: String, repo: String, files wanted: [String]?) async throws {
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
                let tracker = ProgressTracker { [weak self] written in
                    guard total > 0 else { return }
                    Task { @MainActor in self?.progress[id] = Double(base + Int(written)) / Double(total) }
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

    nonisolated static var serverBinary: URL? {
        let url = Bundle.main.resourceURL?.appendingPathComponent("llama/llama-server")
        return url.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
    }

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
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Lamp")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appendingPathComponent(name)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        return try? FileHandle(forWritingTo: log)
    }

    private func ensureLlama() async throws {
        if await Self.healthy("\(Self.baseURL)/health") { serverRunning = true; return }
        guard let binary = Self.serverBinary else { throw LocalError("Lamp's local model server is missing. Download Lamp again.") }
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
        throw LocalError("The local model server didn't start. See ~/Library/Logs/Lamp/llama-server.log.")
    }

    /// mlx_lm.server serves one model; switching models restarts it.
    private func ensureMLX(_ id: String) async throws {
        if mlxModel == id, await Self.healthy("\(Self.mlxBaseURL)/v1/models") { return }
        guard let path = Self.mlxServerPath else {
            throw LocalError("MLX models need mlx-lm. Install it with `uv tool install mlx-lm` (or `pip install mlx-lm`), then try again.")
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
        throw LocalError("The MLX server didn't start. See ~/Library/Logs/Lamp/mlx-server.log.")
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

    // MARK: Ollama and LM Studio

    /// Looks for Ollama (port 11434) and LM Studio (port 1234) and lists their models.
    func detectExternal() async {
        var found: [String: [String]] = [:]
        for (id, port) in [("ext-ollama", 11434), ("ext-lmstudio", 1234)] {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/models")!)
            request.timeoutInterval = 1
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = obj["data"] as? [[String: Any]] else { continue }
            let ids = models.compactMap { $0["id"] as? String }.filter { !$0.lowercased().contains("embed") }
            if !ids.isEmpty { found[id] = ids }
        }
        external = found
        writePiModels()
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
        for (id, models) in external {
            let port = id == "ext-ollama" ? 11434 : 1234
            providers[id] = ["baseUrl": "http://127.0.0.1:\(port)/v1", "api": "openai-completions", "apiKey": "local",
                             "models": models.map { ["id": $0] }]
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

/// Reports bytes written for a URLSession download.
private final class ProgressTracker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let onProgress: (Int64) -> Void
    private var observation: NSKeyValueObservation?

    init(onProgress: @escaping (Int64) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.completedUnitCount) { [weak self] progress, _ in
            self?.onProgress(progress.completedUnitCount)
        }
    }
}
