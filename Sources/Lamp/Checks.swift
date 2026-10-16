import AppKit

/// An app's own checks (`LampCheck` in LampSupport.swift), each the proof that one thing it promises works. They
/// live in the app's code and travel with it, so what was proved once is proved again after every change, and a
/// change is done when they pass rather than when its files are written.
///
/// They run in the app as built, not in a test harness or the agent's shell: a copy of the build, signed as the
/// installed app is, opened out of sight (`LampChecks` there), so a check has the permissions the person gave the
/// app and finds what the app would find. It gets a LampStore of its own; the person's copy, open or not, is
/// left alone.
enum Checks {
    struct Result: Codable, Equatable {
        var name: String
        var promise: String
        var passed: Bool
        var message: String?
        var seconds: Double
        /// The check said this Mac can't try it (`skip`): not a pass, and nothing for the agent to fix.
        var skipped: Bool?

        var failed: Bool { !passed && skipped != true }
    }

    enum Outcome: Equatable {
        /// What each check found, and the end of what they printed.
        case ran([Result], log: String)
        /// The checks couldn't be run, for a reason that isn't the app's, in words for the agent.
        case notRun(String)
        /// The app didn't let its checks finish: it quit, or one never ended.
        case broke(String)
        /// The app has no checks.
        case none
    }

    /// Where the copies run: in Lamp's own folder, which no agent's commands can read, write or run anything in
    /// (`Sandbox`). The copy is signed as the app, so anything put in it would get the app's permissions and
    /// sign-ins. Each Lamp has its own, and clears it at launch.
    static let folder = Edition.supportFolder.appendingPathComponent("Checks")
    /// How long a whole run may take, however many checks: each has a minute of its own (`LampChecks.patience`),
    /// and one that stops the app answering is ended sooner (the `running` file).
    static let patience: TimeInterval = 600

    /// The copy running each app's checks right now, by app: it may read that app's sign-ins (`Store.appSecrets`).
    @MainActor static var running: [String: URL] = [:]

    /// A copy opened to run the checks, which isn't the app the person has open.
    static func isCheckCopy(_ url: URL?) -> Bool {
        guard let path = url?.resolvingSymlinksInPath().path else { return false }
        return path.hasPrefix(folder.resolvingSymlinksInPath().path + "/")
    }

