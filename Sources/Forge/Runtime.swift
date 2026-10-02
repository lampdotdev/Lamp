import AppKit

/// What Forge can see of a generated app while it runs. The app saves what it prints to
/// `.forge/runtime/log.txt` and pictures of its windows next to it (see `ForgeRuntime` in
/// Template.forgeSupportSwift), and macOS writes a report when it crashes. All of it goes to the
/// agent, which otherwise only sees the code.
enum Runtime {
    static func folder(_ project: ForgeProject) -> URL { project.dir.appendingPathComponent(".forge/runtime") }
    static func logURL(_ project: ForgeProject) -> URL { folder(project).appendingPathComponent("log.txt") }
    private static func builtURL(_ project: ForgeProject) -> URL { folder(project).appendingPathComponent("built") }

    /// Remembers when the current build was made, so crashes of older builds aren't blamed on it.
    static func markBuilt(_ project: ForgeProject) {
        try? FileManager.default.createDirectory(at: folder(project), withIntermediateDirectories: true)
        try? Data().write(to: builtURL(project))
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
    static func launchReport(_ project: ForgeProject) async -> String {
        var crash = crash(of: project)
        for _ in 0..<40 where crash == nil {
            try? await Task.sleep(for: .milliseconds(500))
            crash = self.crash(of: project)
        }
        var parts: [String] = []
        if let crash { parts.append(crash) }
        if let tail = logTail(project) { parts.append("Last lines the app printed:\n" + tail) }
        return parts.isEmpty ? "It left no crash report and printed nothing." : parts.joined(separator: "\n\n")
    }

    /// Added to a request when the current build has crashed, so the agent knows without being told.
    static func crashNote(for project: ForgeProject) -> String {
        guard let crash = crash(of: project) else { return "" }
        return """


        Note from Forge: the app has crashed since it was last built. Fix the cause as part of this request.
        What it printed is in .forge/runtime/log.txt (the latest launch) and .forge/runtime/previous-log.txt \
        (the launch before).

        \(crash)
        """
    }

    // MARK: - Screenshots

    /// Added to a request when there's a picture of the current build's window, so the agent can look
    /// at what the user sees. It isn't attached: not every model can read images.
    static func screenshotNote(for project: ForgeProject) -> String {
        func modified(_ url: URL) -> Date? {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        guard let built = modified(builtURL(project)),
              let taken = modified(folder(project).appendingPathComponent("screenshot.png")), taken > built
        else { return "" }
        let more = (2...3).map { "screenshot-\($0).png" }
            .filter { modified(folder(project).appendingPathComponent($0)).map { $0 > built } ?? false }
        return """


        Note from Forge: .forge/runtime/screenshot.png is a picture of the app's front window, taken at \
        \(taken.formatted(date: .omitted, time: .shortened)), just after it opened or when the user last switched away from it\
        \(more.isEmpty ? "" : " (other open windows: " + more.map { ".forge/runtime/" + $0 }.joined(separator: ", ") + ")"). \
        If you can view images, look at it when this request is about how the app looks or behaves.
        """
    }

    /// Asks the running app to save fresh pictures of its windows now (see `ForgeRuntime` in the app).
    static func requestScreenshots(of project: ForgeProject) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("dev.forge.snapshot.\(project.id)"), object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Pictures the app has saved since `date`, frontmost window first. Waits up to `seconds` for the
    /// first one: the app takes it shortly after it opens.
    static func screenshots(of project: ForgeProject, since date: Date, waiting seconds: Double = 6) async -> [URL] {
        func fresh() -> [URL] {
            ["screenshot.png", "screenshot-2.png", "screenshot-3.png"].map { folder(project).appendingPathComponent($0) }
                .filter { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast > date }
        }
        for _ in 0..<Int(seconds * 4) where fresh().isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
        }
        return fresh()
    }

    /// Whether the app needs building: its code or bundled files changed after the current build was made,
    /// or there's no build at all.
    static func sourcesChanged(_ project: ForgeProject) -> Bool {
        guard FileManager.default.fileExists(atPath: project.builtURL.path),
              let built = (try? builtURL(project).resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate else { return true }
        let roots = ["Sources", "Attachments", "Package.swift", "icon.json"].map { project.dir.appendingPathComponent($0) }
        for root in roots {
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey])?
                .compactMap { $0 as? URL } ?? []
            for file in [root] + files {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
                if values?.isDirectory != true, let modified = values?.contentModificationDate, modified > built { return true }
            }
        }
        return false
    }

    // MARK: - Log

    /// The last lines of the latest launch's output.
    static func logTail(_ project: ForgeProject, lines: Int = 30) -> String? {
        guard let data = try? Data(contentsOf: logURL(project)) else { return nil }
        let tail = String(decoding: data.suffix(8_000), as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n").trimmed
        return tail.isEmpty ? nil : tail
    }

    // MARK: - Crash reports

    private static let reports = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DiagnosticReports")

    /// The newest crash of the current build, summarised: what killed the app and the calls that led there.
    static func crash(of project: ForgeProject) -> String? {
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
