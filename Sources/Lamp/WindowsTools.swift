import CryptoKit
import Foundation

/// The tools that build a native game for the Xbox on this Mac (`GameKit`): LLVM's clang-cl and lld-link, Microsoft's
/// Windows SDK and C runtime, and sokol-shdc for the game's shaders. Nothing of these is on a Mac by itself, so Lamp
/// gets them the first time a game is built (`install`, from the setup window, `WindowsSetup`), each checked: LLVM's
/// release and sokol-shdc against the SHA-256 their makers publish, and Microsoft's packages by xwin, which Lamp ships
/// and which checks each against the hash in Microsoft's own manifest, after the person has accepted Microsoft's
/// licence for them (`licenseAccepted`): they can't be passed on, so every Mac fetches its own. Of LLVM only clang,
/// lld and clang's own headers are kept. Like Android's tools they go in the developer folder every Lamp shares, which
/// the agent's sandbox lets a build read and never write.
enum WindowsTools {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Folders

    static let folder = Edition.sharedDeveloperFolder.appendingPathComponent("Windows")
    static let llvmFolder = folder.appendingPathComponent("llvm")
    static let sdkFolder = folder.appendingPathComponent("sdk")
    static var clangCL: String { llvmFolder.appendingPathComponent("bin/clang-cl").path }
    static var lldLink: String { llvmFolder.appendingPathComponent("bin/lld-link").path }
    static var shdc: String { folder.appendingPathComponent("bin/sokol-shdc").path }

    /// What a game's build is run with: where the tools are (the kit's build.sh reads `LAMP_WINDOWS`).
    static var buildEnvironment: [String: String] { ["LAMP_WINDOWS": folder.path] }

    // MARK: Versions

    /// What's downloaded, pinned so every Lamp builds the same way; moved on purpose, with a game built and played on
    /// a console first.
    static let llvmVersion = "23.1.4"
    static let sdkVersion = "10.0.26100"

    struct Release {
        let url: URL
        let sha256: String
        let size: Int64
    }

    /// LLVM's own release for Apple silicon, with the SHA-256 GitHub lists for it. The xz one: macOS's tar reads xz
    /// itself, where it hands zstd (the smaller download) to a zstd program a Mac doesn't have.
    static let llvm = Release(url: URL(string: "https://github.com/llvm/llvm-project/releases/download/llvmorg-\(llvmVersion)/LLVM-\(llvmVersion)-macOS-ARM64.tar.xz")!,
                              sha256: "5d3179db39adeca5b17a34d82708fe976bc60e055b05fe557878fb3fb64d39ef", size: 1_570_051_292)
    /// sokol-shdc for Apple silicon, from the repository its author publishes the binaries in, at one commit.
    static let shdcRelease = Release(url: URL(string: "https://raw.githubusercontent.com/floooh/sokol-tools-bin/b975d5642093d62e76a1e088bdae945d6d8b8ff2/bin/osx_arm64/sokol-shdc")!,
                                     sha256: "2a807d62dffcc67a50a6ab51df57cde2fc8b23a3daf6207177d79e00fbd4086b", size: 12_014_840)

