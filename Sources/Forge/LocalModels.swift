import Foundation
import AppKit

/// A downloadable model (GGUF from Hugging Face).
struct LocalModelSpec: Identifiable, Hashable {
    let id: String          // folder name, which llama-server also uses as the model name
    let name: String
    let repo: String
    let files: [String]     // model file(s), plus an optional mmproj for image input
    let sizeGB: Double
    let minRAMGB: Int
    let blurb: String
}

/// Models that run on this Mac: downloads from Hugging Face, the bundled llama.cpp server
/// (router mode on 127.0.0.1:47812, loading models on demand), and Ollama / LM Studio if they're running.
/// pi reaches all of them through providers Forge writes into its own pi `models.json`.
@MainActor
final class LocalModels: ObservableObject {
    static let shared = LocalModels()

    nonisolated static let port = 47812
    nonisolated static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Forge/Models", isDirectory: true)
    nonisolated static let contextSize = 32768

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

    @Published var installed: [String] = LocalModels.installedIDs()
    @Published var progress: [String: Double] = [:]          // model id → 0…1 while downloading
    @Published var errors: [String: String] = [:]
    @Published var serverRunning = false
    @Published var external: [String: [String]] = [:]       // "ext-ollama" → model ids

    private var server: Process?
    private var downloads: [String: Task<Void, Never>] = [:]

    // MARK: Installed models

