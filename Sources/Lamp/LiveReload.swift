import Foundation
import CryptoKit

/// Putting a change into a Mac app while it's open, without a restart (Settings → Experimental, with the wand).
/// While the experiment is on, a Mac app is built live (build.sh with LAMP_LIVE: debug, -interposable, from the
/// copy of its sources in `.lamp/live` with each view's body wrapped). After a change, the files it touched are
/// compiled into a library, and the running app loads it (`LampLive` in LampSupport.swift), keeping its state.
/// What can't go in that way (a stored property or an enum case added or removed, a file added or removed, the
/// App itself, Lamp's own file) is installed as before, by quitting and reopening the app.
enum LiveReload {
    /// Whether the app is built live: an experiment, for a Mac app on its own with nothing built beside it.
    @MainActor static func eligible(_ project: LampProject) -> Bool {
        MagicPanel.isOn && project.platform == .mac && !Template.hasWidget(project) && !Template.hasShare(project)
    }

    static func folder(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/live") }
    /// The sources the build last used, wrapped (build.sh writes them).
    static func sources(_ project: LampProject) -> URL { folder(project).appendingPathComponent("Sources") }
    /// The sources the open app is running: what was installed, and every change put into it since.
    static func running(_ project: LampProject) -> URL { folder(project).appendingPathComponent("running") }

    /// After an install: the open app is the build, so what it runs is what the build used.
    static func markRunning(_ project: LampProject) {
        let fm = FileManager.default
        try? fm.removeItem(at: running(project))
        try? fm.copyItem(at: sources(project), to: running(project))
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

    /// The files a change touched, relative to Sources, when every one of them can be put into the open app;
    /// nil when something has to go in by reopening it, or when nothing changed.
    static func reloadable(_ project: LampProject) -> [String]? {
        let built = swiftFiles(in: sources(project)), open = swiftFiles(in: running(project))
        guard !open.isEmpty, Set(built.keys) == Set(open.keys) else { return nil }
        var changed: [String] = []
        for (path, url) in built.sorted(by: { $0.key < $1.key }) {
            guard let new = try? String(contentsOf: url, encoding: .utf8),
                  let old = open[path].flatMap({ try? String(contentsOf: $0, encoding: .utf8) }) else { return nil }
            guard new != old else { continue }
            guard (path as NSString).lastPathComponent != "LampSupport.swift", shape(of: new) == shape(of: old),
                  !declaresApp(new) else { return nil }
            changed.append(path)
        }
        return changed.isEmpty ? nil : changed
    }

    private static func swiftFiles(in folder: URL) -> [String: URL] {
        let base = folder.standardizedFileURL.path + "/"
        let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return Dictionary(items.filter { $0.pathExtension == "swift" }.map { (String($0.standardizedFileURL.path.dropFirst(base.count)), $0) },
                          uniquingKeysWith: { first, _ in first })
    }

    /// What a type's memory is made of, as far as the text shows it: the stored properties (a `let` or `var`
    /// line that opens no body, not static) and the enum cases (a `case` line with no colon, so not a
    /// switch's). The open app's objects were laid out by the old ones; a change to these needs a fresh start.
    static func shape(of source: String) -> [String] {
        let stored = try! NSRegularExpression(pattern: #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:private|fileprivate|internal|public|open)(?:\(set\))?\s+)*(?:weak\s+|unowned\s+|lazy\s+)*(?:let|var)\s+\w+[^{]*$"#)
        let enumCase = try! NSRegularExpression(pattern: #"^\s*(?:indirect\s+)?case\s+[^:]*$"#)
        return source.split(separator: "\n", omittingEmptySubsequences: true).map(String.init).filter { line in
            let range = NSRange(line.startIndex..., in: line)
            guard !line.contains("static "), !line.contains("class var") else { return false }
            return stored.firstMatch(in: line, range: range) != nil || enumCase.firstMatch(in: line, range: range) != nil
        }.map { $0.trimmingCharacters(in: .whitespaces) }.sorted()
    }

    /// The App runs once, at launch: a change to it can't show in an app that's already open.
    private static func declaresApp(_ source: String) -> Bool {
        source.range(of: #"@main\b"#, options: .regularExpression) != nil || source.range(of: #":\s*(SwiftUI\.)?App\s*\{"#, options: .regularExpression) != nil
    }

    /// Compiles the whole module from the live copy, the way the live build does, and links the changed files'
    /// objects into a library for the open app. Nil, with the compiler's words, when it doesn't compile.
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
              -D DEBUG -D SWIFT_PACKAGE -D LAMP_LIVE -target arm64-apple-macosx14.0 -sdk "$SDK" -plugin-path "$PLUGINS" 2>&1
            xcrun swiftc -emit-library ${(Q)${(z)LAMP_OBJECTS}} -o "$LAMP_LIBRARY" -target arm64-apple-macosx14.0 -sdk "$SDK" \
              -Xlinker -undefined -Xlinker dynamic_lookup 2>&1
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
