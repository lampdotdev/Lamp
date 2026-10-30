import Foundation
import Compression

/// A wish's repository fetched with no git on this Mac (a Mac without Apple's tools, where /usr/bin/git only opens their
/// installer): GitHub's archive of one commit, read and written by Lamp itself. Nothing the repository holds runs here.
/// The branch or tag is settled to a commit first, so what's reviewed, credited and updated from later is that commit and
/// no other. The whole archive is checked before a byte of it is written, and refused as a whole: a repository that holds
/// anything but plain folders and files at plain paths isn't one Put on GitHub made. The answers come from GitHub
/// anonymously, nothing of the person's going with them.
enum RepoArchive {
    /// What came, for the credits: said by Lamp, which asked, never read from anything in the repository.
    struct Fetched: Equatable, Codable {
        let tree: URL
        let url: String
        let commit: String
    }

    static let maxDownloadBytes = Sharing.maxArchiveBytes
    static let maxFileBytes = Sharing.maxUnpackedBytes
    static let maxFiles = Sharing.maxFiles
    /// Beyond the files, the most their headers may add to what's unpacked: a block each, and a block or two for a long path.
    private static let maxTarBytes = maxFileBytes + (maxFiles + 16) * 2048
    private static let maxPathBytes = 1024

    /// GitHub's answer to a request: its status and what it said, no more of it than the limit. Tests put their own in place.
    typealias Ask = @Sendable (URLRequest, Int) async throws -> (status: Int, body: Data)
    nonisolated(unsafe) static var ask: Ask = askGitHub

    /// The repository at the commit its branch or tag is now, in a tree under `folder`, which is made here, private to
    /// this user, and is the caller's to remove.
    static func fetch(_ source: RepoImport.Source, into folder: URL) async throws -> Fetched {
        let commit = try await resolve(source)
        let archive = try await download(source, commit: commit)
        let tar = try gunzip(archive, limit: maxTarBytes)
        let entries = try read(tar: tar, commit: commit)
        let tree = folder.appendingPathComponent(source.name)
        try write(entries, of: tar, into: tree)
        return Fetched(tree: tree, url: source.url, commit: commit)
    }

    // MARK: Asking GitHub

    /// A commit, never a branch or tag that can move.
    static func resolve(_ source: RepoImport.Source) async throws -> String {
        let ref = source.ref ?? "HEAD"
        guard let path = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.github.com/repos/\(source.owner)/\(source.name)/commits/\(path)") else {
            throw Sharing.ImportError("Lamp couldn't get \(source.owner)/\(source.name) from GitHub.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/vnd.github.sha", forHTTPHeaderField: "Accept")
        let answer = try await ask(request, 1024)
        try check(answer.status, source)
        guard let commit = isCommit(String(decoding: answer.body, as: UTF8.self).trimmed) else {
            throw Sharing.ImportError("Lamp couldn't tell which commit of \(source.owner)/\(source.name) to get.")
        }
        // A commit named outright is that commit or nothing, even one GitHub would find by its first letters.
        if let named = isCommit(ref), named != commit { throw Sharing.ImportError("GitHub gave another commit than the one asked for.") }
        return commit
    }

