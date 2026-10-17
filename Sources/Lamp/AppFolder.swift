import Foundation

/// Lamp's own writes into an app's folder. Everything in that folder is the agent's to write, so any part of a
/// path in it may be a link a build or a command left there, leading anywhere the person can write: written the
/// usual way, a file Lamp means for `.lamp/runtime` would land wherever the link points, as Lamp. Here every step of
/// the path is opened without following a link (a link where a folder should be is refused), and a file is written
/// beside its name and renamed over it, which replaces a link rather than writing through it. Reads go through
/// `AppFile`, on the same terms. The app's folder itself is opened by its name from the folder above it, which is
/// Lamp's, and refused when it's a link: a command can put one in its place (`LampProject.realDir`).
enum AppFolder {
    struct Refused: LocalizedError {
        let path: String
        var errorDescription: String? { "Lamp won't write \(path): part of the way there is a link." }
    }

    /// Writes `data` to `url`, making the folders on the way. Throws when `url` isn't inside `root` or the way
    /// there goes through a link.
    static func write(_ data: Data, to url: URL, in root: URL, mode: mode_t = 0o644) throws {
        let (parent, name) = try open(parentOf: url, in: root, create: true)
        defer { close(parent) }
        let temporary = ".lamp-write-\(UUID().uuidString)"
        let fd = openat(parent, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode)
        guard fd >= 0 else { throw failure(url, errno) }
        var ok = data.withUnsafeBytes { buffer -> Bool in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
        ok = ok && fchmod(fd, mode) == 0
        var code = ok ? 0 : errno
        close(fd)
        if ok, renameat(parent, temporary, parent, name) != 0 { ok = false; code = errno }
        guard ok else {
            unlinkat(parent, temporary, 0)
            throw failure(url, code)
        }
    }

    static func write(_ text: String, to url: URL, in root: URL, mode: mode_t = 0o644) throws {
        try write(Data(text.utf8), to: url, in: root, mode: mode)
    }

    /// Takes away whatever is at `url`: a file, a link (not what it leads to) or a folder and all in it.
    static func remove(_ url: URL, in root: URL) {
        guard let (parent, name) = try? open(parentOf: url, in: root, create: false) else { return }
        defer { close(parent) }
        removeEntry(name, in: parent)
    }

    /// Makes the folder at `url` and the ones on the way.
    static func createDirectory(_ url: URL, in root: URL) throws {
        let fd = try open(url, in: root, create: true)
        close(fd)
    }

    /// Copies the folder or file at `source` to `destination`, both inside `root`, replacing what was there. Plain
    /// files and folders are copied; a link inside is copied as the link it is, never followed.
    static func copy(_ source: URL, to destination: URL, in root: URL) throws {
        try copy(source, in: root, to: destination, in: root)
    }

    /// The same, from one folder to another (an app's build into Lamp's own folder, say), each reached without
    /// following a link.
    static func copy(_ source: URL, in sourceRoot: URL, to destination: URL, in root: URL) throws {
        let (sourceParent, sourceName) = try open(parentOf: source, in: sourceRoot, create: false)
        defer { close(sourceParent) }
        let (parent, name) = try open(parentOf: destination, in: root, create: true)
        defer { close(parent) }
        removeEntry(name, in: parent)
        guard copyEntry(sourceName, from: sourceParent, to: name, in: parent) else { throw failure(destination, errno) }
    }

    /// Makes `url` a link to `target` (as written, relative or not), replacing whatever was there.
    static func link(_ url: URL, to target: String, in root: URL) throws {
        let (parent, name) = try open(parentOf: url, in: root, create: true)
        defer { close(parent) }
        removeEntry(name, in: parent)
        guard symlinkat(target, parent, name) == 0 else { throw failure(url, errno) }
    }

    /// Sets the permissions of the file at `url`, without following a link there.
    static func setMode(_ mode: mode_t, of url: URL, in root: URL) throws {
        let (parent, name) = try open(parentOf: url, in: root, create: false)
        defer { close(parent) }
        guard fchmodat(parent, name, mode, AT_SYMLINK_NOFOLLOW) == 0 else { throw failure(url, errno) }
    }

    // MARK: - The way there

    /// The parts of `url` under `root`, or nil when it isn't under it.
    private static func components(of url: URL, in root: URL) -> [String]? {
        let base = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base + "/") else { return path == base ? [] : nil }
        let parts = path.dropFirst(base.count + 1).split(separator: "/").map(String.init)
        return parts.contains("..") || parts.contains(".") ? nil : parts
    }