    /// Downloaded models (folders with a `.complete` marker).
    nonisolated static func installedIDs() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent(".complete").path) }
            .map(\.lastPathComponent).sorted()
    }

    nonisolated static func hasVision(_ id: String) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(id).path)) ?? []
        return files.contains { $0.lowercased().hasPrefix("mmproj") }
    }

    nonisolated static func externalName(_ id: String) -> String {
        id == "ext-ollama" ? "Ollama" : id == "ext-lmstudio" ? "LM Studio" : id
    }

    func refresh() {
        installed = Self.installedIDs()
        writePiModels()
    }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(id))
        refresh()
        restartServerIfRunning()
    }

    // MARK: Downloads

    func download(_ spec: LocalModelSpec) {
        guard downloads[spec.id] == nil else { return }
        errors[spec.id] = nil
        progress[spec.id] = 0
        downloads[spec.id] = Task {
            defer { downloads[spec.id] = nil; progress[spec.id] = nil }
            do {
                try await fetch(spec)
                refresh()
                restartServerIfRunning()
            } catch is CancellationError {
            } catch {
                errors[spec.id] = error.localizedDescription
            }
        }
    }

    func cancel(_ id: String) { downloads[id]?.cancel() }

    private func fetch(_ spec: LocalModelSpec) async throws {
        let fm = FileManager.default
        let dir = Self.folder.appendingPathComponent(spec.id, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // Sizes from the Hugging Face API, for progress and a disk-space check.
        let sizes = try await Self.fileSizes(repo: spec.repo)
        let total = spec.files.reduce(0) { $0 + (sizes[$1] ?? 0) }
        let free = (try? Self.folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? .max
        if Int64(total) + 2_000_000_000 > free {
            throw LocalError("Not enough disk space: this model needs \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)).")
        }

        var done = 0
        for file in spec.files {
            let target = dir.appendingPathComponent(file)
            let expected = sizes[file] ?? 0
            if let size = (try? target.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size == expected, expected > 0 {
                done += size   // already downloaded
                continue
            }
            let url = URL(string: "https://huggingface.co/\(spec.repo)/resolve/main/\(file)")!
            let base = done
            let tracker = ProgressTracker { [weak self] written in
                guard total > 0 else { return }
                Task { @MainActor in self?.progress[spec.id] = Double(base + Int(written)) / Double(total) }
            }
            let (temp, response) = try await URLSession.shared.download(from: url, delegate: tracker)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw LocalError("Hugging Face returned an error for \(file).")
            }
            try? fm.removeItem(at: target)
            try fm.moveItem(at: temp, to: target)
            done += expected
        }
        let meta: [String: Any] = ["name": spec.name, "repo": spec.repo, "files": spec.files]
        try JSONSerialization.data(withJSONObject: meta).write(to: dir.appendingPathComponent("forge-model.json"))
        fm.createFile(atPath: dir.appendingPathComponent(".complete").path, contents: nil)
    }

    /// Picks a model from any Hugging Face GGUF repo ("owner/repo" or its URL): the Q4_K_M file
    /// (or the smallest Q4), all of its shards, and an F16 vision projector if there is one.
    func spec(forRepo input: String) async throws -> LocalModelSpec {
        var repo = input.trimmed
        if let range = repo.range(of: "huggingface.co/") { repo = String(repo[range.upperBound...]) }
        repo = repo.split(separator: "/").prefix(2).joined(separator: "/")
        guard repo.contains("/") else { throw LocalError("Enter a Hugging Face repo like owner/Model-GGUF.") }
        let sizes = try await Self.fileSizes(repo: repo)
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
        let id = name.lowercased().filter { $0.isLetter || $0.isNumber || ".-_".contains($0) }
        return LocalModelSpec(id: id, name: name, repo: repo, files: files, sizeGB: Double(bytes) / 1e9,
                              minRAMGB: Int((Double(bytes) / 1e9 * 1.4).rounded(.up)), blurb: "From \(repo)")
    }

    private static func fileSizes(repo: String) async throws -> [String: Int] {
        let url = URL(string: "https://huggingface.co/api/models/\(repo)/tree/main?recursive=true")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw LocalError("Couldn't find \(repo) on Hugging Face.")
        }
        var sizes: [String: Int] = [:]
        for item in items where item["type"] as? String == "file" {
            guard let path = item["path"] as? String else { continue }
            sizes[path] = (item["lfs"] as? [String: Any])?["size"] as? Int ?? item["size"] as? Int ?? 0
        }
        return sizes
    }

    // MARK: The llama.cpp server

    nonisolated static var serverBinary: URL? {
        let url = Bundle.main.resourceURL?.appendingPathComponent("llama/llama-server")
        return url.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
    }

    nonisolated static var baseURL: String { "http://127.0.0.1:\(port)" }

    /// Starts the server if needed and waits until it answers. Models load on first use.
    func ensureServer() async throws {
        if await Self.healthy() { serverRunning = true; return }
        guard let binary = Self.serverBinary else { throw LocalError("Forge's local model server is missing. Download Forge again.") }
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Forge")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appendingPathComponent("llama-server.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)

        let process = Process()
        process.executableURL = binary
        process.arguments = ["--models-dir", Self.folder.path, "--jinja", "--host", "127.0.0.1",
                             "--port", String(Self.port), "-ngl", "999", "-c", String(Self.contextSize)]
        process.standardOutput = try? FileHandle(forWritingTo: log)
        process.standardError = process.standardOutput
        process.standardInput = FileHandle.nullDevice
        try process.run()
        server = process
        for _ in 0..<60 {
            if await Self.healthy() { serverRunning = true; return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw LocalError("The local model server didn't start. See ~/Library/Logs/Forge/llama-server.log.")
    }

    func stopServer() {
        server?.terminate()
        server = nil
        serverRunning = false
    }

    private func restartServerIfRunning() {
        guard server != nil else { return }   // only restart one Forge started; it rescans the models folder
        stopServer()
        Task { try? await ensureServer() }
    }

    nonisolated static func healthy() async -> Bool {
        var request = URLRequest(url: URL(string: "\(baseURL)/health")!)
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

    /// Registers local models with Forge's pi through `models.json` (OpenAI-compatible endpoints).
    func writePiModels() {
        var providers: [String: Any] = [:]
        let local = Self.installedIDs()
        if !local.isEmpty {
            providers[Builder.localProvider] = [
                "baseUrl": "\(Self.baseURL)/v1", "api": "openai-completions", "apiKey": "local",
                "models": local.map { ["id": $0, "contextWindow": Self.contextSize,
                                       "input": Self.hasVision($0) ? ["text", "image"] : ["text"]] as [String: Any] },
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
