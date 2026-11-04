import Foundation

/// Errors an app logs after a change goes into it that it hadn't logged before. The app writes what it prints to
/// `.lamp/runtime/log.txt` (`Runtime.logURL`) whatever it is: a Mac app's own output, a page's console, a simulator or a
/// device's lines. Lamp notes where that log was just before each change goes in (`Mark`), and what went wrong before
/// any change of the turn (`keys` of the log and the one before it), and hands the agent only what's new since: the
/// agent rarely looks at the app itself, so this is how it hears that a change broke something.
enum LogErrors {
    /// Where the log was: its length, and how it began, so a log started afresh (the app opened again) is read whole.
    struct Mark: Equatable {
        var length = 0
        var head = Data()
    }

    /// One error, said once however often it came, with the lines just before its first time, which tell where it was.
    struct Found: Equatable {
        var key: String
        var line: String
        var context: [String]
        var count: Int
    }

    /// What a turn knows of one app's log (`Store.markLog`).
    struct Watch {
        var project: LampProject
        /// Errors the log held before the turn's first change: never said to be new.
        var known: Set<String>
        var mark = Mark()
        /// The sources of the latest change: a mark for sources already marked (an install that only acknowledges a
        /// change that went in live, a page that was unchanged) would pass over the errors that change brought.
        var sources = ""
        /// When the latest change began to go in.
        var marked = Date()
        /// What the agent has been told since that change, so no answer says it twice.
        var told: Set<String> = []
    }

    static let headLength = 128
    /// Lines kept before each error, and how much is said in all.
    static let contextLines = 3
    static let most = 8
    static let longest = 4_000

    static func mark(of data: Data?) -> Mark {
        guard let data else { return Mark() }
        return Mark(length: data.count, head: data.prefix(headLength))
    }

    /// What the log says after `mark`: all of it when it was started afresh since (shorter, or beginning otherwise).
    static func since(_ mark: Mark, in data: Data) -> String {
        let same = data.count >= mark.length && data.prefix(mark.head.count) == mark.head
        return String(decoding: same ? data.dropFirst(mark.length) : data[...], as: UTF8.self)
    }

    private static let stamp = #"^\[[0-9]+(\.[0-9]+)? s\] "#

    /// Android's logcat line prefix as Lamp has it written (`Adb.logcat`, `-v brief`: `E/AndroidRuntime(12345): `).
    private static let logcat = #"^[VDIWEF]/[^(]*\(\s*[0-9]+\):\s*"#

    /// A line that says something failed: a page's console error or an uncaught one ("Error: …", lamp-game.js's log with
    /// its time before it), a script's own error types, Swift's fatal errors, an exception nothing caught, Android's
    /// (its logcat prefix aside).
    /// A warning, or a line that only mentions an error ("Refresh failed: Error Domain=…"), isn't one: an app logs those
    /// as it goes, and only what stops something from working is the agent's to look at.
    static func isError(_ line: Substring) -> Bool {
        let text = line.replacingOccurrences(of: stamp, with: "", options: .regularExpression)
            .replacingOccurrences(of: logcat, with: "", options: .regularExpression)
        let starts = #"^(Error|Uncaught|Unhandled|TypeError|ReferenceError|SyntaxError|RangeError|FATAL EXCEPTION|libc\+\+abi: terminating)\b"#
        return text.range(of: starts, options: [.regularExpression, .caseInsensitive]) != nil
            || text.contains("Fatal error:") || line.hasPrefix("E/AndroidRuntime(")
    }

    /// The same error however its numbers came out (the time it was logged, a line in the code that moved, an address).
    static func key(_ line: Substring) -> String {
        line.replacingOccurrences(of: stamp, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"0x[0-9a-fA-F]+|[0-9]+"#, with: "#", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func keys(in text: String) -> Set<String> {
        Set(text.split(separator: "\n").filter(isError).map(key))
    }

    /// Each error in `text` not among `known`, in the order it first came.
    static func errors(in text: String, besides known: Set<String>) -> [Found] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var found: [Found] = []
        var at: [String: Int] = [:]
        for (index, line) in lines.enumerated() where isError(line) {
            let key = key(line)
            guard !known.contains(key) else { continue }
            if let place = at[key] { found[place].count += 1; continue }
            let before = lines[max(0, index - contextLines)..<index].filter { !isError($0) }.map(trimmed)
            at[key] = found.count
            found.append(Found(key: key, line: trimmed(line), context: before, count: 1))
        }
        return found
    }

    private static func trimmed(_ line: Substring) -> String {
        line.count > 400 ? String(line.prefix(400)) + "…" : String(line)
    }

    /// The errors as the agent reads them: each with the lines before it, at most `most` of them and `longest` characters.
    static func listing(_ found: [Found]) -> String {
        var text = ""
        for error in found.prefix(most) {
            let entry = (error.context + [error.line + (error.count > 1 ? "   (\(error.count) times)" : "")]).joined(separator: "\n")
            guard text.count + entry.count < longest else { break }
            text += (text.isEmpty ? "" : "\n…\n") + entry
        }
        if found.count > most { text += "\n…and \(found.count - most) more." }
        return text
    }
}