    private static func download(_ source: RepoImport.Source, commit: String) async throws -> Data {
        guard let url = URL(string: "https://codeload.github.com/\(source.owner)/\(source.name)/tar.gz/\(commit)") else {
            throw Sharing.ImportError("Lamp couldn't get \(source.owner)/\(source.name) from GitHub.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let answer = try await ask(request, maxDownloadBytes)
        try check(answer.status, source)
        return answer.body
    }

    private static func check(_ status: Int, _ source: RepoImport.Source) throws {
        switch status {
        case 200: break
        case 403, 429: throw Sharing.ImportError("GitHub is turning away requests from this network for now.", detail: "Try again in a while.")
        default:
            throw Sharing.ImportError("Lamp couldn't get \(source.owner)/\(source.name) from GitHub.",
                                      detail: "Check the address: the repository may be private, or not there.")
        }
    }

    private static func isCommit(_ text: String) -> String? {
        text.count == 40 && text.allSatisfy { $0.isHexDigit && !$0.isUppercase } ? text : nil
    }

    private final class StaysPut: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }

    /// Over a session with no cookies, cache or saved sign-ins, followed nowhere else: a moved repository is its new address
    /// for the person to open, not something to be fetched from wherever an answer points.
    @Sendable private static func askGitHub(_ request: URLRequest, limit: Int) async throws -> (status: Int, body: Data) {
        let session = URLSession(configuration: .ephemeral, delegate: StaysPut(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw Sharing.ImportError("GitHub didn't answer.") }
        guard http.statusCode == 200 else { return (http.statusCode, Data()) }
        guard response.expectedContentLength <= Int64(limit) else { throw tooLarge }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            guard data.count <= limit else { throw tooLarge }
        }
        return (200, data)
    }

    private static let tooLarge = Sharing.ImportError("This repository holds more than a Lamp app would.",
                                                      detail: "A wish has at most \(maxFiles) files and 256 MB.")
    private static func refused(_ why: String) -> Sharing.ImportError {
        Sharing.ImportError("Lamp can't open this repository without Apple's tools.", detail: why)
    }

    // MARK: Reading

    /// The tar inside a gzip file, unpacked in memory and no further than `limit`, however much the file claims.
    static func gunzip(_ file: Data, limit: Int) throws -> Data {
        let bytes = [UInt8](file)
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8, bytes[3] & 0xe0 == 0 else { throw refused("Its archive isn't one Lamp can read.") }
        let flags = bytes[3]
        var start = 10
        if flags & 4 != 0 {
            guard start + 2 <= bytes.count else { throw refused("Its archive is cut short.") }
            start += 2 + Int(bytes[start]) + Int(bytes[start + 1]) << 8
        }
        for flag: UInt8 in [8, 16] where flags & flag != 0 {
            while start < bytes.count, bytes[start] != 0 { start += 1 }
            start += 1
        }
        if flags & 2 != 0 { start += 2 }
        guard start + 8 <= bytes.count else { throw refused("Its archive is cut short.") }

        let chunk = 1 << 20
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: chunk)
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { throw refused("Its archive isn't one Lamp can read.") }
        defer { compression_stream_destroy(stream) }
        try bytes.withUnsafeBufferPointer { input in
            stream.pointee.src_ptr = input.baseAddress! + start
            stream.pointee.src_size = bytes.count - start
            try buffer.withUnsafeMutableBufferPointer { space in
                while true {
                    stream.pointee.dst_ptr = space.baseAddress!
                    stream.pointee.dst_size = chunk
                    let before = stream.pointee.src_size
                    let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                    guard status != COMPRESSION_STATUS_ERROR else { throw refused("Its archive isn't one Lamp can read.") }
                    let made = chunk - stream.pointee.dst_size
                    out.append(space.baseAddress!, count: made)
                    guard out.count <= limit else { throw tooLarge }
                    if status == COMPRESSION_STATUS_END { break }
                    guard made > 0 || stream.pointee.src_size < before else { throw refused("Its archive is cut short.") }
                }
            }
        }
        // The file ends with the length unpacked: anything cut off or added after the compressed part shows here.
        let told = bytes.suffix(4).reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard told == UInt32(truncatingIfNeeded: out.count) else { throw refused("Its archive is cut short.") }
        return out
    }

    /// A file or folder of the repository, by its path under the tree, and where a file's bytes are in the tar.
    struct Entry: Equatable {
        let path: String
        let bytes: Range<Int>?
    }

