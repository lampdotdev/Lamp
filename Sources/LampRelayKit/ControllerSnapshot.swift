import CryptoKit
import Foundation

/// A game's phone page as Lamp hands it to the controllers' service (`ControllerService`): every file of the page as
/// Lamp published it, by its path inside the page, with Lamp's own lamp-controller.js among them. The service keeps
/// each version it's given in a folder of its own and serves only from there, never from the game's folder, which the
/// agent goes on changing; a game is bound to the version it was built with, so a new build never changes the page
/// under a game that's still being played. The same rules as Lamp's own serving: no hidden names, no links, plain files
/// of a size a page has.
public struct ControllerSnapshot: Equatable, Sendable {
    public struct File: Equatable, Sendable {
        public let path: String
        public let data: Data
        public init(path: String, data: Data) {
            self.path = path
            self.data = data
        }
    }

    public let files: [File]
    public init(files: [File]) { self.files = files.sorted { $0.path < $1.path } }

    /// The largest file served, as Lamp serves a page (`TVs.phoneFile`), and the most a page may hold in all.
    public static let fileLimit = 64 << 20
    public static let totalLimit = 256 << 20
    public static let countLimit = 4000

    public struct Failure: Error, Equatable, CustomStringConvertible {
        public let description: String
        public init(_ description: String) { self.description = description }
    }

    /// Whether a path inside a page is one served: steps of a name each, none hidden, empty or stepping up.
    public static func isServed(_ path: String) -> Bool {
        guard !path.isEmpty, path.utf8.count <= 1024, !path.contains("\0"), !path.contains("\\") else { return false }
        let steps = path.split(separator: "/", omittingEmptySubsequences: false)
        return steps.allSatisfy { !$0.isEmpty && !$0.hasPrefix(".") && $0.utf8.count <= 255 }
    }

    /// The page's checks: each path served, no two the same, sizes within limits, and an index.html to open.
    public func check() throws {
        guard files.count <= Self.countLimit else { throw Failure("The phone page has too many files.") }
        var seen: Set<String> = []
        var total = 0
        for file in files {
            guard Self.isServed(file.path) else { throw Failure("The phone page has a file that can't be served: \(file.path)") }
            guard seen.insert(file.path).inserted else { throw Failure("The phone page names \(file.path) twice.") }
            guard file.data.count <= Self.fileLimit else { throw Failure("\(file.path) is too large for a phone page.") }
            total += file.data.count
        }
        guard total <= Self.totalLimit else { throw Failure("The phone page is too large.") }
        guard seen.contains("index.html") else { throw Failure("The phone page has no index.html.") }
    }

    /// What this version of the page is, from every file's path and bytes: the same page has the same digest.
    public var digest: String {
        var hash = SHA256()
        for file in files {
            hash.update(data: Data(file.path.utf8))
            hash.update(data: Data([0]))
            hash.update(data: Data(String(file.data.count).utf8))
            hash.update(data: Data([0]))
            hash.update(data: file.data)
        }
        return Data(hash.finalize()).urlSafeBase64
    }

    /// A version's name from its digest: short enough for a folder and an Info.plist, unique enough for one game.
    public var version: String { String(digest.prefix(24)) }

    /// The page in `folder`, read as it's served: hidden files left out, as they're never served; a link anywhere, or a
    /// file too large, and there's no page.
    public static func read(_ folder: URL) throws -> ControllerSnapshot {
        let fm = FileManager.default
        let root = folder.standardizedFileURL
        guard (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == false else { throw Failure("The phone page is a link.") }
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            throw Failure("The phone page couldn't be read.")
        }
        var files: [File] = []
        for case let url as URL in walk {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { throw Failure("The phone page has a link: \(url.lastPathComponent)") }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { continue }
            guard (values.fileSize ?? 0) <= fileLimit else { throw Failure("\(url.lastPathComponent) is too large for a phone page.") }
            let path = String(url.standardizedFileURL.path.dropFirst(root.path.count + 1))
            guard isServed(path) else { continue }
            files.append(File(path: path, data: try Data(contentsOf: url)))
        }
        return ControllerSnapshot(files: files)
    }

    /// The page as it crosses to the service, and back.
    public var encoded: [[String: Any]] { files.map { ["path": $0.path, "data": $0.data.base64EncodedString()] } }

    public init(encoded: [[String: Any]]) throws {
        var files: [File] = []
        for each in encoded {
            guard let path = each["path"] as? String, let data = (each["data"] as? String).flatMap({ Data(base64Encoded: $0) }) else {
                throw Failure("The phone page arrived damaged.")
            }
            files.append(File(path: path, data: data))
        }
        self.init(files: files)
    }

    /// Writes the page into `folder`, which mustn't exist yet: made beside it and moved into place whole, so a page is
    /// served whole or not at all.
    public func write(to folder: URL) throws {
        try check()
        let fm = FileManager.default
        let partial = folder.deletingLastPathComponent().appendingPathComponent(".partial-" + UUID().uuidString)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: partial) }
        for file in files {
            let url = partial.appendingPathComponent(file.path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: url)
        }
        try fm.moveItem(at: partial, to: folder)
    }
}
