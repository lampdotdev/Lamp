import Foundation

/// A file in an app's folder read by Lamp itself, outside the sandbox, for what it hands the agent: what the app
/// printed, its screen as text, its answers to Lamp, its pictures. The agent may put a link anywhere in that folder,
/// and Lamp can read what the agent's commands can't, so following one would read the person's files, or Lamp's,
/// for it. So no step of the path may be a link, each step is opened from the one before it (nothing can be swapped
/// in between a look and the read), and only a plain file is read: a pipe there would keep Lamp waiting.
enum AppFile {
    /// The file's contents, or its last `last` bytes; nil when it isn't a plain file reached without a link from
    /// the app's real folder (`LampProject.realDir`), or isn't in that folder at all.
    static func read(_ url: URL, in project: LampProject, last: Int? = nil) -> Data? {
        read(url, inFolder: project.dir, last: last)
    }

    /// The same for an app's folder given by its path (the migration's, before there's a project).
    static func read(_ url: URL, inFolder folder: URL, last: Int? = nil) -> Data? {
        guard let fd = open(url, inFolder: folder) else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        if let last, info.st_size > last { lseek(fd, off_t(info.st_size) - off_t(last), SEEK_SET) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        return (try? handle.readToEnd()) ?? Data()
    }

    /// The file's size and when it was last changed, on the same terms as `read`.
    static func attributes(_ url: URL, in project: LampProject) -> (size: Int, modified: Date)? {
        guard let fd = open(url, inFolder: project.dir) else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        let modified = Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9)
        return (Int(info.st_size), modified)
    }

    /// The file's text, on the same terms as `read`; nil when it isn't UTF-8.
    static func text(_ url: URL, in project: LampProject) -> String? { text(url, inFolder: project.dir) }
    static func text(_ url: URL, inFolder folder: URL) -> String? {
        read(url, inFolder: folder).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Opens the file step by step from the folder holding the app's, which is Lamp's: the app's folder by its
    /// name and every step below it refused when it's a link.
    private static func open(_ url: URL, inFolder folder: URL) -> Int32? {
        let path = url.standardizedFileURL.path
        let way = AppFolder.way(to: folder)
        let named = folder.standardizedFileURL.path
        let real = way.steps.reduce(way.above) { $0.appendingPathComponent($1) }.path
        let inside: Substring
        if path.hasPrefix(named + "/") { inside = path.dropFirst(named.count + 1) }
        else if path.hasPrefix(real + "/") { inside = path.dropFirst(real.count + 1) }
        else { return nil }
        let steps = way.steps + inside.split(separator: "/").map(String.init)
        var fd = Darwin.open(way.above.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        for (index, step) in steps.enumerated() {
            let last = index == steps.count - 1
            let next = openat(fd, step, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | (last ? O_NONBLOCK : O_DIRECTORY))
            close(fd)
            guard next >= 0 else { return nil }
            fd = next
        }
        return fd
    }
}