    /// Whether the app's code has a check, without building it.
    static func has(_ project: LampProject) -> Bool {
        let sources = project.dir.appendingPathComponent("Sources")
        guard let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else { return false }
        for case let file as URL in files where file.pathExtension == "swift" && file.lastPathComponent != "LampSupport.swift" {
            if let text = try? String(contentsOf: file, encoding: .utf8),
               text.range(of: #":\s*LampCheck\b"#, options: .regularExpression) != nil { return true }
        }
        return false
    }

    /// Whether Lamp can run the app's checks where it's going now: on the Mac, not yet on an iPhone.
    /// A widget's code isn't in the app it comes with, so an app that is only its widget has nothing to run.
    @MainActor static func canRun(_ project: LampProject) -> Bool {
        project.platform.hasMac && !project.onIOS && !Template.isWidgetOnly(project)
    }

    /// Copies left by a Lamp that quit while checks ran.
    static func clearLeftovers() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Runs every check in the app's latest build.
    @MainActor static func run(_ project: LampProject, stopped: @escaping @MainActor () -> Bool = { false }) async -> Outcome {
        guard canRun(project) else {
            return .notRun("Lamp runs an app's checks on the Mac only. Check the iPhone app with look_at_app.")
        }
        guard has(project) else { return .none }
        let built = project.builtURL
        let binary = built.appendingPathComponent("Contents/MacOS/\(project.exe)")
        guard let code = try? Data(contentsOf: binary, options: .alwaysMapped) else {
            return .notRun("The app isn't built yet: fix what keeps it from building first.")
        }
        guard code.range(of: Data("LampChecks".utf8)) != nil else {
            return .notRun("The app was built by an earlier Lamp, which couldn't run checks. It's rebuilt with your next change.")
        }
        let run = folder.appendingPathComponent(UUID().uuidString)
        let copy = run.appendingPathComponent(built.lastPathComponent)
        let results = run.appendingPathComponent("results.json")
        do {
            try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: built, to: copy)
        } catch {
            try? FileManager.default.removeItem(at: run)
            return .notRun("Lamp couldn't make a copy of the app to run its checks: \(error.localizedDescription)")
        }
        // Only a build that is this app: Lamp signs the copy as the app, and an id the agent changed would have it
        // sign something as another app.
        let id = NSDictionary(contentsOf: copy.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String
        guard id == project.bundleID else {
            await forget(run, copy: copy)
            return .notRun("The app's build doesn't carry its own id (\(id ?? "none")), so Lamp won't run it as the app.")
        }
        await sign(copy, for: project)
        running[project.id] = copy
        defer { running[project.id] = nil }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        config.addsToRecentItems = false
        config.createsNewApplicationInstance = true
        config.promptsUserIfNeeded = false
        config.arguments = ["-LampChecks", results.path]
        let app: NSRunningApplication
        do {
            app = try await NSWorkspace.shared.openApplication(at: copy, configuration: config)
        } catch {
            await forget(run, copy: copy)
            return .notRun("Lamp couldn't open the app to run its checks: \(error.localizedDescription)")
        }
        let deadline = Date().addingTimeInterval(patience)
        let running = run.appendingPathComponent("running")
        var stuck: String?
        // The results are written all at once, as the copy's last act. A check is given a minute and ends itself
        // after it, unless it has stopped the app answering at all: then the copy is ended a little later.
        while !FileManager.default.fileExists(atPath: results.path), !app.isTerminated, Date() < deadline, !stopped() {
            if let since = (try? running.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               Date().timeIntervalSince(since) > 75 {
                stuck = try? String(contentsOf: running, encoding: .utf8)
                break
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        let printed = (try? String(contentsOf: run.appendingPathComponent("log.txt"), encoding: .utf8))
            .map { $0.split(separator: "\n", omittingEmptySubsequences: false).suffix(30).joined(separator: "\n").trimmed } ?? ""
        let found = (try? Data(contentsOf: results)).flatMap { try? JSONDecoder().decode([Result].self, from: $0) }
        let timedOut = !app.isTerminated
        if timedOut { app.forceTerminate() }
        await forget(run, copy: copy)
        if let found {
            print("Checks of \(project.name): " + found.map { "\($0.passed ? "✓" : $0.skipped == true ? "–" : "✗") \($0.name)" }.joined(separator: ", "))
            return .ran(found, log: printed)
        }
        if stopped() { return .notRun("The person stopped the request.") }
        let why = if let stuck { "\(stuck) didn't finish: the app stopped answering while it ran, so it was ended after a minute." }
            else if timedOut { "The app's checks didn't finish within \(Int(patience / 60)) minutes." }
            else { "The app quit before its checks finished: one of them may have crashed it." }
        return .broke(why + (printed.isEmpty ? "" : "\n\nWhat it printed:\n\(printed)"))
    }

    /// Signs the copy as `Store.deploy` signs the installed app, so macOS takes it for the same app: its
    /// permissions are the app's. An app for both keeps the signature Xcode gave it for the person's team.
    private static func sign(_ app: URL, for project: LampProject) async {
        guard project.platform == .mac else { return }
        // Copied files can carry Finder's metadata, which a certificate signature refuses (as in `deploy`).
        _ = await Subprocess.run("/usr/bin/xattr", ["-cr", app.path], timeout: 60)
        if let team = await Devices.signingIdentity(for: Devices.team),
           await Subprocess.run("/usr/bin/codesign", ["--force", "-s", team, app.path], timeout: 60).status == 0 { return }
        let identity = await AppSigning.identity()
        guard identity != "-" else { return }   // ad hoc, as the build already is
        _ = await Subprocess.run("/usr/bin/codesign", ["--force", "--keychain", AppSigning.keychain, "-s", identity, app.path], timeout: 60)
    }

    /// Takes the copy out of macOS's list of apps once it's gone, so it's never what opens the app's files or links.
    private static func forget(_ run: URL, copy: URL) async {
        _ = await Subprocess.run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                                 ["-u", copy.path], timeout: 30)
        try? FileManager.default.removeItem(at: run)
    }

    /// Whether the app has something to fix: a check failed, or the checks couldn't finish in it. Not when they
    /// all passed, there are none, or they couldn't run for a reason of Lamp's.
    static func needsFixing(_ outcome: Outcome) -> Bool {
        switch outcome {
        case .ran(let results, _): results.isEmpty || results.contains(where: \.failed)
        case .broke: true
        case .none, .notRun: false
        }
    }

    /// What the agent is told of a run.
    static func report(_ outcome: Outcome) -> String {
        switch outcome {
        case .none:
            return "The app has no checks yet. Add one for each thing it must do (a subclass of LampCheck), then run them."
        case .notRun(let why), .broke(let why):
            return why
        case .ran(let results, let log):
            guard !results.isEmpty else {
                return "No checks ran: the app's LampCheck subclasses weren't found in its build. Make sure each is a class that inherits from LampCheck."
            }
            let lines = results.map { result in
                result.passed ? "✓ \(result.name): \(result.promise)"
                    : result.skipped == true ? "– \(result.name): \(result.promise). Not tried on this Mac: \(result.message ?? "")"
                    : "✗ \(result.name): \(result.promise). It failed: \(result.message ?? "no reason given")"
            }
            let failed = results.filter(\.failed).count
            let head = failed == 0 ? "All \(results.count) checks passed." : "\(failed) of \(results.count) checks failed."
            return head + "\n" + lines.joined(separator: "\n") + (failed > 0 && !log.isEmpty ? "\n\nWhat the checks printed:\n\(log)" : "")
        }
    }
}

/// The one thing a wish must do, in the person's words, kept with the app (`.lamp/promise.json`). Lamp writes it
/// from the first request, before the agent starts (`AppName.suggest`), so it says what was asked for, limits
/// included, rather than what turned out easy to build. The agent names the check that proves it (`plan`'s
/// `promise_check`); a new app is built to be seen only once that check has passed, and a promise the agent
/// changes is said in the chat.
struct Promise: Codable, Equatable {
    var text: String
    var check: String?
    /// The request it was taken from.
    var asked: String?

    init(text: String, check: String? = nil, asked: String? = nil, told: Bool? = nil) {
        self.text = text
        self.check = check
        self.asked = asked
        self.told = told
    }
    /// Its check has passed once. From then on it's one of the app's checks like any other.
    var proved: Bool?
    /// The person answered a question while it wasn't proved: they've been told, so the app isn't held back.
    var told: Bool?

    static func file(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/promise.json") }

    static func load(_ project: LampProject) -> Promise? {
        (try? Data(contentsOf: file(project))).flatMap { try? JSONDecoder().decode(Promise.self, from: $0) }
    }

    func save(for project: LampProject) {
        try? JSONEncoder().encode(self).write(to: Self.file(project), options: .atomic)
    }

    /// The promise after the person answered a question about it before it was proved ("Record from now on"),
    /// said by the same helper that first took it from the request, or nil when that can't be had. The agent
    /// isn't left to restate it: it would keep the old words over what it now builds.
    static func revised(_ promise: Promise, answer: String) async -> String? {
        let request = """
            Someone asked for a small app: "\(promise.asked ?? promise.text)"
            Its promise, the one thing it must do for them, was: "\(promise.text)"
            Then they were asked about it and answered:
            \(answer.prefix(2000))

            Say its promise now, as one sentence of at most 15 words, in their words, keeping every limit that \
            still holds. If the answer doesn't change it, give it back exactly as it was.
            Respond with JSON: {"promise": "..."}
            """
        guard let (text, _) = try? await AppAI.complete(prompt: request, images: [], system: "", json: true,
                                                         model: await AppAI.helperModel()),
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let revised = (object["promise"] as? String)?.trimmed, !revised.isEmpty, revised.count <= 160 else { return nil }
        return revised
    }

    /// Its line at the top of the build card's plan, ticked by its check.
    var part: PlanPart { PlanPart(id: 0, title: text, done: false, check: check) }

    /// What the agent is told with a new app's request.
    var note: String {
        """


        ---
        The main promise, in the person's words (from Lamp, not part of the request above): “\(text)”
        Prove it before any design: write the least code that really does it, a LampCheck that does it for real, \
        name that check in `plan`'s promise_check, and run_checks. The app can't be looked at until it passes. \
        If it can't be done, tell the person with `ask` what can't be done and what can, instead of building \
        something else. When they have chosen another promise since, give it as `plan`'s promise.
        """
    }

    /// Why a new app can't be built to be seen yet, or nil once its promise is proved.
    func unproved(_ checks: [String: Bool]) -> String? {
        guard let check else {
            return "Prove the main promise first: “\(text)”. Write a LampCheck that does it for real, name it in plan's promise_check, and run_checks."
        }
        switch checks[check] {
        case true?: return nil
        case false?: return "The main promise's check (\(check)) fails, so the app isn't shown yet. Fix it, or if it can't be done, tell the person with `ask` what can't be done and what can, instead of building something else."
        case nil: return "Run the main promise's check (\(check)) with run_checks before looking at the app."
        }
    }
}