    /// What the tar GitHub made of `commit` holds, with everything checked and nothing written. Refused as a whole for
    /// anything but plain folders and files, at paths that stay in the tree and that this Mac's disk can tell apart.
    static func read(tar: Data, commit: String) throws -> [Entry] {
        let tar = tar.startIndex == 0 ? tar : Data(tar)
        var entries: [Entry] = []
        var kinds: [String: Bool] = [:]   // every path, as the disk would see it: whether it's a folder
        var spelled: [String: String] = [:]   // every folder, as the disk would see it: as the archive writes it
        var top: String?
        var said: [String: String] = [:]   // the extended header for the next entry
        var saidCommit: String?
        var offset = 0
        var bytes = 0
        var files = 0

        while true {
            guard offset + 512 <= tar.count else { throw refused("Its archive is cut short.") }
            let header = tar.subdata(in: offset..<(offset + 512))
            if header.allSatisfy({ $0 == 0 }) {
                guard offset + 1024 <= tar.count, tar[(offset + 512)..<(offset + 1024)].allSatisfy({ $0 == 0 }) else { throw refused("Its archive is cut short.") }
                break
            }
            guard checksumHolds(header) else { throw refused("Its archive isn't one Lamp can read.") }
            guard let size = octal(header[124..<136]), size <= maxTarBytes else { throw tooLarge }
            let start = offset + 512
            let padded = (size + 511) / 512 * 512
            guard start + padded <= tar.count else { throw refused("Its archive is cut short.") }
            offset = start + padded
            let body = start..<(start + size)
            let type = header[156]

            switch type {
            case UInt8(ascii: "g"):
                let global = try records(tar.subdata(in: body))
                guard global.keys.allSatisfy({ $0 == "comment" }) else { throw refused("Its archive isn't one Lamp can read.") }
                saidCommit = global["comment"]
                continue
            case UInt8(ascii: "x"):
                said = try records(tar.subdata(in: body))
                // A size or a link said here would change what the fields above mean, and GitHub writes neither.
                guard said.keys.allSatisfy({ $0 == "path" }) else { throw refused("Its archive isn't one Lamp can read.") }
                continue
            case UInt8(ascii: "0"), 0, UInt8(ascii: "5"):
                break
            case UInt8(ascii: "1"), UInt8(ascii: "2"):
                throw refused("It holds links, which a Lamp app doesn't have.")
            default:
                throw refused("It holds something other than folders and files.")
            }

            let folder = type == UInt8(ascii: "5")
            guard let raw = try said["path"] ?? headerPath(header) else { throw refused("It holds a file with no name.") }
            said = [:]
            guard !folder || size == 0 else { throw refused("Its archive isn't one Lamp can read.") }
            let steps = try steps(of: raw, folder: folder)
            if top == nil, folder, steps.count == 1 { top = steps[0] }
            guard let top, steps[0] == top else { throw refused("It has more than one folder at its top.") }
            guard steps.count > 1 else {
                guard folder else { throw refused("It has more than one folder at its top.") }
                continue
            }
            let inside = Array(steps.dropFirst())
            var seen = ""
            var written = ""
            // A folder spelled a second way is the same folder to the disk, which would put the two's files together.
            func follow(_ step: String) throws {
                seen += (seen.isEmpty ? "" : "/") + disk(step)
                written += (written.isEmpty ? "" : "/") + step
                // By their bytes: Swift counts the two ways of writing an accent as equal.
                if !spelled[seen, default: written].utf8.elementsEqual(written.utf8) { throw refused("It holds two things under one name.") }
                spelled[seen] = written
            }
            for step in inside.dropLast() {
                try follow(step)
                if kinds[seen] == false { throw refused("It holds a file and a folder under one name.") }
                kinds[seen] = true
            }
            if folder {
                try follow(inside.last!)
                if kinds[seen] == false { throw refused("It holds two things under one name.") }
            } else {
                seen += (seen.isEmpty ? "" : "/") + disk(inside.last!)
                if kinds[seen] != nil { throw refused("It holds two things under one name.") }
            }
            kinds[seen] = folder

            if !folder {
                files += 1
                bytes += size
                guard files <= maxFiles, bytes <= maxFileBytes else { throw tooLarge }
            }
            entries.append(Entry(path: inside.joined(separator: "/"), bytes: folder ? nil : body))
        }
        // What's named is the commit asked for, in both the places GitHub names it.
        guard let top, top.hasSuffix("-" + commit) else { throw refused("It isn't the commit Lamp asked for.") }
        if let saidCommit, saidCommit != commit { throw refused("It isn't the commit Lamp asked for.") }
        return entries
    }

    /// How the disk tells names apart: the two ways of writing an accent, and upper and lower case, are one name to it.
    private static func disk(_ step: String) -> String { step.precomposedStringWithCanonicalMapping.lowercased() }