    /// The folder at `url`, opened one step at a time from `root` without following a link.
    private static func open(_ url: URL, in root: URL, create: Bool) throws -> Int32 {
        guard let parts = components(of: url, in: root) else { throw Refused(path: url.path) }
        let above = root.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let parent = Darwin.open(above.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parent >= 0 else { throw failure(url, errno) }
        var fd = openat(parent, root.standardizedFileURL.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        let code = errno
        close(parent)
        guard fd >= 0 else { throw code == ELOOP || code == ENOTDIR ? Refused(path: url.path) : failure(url, code) }
        for part in parts {
            var next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0, errno == ENOENT, create {
                mkdirat(fd, part, 0o755)
                next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            let code = errno
            close(fd)
            guard next >= 0 else { throw code == ELOOP || code == ENOTDIR ? Refused(path: url.path) : failure(url, code) }
            fd = next
        }
        return fd
    }

    private static func open(parentOf url: URL, in root: URL, create: Bool) throws -> (Int32, String) {
        guard let parts = components(of: url, in: root), let name = parts.last else { throw Refused(path: url.path) }
        return (try open(url.deletingLastPathComponent(), in: root, create: create), name)
    }

    /// `code` is taken as the call failed, before anything else can change `errno`.
    private static func failure(_ url: URL, _ code: Int32) -> Error {
        CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path, NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)])
    }

    private static func removeEntry(_ name: String, in parent: Int32) {
        if unlinkat(parent, name, 0) == 0 || errno == ENOENT { return }
        let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return }
        for entry in entries(of: fd) { removeEntry(entry, in: fd) }
        close(fd)
        unlinkat(parent, name, AT_REMOVEDIR)
    }

    /// The names in an open folder. The folder stays open: `fdopendir` is given a copy.
    private static func entries(of fd: Int32) -> [String] {
        let copy = dup(fd)
        guard copy >= 0, let dir = fdopendir(copy) else { return [] }
        defer { closedir(dir) }
        var names: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
            if name != "." && name != ".." { names.append(name) }
        }
        return names
    }

    private static func copyEntry(_ name: String, from sourceParent: Int32, to target: String, in parent: Int32) -> Bool {
        var info = stat()
        guard fstatat(sourceParent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { return false }
        switch info.st_mode & S_IFMT {
        case S_IFLNK:
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) + 1)
            let count = readlinkat(sourceParent, name, &buffer, Int(MAXPATHLEN))
            guard count >= 0 else { return false }
            buffer[count] = 0
            return symlinkat(buffer, parent, target) == 0
        case S_IFDIR:
            let source = openat(sourceParent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard source >= 0 else { return false }
            defer { close(source) }
            guard mkdirat(parent, target, info.st_mode & 0o7777) == 0 else { return false }
            let made = openat(parent, target, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard made >= 0 else { return false }
            defer { close(made) }
            return entries(of: source).allSatisfy { copyEntry($0, from: source, to: $0, in: made) }
        case S_IFREG:
            let input = openat(sourceParent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard input >= 0 else { return false }
            defer { close(input) }
            let output = openat(parent, target, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, info.st_mode & 0o7777)
            guard output >= 0 else { return false }
            defer { close(output) }
            return fcopyfile(input, output, nil, copyfile_flags_t(COPYFILE_DATA)) == 0
        default:
            return true   // pipes and the like aren't anything Lamp copies
        }
    }
}
