import Foundation
import CryptoKit

/// Putting a change into a Mac app while it's open, without a restart (Settings → Experimental, its own switch).
/// While the experiment is on, a Mac app is built live (build.sh with LAMP_LIVE: debug, -interposable, from the
/// copy of its sources in `.lamp/live` with each view's body wrapped). After a change, the files it touched are
/// compiled into a library, and the running app loads it (`LampLive` in LampSupport.swift), keeping its state.
/// What can't go in that way (a stored property or an enum case added, removed or changed, a file removed, the
/// App itself, Lamp's own file, the app's assets or settings) is installed as before, by reopening the app.
enum LiveReload {
    /// Whether the app is built live: an experiment, for a Mac app, or the Mac half of an app for both while
    /// Try On points at this Mac, with nothing built beside it (a widget or share extension, which share no
    /// code with the open app).
    @MainActor static func eligible(_ project: LampProject) -> Bool {
        isOn && project.platform.hasMac && !project.onIOS && !Template.hasWidget(project) && !Template.hasShare(project)
    }

    /// Settings → Experimental: off by default. Turning it on or off changes how apps are built from their next
    /// build on (a live build, or the usual one).
    static let switchKey = "experimentLiveReload"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: switchKey) }

    static func folder(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/live") }
    /// The sources the build last used, wrapped (build.sh writes them).
    static func sources(_ project: LampProject) -> URL { folder(project).appendingPathComponent("Sources") }
    /// The sources the open app is running: what was installed, and every change put into it since.
    static func running(_ project: LampProject) -> URL { folder(project).appendingPathComponent("running") }

    /// After an install: the open app is the build, so what it runs is what the build used, with the other
    /// things the build puts in the app as they were.
    static func markRunning(_ project: LampProject) {
        let fm = FileManager.default
        try? fm.removeItem(at: running(project))
        try? fm.copyItem(at: sources(project), to: running(project))
        try? inputs(project).write(to: runningInputs(project), atomically: true, encoding: .utf8)
    }

    private static func runningInputs(_ project: LampProject) -> URL { folder(project).appendingPathComponent("running-inputs.txt") }

    /// What else goes into the installed app besides the code, which a library can't bring: what it declares
    /// (capabilities.json), the package and the icon. A change to any of them is installed by reopening the app.
    /// Not its own files (Assets): a live build reads them from the app's folder (`LampAssets`), new ones included.
    static func inputs(_ project: LampProject) -> String {
        let fm = FileManager.default
        return ["Package.swift", Template.Capabilities.file, "icon.json"].map { name in
            let data = fm.contents(atPath: project.dir.appendingPathComponent(name).path) ?? Data()
            return name + " " + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }.joined(separator: "\n")
    }

    static func forget(_ project: LampProject) {
        try? FileManager.default.removeItem(at: running(project))
    }

    /// The open app has a change the copy in the apps folder doesn't: the build goes in when the app closes.
    /// Not `Runtime.holdBuild`, which says the reverse (the open copy is the older one) and keeps the agent off it.
    /// Kept on disk, so the install still happens after Lamp itself has been quit and opened again.
    private static func pendingURL(_ project: LampProject) -> URL { folder(project).appendingPathComponent("install-pending") }
    static func awaitInstall(_ project: LampProject) {
        try? FileManager.default.createDirectory(at: folder(project), withIntermediateDirectories: true)
        try? Data().write(to: pendingURL(project))
    }
    static func installed(_ project: LampProject) { try? FileManager.default.removeItem(at: pendingURL(project)) }
    static func awaitsInstall(_ project: LampProject) -> Bool { FileManager.default.fileExists(atPath: pendingURL(project).path) }

    /// What to do with a change: put the files it touched (relative to Sources) into the open app, reopen the
    /// app (with why, for the chat's details, so the rules can be tuned by what actually happens), or nothing.
    enum Verdict: Equatable {
        case reload([String])
        case reopen(String)
        case unchanged
    }

    static func verdict(_ project: LampProject) -> Verdict {
        let built = swiftFiles(in: sources(project)), open = swiftFiles(in: running(project))
        guard !open.isEmpty else { return .reopen("Lamp doesn't know what the open copy was built from") }
        // A new file only brings new types and functions, which the library holds; one taken away may have held
        // something the open app still uses.
        if let gone = Set(open.keys).subtracting(built.keys).sorted().first { return .reopen("\(gone) was removed") }
        if (try? String(contentsOf: runningInputs(project), encoding: .utf8)) != inputs(project) {
            return .reopen("the package, the app's settings or its icon changed")
        }
        var changed: [String] = []
        for (path, url) in built.sorted(by: { $0.key < $1.key }) {
            guard let new = try? String(contentsOf: url, encoding: .utf8) else { return .reopen("\(path) couldn't be read") }
            guard let old = open[path].flatMap({ try? String(contentsOf: $0, encoding: .utf8) }) else {
                // Added: its types are new to the app, so their layout is whatever it says, but not the App.
                if declaresApp(new) { return .reopen("\(path) is the app's entry point") }
                changed.append(path)
                continue
            }
            guard new != old else { continue }
            if (path as NSString).lastPathComponent == "LampSupport.swift" { return .reopen("Lamp's own building blocks changed") }
            if declaresApp(new) { return .reopen("\(path) is the app's entry point") }
            let before = shape(of: old), after = shape(of: new)
            if before != after {
                let what = Set(after).subtracting(before).first ?? Set(before).subtracting(after).first ?? "the order of the fields"
                return .reopen("\(path) changes what its types hold (\(what))")
            }
            changed.append(path)
        }
        return changed.isEmpty ? .unchanged : .reload(changed)
    }

    private static func swiftFiles(in folder: URL) -> [String: URL] {
        let base = folder.standardizedFileURL.path + "/"
        let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return Dictionary(items.filter { $0.pathExtension == "swift" }.map { (String($0.standardizedFileURL.path.dropFirst(base.count)), $0) },
                          uniquingKeysWith: { first, _ in first })
    }

    /// What a type's memory is made of, as far as the text shows it, in the order written (a field's place is
    /// part of the layout): the stored properties (a `let` or `var` line that opens no body, not static) and the
    /// enum cases with what they carry (a `case` naming one or more cases, not a switch's `case .x:` or
    /// `case let`). The open app's objects were laid out by the old ones; a change to these needs a fresh start.
    static func shape(of source: String) -> [String] {
        let stored = try! NSRegularExpression(pattern: #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:private|fileprivate|internal|public|open)(?:\(set\))?\s+)*(?:weak\s+|unowned\s+|lazy\s+)*(?:let|var)\s+\w+[^{]*$"#)
        let enumCase = try! NSRegularExpression(pattern: #"^\s*(?:indirect\s+)?case\s+(?!let\b|var\b)[A-Za-z_]\w*(?:\(.*\))?\s*(?:=\s*[^:]+)?\s*(?:,\s*[A-Za-z_]\w*(?:\(.*\))?\s*)*$"#)
        let typeOpening = try! NSRegularExpression(pattern: #"\b(?:struct|class|enum|actor)\b"#)
        let notType = try! NSRegularExpression(pattern: #"\b(?:func|var|let|init|subscript)\b|="#)
        // Only what's declared directly in a type's body counts: a local `let` in a function, or a closure's,
        // isn't part of any layout. Each brace is a type's when its line opens a struct, class, enum or actor.
        var stack: [Bool] = [], out: [String] = []
        for line in declarations(in: source) {
            let range = NSRange(line.startIndex..., in: line)
            if stack.last == true, !line.contains("static "), !line.contains("class var"),
               stored.firstMatch(in: line, range: range) != nil || enumCase.firstMatch(in: line, range: range) != nil {
                // What it is and its type, not its starting value, which a new instance takes from the new code;
                // with no type written, the kind of value it starts with stands for the type.
                var shape = line.trimmingCharacters(in: .whitespaces)
                if shape.range(of: #"^(?:indirect\s+)?case\b"#, options: .regularExpression) == nil, let equals = shape.range(of: " = ") {
                    let start = String(shape[equals.upperBound...]).trimmingCharacters(in: .whitespaces)
                    let declared = String(shape[..<equals.lowerBound])
                    shape = declared.contains(":") ? declared : declared + " = " + Self.kind(of: start)
                }
                out.append(shape)
            }
            let isType = typeOpening.firstMatch(in: line, range: range) != nil && notType.firstMatch(in: line, range: range) == nil
            for character in line {
                if character == "{" { stack.append(isType && !stack.contains(false)) }
                else if character == "}", !stack.isEmpty { stack.removeLast() }
            }
        }
        return out
    }

    /// What kind of value a starting value is, for a property with no type written: a number, text, true or
    /// false, a list, or what it's made with (`Foo(…)`, `.init`), else the whole of it, so another value of the
    /// same kind keeps the layout and another kind doesn't.
    static func kind(of value: String) -> String {
        if value.range(of: #"^-?\d[\d_]*$"#, options: .regularExpression) != nil { return "<integer>" }
        if value.range(of: #"^-?\d[\d_]*\.\d[\d_]*$"#, options: .regularExpression) != nil { return "<decimal>" }
        if value.hasPrefix("\"") { return "<text>" }
        if value == "true" || value == "false" { return "<bool>" }
        if value.hasPrefix("[") { return "<list>" }
        if let call = value.range(of: #"^[A-Za-z_][\w.]*(?=\s*[({])"#, options: .regularExpression) { return String(value[call]) + "(…)" }
        return value
    }

    /// The source's lines with comments taken out and a declaration that runs over several lines (inside
    /// parentheses: a case's payload, a property's type) joined into one, so the layout check reads each
    /// declaration whole whatever its formatting. Strings are kept as they are, comment marks in them included.
    static func declarations(in source: String) -> [String] {
        let chars = Array(source)
        var out = "", depth = 0, i = 0
        func at(_ k: Int) -> Character { k < chars.count ? chars[k] : "\0" }
        while i < chars.count {
            let c = chars[i]
            // A string, plain, raw (#"…"#, with any number of #) or multi-line ("""…"""), copied whole: what's in it
            // is never a comment or a bracket.
            var hashes = 0
            while at(i + hashes) == "#" { hashes += 1 }
            if at(i + hashes) == "\"" {
                let triple = at(i + hashes + 1) == "\"" && at(i + hashes + 2) == "\""
                let quote = triple ? 3 : 1
                let closing = Array(String(repeating: "\"", count: quote) + String(repeating: "#", count: hashes))
                var k = i + hashes + quote
                while k < chars.count {
                    if hashes == 0, chars[k] == "\\" { k += 2; continue }   // an escaped character in a plain string
                    if Array(chars[k..<min(chars.count, k + closing.count)]) == closing { k += closing.count; break }
                    k += 1
                }
                // Its words never matter to a layout, and its braces or line breaks would be read as code: kept as
                // an empty string, which still says a starting value is text.
                out += "\"\""
                i = k
                continue
            }
            if c == "/", at(i + 1) == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", at(i + 1) == "*" {
                i += 2
                while i < chars.count, !(chars[i] == "*" && at(i + 1) == "/") { i += 1 }
                i += 2
                continue
            }
            if c == "(" { depth += 1 } else if c == ")" { depth = max(0, depth - 1) }
            // One declaration a line: a body opened or closed, or a `;`, ends the line, so a type written on one
            // line (`enum Shape { case star, circle }`) is read like any other.
            if depth == 0, c == "{" { out += "{\n" }
            else if depth == 0, c == "}" { out += "\n}\n" }
            else if depth == 0, c == ";" { out += "\n" }
            else { out.append(c == "\n" && depth > 0 ? " " : c) }
            i += 1
        }
        return out.split(separator: "\n", omittingEmptySubsequences: true).map { String($0).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) }
    }

    /// The App runs once, at launch: a change to it can't show in an app that's already open.
    private static func declaresApp(_ source: String) -> Bool {
        source.range(of: #"@main\b"#, options: .regularExpression) != nil || source.range(of: #":\s*(SwiftUI\.)?App\s*\{"#, options: .regularExpression) != nil
    }

    /// Compiles the whole module from the live copy, the way the live build does (SwiftPM's for a Mac app,
    /// Xcode's for the Mac half of an app for both: both unoptimized, testable, for macOS 14, named after the app),
    /// and links the changed files' objects into a library for the open app. Nil, with the compiler's words, when it doesn't compile.
    static func compile(_ project: LampProject, changed: [String]) async -> (url: URL?, problem: String?) {
        let live = folder(project)
        let work = live.appendingPathComponent("hot")
        try? FileManager.default.removeItem(at: work)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let library = live.appendingPathComponent("hot-\(UUID().uuidString.prefix(8)).dylib")
        let all = swiftFiles(in: sources(project)).values.map(\.path).sorted()
        // The objects come out named after their files, in the work folder.
        let objects = changed.map { work.appendingPathComponent(((($0 as NSString).lastPathComponent) as NSString).deletingPathExtension + ".o").path }
        let script = """
            set -e
            SDK="$(xcrun --sdk macosx --show-sdk-path)"
            PLUGINS="$(dirname "$(dirname "$(xcrun -f swiftc)")")/lib/swift/host/plugins"
            cd "$LAMP_WORK"
            xcrun swiftc -c "$@" -module-name "$LAMP_EXE" -parse-as-library -Onone -enable-testing \
              -D DEBUG -D LAMP_LIVE -target arm64-apple-macosx14.0 -sdk "$SDK" -plugin-path "$PLUGINS" 2>&1
            xcrun swiftc -emit-library ${(Q)${(z)LAMP_OBJECTS}} -o "$LAMP_LIBRARY" -target arm64-apple-macosx14.0 -sdk "$SDK" \
              -Xlinker -undefined -Xlinker dynamic_lookup -Xlinker -interposable 2>&1
            codesign --force -s - "$LAMP_LIBRARY" 2>&1
            """
        var output: [String] = []
        let quoted = all.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let status = await Shell.run("set -- \(quoted)\n" + script, cwd: project.dir,
                                     env: ["LAMP_WORK": work.path, "LAMP_EXE": project.exe, "LAMP_LIBRARY": library.path,
                                           "LAMP_OBJECTS": objects.map { "'\($0)'" }.joined(separator: " ")]) { output.append($0) }
        guard status == 0 else { return (nil, output.suffix(30).joined(separator: "\n")) }
        return (library, nil)
    }

    /// Asks the open app to load the library, signed with its token (only Lamp has it), and waits a moment for
    /// its answer, which it leaves in its runtime folder.
    static func send(_ library: URL, to project: LampProject, token: String) async -> Bool {
        let answer = Runtime.macFolder(project).appendingPathComponent("reloaded.txt")
        try? FileManager.default.removeItem(at: answer)
        let key = SymmetricKey(data: Data(token.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data("reload\n\(library.path)".utf8), using: key)
            .map { String(format: "%02x", $0) }.joined()
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "reload"), object: project.bundleID,
            userInfo: ["path": library.path, "signature": signature], deliverImmediately: true)
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(100))
            if let text = try? String(contentsOf: answer, encoding: .utf8) { return text.hasPrefix("ok") }
        }
        return false
    }
}