    private static func steps(of path: String, folder: Bool) throws -> [String] {
        var text = path
        if folder, text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty, text.utf8.count <= maxPathBytes else { throw refused("It holds a path Lamp won't write.") }
        guard !text.hasPrefix("/"), !text.hasPrefix("~") else { throw refused("It holds a path that leaves its folder.") }
        let steps = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for step in steps {
            guard step != "..", step != "." else { throw refused("It holds a path that leaves its folder.") }
            guard !step.isEmpty, step.utf8.count <= 255,
                  step.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7f && $0 != "\\" }) else { throw refused("It holds a path Lamp won't write.") }
        }
        return steps
    }

    private static func checksumHolds(_ header: Data) -> Bool {
        guard let stored = octal(header[148..<156]) else { return false }
        let sum = header.enumerated().reduce(0) { $0 + (148..<156 ~= $1.offset ? 32 : Int($1.element)) }
        return sum == stored
    }

    /// An octal field, with its padding; nil for anything else, a binary size included.
    private static func octal(_ field: Data) -> Int? {
        let body = field.drop { $0 == 32 }
        let digits = body.prefix { $0 != 0 && $0 != 32 }
        guard !digits.isEmpty, digits.count <= 12, digits.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "7")).contains($0) }),
              body.dropFirst(digits.count).allSatisfy({ $0 == 0 || $0 == 32 }) else { return nil }
        return digits.reduce(0) { $0 * 8 + Int($1 - UInt8(ascii: "0")) }
    }

    private static func headerPath(_ header: Data) throws -> String? {
        func text(_ field: Data) throws -> String {
            guard let text = String(data: field.prefix { $0 != 0 }, encoding: .utf8) else { throw refused("It holds a path Lamp won't write.") }
            return text
        }
        let name = try text(header[0..<100])
        guard header[257..<262] == Data("ustar".utf8) else { throw refused("Its archive isn't one Lamp can read.") }
        let prefix = try text(header[345..<500])
        let path = prefix.isEmpty ? name : prefix + "/" + name
        return path.isEmpty ? nil : path
    }

    /// An extended header's records, "<length> <key>=<value>\n", each key once.
    private static func records(_ data: Data) throws -> [String: String] {
        var found: [String: String] = [:]
        var bytes = data[...]
        while !bytes.isEmpty {
            let digits = bytes.prefix { $0 != 32 }
            guard digits.count < 12, let length = Int(String(decoding: digits, as: UTF8.self)), length > digits.count + 2, length <= bytes.count else {
                throw refused("Its archive isn't one Lamp can read.")
            }
            let record = bytes.prefix(length)
            let inner = record.dropFirst(digits.count + 1)
            guard record.last == 10, let equals = inner.firstIndex(of: UInt8(ascii: "=")),
                  let key = String(data: inner[inner.startIndex..<equals], encoding: .utf8),
                  let value = String(data: inner[(equals + 1)..<(record.endIndex - 1)], encoding: .utf8),
                  !value.utf8.contains(0), found.updateValue(value, forKey: key) == nil else {
                throw refused("Its archive isn't one Lamp can read.")
            }
            bytes = bytes.dropFirst(length)
        }
        return found
    }

    // MARK: Writing

    /// Everything into a folder made here and open only to this user: nothing was there to be followed, and no file made
    /// here can be followed either. No file is left runnable.
    static func write(_ entries: [Entry], of tar: Data, into tree: URL) throws {
        let fm = FileManager.default
        let open700: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        try fm.createDirectory(at: tree.deletingLastPathComponent().deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: tree.deletingLastPathComponent(), withIntermediateDirectories: false, attributes: open700)
        try fm.createDirectory(at: tree, withIntermediateDirectories: false, attributes: open700)
        for entry in entries {
            let target = tree.appendingPathComponent(entry.path)
            guard let range = entry.bytes else {
                try fm.createDirectory(at: target, withIntermediateDirectories: true, attributes: open700)
                continue
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: open700)
            let file = open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard file >= 0 else { throw refused("Lamp couldn't write it to disk.") }
            defer { close(file) }
            try tar[range].withUnsafeBytes { body in
                var written = 0
                while written < body.count {
                    let wrote = Darwin.write(file, body.baseAddress! + written, body.count - written)
                    guard wrote > 0 else { throw refused("Lamp couldn't write it to disk.") }
                    written += wrote
                }
            }
        }
    }
}
