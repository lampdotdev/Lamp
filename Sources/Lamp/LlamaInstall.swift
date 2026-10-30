import Foundation

/// llama.cpp's server and libraries, which run GGUF models on this Mac (`LocalModels`): fetched the first time someone
/// downloads or picks a local model, not carried by every Lamp. build.sh signs them as it signs Lamp and zips them as
/// an asset of Lamp's release on GitHub (notarized with the release), pinning the asset's address, size and SHA-256 in
/// the bundle (`llama.json`); a build from source points at the zip it made itself, through the same checks. They're
/// kept by edition in Lamp's folder (`folder`, which the agent's sandbox closes), under the llama.cpp build and the
/// asset's hash, so a newer Lamp that pins another build fetches it again and the older one goes. Every program and
/// library is checked for Lamp's own signature once unpacked and again before the server starts (`verified`).
enum LlamaInstall {
    /// What this Lamp pins: llama.cpp's build, and the asset holding it.
    struct Pin: Codable {
        var build: String
        var asset: Downloads.Pinned
    }

    static let pin: Pin? = Bundle.main.url(forResource: "llama", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Pin.self, from: $0) }

    static var root: URL { Edition.supportFolder.appendingPathComponent("llama") }

    /// Where this Lamp's pinned build is kept once fetched.
    static var folder: URL? {
        pin.map { root.appendingPathComponent("\($0.build)-\($0.asset.sha256.prefix(16))") }
    }

    static var server: URL? { folder?.appendingPathComponent("llama-server") }

    static var isInstalled: Bool { server.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false }

    /// Whether an older build is here: someone has used local models, so a newer Lamp fetches the build it needs
    /// without waiting to be asked (`LocalModels`).
    static var hasOlder: Bool {
        guard !isInstalled, let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return false }
        return names.contains { !$0.hasPrefix(".") }
    }

    /// Fetches, unpacks and checks the pinned build, then puts it in place of any other. A failure leaves nothing.
    static func install(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard let pin, let folder else { throw Downloads.Failure("This Lamp can't run models on this Mac. Download Lamp again.") }
        if isInstalled { return }
        let fm = FileManager.default
        let work = root.appendingPathComponent(".partial-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: work) }
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("llama.zip")
        try await Downloads.fetch(pin.asset, to: zip, progress: progress)
        let unpacked = work.appendingPathComponent("unpacked")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unpacked.path]
        try ditto.run()
        ditto.waitUntilExit()
        // The zip holds one folder, llama-<build>, with the server and its libraries.
        let built = unpacked.appendingPathComponent("llama-\(pin.build)")
        guard ditto.terminationStatus == 0, verified(built) else { throw Downloads.Failure(Downloads.refused) }
        // The same build put in place meanwhile (another Lamp of this edition) stays: it may be running.
        if isInstalled, verified(folder) { return }
        try? fm.removeItem(at: folder)
        try fm.moveItem(at: built, to: folder)
        for old in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent != folder.lastPathComponent && !old.lastPathComponent.hasPrefix(".") {
            try? fm.removeItem(at: old)
        }
    }

    /// Whether a folder holds the server, and every program and library in it is signed as Lamp is. Links (a library's
    /// versioned names) are left to what they point to, which is checked in its own right.
    static func verified(_ folder: URL) -> Bool {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: folder.appendingPathComponent("llama-server").path),
              let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return false }
        for name in names where name == "llama-server" || name.hasSuffix(".dylib") {
            let file = folder.appendingPathComponent(name)
            if (try? fm.destinationOfSymbolicLink(atPath: file.path)) != nil { continue }
            guard Downloads.signedLikeLamp(file) else { return false }
        }
        return true
    }
}
