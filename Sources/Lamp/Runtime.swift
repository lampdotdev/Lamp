import AppKit
import CryptoKit

/// What Lamp can see of a generated app while it runs. The app saves what it prints to
/// `.lamp/runtime/log.txt` and pictures of its windows next to it (see `LampRuntime` in
/// Template.lampSupportSwift), and macOS writes a report when it crashes. All of it goes to the
/// agent, which otherwise only sees the code.
enum Runtime {
    /// Where the copy Try On points at keeps what it prints and its pictures. An app for both can be open on
    /// this Mac and in a simulator at once, so its iPhone copy has a folder of its own beside the Mac copy's,
    /// and neither writes over the other.
    static func folder(_ project: LampProject) -> URL {
        project.platform == .universal && project.onIOS ? macFolder(project).appendingPathComponent("ios") : macFolder(project)
    }
    /// The Mac copy's folder, which the app itself writes to (`LampRuntime`): what only a Mac copy has, such as
    /// its answer to being asked to quit or a build held while it stays open, is read here wherever Try On points.
    static func macFolder(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/runtime") }
    /// `folder` as the agent names it, from the app's folder.
    static func folderPath(_ project: LampProject) -> String { String(folder(project).path.dropFirst(project.dir.path.count + 1)) }
    static func logURL(_ project: LampProject) -> URL { folder(project).appendingPathComponent("log.txt") }
    private static func builtURL(_ project: LampProject) -> URL { folder(project).appendingPathComponent("built") }

    /// Remembers when the current build was made (the file's date, so crashes of older builds aren't blamed
    /// on it) and what it was made from: the fingerprint of the sources as they were when the build started.
    static func markBuilt(_ project: LampProject, from fingerprint: String) {
        try? FileManager.default.createDirectory(at: folder(project), withIntermediateDirectories: true)
        try? Data(fingerprint.utf8).write(to: builtURL(project))
    }

    /// A build that hasn't been installed because the person kept the app open when it was asked to quit. The
    /// copy that's open, and the one in the apps folder, are older than the build until it closes. Kept on
    /// disk, so the build still goes in after Lamp itself has been quit and opened again.
    private static func heldURL(_ project: LampProject) -> URL { macFolder(project).appendingPathComponent("held-build") }
    static func holdBuild(_ project: LampProject) {
        try? FileManager.default.createDirectory(at: macFolder(project), withIntermediateDirectories: true)
        try? Data().write(to: heldURL(project))
    }
    static func releaseBuild(_ project: LampProject) { try? FileManager.default.removeItem(at: heldURL(project)) }
    static func holdsBuild(_ project: LampProject) -> Bool { FileManager.default.fileExists(atPath: heldURL(project).path) }

    /// What the app is built from, as one hash: the contents of Sources, its widget's folder, Package.swift and the icon design,
    /// and the attached files the app itself uses (they're copied into the bundle, so a new picture for the
    /// app needs a build; a screenshot attached for the agent to look at doesn't). Not file dates, which move
    /// when a file is rewritten unchanged. Comparing this with the one recorded at build time says whether
    /// a build is needed, including for an edit made while the last build was running.
    static func fingerprint(_ project: LampProject) -> String {
        var hasher = SHA256()
        // An app for both is a different build for each place, so moving it under Try On is a change.
        if project.platform == .universal { hasher.update(data: Data(project.destination.rawValue.utf8)) }
        // A Mac app's App Intents are kept or left out by whether it can be signed for a team, so a new team is a
        // change for an app that has them (Store.intentsCanComeBack).
        if project.platform == .mac, Store.usesAppIntents(project) { hasher.update(data: Data(Devices.team.utf8)) }
        let roots = ["Sources", Template.widgetFolder, Template.watchFolder, "Package.swift", "icon.json", "capabilities.json"].map { project.dir.appendingPathComponent($0) }
        for root in roots {
            let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            for file in ([root] + files).sorted(by: { $0.path < $1.path }) {
                guard let data = try? Data(contentsOf: file) else { continue }
                hasher.update(data: Data(file.path.dropFirst(project.dir.path.count).utf8))
                hasher.update(data: data)
            }
        }
        // The app's own files can be big (pictures, data files): name, size and date stand in for their contents.
        for file in Sharing.assetFiles(of: project).sorted(by: { $0.path < $1.path }) {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            hasher.update(data: Data("\(file.lastPathComponent)\n\(values?.fileSize ?? 0)\n\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)".utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Starts a new log for a launch the simulator makes (a Mac app does this itself in LampRuntime.start):
    /// the last one becomes previous-log.txt.
    static func startLog(_ project: LampProject) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder(project), withIntermediateDirectories: true)
        let log = logURL(project), previous = folder(project).appendingPathComponent("previous-log.txt")
        try? fm.removeItem(at: previous)
        try? fm.moveItem(at: log, to: previous)
        fm.createFile(atPath: log.path, contents: nil)
    }

    // MARK: - Launch

    /// Waits a few seconds after launch. True when the app is already gone: it crashed or quit by itself.
    @MainActor
    static func diedOnLaunch(_ app: NSRunningApplication) async -> Bool {
        for _ in 0..<12 where !app.isTerminated {
            try? await Task.sleep(for: .milliseconds(250))
        }
        return app.isTerminated
    }

    /// What's known about an app that died on launch: the crash report and the last lines it printed.
    /// macOS can take a while to write the report, so this waits for it.
    static func launchReport(_ project: LampProject) async -> String {
        var crash = crash(of: project)
        for _ in 0..<40 where crash == nil {
            try? await Task.sleep(for: .milliseconds(500))
            crash = self.crash(of: project)
        }
        var parts: [String] = []
        if let crash { parts.append(crash) }
        if Privacy.sharesLog, let tail = logTail(project) { parts.append("Last lines the app printed:\n" + tail) }
        return parts.isEmpty ? "It left no crash report and printed nothing." : parts.joined(separator: "\n\n")
    }

    /// Added to a request when the current build has crashed, so the agent knows without being told.
    static func crashNote(for project: LampProject) -> String {
        guard let crash = crash(of: project) else { return "" }
        return """


        Note from Lamp: the app has crashed since it was last built. Fix the cause as part of this request.\
        \(Privacy.sharesLog ? "\nWhat it printed is in \(folderPath(project))/log.txt (the latest launch) and \(folderPath(project))/previous-log.txt (the launch before)." : "")

        \(crash)
        """
    }

    // MARK: - Screenshots

    /// Added to a request when there's a picture of the current build's window, so the agent can look
    /// at what the user sees. It isn't attached: not every model can read images.
    static func screenshotNote(for project: LampProject) -> String {
        func modified(_ url: URL) -> Date? {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        guard Privacy.sharesPictures, let built = modified(builtURL(project)),
              let taken = modified(folder(project).appendingPathComponent("screenshot.png")), taken > built
        else { return "" }
        let more = (2...3).map { "screenshot-\($0).png" }
            .filter { modified(folder(project).appendingPathComponent($0)).map { $0 > built } ?? false }
        return """


        Note from Lamp: \(folderPath(project))/screenshot.png is a picture of the app's front window, taken at \
        \(taken.formatted(date: .omitted, time: .shortened)), just after it opened or when the user last switched away from it\
        \(more.isEmpty ? "" : " (other open windows: " + more.map { folderPath(project) + "/" + $0 }.joined(separator: ", ") + ")"). \
        If you can view images, look at it when this request is about how the app looks or behaves.
        """
    }

    /// The picture of the app's front window, if it was taken of the current build.
    static func currentScreenshot(of project: LampProject) -> URL? {
        func modified(_ url: URL) -> Date? {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        let url = folder(project).appendingPathComponent("screenshot.png")
        guard let built = modified(builtURL(project)), let taken = modified(url), taken > built else { return nil }
        return url
    }

    /// Asks the running app to save fresh pictures of its windows now (see `LampRuntime` in the app).
    static func requestScreenshots(of project: LampProject) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "snapshot.\(project.id)"), object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Pictures the app has saved since `date`, frontmost window first. Waits up to `seconds` for the
    /// first one: the app takes it shortly after it opens.
    static func screenshots(of project: LampProject, since date: Date, waiting seconds: Double = 6) async -> [URL] {
        func fresh() -> [URL] {
            ["screenshot.png", "screenshot-2.png", "screenshot-3.png"].map { folder(project).appendingPathComponent($0) }
                .filter { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast > date }
        }
        for _ in 0..<Int(seconds * 4) where fresh().isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
        }
        return fresh()
    }

    /// What the app says happened when it carried out a `use_app` request (see `LampDriver` in the app). It
    /// writes this after its fresh pictures, so once it's here they're ready too. nil if it never answers,
    /// or `running` turns false: the app is gone.
    @MainActor
    static func useReport(of project: LampProject, id: String, waiting seconds: Double,
                          while running: () -> Bool) async -> String? {
        let url = folder(project).appendingPathComponent("use.json")
        for _ in 0..<Int(seconds * 4) where running() {
            if let data = try? Data(contentsOf: url),
               let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: String], answer["id"] == id {
                return answer["report"]
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    /// The front window as text, which a Mac app writes beside its pictures (`LampScreen` in the app): what's on
    /// it with an id for each thing, for the agent to read and act on by name. Written a moment after the
    /// pictures, so it's waited for briefly. Nil when the app wrote none since `date` (an app built before
    /// there was one, or a window with nothing named in it).
    static func screenText(of project: LampProject, since date: Date) async -> String? {
        let url = folder(project).appendingPathComponent("screen.txt")
        func fresh() -> String? {
            guard (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast > date else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        for _ in 0..<6 where fresh() == nil {
            try? await Task.sleep(for: .milliseconds(250))
        }
        return fresh()
    }

    /// The pictures the app last saved of its windows, frontmost first.
    static func pictures(of project: LampProject) -> [URL] {
        ["screenshot.png", "screenshot-2.png", "screenshot-3.png"].map { folder(project).appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Whether the app needs building: its code or bundled files changed after the current build was made,
    /// or there's no build at all.
    static func sourcesChanged(_ project: LampProject) -> Bool {
        guard FileManager.default.fileExists(atPath: project.builtURL.path),
              let built = try? String(contentsOf: builtURL(project), encoding: .utf8), !built.isEmpty else { return true }
        return built != fingerprint(project)
    }

    // MARK: - Log

    /// The last lines of the latest launch's output.
    static func logTail(_ project: LampProject, lines: Int = 30) -> String? {
        guard let data = try? Data(contentsOf: logURL(project)) else { return nil }
        let tail = String(decoding: data.suffix(8_000), as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n").trimmed
        return tail.isEmpty ? nil : tail
    }

    /// How much the app has printed so far, to tell later what's new.
    static func logSize(_ project: LampProject) -> Int {
        ((try? logURL(project).resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
    }

    /// What the app has printed since its log was `offset` bytes long, at most the last 30 lines. nil if nothing.
    static func log(of project: LampProject, from offset: Int) -> String? {
        guard let data = try? Data(contentsOf: logURL(project)), data.count > offset else { return nil }
        let lines = String(decoding: data.dropFirst(offset).suffix(8_000), as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false).suffix(30).joined(separator: "\n").trimmed
        return lines.isEmpty ? nil : lines
    }

    // MARK: - Crash reports

    private static let reports = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DiagnosticReports")

    /// The newest crash of the current build, summarized: what killed the app and the calls that led there.
    static func crash(of project: LampProject) -> String? {
        guard let built = (try? builtURL(project).resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate else { return nil }
        let files = (try? FileManager.default.contentsOfDirectory(at: reports, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "ips" && $0.lastPathComponent.hasPrefix(project.exe + "-") }
            .compactMap { report($0, bundleID: project.bundleID) }
            .filter { $0.date > built }
            .max { $0.date < $1.date }?.summary
    }

    /// Reads a macOS crash report (.ips): one line of JSON metadata, then the report as JSON.
    private static func report(_ url: URL, bundleID: String) -> (date: Date, summary: String)? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let newline = text.firstIndex(of: "\n"),
              let body = (try? JSONSerialization.jsonObject(with: Data(text[newline...].utf8))) as? [String: Any],
              (body["bundleInfo"] as? [String: Any])?["CFBundleIdentifier"] as? String == bundleID,
              let captured = body["captureTime"] as? String, let date = captureFormat.date(from: captured)
        else { return nil }

        let exception = body["exception"] as? [String: Any] ?? [:]
        let termination = body["termination"] as? [String: Any] ?? [:]
        var reason = [exception["type"] as? String, (exception["signal"] as? String).map { "(\($0))" }]
            .compactMap { $0 }.joined(separator: " ")
        if let indicator = termination["indicator"] as? String { reason += reason.isEmpty ? indicator : ", \(indicator)" }
        var lines = ["Crashed at \(date.formatted(date: .omitted, time: .standard)): \(reason.isEmpty ? "unknown reason" : reason)"]
        for messages in (body["asi"] as? [String: [String]] ?? [:]).values { lines += messages }

        // An uncaught exception carries its own backtrace; otherwise use the thread that crashed.
        let threads = body["threads"] as? [[String: Any]] ?? []
        let crashed = threads.first { $0["triggered"] as? Bool == true }?["frames"] as? [[String: Any]]
        let frames = body["lastExceptionBacktrace"] as? [[String: Any]] ?? crashed ?? []
        let images = body["usedImages"] as? [[String: Any]] ?? []
        if !frames.isEmpty { lines.append("Calls that led there, innermost first:") }
        for frame in frames.prefix(16) {
            let image = (frame["imageIndex"] as? Int).flatMap { images.indices.contains($0) ? images[$0]["name"] as? String : nil }
            var line = "  \(image ?? "?")  \(frame["symbol"] as? String ?? "?")"
            if let file = frame["sourceFile"] as? String, let number = frame["sourceLine"] as? Int {
                line += "  (\(file):\(number))"
            }
            lines.append(line)
        }
        return (date, lines.joined(separator: "\n"))
    }

    private static let captureFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSS Z"
        return format
    }()
}