    /// xwin, which fetches Microsoft's packages: built with Lamp and shipped inside it (it publishes no build for a Mac).
    static var xwin: String? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("bin/xwin"),
              FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url.path
    }

    /// Microsoft's licence for what xwin downloads, which the person reads and accepts in the setup window.
    static let licenseURL = URL(string: "https://go.microsoft.com/fwlink/?LinkId=2086102")!

    // MARK: What's there

    /// LLVM publishes these for Apple silicon only.
    static var supported: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    static var hasLLVM: Bool {
        FileManager.default.isExecutableFile(atPath: clangCL) && FileManager.default.isExecutableFile(atPath: lldLink)
            && FileManager.default.fileExists(atPath: llvmFolder.appendingPathComponent("lib/clang/23/include/intrin.h").path)
    }
    static var hasShdc: Bool { FileManager.default.isExecutableFile(atPath: shdc) }
    static var hasSDK: Bool {
        FileManager.default.fileExists(atPath: sdkFolder.appendingPathComponent("sdk/lib/um/x86_64/WindowsApp.lib").path)
            && FileManager.default.fileExists(atPath: sdkFolder.appendingPathComponent("crt/lib/onecore/x86_64/libcmt.lib").path)
            && FileManager.default.fileExists(atPath: sdkFolder.appendingPathComponent("sdk/include/cppwinrt/winrt/base.h").path)
    }
    static var isReady: Bool { !Pretend.isMissing("windows") && hasLLVM && hasShdc && hasSDK }

    /// Whether the person accepted Microsoft's licence on this Mac: asked once, before the first download.
    static var licenseAccepted: Bool {
        get { UserDefaults.standard.object(forKey: licenseKey) != nil && !Pretend.isMissing("windows") }
        set { UserDefaults.standard.set(newValue ? Date() : nil, forKey: licenseKey) }
    }
    private static let licenseKey = "windowsSDKLicenseAccepted"

    /// What's in the way of building a game now, in the person's words, or nil.
    static var problem: String? {
        guard supported else { return "Native Xbox games are built with tools that run on Macs with Apple silicon only." }
        guard isReady else { return "The tools that build Xbox games aren't on this Mac yet. The window that gets them is open." }
        return nil
    }

    // MARK: Installing

    /// Downloads and puts in place what's missing, saying how far it is (0…1) and what it's doing. A download that
    /// doesn't match its published hash isn't used, and nothing is left half done: each piece is made beside its
    /// place and moved in whole.
    static func install(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        guard supported else { throw Failure(message: "These tools run on Macs with Apple silicon only.") }
        guard licenseAccepted else { throw Failure(message: "Microsoft's licence has to be accepted first.") }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if !hasShdc {
            let staging = try stagingFolder()
            defer { try? fm.removeItem(at: staging) }
            let download = staging.appendingPathComponent("sokol-shdc")
            try await fetch(shdcRelease, to: download, name: "the shader compiler", from: 0, to: 0.02, progress: progress)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: download.path)
            let bin = folder.appendingPathComponent("bin")
            try fm.createDirectory(at: bin, withIntermediateDirectories: true)
            if fm.fileExists(atPath: shdc) { try fm.removeItem(atPath: shdc) }
            try fm.moveItem(at: download, to: URL(fileURLWithPath: shdc))
        }
        if !hasLLVM {
            let staging = try stagingFolder()
            defer { try? fm.removeItem(at: staging) }
            let download = staging.appendingPathComponent("llvm.tar.xz")
            try await fetch(llvm, to: download, name: "LLVM's compiler", from: 0.02, to: 0.5, progress: progress)
            progress(0.5, "Unpacking LLVM's compiler…")
            // Only the compiler, the linker and the compiler's own headers: the rest of LLVM is 2 GB nothing here uses.
            let top = "LLVM-\(llvmVersion)-macOS-ARM64"
            let unpacked = staging.appendingPathComponent("unpacked")
            try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
            let result = await Subprocess.run("/usr/bin/tar", ["-xf", download.path, "-C", unpacked.path, "--strip-components", "1",
                                                               "--include", "\(top)/bin/clang-23", "--include", "\(top)/bin/lld",
                                                               "--include", "\(top)/lib/clang/23/include/*", "--include", "\(top)/LICENSE.TXT"],
                                              timeout: 1200)
            guard result.ok else { throw Failure(message: "Lamp couldn't unpack LLVM's compiler.\n\n" + result.output.suffix(400)) }
            try? fm.removeItem(at: download)
            let bin = unpacked.appendingPathComponent("bin")
            try fm.createSymbolicLink(atPath: bin.appendingPathComponent("clang-cl").path, withDestinationPath: "clang-23")
            try fm.createSymbolicLink(atPath: bin.appendingPathComponent("lld-link").path, withDestinationPath: "lld")
            guard await Subprocess.run(bin.appendingPathComponent("clang-cl").path, ["--version"], timeout: 60).ok else {
                throw Failure(message: "LLVM's compiler didn't start on this Mac.")
            }
            if fm.fileExists(atPath: llvmFolder.path) { try fm.removeItem(at: llvmFolder) }
            try fm.moveItem(at: unpacked, to: llvmFolder)
        }
        if !hasSDK {
            guard let xwin else { throw Failure(message: "This copy of Lamp was built without the tool that fetches Microsoft's Windows SDK.") }
            let staging = try stagingFolder()
            defer { try? fm.removeItem(at: staging) }
            progress(0.55, "Downloading Microsoft's Windows SDK…")
            let output = staging.appendingPathComponent("sdk")
            var lines: [String] = []
            // The licence was accepted in the setup window, which is what --accept-license says. xwin checks each of
            // Microsoft's packages against the hash in Microsoft's manifest, and the cache goes with the staging folder.
            let arguments = ["--accept-license", "--json", "--log-level", "info", "--http-retry", "3", "--timeout", "300s",
                             "--cache-dir", staging.appendingPathComponent("cache").path, "--arch", "x86_64",
                             "--variant", "desktop", "--variant", "onecore", "--sdk-version", sdkVersion, "splat", "--output", output.path]
            let status = await Shell.run(([xwin] + arguments).map(Sandbox.quoted).joined(separator: " "), cwd: staging, env: [:], login: false) { line in
                lines.append(line)
                if lines.count > 200 { lines.removeFirst(100) }
                // xwin's JSON lines name each package as it goes; the share done is counted from them.
                if line.contains("\"downloaded\"") || line.contains("\"unpacked\"") || line.contains("downloading") {
                    progress(min(0.97, 0.55 + Double(lines.count) * 0.002), "Downloading Microsoft's Windows SDK…")
                }
            }
            guard status == 0, fm.fileExists(atPath: output.appendingPathComponent("sdk/lib/um/x86_64/WindowsApp.lib").path) else {
                throw Failure(message: "Microsoft's Windows SDK couldn't be downloaded.\n\n" + lines.suffix(6).joined(separator: "\n"))
            }
            if fm.fileExists(atPath: sdkFolder.path) { try fm.removeItem(at: sdkFolder) }
            try fm.moveItem(at: output, to: sdkFolder)
        }
        progress(1, "Ready")
    }

    private static func stagingFolder() throws -> URL {
        let staging = folder.appendingPathComponent(".staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        return staging
    }

    private static func fetch(_ release: Release, to file: URL, name: String, from: Double, to: Double,
                              progress: @escaping @Sendable (Double, String) -> Void) async throws {
        progress(from, "Downloading \(name)…")
        try await Download.file(from: release.url, to: file, expected: release.size) { part in progress(from + (to - from) * part, "Downloading \(name)…") }
        guard try sha256(of: file) == release.sha256 else {
            try? FileManager.default.removeItem(at: file)
            throw Failure(message: "The download of \(name) didn't match what its maker published, so Lamp didn't use it.")
        }
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
