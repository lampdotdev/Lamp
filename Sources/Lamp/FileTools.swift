import Foundation

/// Reading and searching files for an agent with no file tools of its own. Codex has only its shell, where
/// Lamp can't tell what a command will read; `read`, `ls`, `find` and `grep` from Lamp's MCP endpoint
/// (Store.mcp) give it the same four tools pi has built in, with pi's names, arguments and limits, so one
/// privacy rule (Privacy.verdict) and one set of names in the chat cover both.
///
/// Store checks the path a call names before running it. A search then goes through everything below that
/// path, so `hidden` is asked about each thing it meets, and links are never followed: a link inside the
/// app's folder could lead out of it.
enum FileTools {
    static let names: Set<String> = ["read", "ls", "find", "grep"]

    struct Reply {
        var text: String
        var image: (data: Data, mimeType: String)?
    }

    struct Failure: Error {
        let message: String
    }

    /// pi's limits for its own file tools.
    private static let maxLines = 2000, maxBytes = 50 * 1024, maxLineLength = 500
    private static let imageTypes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
                                     "webp": "image/webp", "bmp": "image/bmp"]
    /// Folders a search doesn't go into unless it starts there: version control, build output, and Lamp's own.
    private static let skipped: Set<String> = [".git", ".build", "node_modules", ".lamp"]

    /// The descriptions and arguments are those of pi's own tools.
    static let definitions: [[String: Any]] = [
        ["name": "read",
         "description": "Read the contents of a file. Supports text files and images (jpg, png, gif, webp, bmp). Images are " +
            "sent as attachments. For text files, output is truncated to \(maxLines) lines or \(maxBytes / 1024)KB " +
            "(whichever is hit first). Use offset/limit for large files. When you need the full file, continue with " +
            "offset until complete.",
         "inputSchema": ["type": "object", "required": ["path"], "additionalProperties": false, "properties": [
            "path": ["type": "string", "description": "Path to the file to read (relative or absolute)"],
            "offset": ["type": "number", "description": "Line number to start reading from (1-indexed)"],
            "limit": ["type": "number", "description": "Maximum number of lines to read"],
         ]]],
        ["name": "ls",
         "description": "List directory contents. Returns entries sorted alphabetically, with '/' suffix for directories. " +
            "Includes dotfiles. Output is truncated to 500 entries or \(maxBytes / 1024)KB (whichever is hit first).",
         "inputSchema": ["type": "object", "additionalProperties": false, "properties": [
            "path": ["type": "string", "description": "Directory to list (default: current directory)"],
            "limit": ["type": "number", "description": "Maximum number of entries to return (default: 500)"],
         ]]],
        ["name": "find",
         "description": "Search for files by glob pattern. Returns matching file paths relative to the search directory. " +
            "Skips build output and version-control folders. Output is truncated to 1000 results or " +
            "\(maxBytes / 1024)KB (whichever is hit first).",
         "inputSchema": ["type": "object", "required": ["pattern"], "additionalProperties": false, "properties": [
            "pattern": ["type": "string", "description": "Glob pattern to match files, e.g. '*.swift', '**/*.json', or 'Sources/**/*View.swift'"],
            "path": ["type": "string", "description": "Directory to search in (default: current directory)"],
            "limit": ["type": "number", "description": "Maximum number of results (default: 1000)"],
         ]]],
        ["name": "grep",
         "description": "Search file contents for a pattern. Returns matching lines with file paths and line numbers. " +
            "Skips build output and version-control folders. Output is truncated to 100 matches or " +
            "\(maxBytes / 1024)KB (whichever is hit first). Long lines are truncated to \(maxLineLength) chars.",
         "inputSchema": ["type": "object", "required": ["pattern"], "additionalProperties": false, "properties": [
            "pattern": ["type": "string", "description": "Search pattern (regex or literal string)"],
            "path": ["type": "string", "description": "Directory or file to search (default: current directory)"],
            "glob": ["type": "string", "description": "Filter files by glob pattern, e.g. '*.swift' or '**/*View.swift'"],
            "ignoreCase": ["type": "boolean", "description": "Case-insensitive search (default: false)"],
            "literal": ["type": "boolean", "description": "Treat pattern as literal string instead of regex (default: false)"],
            "context": ["type": "number", "description": "Number of lines to show before and after each match (default: 0)"],
            "limit": ["type": "number", "description": "Maximum number of matches to return (default: 100)"],
         ]]],
    ]

    /// Runs one call. `path` is where it points, already worked out and allowed (Privacy.resolved); `folder`
    /// is the app's folder.
    static func run(_ tool: String, path: String, arguments: [String: Any], folder: URL,
                    hidden: (String) -> Bool) throws -> Reply {
        func number(_ key: String) -> Int? { (arguments[key] as? NSNumber)?.intValue }
        switch tool {
        case "read":
            return try read(path, offset: number("offset"), limit: number("limit"))
        case "ls":
            return Reply(text: try list(path, limit: number("limit") ?? 500, hidden: hidden))
        case "find":
            guard let pattern = (arguments["pattern"] as? String)?.nilIfEmpty else { throw Failure(message: "find needs a pattern.") }
            return Reply(text: try find(pattern, in: path, limit: number("limit") ?? 1000, folder: folder, hidden: hidden))
        case "grep":
            guard let pattern = (arguments["pattern"] as? String)?.nilIfEmpty else { throw Failure(message: "grep needs a pattern.") }
            return Reply(text: try grep(pattern, in: path, glob: arguments["glob"] as? String,
                                        ignoreCase: arguments["ignoreCase"] as? Bool ?? false,
                                        literal: arguments["literal"] as? Bool ?? false,
                                        context: max(0, number("context") ?? 0), limit: number("limit") ?? 100,
                                        folder: folder, hidden: hidden))
        default:
            throw Failure(message: "Unknown tool \(tool).")
        }
    }

    private static func isFolder(_ path: String) -> Bool? {
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &folder) ? folder.boolValue : nil
    }

    private static func read(_ path: String, offset: Int?, limit: Int?) throws -> Reply {
        guard let folder = isFolder(path) else { throw Failure(message: "There's no file at \(path).") }
        if folder { throw Failure(message: "\(path) is a folder. Use ls to list it.") }
        guard let data = FileManager.default.contents(atPath: path) else { throw Failure(message: "Couldn't read \(path).") }
        if let type = imageTypes[(path as NSString).pathExtension.lowercased()] {
            guard data.count <= 10 * 1024 * 1024 else { throw Failure(message: "That picture is too large to show (over 10 MB).") }
            return Reply(text: "Read image file [\(type)]", image: (data, type))
        }
        guard !data.prefix(8192).contains(0) else { throw Failure(message: "\(path) isn't a text file.") }
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        let start = max(0, (offset ?? 1) - 1)
        guard start < lines.count else {
            throw Failure(message: "Offset \(offset ?? 1) is beyond end of file (\(lines.count) lines total)")
        }
        var shown: [String] = []
        var bytes = 0
        for line in lines[start...].prefix(min(max(1, limit ?? maxLines), maxLines)) {
            bytes += line.utf8.count + 1
            if bytes > maxBytes, !shown.isEmpty { break }
            shown.append(line)
        }
        let end = start + shown.count
        var text = shown.joined(separator: "\n")
        if end < lines.count {
            text += "\n\n[Showing lines \(start + 1)-\(end) of \(lines.count). Use offset=\(end + 1) to continue.]"
        }
        return Reply(text: text)
    }

    private static func list(_ path: String, limit: Int, hidden: (String) -> Bool) throws -> String {
        guard isFolder(path) == true else { throw Failure(message: "There's no folder at \(path).") }
        let names = try FileManager.default.contentsOfDirectory(atPath: path)
            .filter { !hidden(path + "/" + $0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        guard !names.isEmpty else { return "(empty directory)" }
        return clipped(names.map { isFolder(path + "/" + $0) == true ? $0 + "/" : $0 }, limit: limit, noun: "entries")
    }

    private static func find(_ pattern: String, in path: String, limit: Int, folder: URL, hidden: (String) -> Bool) throws -> String {
        guard isFolder(path) == true else { throw Failure(message: "There's no folder at \(path).") }
        let wanted = try matcher(for: pattern)
        let found = files(under: path, folder: folder, hidden: hidden, folders: true).filter { wanted($0) }
        return found.isEmpty ? "No files found matching pattern" : clipped(found, limit: limit, noun: "results")
    }

    private static func grep(_ pattern: String, in path: String, glob: String?, ignoreCase: Bool, literal: Bool,
                             context: Int, limit: Int, folder: URL, hidden: (String) -> Bool) throws -> String {
        guard let isFolder = isFolder(path) else { throw Failure(message: "There's nothing at \(path).") }
        guard let regex = try? NSRegularExpression(pattern: literal ? NSRegularExpression.escapedPattern(for: pattern) : pattern,
                                                   options: ignoreCase ? [.caseInsensitive] : []) else {
            throw Failure(message: "\(pattern) isn't a valid regular expression. Set literal to search for it as written.")
        }
        let wanted = try glob.flatMap { $0.nilIfEmpty }.map(matcher(for:))
        // A single file is searched as asked; in a folder, paths are shown relative to it.
        let targets = isFolder ? files(under: path, folder: folder, hidden: hidden, folders: false).filter { wanted?($0) ?? true }
                               : [(path as NSString).lastPathComponent]
        let base = isFolder ? path : (path as NSString).deletingLastPathComponent
        var out: [String] = []
        var matches = 0
        search: for name in targets {
            guard let data = FileManager.default.contents(atPath: base + "/" + name), data.count <= 2 * 1024 * 1024,
                  !data.prefix(8192).contains(0) else { continue }
            let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
            var hits = Set<Int>()
            var full = false
            for (index, line) in lines.enumerated()
            where regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                if matches == limit { full = true; break }
                matches += 1
                hits.insert(index)
            }
            // Each match with the lines around it; lines shared by two matches are shown once.
            var last = -1
            for index in hits.sorted() {
                let first = max(last + 1, index - context), end = min(lines.count - 1, index + context)
                guard first <= end else { continue }
                for shown in first...end {
                    let text = lines[shown].count > maxLineLength ? lines[shown].prefix(maxLineLength) + "… [truncated]" : lines[shown]
                    out.append(hits.contains(shown) ? "\(name):\(shown + 1): \(text)" : "\(name)-\(shown + 1)- \(text)")
                    last = shown
                }
            }
            if full {
                out.append("\n[\(limit) matches limit reached. Use limit=\(limit * 2) for more, or refine pattern]")
                break search
            }
        }
        return matches == 0 ? "No matches found" : clipped(out, limit: .max, noun: "lines")
    }

    /// Lines up to a count and pi's size limit, with a note when some were left out.
    private static func clipped(_ lines: [String], limit: Int, noun: String) -> String {
        var shown: [String] = []
        var bytes = 0
        for line in lines.prefix(max(1, limit)) {
            bytes += line.utf8.count + 1
            if bytes > maxBytes, !shown.isEmpty { break }
            shown.append(line)
        }
        let rest = lines.count - shown.count
        return shown.joined(separator: "\n") + (rest > 0 ? "\n\n[\(rest) more \(noun) not shown. Narrow the search, or raise limit.]" : "")
    }

    /// Everything below a folder, as paths relative to it, in order.
    private static func files(under root: String, folder: URL, hidden: (String) -> Bool, folders: Bool) -> [String] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: keys) else { return [] }
        // The built app sits in the app's folder too: thousands of files that are never what's being looked for.
        let built = Privacy.resolved("build", in: folder)
        var found: [String] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isFolder = values?.isDirectory == true
            if values?.isSymbolicLink == true || hidden(url.path) || (isFolder && (skipped.contains(url.lastPathComponent) || url.path == built)) {
                walker.skipDescendants()
                continue
            }
            guard folders || !isFolder, url.path.hasPrefix(root + "/") else { continue }
            found.append(String(url.path.dropFirst(root.count + 1)))
            if found.count == 50_000 { break }
        }
        return found.sorted()
    }

    /// A glob as a test on a relative path: `*` and `?` stay within one folder, `**` crosses them, `{a,b}`
    /// is either. A pattern with no `/` is matched against the file's name, wherever it is.
    private static func matcher(for glob: String) throws -> (String) -> Bool {
        var pattern = ""
        var braces = 0
        var rest = Substring(glob)
        while let character = rest.first {
            rest = rest.dropFirst()
            switch character {
            case "*":
                if rest.hasPrefix("*/") { pattern += "(?:.*/)?"; rest = rest.dropFirst(2) }
                else if rest.hasPrefix("*") { pattern += ".*"; rest = rest.dropFirst() }
                else { pattern += "[^/]*" }
            case "?": pattern += "[^/]"
            case "{": pattern += "(?:"; braces += 1
            case "}" where braces > 0: pattern += ")"; braces -= 1
            case "," where braces > 0: pattern += "|"
            default: pattern += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        guard braces == 0, let regex = try? NSRegularExpression(pattern: "^" + pattern + "$") else {
            throw Failure(message: "\(glob) isn't a valid glob pattern.")
        }
        let wholePath = glob.contains("/")
        return { path in
            let subject = wholePath ? path : (path as NSString).lastPathComponent
            return regex.firstMatch(in: subject, range: NSRange(subject.startIndex..., in: subject)) != nil
        }
    }
}
