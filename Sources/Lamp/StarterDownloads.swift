import CryptoKit
import Foundation

/// A starter's files, fetched when it's first opened rather than shipped in Lamp's bundle, which carries only what the
/// desk lists it by (`Starters.Listed`). Two things come down:
///
/// - **Its tree**: the starter's repository at the commit this Lamp pins, as GitHub's archive of that commit, so it's
///   what Update from GitHub… merges against and Send Changes Back… goes on top of, and needs no git (a new person's
///   Mac has none until Apple's tools come). It's checked against the pin itself: the commit object Lamp ships
///   (`Listed.commit`, from the build's fetch) must hash to the pinned commit, and the files must hash to the tree that
///   commit names, as git hashes a tree. Anything else is refused and removed.
/// - **Its prebuilt app**, when this Lamp's release made one (`PrebuiltStarters`): an asset of Lamp's release on
///   GitHub, pinned by size and SHA-256 in the bundle (`Listed.prebuilt`), and checked again for Lamp's own signature
///   once unpacked, before it's used.
///
/// Both are kept by edition in Lamp's folder (`cache`), so another instance never shares them, and the agent's sandbox
/// closes them. A starter's older trees and prebuilt apps go when a newer one comes.
enum StarterDownloads {
    static var cache: URL { Edition.supportFolder.appendingPathComponent("Starters") }

    /// Where a starter's tree is kept once fetched: by its folder and the commit.
    static func treeFolder(_ folder: String, commit: String) -> URL {
        cache.appendingPathComponent(folder).appendingPathComponent(commit)
    }

    /// Where its prebuilt app is kept once fetched: by its hash, so one from another Lamp is never taken for it.
    static func prebuiltArchive(_ folder: String, sha256: String) -> URL {
        cache.appendingPathComponent(folder).appendingPathComponent("Prebuilt-\(sha256.prefix(16)).zip")
    }

    /// Everything opening the starter needs, fetched when it isn't here yet: its tree, then its prebuilt app. The
    /// prebuilt app is a nicety: once Apple's tools are here a starter without it is built, so a failure to fetch it
    /// fails the whole only when there's nothing to build with (`needsPrebuilt`).
    static func fetch(_ starter: Starters.Starter, needsPrebuilt: Bool = false) async throws {
        try await fetchTree(starter)
        do {
            try await fetchPrebuilt(starter)
        } catch {
            NSLog("Lamp couldn't get the prebuilt %@: %@", starter.name, error.localizedDescription)
            // One no longer there (an old nightly's) isn't coming back: the starter is copied all the same, and built once
            // Apple's tools are here, as one whose prebuilt app this Mac refused is (`Store.awaitToolsToOpen`).
            if needsPrebuilt, (error as? Downloads.Failure)?.gone != true { throw error }
        }
    }

    // MARK: The tree

    static func fetchTree(_ starter: Starters.Starter) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: starter.tree.appendingPathComponent("lamp-app.json").path) { return }
        guard let commit = starter.commit, let archive = archiveURL(of: starter),
              let object = try? Data(contentsOf: Starters.listed(.commit, of: starter)),
              let tree = treeNamed(by: object, commit: commit) else { throw Downloads.Failure(Downloads.refused) }
        let work = cache.appendingPathComponent(".partial-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: work) }
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let downloaded: URL
        do {
            let (file, response) = try await URLSession.shared.download(from: archive)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Downloads.Failure(Downloads.offline) }
            downloaded = work.appendingPathComponent("archive.tar.gz")
            try fm.moveItem(at: file, to: downloaded)
        } catch {
            throw Downloads.Failure(Downloads.offline)
        }
        guard (try? downloaded.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? .max <= maxArchive else {
            throw Downloads.Failure(Downloads.refused)
        }
        let unpacked = work.appendingPathComponent("tree")
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        // macOS's own tar, which refuses paths outside the folder and writing through links by default.
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", downloaded.path, "-C", unpacked.path, "--no-same-owner"]
        tar.standardOutput = FileHandle.nullDevice
        tar.standardError = FileHandle.nullDevice
        try tar.run()
        tar.waitUntilExit()
        // GitHub's archive holds one folder, <repository>-<commit>, with the tree in it.
        let top = (try? fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)) ?? []
        guard tar.terminationStatus == 0, top.count == 1, let root = top.first, root.hasDirectoryPath,
              (try? treeHash(of: root)) == tree else { throw Downloads.Failure(Downloads.refused) }
        let destination = treeFolder(starter.folder.lastPathComponent, commit: commit)
        try? fm.removeItem(at: destination)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: root, to: destination)
        // Trees of the commits this Lamp no longer pins.
        for old in (try? fm.contentsOfDirectory(at: destination.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
        where old.hasDirectoryPath && old.lastPathComponent != commit && Credits.validCommit(old.lastPathComponent) != nil {
            try? fm.removeItem(at: old)
        }
    }

    /// No starter's archive comes near this: one that does isn't one.
    private static let maxArchive = 300 << 20

    /// GitHub's archive of the commit, from the repository starter.md names, which is only ever on GitHub.
    static func archiveURL(of starter: Starters.Starter) -> URL? {
        guard let repository = starter.repository, let url = URL(string: repository), url.scheme == "https", url.host == "github.com",
              let commit = starter.commit else { return nil }
        let path = url.path.split(separator: "/")
        guard path.count == 2 else { return nil }
        return URL(string: "https://github.com/\(path[0])/\(path[1])/archive/\(commit).tar.gz")
    }

    /// The tree a commit object names, when the object is that commit: its git hash is the pin.
    static func treeNamed(by object: Data, commit: String) -> String? {
        guard hex(Insecure.SHA1.hash(data: Data("commit \(object.count)\0".utf8) + object)) == commit.lowercased(),
              let first = String(decoding: object.prefix(46), as: UTF8.self).split(separator: "\n").first,
              first.hasPrefix("tree ") else { return nil }
        return String(first.dropFirst(5))
    }

    /// A folder's git tree hash, as `git write-tree` would make it of the folder checked in: each file a blob with its
    /// mode (executable or not, or a link), each folder a tree, empty ones left out, `.git` never in it.
    static func treeHash(of folder: URL) throws -> String { hex(try tree(folder) ?? emptyTree) }

    private static let emptyTree = Data(Insecure.SHA1.hash(data: Data("tree 0\0".utf8)))

    private static func tree(_ folder: URL) throws -> Data? {
        let fm = FileManager.default
        var entries: [(key: [UInt8], line: Data)] = []
        for name in try fm.contentsOfDirectory(atPath: folder.path) where name != ".git" {
            let url = folder.appendingPathComponent(name)
            let attributes = try fm.attributesOfItem(atPath: url.path)
            let mode: String, hash: Data
            switch attributes[.type] as? FileAttributeType {
            case .typeSymbolicLink?:
                mode = "120000"
                hash = blob(Data(try fm.destinationOfSymbolicLink(atPath: url.path).utf8))
            case .typeDirectory?:
                guard let sub = try tree(url) else { continue }
                mode = "40000"
                hash = sub
            case .typeRegular?:
                let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
                mode = permissions & 0o100 != 0 ? "100755" : "100644"
                hash = blob(try Data(contentsOf: url))
            default:
                throw Downloads.Failure(Downloads.refused)
            }
            // Git orders a tree's entries by name, a folder's as though it ended in "/".
            let bytes = Array(name.utf8)
            entries.append((mode == "40000" ? bytes + [UInt8(ascii: "/")] : bytes, Data("\(mode) \(name)\0".utf8) + hash))
        }
        guard !entries.isEmpty else { return nil }
        let body = entries.sorted { $0.key.lexicographicallyPrecedes($1.key) }.reduce(into: Data()) { $0 += $1.line }
        return Data(Insecure.SHA1.hash(data: Data("tree \(body.count)\0".utf8) + body))
    }

    private static func blob(_ data: Data) -> Data {
        Data(Insecure.SHA1.hash(data: Data("blob \(data.count)\0".utf8) + data))
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: The prebuilt app

    /// What this Lamp's release pins for the starter's prebuilt app, when it made one.
    static func prebuilt(of starter: Starters.Starter) -> Downloads.Pinned? {
        (try? Data(contentsOf: Starters.listed(.prebuilt, of: starter))).flatMap { try? JSONDecoder().decode(Downloads.Pinned.self, from: $0) }
    }

    /// The prebuilt app's archive on this Mac, once fetched.
    static func prebuiltArchive(of starter: Starters.Starter) -> URL? {
        guard let pinned = prebuilt(of: starter) else { return nil }
        let archive = prebuiltArchive(starter.folder.lastPathComponent, sha256: pinned.sha256)
        return FileManager.default.fileExists(atPath: archive.path) ? archive : nil
    }

    static func fetchPrebuilt(_ starter: Starters.Starter) async throws {
        guard let pinned = prebuilt(of: starter), prebuiltArchive(of: starter) == nil else { return }
        let archive = prebuiltArchive(starter.folder.lastPathComponent, sha256: pinned.sha256)
        try await Downloads.fetch(pinned, to: archive)
        let fm = FileManager.default
        for old in (try? fm.contentsOfDirectory(at: archive.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent.hasPrefix("Prebuilt-") && old.lastPathComponent != archive.lastPathComponent {
            try? fm.removeItem(at: old)
        }
    }
}
